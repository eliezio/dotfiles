"""mitmproxy addon: cache GET/HEAD responses to disk by URL.

Run on the host:
    pip install mitmproxy
    mitmdump -p 3128 -s test/mitmproxy/cache.py

Cache layout (default ~/.cache/mitmproxy-cache, override with $MITMPROXY_CACHE_DIR):
    <sha256>.json   status, headers, original URL
    <sha256>.bin    raw response body

Caveats:
- Caches forever. Ignores Cache-Control / ETag.
- Caches 200/301/302/304 responses only.
- Delete the cache dir to force a refresh.
"""

import hashlib
import json
import os
from pathlib import Path

from mitmproxy import ctx, http

CACHE_DIR = Path(
    os.environ.get(
        "MITMPROXY_CACHE_DIR",
        str(Path.home() / ".cache" / "mitmproxy-cache"),
    )
)


def _key(flow: http.HTTPFlow) -> str:
    return hashlib.sha256(
        f"{flow.request.method} {flow.request.url}".encode()
    ).hexdigest()


def _meta_path(key: str) -> Path:
    return CACHE_DIR / f"{key}.json"


def _body_path(key: str) -> Path:
    return CACHE_DIR / f"{key}.bin"


def _cacheable(flow: http.HTTPFlow) -> bool:
    return flow.request.method in ("GET", "HEAD")


def request(flow: http.HTTPFlow) -> None:
    if not _cacheable(flow):
        return
    key = _key(flow)
    meta_p = _meta_path(key)
    body_p = _body_path(key)
    if not (meta_p.exists() and body_p.exists()):
        return
    meta = json.loads(meta_p.read_text())
    # JSON stored headers as (str, str); mitmproxy Headers needs (bytes, bytes).
    headers = [(k.encode("latin-1"), v.encode("latin-1")) for k, v in meta["headers"]]
    flow.response = http.Response.make(
        meta["status"],
        body_p.read_bytes(),
        headers,
    )
    ctx.log.info(f"HIT  {flow.request.url}")


def response(flow: http.HTTPFlow) -> None:
    if not _cacheable(flow):
        return
    if flow.response is None or flow.response.status_code not in (200, 301, 302, 304):
        return
    key = _key(flow)
    meta_p = _meta_path(key)
    if meta_p.exists():
        return
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    meta_p.write_text(
        json.dumps(
            {
                "status": flow.response.status_code,
                "headers": list(flow.response.headers.items()),
                "url": flow.request.url,
            }
        )
    )
    _body_path(key).write_bytes(flow.response.content or b"")
    ctx.log.info(f"STORE {flow.request.url}")
