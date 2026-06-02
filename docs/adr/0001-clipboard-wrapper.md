# Clipboard wrapper (`clip`) for runtime backend selection

A single machine — e.g. the Arch desktop — is used both at the console and over SSH. The chezmoi-template-time check that previously decided "use lemonade if SSH" baked the choice in at apply time and was wrong half the time. We replaced it with a small POSIX-sh wrapper at `~/.local/bin/clip` that picks the backend at each invocation (SSH/WSL/container → `lemonade`; else macOS → `pbcopy`; else Linux → `xclip`). Lazygit and the `pbcopy`/`pbpaste` shell aliases call `clip`; one policy everywhere.

## Considered alternatives

- **OMZ's `clipboard.zsh`** (already in `~/.zsh-plugins/oh-my-zsh/`). Defines `clipcopy`/`clippaste` as zsh *functions*, so they aren't reachable from lazygit's `/bin/sh` subprocess. Its detection order also prefers `wl-copy`/`xclip` over `lemonade`, which is the wrong priority under SSH for our setup.
- **Shadowing `pbcopy`/`pbpaste` on `$PATH`.** Rejected — silently overriding a system binary is a debugging trap. We alias instead, keeping `/usr/bin/pbcopy` untouched.
- **Keeping the chezmoi template-time gate.** Rejected — fundamentally can't represent "this machine, accessed both ways" in a single rendered file.
