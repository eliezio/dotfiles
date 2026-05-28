# chezmoi dotfiles — Context

Domain vocabulary for this dotfiles repo. Project-specific terms only — general programming concepts are out of scope.

## Language

**Trust roots**:
The individual `*.crt` files under `dot_local/share/certs/` (source state) and `$XDG_DATA_HOME/certs/` (deployed). Canonical source-of-truth for CA trust in this repo — everything else is derived.
_Avoid_: certs, certificates, CA files (too generic).

**Trust bundle**:
A single concatenated PEM file at `$XDG_DATA_HOME/certs/trust-bundle.pem`, built from the trust roots. Exists only because some runtimes (Node `NODE_EXTRA_CA_CERTS`, Python `REQUESTS_CA_BUNDLE`, curl, Nix) take one file path, not a directory. Derived; never source-of-truth.
_Avoid_: CA bundle, trust-bundle.pem (filename, not concept).

**Trust paths**:
The two literal strings (`certs_dir_rel`, `bundle_filename`) that locate the trust roots and bundle. Source-of-truth is `.chezmoidata/trust.yaml`; templates resolve them via `joinPath .chezmoi.homeDir .trust.*`. `apply.sh` duplicates them as bash constants with a sync comment, because it runs before chezmoi is available.

**Bootstrap**:
The work `apply.sh` does on a fresh machine before `chezmoi apply` can run: self-exec into bash 5+, download chezmoi+sops to `.cache/`, build the trust bundle, `chezmoi init`, then `exec chezmoi apply`. Idempotent; safe to re-run.

**Daily apply**:
After bootstrap, the user runs `chezmoi apply` directly. No wrapper. Templates are pure (no secret-decryption at template-resolution time); the only sops invocation is in `run_after_secrets.sh.tmpl` at script-execution time.

**Age identity**:
The user-managed file at `~/.config/sops/age/keys.txt`, restored from a password manager on each new machine. It is the **sole** identity that can decrypt `secrets.yaml`. The repo never sees the private key. `.sops.yaml` lists only the corresponding public key as a recipient.
_Note_: On macOS, sops's default lookup path is `~/Library/Application Support/sops/age/keys.txt`. We standardise on the XDG path across all OSes and `run_after_secrets.sh.tmpl` sets `SOPS_AGE_KEY_FILE` explicitly.

## Example

> **Maintainer A:** Why does `apply.sh` know about `.local/share/certs/trust-bundle.pem` when `.chezmoidata/trust.yaml` already declares it?
>
> **Maintainer B:** Bootstrap chicken-and-egg. `apply.sh` builds the trust bundle before chezmoi is downloaded, so it can't read the chezmoi data file yet. The two locations are duplicated with a sync comment. Templates read from `.chezmoidata/trust.yaml`; only `apply.sh` duplicates.
>
> **A:** And secrets?
>
> **B:** `secrets.yaml` is encrypted with sops to a single age recipient. The private key (`~/.config/sops/age/keys.txt`) is restored manually from a password manager — never in the repo. `chezmoi apply` resolves templates without touching sops; the only sops call is in `run_after_secrets.sh.tmpl`, which decrypts at execution time and pipes the token into `gh auth login`. `chezmoi diff` / `status` / `cat` never call sops.
