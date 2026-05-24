# chezmoi dotfiles — Context

Domain vocabulary for this dotfiles repo. Project-specific terms only — general programming concepts are out of scope.

## Language

**Trust roots**:
The individual `*.crt` files under `dot_local/share/certs/` (source state) and `$XDG_DATA_HOME/certs/` (deployed). Canonical source-of-truth for CA trust in this repo — everything else is derived.
_Avoid_: certs, certificates, CA files (too generic).

**Trust bundle**:
A single concatenated PEM file at `$XDG_DATA_HOME/certs/certs-bundle.pem`, built from the trust roots. Exists only because some runtimes (Node `NODE_EXTRA_CA_CERTS`, Python `REQUESTS_CA_BUNDLE`, curl, Nix) take one file path, not a directory. Derived; never source-of-truth.
_Avoid_: CA bundle, certs-bundle.pem (filename, not concept).

**Apply phase**:
Execution context during `chezmoi apply` — bash scripts (`apply.sh`, `run_once_*.sh.tmpl`) running with `$CERTS_SOURCE_DIR` pointing at the chezmoi source state. Trust roots read from there because deployed files may not exist yet.
_Avoid_: bootstrap (overloaded — apply.sh has its own bootstrap step for chezmoi/sops binaries).

**Runtime phase**:
Execution context after apply has finished — interactive shells, mise hooks, the JVM truststore sync. Trust roots read from the deployed `$XDG_DATA_HOME/certs/`. `$CERTS_SOURCE_DIR` must not be relied on here.

## Example

> **Maintainer A:** Why does `apply.sh` read certs from `dot_local/share/certs/` but `nodejs.zsh` reads them from `~/.local/share/certs/`?
>
> **Maintainer B:** They're in different phases. `apply.sh` is the apply phase — the deployed dir might not exist yet, so it reads trust roots straight from the chezmoi source state via `$CERTS_SOURCE_DIR`. `nodejs.zsh` is runtime phase, so it points at the deployed dir.
>
> **A:** And the bundle?
>
> **B:** The trust bundle is derived from the trust roots — `apply.sh` builds it once at the end of the apply phase. Node and Python read it from the deployed path because they want a single file, not a directory. The JVM script doesn't use the bundle at all; it imports each trust root by SHA-1 fingerprint.
