"""Tests for the mitmproxy caching addon.

Run from repo root:
    pytest test/mitmproxy/

Uses mitmproxy's official test factories (mitmproxy.test.tflow) so we exercise
real HTTPFlow / Request / Response objects rather than mocks.
"""

from __future__ import annotations

import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest
from mitmproxy import http
from mitmproxy.test import tflow, tutils

# Make `cache` and `_freshness` importable when running from repo root.
HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))

import cache  # noqa: E402


# ────────────────────────────────────────────────────────────────────────
# Fixtures
# ────────────────────────────────────────────────────────────────────────


@pytest.fixture(autouse=True)
def isolated_cache_dir(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """Each test gets a fresh cache dir; no env pollution."""
    monkeypatch.setattr(cache, "CACHE_DIR", tmp_path)
    return tmp_path


@pytest.fixture
def fixed_now(monkeypatch: pytest.MonkeyPatch) -> datetime:
    """Pin utcnow() in cache.py to a fixed instant."""
    pinned = datetime(2026, 5, 28, 12, 0, 0, tzinfo=timezone.utc)
    monkeypatch.setattr(cache, "utcnow", lambda: pinned)
    return pinned


def make_flow(
    method: str = "GET",
    url: str = "https://example.com/resource",
    response_status: int = 200,
    response_body: bytes = b"hello",
    response_headers: tuple[tuple[bytes, bytes], ...] = (),
    has_response: bool = True,
) -> http.HTTPFlow:
    """Synthesize an HTTPFlow with the given request and (optional) response."""
    # Parse the URL crudely — tutils.treq wants host/port/scheme/path separately.
    from urllib.parse import urlsplit

    parts = urlsplit(url)
    scheme = parts.scheme.encode()
    host = parts.hostname.encode() if parts.hostname else b"example.com"
    port = parts.port or (443 if parts.scheme == "https" else 80)
    path = (parts.path or "/").encode()
    if parts.query:
        path += b"?" + parts.query.encode()

    req = tutils.treq(
        method=method.encode(),
        scheme=scheme,
        host=host,
        port=port,
        path=path,
    )
    if has_response:
        resp = tutils.tresp(
            status_code=response_status,
            content=response_body,
            headers=response_headers,
        )
        return tflow.tflow(req=req, resp=resp)
    return tflow.tflow(req=req)


# ────────────────────────────────────────────────────────────────────────
# Tests
# ────────────────────────────────────────────────────────────────────────


def test_miss_stores_response(isolated_cache_dir: Path, fixed_now: datetime):
    """First time URL seen: response written to cache, STORE state."""
    flow = make_flow(
        response_headers=(
            (b"cache-control", b"max-age=600"),
            (b"etag", b'"v1"'),
        ),
        response_body=b"body-v1",
    )
    cache.request(flow)  # MISS — no cache entry, no flow.response set by us
    # (tflow gave us a response object too, but request() doesn't replace it on MISS.)
    cache.response(flow)

    stored_files = list(isolated_cache_dir.iterdir())
    assert len(stored_files) == 2  # .json + .bin
    key = cache._key(flow)
    assert (isolated_cache_dir / f"{key}.json").exists()
    assert (isolated_cache_dir / f"{key}.bin").read_bytes() == b"body-v1"


def test_fresh_hit_no_upstream(isolated_cache_dir: Path, fixed_now: datetime):
    """Cached entry within max-age: request hook serves cached body without upstream call.

    Also: response hook must skip the synthesized response (no double-STORE).
    """
    # Seed cache by running a full request/response cycle.
    flow1 = make_flow(
        response_headers=((b"cache-control", b"max-age=600"),),
        response_body=b"cached-body",
    )
    cache.request(flow1)
    cache.response(flow1)

    # Snapshot the meta file's mtime / cached_at to detect spurious re-stores.
    import json

    key = cache._key(flow1)
    meta_path = isolated_cache_dir / f"{key}.json"
    cached_at_before = json.loads(meta_path.read_text())["cached_at"]

    # New request for same URL — should be served from cache by request hook.
    flow2 = make_flow(response_body=b"WOULD-BE-UPSTREAM", has_response=False)
    cache.request(flow2)

    # request() sets flow.response itself when serving from cache.
    assert flow2.response is not None
    assert flow2.response.content == b"cached-body"
    # And we didn't tag it as revalidating.
    assert cache.META_REVAL_KEY not in flow2.metadata
    # The HIT tag was set, so the response hook will skip.
    assert flow2.metadata.get(cache.META_HIT_KEY) is True

    # Now call the response hook (mitmproxy will call it on the synthesized
    # response). It must NOT re-store and must clear the HIT tag.
    cache.response(flow2)
    cached_at_after = json.loads(meta_path.read_text())["cached_at"]
    assert cached_at_after == cached_at_before  # no rewrite
    assert cache.META_HIT_KEY not in flow2.metadata  # tag consumed


def test_stale_revalidates_with_etag(
    isolated_cache_dir: Path, monkeypatch: pytest.MonkeyPatch
):
    """Past max-age + ETag present: request hook attaches If-None-Match."""
    t0 = datetime(2026, 5, 28, 12, 0, 0, tzinfo=timezone.utc)
    monkeypatch.setattr(cache, "utcnow", lambda: t0)

    seed = make_flow(
        response_headers=(
            (b"cache-control", b"max-age=60"),
            (b"etag", b'"v1"'),
        ),
        response_body=b"old",
    )
    cache.request(seed)
    cache.response(seed)

    # Jump 10 minutes into the future — well past max-age=60s.
    t1 = t0 + timedelta(minutes=10)
    monkeypatch.setattr(cache, "utcnow", lambda: t1)

    flow = make_flow(has_response=False)
    cache.request(flow)

    # Not served from cache; passed through with validators attached.
    assert flow.response is None
    assert flow.request.headers.get("If-None-Match") == '"v1"'
    assert flow.metadata[cache.META_REVAL_KEY] == cache._key(flow)


def test_stale_revalidates_with_last_modified(
    isolated_cache_dir: Path, monkeypatch: pytest.MonkeyPatch
):
    """Past max-age + only Last-Modified: request hook attaches If-Modified-Since.

    Models the Nix install script: ETag + Last-Modified, no Cache-Control.
    Since no max-age means "always stale" in our policy, this exercises the
    revalidation path with only Last-Modified.
    """
    t0 = datetime(2026, 5, 28, 12, 0, 0, tzinfo=timezone.utc)
    monkeypatch.setattr(cache, "utcnow", lambda: t0)

    seed = make_flow(
        url="https://nixos.org/nix/install",
        response_headers=((b"last-modified", b"Mon, 04 May 2026 18:52:30 GMT"),),
        response_body=b"nix-install-script",
    )
    cache.request(seed)
    cache.response(seed)

    # Even at t0, "no Cache-Control" means stale per our policy.
    flow = make_flow(url="https://nixos.org/nix/install", has_response=False)
    cache.request(flow)

    assert flow.response is None
    assert (
        flow.request.headers.get("If-Modified-Since")
        == "Mon, 04 May 2026 18:52:30 GMT"
    )
    assert "If-None-Match" not in flow.request.headers


def test_pacman_db_stale_then_refreshed(
    isolated_cache_dir: Path, monkeypatch: pytest.MonkeyPatch
):
    """Regression for `pacman -S nodejs` failure caused by stale extra.db.

    Sequence:
    1. Cache extra.db with body B1 / ETag E1.
    2. Time advances past freshness window.
    3. Upstream returns 200 + body B2 + ETag E2 (mirror updated).
    4. Cache must now hold B2/E2.
    5. Subsequent request: upstream returns 304 → serves B2 from cache.
    """
    t0 = datetime(2026, 5, 28, 12, 0, 0, tzinfo=timezone.utc)
    monkeypatch.setattr(cache, "utcnow", lambda: t0)
    url = "https://geo.mirror.pkgbuild.com/extra/os/x86_64/extra.db"

    # Step 1: seed cache with B1/E1. Arch DBs have no Cache-Control in the
    # wild → stale on every subsequent request → revalidation each time.
    seed = make_flow(
        url=url,
        response_headers=((b"etag", b'"E1"'),),
        response_body=b"DB-CONTENTS-V1-references-nodejs-22.5.1",
    )
    cache.request(seed)
    cache.response(seed)

    # Step 2-3: pacman fetches again. Our cache is "stale" (no max-age), so we
    # attach If-None-Match: "E1". Upstream answers with a fresh 200+E2 because
    # nodejs got updated.
    monkeypatch.setattr(cache, "utcnow", lambda: t0 + timedelta(days=14))
    reval = make_flow(
        url=url,
        response_headers=((b"etag", b'"E2"'),),
        response_body=b"DB-CONTENTS-V2-references-nodejs-22.7.0",
    )
    cache.request(reval)
    # request() should have attached If-None-Match and tagged for revalidation.
    assert reval.request.headers.get("If-None-Match") == '"E1"'
    assert cache.META_REVAL_KEY in reval.metadata
    # Simulate upstream returning 200 with the new body (already on the flow).
    cache.response(reval)

    # Step 4: cache now holds B2/E2.
    key = cache._key(reval)
    stored_body = (isolated_cache_dir / f"{key}.bin").read_bytes()
    assert stored_body == b"DB-CONTENTS-V2-references-nodejs-22.7.0"
    import json

    stored_meta = json.loads((isolated_cache_dir / f"{key}.json").read_text())
    stored_headers = {k.lower(): v for k, v in stored_meta["headers"]}
    assert stored_headers["etag"] == '"E2"'

    # Step 5: another fetch a moment later → upstream returns 304 → cache serves B2.
    monkeypatch.setattr(cache, "utcnow", lambda: t0 + timedelta(days=14, seconds=1))
    final_req = make_flow(url=url, has_response=False)
    cache.request(final_req)
    assert final_req.request.headers.get("If-None-Match") == '"E2"'
    # Simulate the 304 reply by attaching a 304 response, then call response hook.
    final_req.response = tutils.tresp(status_code=304, content=b"", headers=())
    cache.response(final_req)
    # The 304 must have been rewritten to a 200 served from cache.
    assert final_req.response.status_code == 200
    assert final_req.response.content == b"DB-CONTENTS-V2-references-nodejs-22.7.0"


def test_304_serves_cached_body(
    isolated_cache_dir: Path, monkeypatch: pytest.MonkeyPatch
):
    """Stale entry + upstream 304: response body becomes cached body, cached_at refreshed."""
    t0 = datetime(2026, 5, 28, 12, 0, 0, tzinfo=timezone.utc)
    monkeypatch.setattr(cache, "utcnow", lambda: t0)

    seed = make_flow(
        response_headers=((b"etag", b'"v1"'),),
        response_body=b"original-body",
    )
    cache.request(seed)
    cache.response(seed)

    # Time advances.
    t1 = t0 + timedelta(hours=1)
    monkeypatch.setattr(cache, "utcnow", lambda: t1)

    # Revalidation request goes upstream, upstream returns 304.
    flow = make_flow(has_response=False)
    cache.request(flow)
    flow.response = tutils.tresp(status_code=304, content=b"", headers=())
    cache.response(flow)

    assert flow.response.status_code == 200
    assert flow.response.content == b"original-body"

    # cached_at should now reflect t1, not t0.
    import json

    key = cache._key(flow)
    meta = json.loads((isolated_cache_dir / f"{key}.json").read_text())
    assert meta["cached_at"] == t1.isoformat()


def test_no_store_skips_cache(isolated_cache_dir: Path, fixed_now: datetime):
    """Upstream Cache-Control: no-store → nothing written."""
    flow = make_flow(
        response_headers=((b"cache-control", b"no-store"),),
        response_body=b"secret",
    )
    cache.request(flow)
    cache.response(flow)

    assert list(isolated_cache_dir.iterdir()) == []


def test_missing_cached_at_treated_as_stale(
    isolated_cache_dir: Path, monkeypatch: pytest.MonkeyPatch
):
    """Legacy cache entries without `cached_at` must force revalidation."""
    import json

    t0 = datetime(2026, 5, 28, 12, 0, 0, tzinfo=timezone.utc)
    monkeypatch.setattr(cache, "utcnow", lambda: t0)

    # Hand-write a legacy entry: no `cached_at` field.
    flow = make_flow(has_response=False)
    key = cache._key(flow)
    legacy_meta = {
        "status": 200,
        "headers": [["etag", '"legacy"'], ["cache-control", "max-age=99999"]],
        "url": flow.request.url,
        # No cached_at!
    }
    (isolated_cache_dir / f"{key}.json").write_text(json.dumps(legacy_meta))
    (isolated_cache_dir / f"{key}.bin").write_bytes(b"legacy-body")

    cache.request(flow)
    # Treated as stale → no response set, validators attached, tagged for reval.
    assert flow.response is None
    assert flow.request.headers.get("If-None-Match") == '"legacy"'
    assert cache.META_REVAL_KEY in flow.metadata


def test_post_not_cached(isolated_cache_dir: Path, fixed_now: datetime):
    """Non-GET/HEAD methods bypass the cache entirely."""
    flow = make_flow(
        method="POST",
        response_headers=((b"cache-control", b"max-age=600"),),
        response_body=b"post-response",
    )
    cache.request(flow)
    cache.response(flow)

    assert list(isolated_cache_dir.iterdir()) == []


# ────────────────────────────────────────────────────────────────────────
# _freshness unit tests (quick sanity)
# ────────────────────────────────────────────────────────────────────────


def test_freshness_parse_cache_control():
    from _freshness import parse_cache_control

    assert parse_cache_control(None) == {}
    assert parse_cache_control("") == {}
    assert parse_cache_control("max-age=600") == {"max-age": "600"}
    assert parse_cache_control("public, max-age=600") == {
        "public": True,
        "max-age": "600",
    }
    assert parse_cache_control("no-store") == {"no-store": True}
    assert parse_cache_control("max-age=0, proxy-revalidate, s-maxage=3300") == {
        "max-age": "0",
        "proxy-revalidate": True,
        "s-maxage": "3300",
    }


def test_freshness_is_fresh_max_age():
    from _freshness import is_fresh

    t0 = datetime(2026, 5, 28, 12, 0, 0, tzinfo=timezone.utc)
    assert is_fresh({"cache-control": "max-age=600"}, t0, t0 + timedelta(seconds=100))
    assert not is_fresh(
        {"cache-control": "max-age=600"}, t0, t0 + timedelta(seconds=700)
    )


def test_freshness_prefers_s_maxage():
    from _freshness import is_fresh

    t0 = datetime(2026, 5, 28, 12, 0, 0, tzinfo=timezone.utc)
    # Ubuntu Release: max-age=0 for clients, s-maxage=3300 for shared caches.
    headers = {"cache-control": "max-age=0, s-maxage=3300"}
    assert is_fresh(headers, t0, t0 + timedelta(seconds=1000))
    assert not is_fresh(headers, t0, t0 + timedelta(seconds=4000))


def test_freshness_no_cache_control_is_stale():
    from _freshness import is_fresh

    t0 = datetime(2026, 5, 28, 12, 0, 0, tzinfo=timezone.utc)
    # No max-age → stale by our policy (force revalidation).
    assert not is_fresh({}, t0, t0)
    assert not is_fresh({}, t0, t0 + timedelta(days=365))


def test_freshness_no_cache_directive_is_stale():
    from _freshness import is_fresh

    t0 = datetime(2026, 5, 28, 12, 0, 0, tzinfo=timezone.utc)
    # Even within max-age, no-cache forces revalidation. Models GitHub releases.
    headers = {"cache-control": "no-cache, max-age=31536000"}
    assert not is_fresh(headers, t0, t0)
