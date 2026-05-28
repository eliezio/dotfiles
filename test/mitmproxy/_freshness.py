"""HTTP freshness helpers — pure functions, no I/O.

Implements a subset of RFC 9111 sufficient for our workload:
- Parse `Cache-Control` directives.
- Decide whether a cached entry is fresh given response headers and the
  time at which it was cached.

No heuristic freshness (RFC 9111 §4.2.2): every upstream we care about
ships either ETag or Last-Modified, so when explicit max-age is absent
we return stale and let the caller revalidate. Cheap and correct.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Mapping


def parse_cache_control(value: str | None) -> dict[str, str | bool]:
    """Parse a Cache-Control header value into a dict.

    Directives without `=value` map to True. Unknown directives are kept
    so callers can check for `no-store`, `private`, etc.
    """
    if not value:
        return {}
    out: dict[str, str | bool] = {}
    for token in value.split(","):
        token = token.strip()
        if not token:
            continue
        if "=" in token:
            k, v = token.split("=", 1)
            out[k.strip().lower()] = v.strip().strip('"')
        else:
            out[token.lower()] = True
    return out


def max_age_seconds(cc: Mapping[str, str | bool]) -> int | None:
    """Return effective max-age in seconds, preferring s-maxage (we are a shared cache).

    Returns None if no max-age directive is present.
    """
    for key in ("s-maxage", "max-age"):
        v = cc.get(key)
        if isinstance(v, str):
            try:
                return int(v)
            except ValueError:
                continue
    return None


def is_fresh(
    response_headers: Mapping[str, str],
    cached_at: datetime,
    now: datetime,
) -> bool:
    """True if the cached entry can be served without revalidating.

    Rules (subset of RFC 9111 §4.2):
    - `no-cache` or `no-store` in Cache-Control → never fresh.
    - `max-age` / `s-maxage` set → fresh if age < max-age.
    - Otherwise → stale (we force revalidation rather than guessing).
    """
    cc = parse_cache_control(response_headers.get("cache-control"))
    if cc.get("no-cache") or cc.get("no-store"):
        return False
    max_age = max_age_seconds(cc)
    if max_age is None:
        return False
    age = (now - cached_at).total_seconds()
    return age < max_age


def is_response_storable(response_headers: Mapping[str, str]) -> bool:
    """True if the response may be written to cache.

    We refuse to store `no-store` or `private` responses. `no-cache` is
    storable but must always be revalidated — handled by is_fresh().
    """
    cc = parse_cache_control(response_headers.get("cache-control"))
    return not (cc.get("no-store") or cc.get("private"))


def utcnow() -> datetime:
    """Wall-clock UTC. Indirected for test patching."""
    return datetime.now(timezone.utc)
