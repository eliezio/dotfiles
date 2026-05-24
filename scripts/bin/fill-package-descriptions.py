#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["ruamel.yaml>=0.18"]
# ///
"""
Fill in missing `description` fields in .chezmoidata/packages.yaml.

For each entry under `packages.cli` / `packages.gui` without a `description`,
query `brew info --json=v2 <name>` and copy the upstream `desc` into the entry.

Honors the per-entry `brew:` override (e.g. a tap-qualified formula name)
and the `brew_cask: true` flag. The flat `packages.system.*` lists are skipped
(no schema slot for descriptions there).

Re-runnable: entries that already have a description are left untouched, so
running it after adding new packages will only fetch the missing ones.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

from ruamel.yaml import YAML

REPO_ROOT = Path(__file__).resolve().parents[2]
PACKAGES_YAML = REPO_ROOT / ".chezmoidata" / "packages.yaml"


def brew_lookup_name(entry: dict) -> str:
    """The name to pass to `brew info`. Tap-qualified `brew:` overrides win."""
    return entry.get("brew") or entry["name"]


def fetch_description(name: str, *, is_cask: bool) -> str | None:
    cmd = ["brew", "info", "--json=v2"]
    if is_cask:
        cmd.append("--cask")
    cmd.append(name)

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        msg = result.stderr.strip().splitlines()[-1] if result.stderr else "unknown error"
        print(f"  ! brew info failed for {name}: {msg}", file=sys.stderr)
        return None

    payload = json.loads(result.stdout)
    items = payload.get("casks" if is_cask else "formulae", [])
    if not items:
        print(f"  ! no {'cask' if is_cask else 'formula'} returned for {name}", file=sys.stderr)
        return None
    return items[0].get("desc")


def main() -> int:
    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.width = 4096  # don't wrap long description strings
    # Match the file's existing indent style: 2-space mapping, sequence dash
    # indented 4 from parent (offset 2 puts the `-` at column parent+2).
    yaml.indent(mapping=2, sequence=4, offset=2)

    with PACKAGES_YAML.open() as f:
        data = yaml.load(f)

    updated = 0
    skipped = 0
    failed: list[str] = []

    for section in ("cli", "gui"):
        for entry in data["packages"].get(section, []) or []:
            if "description" in entry:
                skipped += 1
                continue

            name = brew_lookup_name(entry)
            is_cask = bool(entry.get("brew_cask"))
            tag = " (cask)" if is_cask else ""
            print(f"-> {entry['name']}{tag}: looking up `{name}`")

            desc = fetch_description(name, is_cask=is_cask)
            if not desc:
                failed.append(entry["name"])
                continue

            # Insert `description` right after `name` for readability, matching
            # the placement of existing entries like `atuin` and `pgcli`.
            keys = list(entry.keys())
            name_idx = keys.index("name")
            entry.insert(name_idx + 1, "description", desc)
            updated += 1
            print(f"   {desc}")

    if updated:
        with PACKAGES_YAML.open("w") as f:
            yaml.dump(data, f)

    print(
        f"\nDone. updated={updated} already_had_desc={skipped} failed={len(failed)}"
    )
    if failed:
        print("Failed lookups: " + ", ".join(failed), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
