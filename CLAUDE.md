# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

[chezmoi](https://chezmoi.io)-managed dotfiles for developer machines on macOS, Manjaro/Arch, and Ubuntu/Debian. Designed to be runnable inside corporate MITM-proxy environments by injecting a custom CA bundle.

## Common Commands

- `./apply.sh` — sole entrypoint. Downloads chezmoi + sops into `.cache/`, runs `chezmoi init`, then one secrets-aware `chezmoi apply` (no two-phase bootstrap).
- `chezmoi execute-template < FILE.tmpl` — render a template against current data. Use this to debug template logic before applying.
- `chezmoi diff` — preview pending changes.
- `bash -n FILE.sh` / `zsh -n FILE.zsh` — syntax-check shell scripts. Recommended after every edit.

### Testing in containers

Smoke-test installs in throwaway containers under `test/{manjaro,ubuntu}/`:

```bash
cd test/manjaro && docker compose up -d
docker compose exec dotfiles2 /home/manjaro/chezmoi/apply.sh
```

Both compose files mount the chezmoi source as a volume and bake in proxy env vars (`http_proxy=http://host.docker.internal:3128`). The `extra_hosts: ["host.docker.internal:host-gateway"]` line is required on Linux Docker.

## Architecture

**Bootstrap flow (`apply.sh`)**

1. Sources `scripts/lib/log.sh` (colored `log_*` helpers + `run_stage`/`review_logs`) and `scripts/lib/github.sh` (`get_github_release` for cached binary downloads).
2. Builds a user CA bundle at `~/.local/share/certs/certs-bundle.pem` from `dot_local/share/certs/*.crt`. Exports `SSL_CERT_FILE`, `NIX_SSL_CERT_FILE`, `CURL_CA_BUNDLE`. No-op if no certs.
3. Downloads chezmoi + sops binaries to `.cache/` (early-out if already on PATH or cached).
4. `chezmoi init --force`, then `sops exec-env … chezmoi apply` — secrets templated in one pass.

**Platform branching** uses `os_like` ∈ {`macos`, `arch`, `debian`}:

- `.chezmoi.toml.tmpl` derives `os_like` from `chezmoi.os` + `chezmoi.osRelease.idLike`.
- Package install is split into per-platform files at `scripts/lib/{macos,arch,debian}/installer.sh`, included by `run_once_install_packages.sh.tmpl` via `{{ includeTemplate (printf "scripts/lib/%s/installer.sh" .os_like) . }}`. Each installer file defines `SYSTEM_PKGS`, name-resolution maps, and the `install_packages` function. Backends: macOS = Homebrew (`brew bundle`); Arch = yay; Debian = apt + Nix single-user (`nix profile add nixpkgs#…`).

**ZSH plugin layer** (no zinit/antigen)

- OMZ + third-party plugins are downloaded as tarball externals via `.chezmoiexternals/zsh-plugins.toml.tmpl` into `~/.zsh-plugins/`.
- `dot_zshrc.tmpl` sets up `fpath`, runs `compinit` *early* (OMZ libs/plugins call `compdef`, which only exists after compinit), then sources OMZ libs → OMZ plugins → third-party plugins. **Order constraint: `fast-syntax-highlighting` must be last.**
- Tool-specific shell setup lives in `dot_zsh/integrations/<tool>.zsh`. `dot_zshrc.tmpl` auto-discovers them with `{{ glob }}` at apply time — drop a new file in the dir, no zshrc edit needed.

**Tmux plugins**: same archive-externals model — listed in `.chezmoidata/tmux.yaml`, downloaded via `.chezmoiexternals/tmux-plugins.toml.tmpl`, sourced from `dot_config/tmux/tmux.conf.tmpl`.

**Cert / proxy CA management**

- Drop `*.crt` files in `dot_local/share/certs/` → applied to `~/.local/share/certs/`.
- `apply.sh` writes the user bundle to `~/.local/share/certs/certs-bundle.pem`. `dot_zsh/integrations/{nodejs,python}.zsh` point `NODE_EXTRA_CA_CERTS` and `REQUESTS_CA_BUNDLE` at it.
- `run_once_install_packages.sh.tmpl:install_system_certs` registers each `.crt` with the system trust store on Linux (auto-detects `update-ca-trust` on Arch vs `update-ca-certificates` on Debian).
- `dot_local/bin/executable_jvm-import-pem-cacerts.zsh` syncs certs into a JVM `cacerts` keyed by SHA-1 fingerprint (idempotent). Invoked from the mise post-install hook for each newly-installed Java install (the hook iterates `$MISE_INSTALLED_TOOLS`, not `mise where java`).

**Secrets** (sops + age)

- `secrets.yaml` is sops-encrypted, decrypted via `scripts/bin/decrypt-ssh-key.sh` using the user's SSH key as the age identity.
- Every chezmoi apply runs inside `sops exec-env`, so secret env vars are available in templates without a separate decryption step.
- `run_after_secrets.sh.tmpl` runs post-apply; uses `$GITHUB_TOKEN` from sops to re-auth `gh` CLI.

## Conventions

- **Bash 4+ required.** `run_once_install_packages.sh.tmpl` self-execs `/opt/homebrew/bin/bash` on macOS to satisfy this (Apple ships bash 3.2 — no associative arrays).
- **`set -euo pipefail` is standard.** Under errexit, **prefer `(( ++var ))` over `(( var++ ))`** — post-increment exposes the pre-value, so the first increment when `var=0` evaluates to 0 (false) and trips errexit. Same trap for any `(( expr ))` whose result might be zero.
- **`scripts/` is in `.chezmoiignore`** — treated as a source-only library directory, not deployed to home. Files there are sourced from `apply.sh` directly or templated into managed scripts via `{{ include }}` / `{{ includeTemplate }}`.
- **`dot_zsh/integrations/*.zsh`** is glob-discovered at apply time. Adding a new tool integration means dropping a file there — no other edits.
- **Per-platform installer files** are templates, not standalone shell scripts. They reference `CLI_PKGS`, `GUI_PKGS`, `resolve_name` from the parent run_once script (which sources the lib via `includeTemplate`).
- **Minimum chezmoi version**: `2.36.0` (`.chezmoiexternals/` directory). `apply.sh` pins `2.70.2`.
- **Certs**: source-state path is `dot_local/share/certs/*.crt`. The `.pem` extension is intentionally not globbed (the bundle is a `.pem` co-located there; this prevents recursive imports).

---

# Behavioral guidelines

These guidelines reduce common LLM coding mistakes; they apply on top of the project context above. Bias toward caution over speed; for trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.
