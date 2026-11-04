# apt-repo-policy

Keeps third-party APT repositories on this Debian machine on a short leash. The
policy holds for repositories you add later, not just the ones present today.

## The policy

Every repository that isn't Debian's must:

1. **Be a DEB822 `.sources` file** in `/etc/apt/sources.list.d/`. No one-line
   `.list` files, and no third-party lines in `/etc/apt/sources.list`.
2. **Name its own key** with `Signed-By:`, stored under `/etc/apt/keyrings/` or
   `/usr/share/keyrings/`. No key may sit in `/etc/apt/trusted.gpg` or
   `/etc/apt/trusted.gpg.d/`, because APT trusts keys there for *every*
   repository. The only keys allowed there are `debian-archive-*`.
3. **List its `Components:`**. A flat repository can't be scoped to one component.
4. **Supply only allow-listed packages.** `zz-default-deny.pref` gives every
   non-Debian origin priority -1. A repository supplies nothing until
   `apt-repo-allow` names the packages it may provide, and a name that Debian
   also ships can never be allowed. This makes the policy fail closed: if you
   add a repository and forget the rest, nothing gets installed from it.

`apt-repo-audit` checks points 1 to 4, plus the pin files themselves. It runs
after every successful `apt update` through `APT::Update::Post-Invoke-Success`.
It only warns, so it never blocks unattended-upgrades.

## Files

| Path | Installed to | Role |
|---|---|---|
| `etc/apt/preferences.d/00-debian.pref` | `/etc/apt/preferences.d/` | Debian origin at 500 |
| `etc/apt/preferences.d/zz-default-deny.pref` | `/etc/apt/preferences.d/` | every other origin at -1 |
| `etc/apt/apt.conf.d/99apt-repo-audit` | `/etc/apt/apt.conf.d/` | runs the audit after `apt update` |
| `etc/apt/preferences.d/50-*.pref` | `/etc/apt/preferences.d/` | per-repo allow-lists, inert when the repo is absent |
| `sbin/apt-repo-audit` | `/usr/local/sbin/` | policy checker |
| `sbin/apt-repo-allow` | `/usr/local/sbin/` | writes `50-<name>.pref` allow-lists |
| `tests/run.sh` | — | offline tests against fixture trees |

The file names matter. Among the catch-all `Package: *` records, the **first
match wins**, and APT reads `preferences.d` in alphabetical order. So
`00-debian` must sort before `zz-default-deny`. The per-package records in
`50-*.pref` override both, whatever their position.

## Adding a repository

The vendor's instructions usually say `curl | gpg --dearmor > /etc/apt/trusted.gpg.d/...`
plus a `.list` line. Do this instead:

```sh
# 1. key: dedicated file; check its fingerprint against the vendor's docs
curl -fsSL https://apt.example.com/key.asc | sudo tee /etc/apt/keyrings/example.asc >/dev/null
gpg --show-keys /etc/apt/keyrings/example.asc

# 2. source: DEB822, scoped
sudo tee /etc/apt/sources.list.d/example.sources <<'EOF'
X-Repolib-Name: Example
Enabled: yes
Types: deb
URIs: https://apt.example.com/debian
Suites: stable
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/example.asc
EOF

# 3. fetch the index; the audit warns that the host has no allow-list yet
sudo apt update

# 4. see what the repository offers, then allow only what you need
apt-repo-allow --list apt.example.com
sudo apt-repo-allow example apt.example.com example-tool example-tool-cli

sudo apt install example-tool
```

The host is the hostname in `URIs:`, which is what APT's `origin` pin matches.
Two repositories on the same host, such as Claude Code and Claude Desktop on
`downloads.claude.ai`, share one allow-list.

## Troubleshooting

- **"has no installation candidate"**, or an upgrade fails on a missing
  dependency: the vendor added a package. Check `apt-repo-allow --list <host>`,
  then rerun `apt-repo-allow` with the full list. The command replaces the
  file, so include the existing names too.
- **Checking a package's priority:** `apt-cache policy <pkg>`. The number next
  to each version is that version's real priority. The indented number under it
  is the repository's priority, which stays at -1 for third-party repos even
  when the package is allowed.
- **A package installer recreated a `.list` file or a key in `trusted.gpg.d`:**
  the audit reports it on the next `apt update`. Delete it, since the `.sources`
  file already covers it.
  `claude-desktop` and `brave-keyring` both detect an existing `.sources` file
  and leave it alone. Set `CLAUDE_DESKTOP_ADD_REPO=false` in
  `/etc/default/claude-desktop` to make that certain.

## Install / test

```sh
tests/run.sh          # offline; no root needed
sudo ./install.sh     # installs, audits; tests are separate
```

## chezmoi

This directory lives in the dotfiles source under `scripts/`, which
`.chezmoiignore` keeps out of `$HOME`. `run_onchange_after_20_apt_repo_policy.sh.tmpl`
runs `install.sh` with `sudo` whenever a hashed file changes, on Debian proper
only. It must not run on Ubuntu: its archive has `o=Ubuntu`, so
`zz-default-deny.pref` would pin the whole distribution to -1.

`apt-repo-allow` writes to `/etc`, so after using it copy the result back:

```sh
cp /etc/apt/preferences.d/50-<name>.pref scripts/apt-repo-policy/etc/apt/preferences.d/
```

A new file also needs a hash line in the run script, or changes to it won't
re-trigger the install.
