# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project Overview

[chezmoi](https://chezmoi.io)-managed dotfiles for developer machines on macOS, Manjaro/Arch, and Ubuntu/Debian. Designed to be runnable inside corporate MITM-proxy environments by injecting a custom CA bundle.

## Common Commands

- `chezmoi apply` — daily command. Works directly on any already-bootstrapped machine.
- `./apply.sh` — first-machine bootstrap. Downloads chezmoi + sops into `.cache/`, builds the trust bundle, runs `chezmoi init`, then `exec`s `chezmoi apply`. After first run, prefer bare `chezmoi apply`.
- `sops edit secrets.yaml` — edit secrets (single sops-encrypted file).
- `chezmoi execute-template < FILE.tmpl` — render a template against current data. Use this to debug template logic before applying.
- `chezmoi diff` — preview pending changes. **Silent: never invokes sops.** Secret decryption happens at apply-time inside `run_onchange_after_gh_setup.sh.tmpl`.
- `bash -n FILE.sh` / `zsh -n FILE.zsh` — syntax-check shell scripts. Recommended after every edit.

### Testing in containers

Smoke-test installs in throwaway containers under `test/{manjaro,ubuntu}/`:

```bash
mise run manjaro    # or: mise run ubuntu
docker compose exec dotfiles2 /home/manjaro/chezmoi/apply.sh
```

- Proxy env vars and `extra_hosts: ["host.docker.internal:host-gateway"]` live in `test/compose.mitm.yaml` (overlay), not the per-distro `compose.yaml`. The `extra_hosts` line is required on Linux Docker so containers can reach the host's mitmproxy.
- Containers bind-mount `~/.config/sops/age/keys.txt` from the host, so the host must have the age key restored before container tests work.

### Testing the mitmproxy cache addon

`test/mitmproxy/cache.py` is an RFC 9111-lite caching addon for `mitmdump`. Notes for agents who need to modify it:

- mitmproxy is installed as a brew **cask** on macOS; its bundled Python is not importable from the system Python. **Pytest requires a venv** with `mitmproxy==12.2.3` + `pytest` installed:
  ```sh
  python3 -m venv /tmp/mitmproxy-venv
  /tmp/mitmproxy-venv/bin/pip install mitmproxy==12.2.3 pytest
  /tmp/mitmproxy-venv/bin/pytest test/mitmproxy/
  ```
- Build mock flows with `mitmproxy.test.tflow`, not hand-rolled mocks.
- mitmproxy 12 removed `ctx.log`; use stdlib `logging.getLogger(__name__)`.
- `flow.metadata` is a usable dict — `cache.py` uses it to thread state across the `request` and `response` hooks.
- **HTTP/2 requires lowercase header names.** `cache.py` sends `if-none-match` / `if-modified-since` lowercase. Tests using `If-None-Match` still pass because mitmproxy's `Headers` is case-insensitive, but real HTTP/2 fails on uppercase.
- Launch the cache locally with `mise run mitmproxy`; wipe it with `mise run mitmproxy-clean` (honors `MITMPROXY_CACHE_DIR`).

## Architecture

**Bootstrap flow (`apply.sh`)** — first-machine only; after that, use bare `chezmoi apply`.

1. Self-execs into bash 5+ (macOS ships bash 3.2; `$EPOCHREALTIME` in `log.sh` needs ≥5). **Don't introduce bash-5-only constructs above the self-exec block (lines 14–21)** — that code still runs under 3.2 on a clean macOS.
2. Sources `scripts/lib/log.sh` (colored `log_*` helpers) and `scripts/lib/github.sh` (`get_github_release` for cached binary downloads).
3. Builds the trust bundle at `~/.local/share/certs/trust-bundle.pem` from `dot_local/share/certs/*.crt`. Exports `SSL_CERT_FILE`, `NIX_SSL_CERT_FILE`, `CURL_CA_BUNDLE`. No-op if no certs.
4. Downloads chezmoi + sops binaries to `.cache/` (early-out if already on PATH).
5. `chezmoi init --force`, then `exec chezmoi apply` — templates are pure (no template-time sops).

**Platform branching** uses `os_like` ∈ {`macos`, `arch`, `debian`}:

- `.chezmoi.toml.tmpl` derives `os_like` from `chezmoi.os` + `chezmoi.osRelease.idLike`.
- Package install is split into per-platform files at `scripts/lib/{macos,arch,debian}/installer.sh`, included by `run_once_install_packages.sh.tmpl` via `{{ includeTemplate (printf "scripts/lib/%s/installer.sh" .os_like) . }}`. Each installer file defines `SYSTEM_PKGS`, name-resolution maps, and the `install_packages` function. Backends: macOS = Homebrew (`brew bundle`); Arch = yay; Debian = apt + Nix single-user (`nix profile add nixpkgs#…`).

**ZSH plugin layer** (no zinit/antigen)

- OMZ + third-party plugins are downloaded as tarball externals via `.chezmoiexternals/zsh-plugins.toml.tmpl` into `~/.zsh-plugins/`.
- `dot_zshrc.tmpl` sets up `fpath`, runs `compinit` *early* (OMZ libs/plugins call `compdef`, which only exists after compinit), then sources OMZ libs → OMZ plugins → third-party plugins. **Order constraint: `fast-syntax-highlighting` must be last.**
- Tool-specific shell setup lives in `dot_zsh/integrations/<tool>.zsh`. `dot_zshrc.tmpl` (line 49) auto-discovers them with `{{ glob }}` at apply time — drop a new file in the dir, no zshrc edit needed.

**Tmux plugins**: same archive-externals model — listed in `.chezmoidata/tmux.yaml`, downloaded via `.chezmoiexternals/tmux-plugins.toml.tmpl`, sourced from `dot_config/tmux/tmux.conf.tmpl`.

**Cert / proxy CA management**

- Drop `*.crt` files in `dot_local/share/certs/` → applied to `~/.local/share/certs/`.
- `apply.sh` writes `~/.local/share/certs/trust-bundle.pem` on first bootstrap. The two literal paths (`certs_dir_rel`, `bundle_filename`) live in `.chezmoidata/trust.yaml`; templates resolve them via `joinPath .chezmoi.homeDir .trust.*`. `apply.sh` duplicates them with a sync comment (bootstrap chicken-and-egg).
- `dot_zsh/integrations/{nodejs,python}.zsh.tmpl` point `NODE_EXTRA_CA_CERTS` and `REQUESTS_CA_BUNDLE` at the bundle.
- `run_once_before_install_packages.sh.tmpl:install_system_certs` registers each `.crt` with the system trust store on Linux (auto-detects `update-ca-trust` on Arch vs `update-ca-certificates` on Debian). Reads from `.chezmoi.sourceDir/dot_local/share/certs` because `run_*before_*` scripts execute before file deployment.
- `dot_local/bin/executable_jvm-import-pem-cacerts.zsh.tmpl` syncs certs into a JVM `cacerts` keyed by SHA-1 fingerprint (idempotent). Invoked from the mise post-install hook for each newly-installed Java install (the hook iterates `$MISE_INSTALLED_TOOLS`, not `mise where java`).

**Secrets** (sops + age)

- `secrets.yaml` is sops-encrypted to a single age recipient. The recipient list is declared in `.sops.yaml`.
- The age identity (`~/.config/sops/age/keys.txt`) is **user-managed**: restored from a password manager on each new machine. The private key never enters the repo.
- Templates are pure — no sops invocation at template-resolution time. `chezmoi diff` / `status` / `cat` never touch sops.
- `run_onchange_after_gh_setup.sh.tmpl` calls `sops --decrypt --extract '["GITHUB_TOKEN"]' …` at script-execution time and pipes the token into `gh auth login --with-token`. Sets `SOPS_AGE_KEY_FILE` explicitly to the XDG path, since sops's default on macOS is `~/Library/Application Support/sops/age/keys.txt`. The `run_onchange_` prefix means chezmoi only re-runs the script when its rendered hash changes; the rendered body embeds the sha256 of `secrets.yaml`'s ciphertext so re-encryption (e.g. after `sops edit`, which is when token rotation actually happens) triggers a re-run. Manual recovery (e.g. token revoked server-side without a `sops edit`): run the script directly, or `sops edit` and save without changes to force re-encryption.

## Conventions

- **Bash 5+ required.** `apply.sh` self-execs `/opt/homebrew/bin/bash` on macOS to satisfy this (Apple ships bash 3.2; `$EPOCHREALTIME` in `log.sh` needs ≥5).
- **`set -euo pipefail` is standard.** Under errexit:
  - **Prefer `(( ++var ))` over `(( var++ ))`** — post-increment exposes the pre-value, so the first increment when `var=0` evaluates to 0 (false) and trips errexit. Same trap for any `(( expr ))` whose result might be zero.
  - Split `export VAR=$(cmd)` into two lines (`VAR=$(cmd)` then `export VAR`) so errexit catches subcommand failures.
- **`scripts/` is in `.chezmoiignore`** — treated as a source-only library directory, not deployed to home. Files there are sourced from `apply.sh` directly or templated into managed scripts via `{{ include }}` / `{{ includeTemplate }}`.
- **`run_*before_*` scripts execute before file deployment.** Read source data from `.chezmoi.sourceDir`, not from `~`. The user's home tree doesn't exist yet at that point.
- **`dot_zsh/integrations/*.zsh`** is glob-discovered at apply time. Adding a new tool integration means dropping a file there — no other edits.
- **Per-platform installer files** are templates, not standalone shell scripts. They reference `CLI_PKGS`, `GUI_PKGS`, `resolve_name` from the parent run_once script (which sources the lib via `includeTemplate`).
- **Minimum chezmoi version**: `2.36.0` (`.chezmoiexternals/` directory). `apply.sh` pins `2.70.3`.
- **Trust paths**: source of truth is `.chezmoidata/trust.yaml` (`certs_dir_rel`, `bundle_filename`). Templates use `joinPath .chezmoi.homeDir .trust.*`. `apply.sh` hardcodes the same paths with a sync comment because bootstrap runs before chezmoi data is available. **If you change one, change the other.**

## Agent skills

### Issue tracker

Issues live in GitHub Issues on `eliezio/dotfiles` (uses the `gh` CLI). See `docs/agents/issue-tracker.md`.

### Triage labels

Canonical names used unchanged (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.

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

## Rule 5 — Use the model only for judgment calls
Use me for: classification, drafting, summarization, extraction.
Do NOT use me for: routing, retries, deterministic transforms.
If code can answer, code answers.

## Rule 6 — Token budgets are not advisory
Per-task: 4,000 tokens. Per-session: 30,000 tokens.
If approaching budget, summarize and start fresh.
Surface the breach. Do not silently overrun.

## Rule 7 — Surface conflicts, don't average them
If two patterns contradict, pick one (more recent / more tested).
Explain why. Flag the other for cleanup.
Don't blend conflicting patterns.

## Rule 8 — Read before you write
Before adding code, read exports, immediate callers, shared utilities.
"Looks orthogonal" is dangerous. If unsure why code is structured a way, ask.

## Rule 9 — Tests verify intent, not just behavior
Tests must encode WHY behavior matters, not just WHAT it does.
A test that can't fail when business logic changes is wrong.

## Rule 10 — Checkpoint after every significant step
Summarize what was done, what's verified, what's left.
Don't continue from a state you can't describe back.
If you lose track, stop and restate.

## Rule 11 — Match the codebase's conventions, even if you disagree
Conformance > taste inside the codebase.
If you genuinely think a convention is harmful, surface it. Don't fork silently.

## Rule 12 — Fail loud
"Completed" is wrong if anything was skipped silently.
"Tests pass" is wrong if any were skipped.
Default to surfacing uncertainty, not hiding it.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.
