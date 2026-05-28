"""mitmproxy addon: RFC 9111-lite caching proxy for the test containers.

Run on the host:
    pip install mitmproxy
    mitmdump -p 3128 -s test/mitmproxy/cache.py

Cache layout (default ~/.cache/mitmproxy-cache, override with $MITMPROXY_CACHE_DIR):
    <sha256>.json   status, headers, original URL, cached_at (ISO8601 UTC)
    <sha256>.bin    raw response body

Behavior:
    GET/HEAD only. Honors Cache-Control (max-age, s-maxage, no-cache, no-store,
    private). When a cached entry is stale and has ETag or Last-Modified, the
    request is mutated with If-None-Match / If-Modified-Since and forwarded
    upstream; a 304 reply serves the cached body, a 200 replaces it.

Logged states (visible in mitmdump output):
    STORE       first time URL seen; response cached
    HIT         cached entry fresh per max-age; served without upstream call
    REVAL-304   cached entry stale; upstream confirmed unchanged
    REVAL-200   cached entry stale; upstream returned new body, replaced
    BYPASS      response is no-store / private / non-cacheable

Caveats / known limitations:
    - No Vary handling. Acceptable because our clients negotiate uniformly;
      revisit if observed.
    - No Range / partial responses (workload doesn't use them).
    - No size cap or LRU eviction. Delete the cache dir if it grows.
    - Dev-tool threat model: trusts upstream; not hardened against poisoning.

Delete the cache dir to force a cold start.
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
from datetime import datetime
from pathlib import Path

from mitmproxy import http

from _freshness import (
    is_fresh,
    is_response_storable,
    parse_cache_control,
    utcnow,
)

log = logging.getLogger(__name__)

CACHE_DIR = Path(
    os.environ.get(
        "MITMPROXY_CACHE_DIR",
        str(Path.home() / ".cache" / "mitmproxy-cache"),
    )
)

# Status codes we are willing to store. 304 is excluded — it only appears as
# a revalidation reply, never as a primary response we'd cache.
CACHEABLE_STATUS = frozenset({200, 301, 308})

# Keys used in flow.metadata to thread state between request and response
# hooks. When the response hook sees META_REVAL_KEY, we initiated a
# revalidation upstream. When it sees META_HIT_KEY, the request hook already
# served from cache and the response hook must not touch it.
META_REVAL_KEY = "mitm_cache_revalidating"
META_HIT_KEY = "mitm_cache_hit"


# ────────────────────────────────────────────────────────────────────────
# Paths and key derivation
# ────────────────────────────────────────────────────────────────────────


def _key(flow: http.HTTPFlow) -> str:
    return hashlib.sha256(
        f"{flow.request.method} {flow.request.url}".encode()
    ).hexdigest()


def _meta_path(key: str) -> Path:
    return CACHE_DIR / f"{key}.json"


def _body_path(key: str) -> Path:
    return CACHE_DIR / f"{key}.bin"


# ────────────────────────────────────────────────────────────────────────
# Cacheability
# ────────────────────────────────────────────────────────────────────────


def _request_cacheable(flow: http.HTTPFlow) -> bool:
    return flow.request.method in ("GET", "HEAD")


# ────────────────────────────────────────────────────────────────────────
# Meta load/store
# ────────────────────────────────────────────────────────────────────────


def _load_meta(key: str) -> dict | None:
    meta_p = _meta_path(key)
    body_p = _body_path(key)
    if not (meta_p.exists() and body_p.exists()):
        return None
    try:
        return json.loads(meta_p.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def _store(
    key: str,
    flow: http.HTTPFlow,
    cached_at: datetime,
) -> None:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    response = flow.response
    assert response is not None  # caller guarantees
    meta = {
        "status": response.status_code,
        "headers": list(response.headers.items()),
        "url": flow.request.url,
        "cached_at": cached_at.isoformat(),
    }
    _meta_path(key).write_text(json.dumps(meta))
    _body_path(key).write_bytes(response.content or b"")


def _update_cached_at(key: str, cached_at: datetime) -> None:
    meta = _load_meta(key)
    if meta is None:
        return
    meta["cached_at"] = cached_at.isoformat()
    _meta_path(key).write_text(json.dumps(meta))


def _headers_dict(meta: dict) -> dict[str, str]:
    """Lowercased header lookup from stored (key, value) pairs."""
    return {k.lower(): v for k, v in meta["headers"]}


def _serve_from_cache(flow: http.HTTPFlow, meta: dict, body: bytes) -> None:
    """Set flow.response from cached meta+body so the upstream is not contacted."""
    # JSON stored headers as (str, str); mitmproxy Headers takes (bytes, bytes).
    headers = [(k.encode("latin-1"), v.encode("latin-1")) for k, v in meta["headers"]]
    flow.response = http.Response.make(meta["status"], body, headers)


def _parse_cached_at(meta: dict) -> datetime | None:
    """Returns None for legacy entries without `cached_at` — treated as stale."""
    raw = meta.get("cached_at")
    if not raw:
        return None
    try:
        return datetime.fromisoformat(raw)
    except ValueError:
        return None


# ────────────────────────────────────────────────────────────────────────
# Hooks
# ────────────────────────────────────────────────────────────────────────


def request(flow: http.HTTPFlow) -> None:
    if not _request_cacheable(flow):
        return
    key = _key(flow)
    meta = _load_meta(key)
    if meta is None:
        return  # MISS — let it pass through; response() will STORE if cacheable.

    headers = _headers_dict(meta)
    cached_at = _parse_cached_at(meta)
    now = utcnow()

    if cached_at is not None and is_fresh(headers, cached_at, now):
        body = _body_path(key).read_bytes()
        _serve_from_cache(flow, meta, body)
        flow.metadata[META_HIT_KEY] = True
        log.info(f"HIT  {flow.request.url}")
        return

    # Stale. Attach validators if we have them; let it go upstream.
    # Lowercase header names: required for HTTP/2, harmless for HTTP/1.1.
    etag = headers.get("etag")
    last_mod = headers.get("last-modified")
    if etag:
        flow.request.headers["if-none-match"] = etag
    if last_mod:
        flow.request.headers["if-modified-since"] = last_mod
    flow.metadata[META_REVAL_KEY] = key


def response(flow: http.HTTPFlow) -> None:
    if not _request_cacheable(flow) or flow.response is None:
        return

    # If the request hook already served from cache, the "response" mitmproxy is
    # processing is our own synthesized one — don't re-store it.
    if flow.metadata.pop(META_HIT_KEY, False):
        return

    reval_key: str | None = flow.metadata.pop(META_REVAL_KEY, None)
    status = flow.response.status_code

    # Branch A: revalidation in progress.
    if reval_key is not None:
        if status == 304:
            meta = _load_meta(reval_key)
            if meta is not None:
                body = _body_path(reval_key).read_bytes()
                _serve_from_cache(flow, meta, body)
                _update_cached_at(reval_key, utcnow())
                log.info(f"REVAL-304 {flow.request.url}")
                return
            # Cache disappeared between request and response hooks; fall through
            # and treat as fresh STORE if upstream gave us a usable response.
        if status in CACHEABLE_STATUS and is_response_storable(flow.response.headers):
            _store(reval_key, flow, utcnow())
            log.info(f"REVAL-200 {flow.request.url}")
            return
        log.info(f"BYPASS {flow.request.url} (reval status={status})")
        return

    # Branch B: fresh request, no cache entry yet.
    if status not in CACHEABLE_STATUS:
        return  # Don't log every uncacheable status — too noisy for 4xx/5xx.
    if not is_response_storable(flow.response.headers):
        log.info(f"BYPASS {flow.request.url} (no-store/private)")
        return
    key = _key(flow)
    _store(key, flow, utcnow())
    log.info(f"STORE {flow.request.url}")
