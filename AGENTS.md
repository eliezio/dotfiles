# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project Overview

[chezmoi](https://chezmoi.io)-managed dotfiles for developer machines on macOS, Manjaro/Arch, Ubuntu/Debian, and Aurora (atomic Fedora). Designed to be runnable inside corporate MITM-proxy environments by injecting a custom CA bundle.

## Common Commands

- `chezmoi apply` — daily command. Works directly on any already-bootstrapped machine.
- `./apply.sh` — first-machine bootstrap. Downloads chezmoi + sops into `.cache/${os}_${arch}/`, builds the trust bundle, runs `chezmoi init`, then `exec`s `chezmoi apply`. After first run, prefer bare `chezmoi apply`.
- `./apply.sh --skip-certs` — same, but leaves the custom CAs in `dot_local/share/certs/` out entirely: no trust bundle, no system trust store, nothing deployed to `~/.local/share/certs`. Stored as `skip_certs` in chezmoi's config data (sticky across `chezmoi init`); `DOTFILES_SKIP_CERTS=0 ./apply.sh` re-enables. Other arguments pass through to `chezmoi apply`.
- `./remove-legacy-packages.sh` — one-off cleanup after moving a machine to mise: offers, one `[y/N/q]` prompt each, to remove the Homebrew / pacman / Nix-profile packages that mise tools now replace (only when mise already has the replacement installed), plus tools the dotfiles dropped (curlie, httpie, lemonade, tmux). Old names that differ from `packages.cli` names live in its `LEGACY_*` tables, dropped tools in `DROPPED_*`. chezmoi runs it once per machine via `run_once_after_10_remove_legacy_packages.sh.tmpl` (after `00_install_mise_tools`; skipped when there is no terminal, e.g. `docker exec` without `-t`).
- `scripts/apt-repo-policy/` — third-party APT repo policy for Debian proper (not Ubuntu): default-deny pins, per-repo allow-lists, audit. See its README. Installed to `/etc/apt` and `/usr/local/sbin` by `run_onchange_after_20_apt_repo_policy.sh.tmpl`; a new `50-*.pref` needs a hash line there.
- `sops edit secrets.yaml` — edit secrets (single sops-encrypted file).
- `chezmoi execute-template < FILE.tmpl` — render a template against current data. Use this to debug template logic before applying.
- `chezmoi diff` — preview pending changes. **Invokes sops** (and so needs the age key) because templates decrypt at render time via `[secret] command = "sops"`. The rendered gh-setup script — including the plaintext token — shows in the diff.
- `bash -n FILE.sh` / `zsh -n FILE.zsh` — syntax-check shell scripts. Recommended after every edit.

### Testing in containers

Smoke-test installs in throwaway containers under `test/{debian,manjaro,ubuntu}/`:

```bash
mise run manjaro    # or: mise run ubuntu / mise run debian
docker compose exec dotfiles2 bash -c 'umask 022 && exec ~/.local/share/chezmoi/apply.sh'
```

- The explicit `umask 022` works around OrbStack: its VM runs `dockerd`/`containerd`/the shims with umask `0000` (a systemd-managed `dockerd` gets `0022`), and `docker exec` processes inherit it, while runc resets only PID 1 to `0022`. Without it every file `apply.sh` creates is world-writable and zsh's `compinit` rejects `~/.zsh-plugins` as insecure. Harmless on engines that already use `0022`.

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
2. Sources `scripts/lib/log.sh` (colored `log_*` helpers). Downloads chezmoi and sops with `curl` into `$CACHE_DIR/${os}_${arch}/` (skipped if on PATH or cached), and rejects any download whose SHA-256 differs from the pin in `PIN_SHA256`. Tags, pins and download functions live in `scripts/lib/pinned.sh`, shared with `reset-secrets.sh` (which also fetches age). Bumping a version means updating its tag and its four pins; the `gh api` commands that print them sit next to the table.
3. Builds the trust bundle at `~/.local/share/certs/trust-bundle.pem` from `dot_local/share/certs/*.crt`. Exports `SSL_CERT_FILE`, `CURL_CA_BUNDLE`. No-op if no certs.
4. Downloads chezmoi + sops binaries to `.cache/${os}_${arch}/` (early-out if already on PATH).
5. Exports `SOPS_AGE_KEY_FILE` (XDG path) so chezmoi's secret subprocess can decrypt during rendering, then `chezmoi init --force` and `exec chezmoi apply`.

**Platform branching** uses `os_like` ∈ {`macos`, `arch`, `debian`, `fedora`}:

- `.chezmoi.toml.tmpl` derives `os_like` from `chezmoi.os` + `chezmoi.osRelease.idLike` (plus `id` for Debian and Fedora, whose os-release has no `ID_LIKE`).
- **CLI tools (`packages.cli`) are installed by mise on every platform**, always at `latest`. Each entry names its backend explicitly in `mise:` (prefer `aqua:`). `dot_config/mise/conf.d/packages.toml.tmpl` renders them into a global mise config (kept out of `config.toml` so `mise use -g` still works); `run_onchange_after_00_install_mise_tools.sh.tmpl` runs `mise install` whenever that rendered list changes. Updates: `topgrade` (mise step), followed by the global task `mise run audit` (`dot_config/mise/tasks/executable_audit`): a red/amber/green report on upstream health, repo-identity changes (pinned in `~/.local/state/mise-audit/identity.json`), download verification and runtime EOL. No CVE scanning yet.
- System and GUI packages are split into per-platform files at `scripts/lib/{macos,arch,debian,fedora}/installer.sh`, included by `run_once_before_install_packages.sh.tmpl` via `{{ includeTemplate (printf "scripts/lib/%s/installer.sh" .os_like) . }}`. Each defines `SYSTEM_PKGS`, `install_system_packages` (must leave `mise` installed) and `install_gui_packages`. Backends: macOS = Homebrew (`brew bundle`); Arch = pacman (no AUR) + the `mise.run` installer; Debian = apt + the `mise.run` installer (shared `install_mise` in `scripts/lib/mise_run.sh`; Manjaro's mise package lags weeks behind); Fedora = Aurora's bundled Homebrew (the image is read-only, so no dnf). Debian and Fedora have no GUI source and log what they skip.

**ZSH plugin layer** (no zinit/antigen)

- OMZ + third-party plugins are downloaded as tarball externals via `.chezmoiexternals/zsh-plugins.toml.tmpl` into `~/.zsh-plugins/`.
- `dot_zshrc.tmpl` sets up `fpath`, runs `compinit` *early* (OMZ libs/plugins call `compdef`, which only exists after compinit), then sources OMZ libs → OMZ plugins → third-party plugins. **Order constraint: `fast-syntax-highlighting` must be last.**
- Tool-specific shell setup lives in `dot_zsh/integrations/<tool>.zsh`. `dot_zshrc.tmpl` (line 49) auto-discovers them with `{{ glob }}` at apply time — drop a new file in the dir, no zshrc edit needed.

**Cert / proxy CA management**

- Drop `*.crt` files in `dot_local/share/certs/` → applied to `~/.local/share/certs/`.
- `apply.sh` writes `~/.local/share/certs/trust-bundle.pem` on first bootstrap. The two literal paths (`certs_dir_rel`, `bundle_filename`) live in `.chezmoidata/trust.yaml`; templates resolve them via `joinPath .chezmoi.homeDir .trust.*`. `apply.sh` duplicates them with a sync comment (bootstrap chicken-and-egg).
- `dot_zsh/integrations/{nodejs,python}.zsh.tmpl` point `NODE_EXTRA_CA_CERTS` and `REQUESTS_CA_BUNDLE` at the bundle.
- `run_once_before_install_packages.sh.tmpl:install_system_certs` registers each `.crt` with the system trust store on Linux (auto-detects `update-ca-trust` on Arch vs `update-ca-certificates` on Debian). Reads from `.chezmoi.sourceDir/dot_local/share/certs` because `run_*before_*` scripts execute before file deployment.
- `dot_local/bin/executable_jvm-import-pem-cacerts.zsh.tmpl` syncs certs into a JVM `cacerts` keyed by SHA-1 fingerprint (idempotent). Invoked from the mise post-install hook for each newly-installed Java install (the hook iterates `$MISE_INSTALLED_TOOLS`, not `mise where java`).

**Secrets** (sops + age)

- `secrets.yaml` is sops-encrypted to a single age recipient. The recipient list is declared in `.sops.yaml`.
- The age identity (`~/.config/sops/age/keys.txt`) is **user-managed**: restored from a password manager on each new machine. The private key never enters the repo.
- Decryption happens at **template-render time** via chezmoi's secret function: `[secret] command = "sops"` (in `.chezmoi.toml.tmpl`) wires up the `secret`/`secretJSON` template functions to shell out to sops. Consequence: any template operation that renders the gh-setup script — `chezmoi apply` / `diff` / `status` / `execute-template` — invokes sops and **requires the age key**, and the **plaintext token appears in rendered output** (chezmoi does not redact secret-function results).
- `SOPS_AGE_KEY_FILE` must be in chezmoi's environment for the sops subprocess to find the key (sops's default on macOS is `~/Library/Application Support/sops/age/keys.txt`, not the XDG path this repo uses). It's exported in `dot_zsh/integrations/sops.zsh` for interactive runs and in `apply.sh` for the bootstrap run.
- `run_onchange_after_gh_setup.sh.tmpl` reads the token with `secretJSON "-d" "--output-type=json" secrets.yaml` and feeds it to `gh auth login --with-token` via a here-string. The `run_onchange_` prefix means chezmoi re-runs the script when its rendered body changes — and since the body embeds the token value, **rotation re-triggers it automatically** (re-encryption alone, without a value change, does not).

## Conventions

- **Bash 5+ required.** `apply.sh` resolves bash via `brew --prefix` (Apple ships bash 3.2; `$EPOCHREALTIME` in `log.sh` needs ≥5).
- **`set -euo pipefail` is standard.** Under errexit:
  - **Prefer `(( ++var ))` over `(( var++ ))`** — post-increment exposes the pre-value, so the first increment when `var=0` evaluates to 0 (false) and trips errexit. Same trap for any `(( expr ))` whose result might be zero.
  - Split `export VAR=$(cmd)` into two lines (`VAR=$(cmd)` then `export VAR`) so errexit catches subcommand failures.
- **`scripts/` is in `.chezmoiignore`** — treated as a source-only library directory, not deployed to home. Files there are sourced from `apply.sh` directly or templated into managed scripts via `{{ include }}` / `{{ includeTemplate }}`.
- **`run_*before_*` scripts execute before file deployment.** Read source data from `.chezmoi.sourceDir`, not from `~`. The user's home tree doesn't exist yet at that point.
- **`dot_zsh/integrations/*.zsh`** is glob-discovered at apply time. Adding a new tool integration means dropping a file there — no other edits.
- **Per-platform installer files** are templates, not standalone shell scripts. They read `GUI_PKGS` from the parent run_once script (which sources the lib via `includeTemplate`) and define `install_system_packages` / `install_gui_packages`; `install_mise` comes from `scripts/lib/mise_run.sh`.
- **Minimum chezmoi version**: `2.36.0` (`.chezmoiexternals/` directory). `scripts/lib/pinned.sh` pins the bootstrap version (`CHEZMOI_TAG`).
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
