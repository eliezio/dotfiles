# Clipboard wrapper (`clip`) for runtime backend selection

A single machine — e.g. the Arch desktop — is used both at the console and over SSH. The chezmoi-template-time check that previously decided "use lemonade if SSH" baked the choice in at apply time and was wrong half the time. We replaced it with a small POSIX-sh wrapper at `~/.local/bin/clip` that picks the backend at each invocation (SSH/WSL/container → OSC 52; else macOS → `pbcopy`; else Linux → `xclip`). Lazygit and the `pbcopy`/`pbpaste` shell aliases call `clip`; one policy everywhere.

In a remote session `clip copy` emits an OSC 52 escape sequence on `/dev/tty`, asking the local terminal to set its clipboard. `clip paste` fails there with a message: OSC 52 reads are denied or prompted by most terminals, so remote paste goes through the terminal's own paste.

## Considered alternatives

- **OMZ's `clipboard.zsh`** (already in `~/.zsh-plugins/oh-my-zsh/`). Defines `clipcopy`/`clippaste` as zsh *functions*, so they aren't reachable from lazygit's `/bin/sh` subprocess. Its detection order also prefers `wl-copy`/`xclip` over `lemonade`, which is the wrong priority under SSH for our setup.
- **Shadowing `pbcopy`/`pbpaste` on `$PATH`.** Rejected — silently overriding a system binary is a debugging trap. We alias instead, keeping `/usr/bin/pbcopy` untouched.
- **Keeping the chezmoi template-time gate.** Rejected — fundamentally can't represent "this machine, accessed both ways" in a single rendered file.
- **`lemonade` for the remote case** (the original backend). Dropped 2026-11: upstream's last release is from 2016 and OpenSSF Scorecard rates it unmaintained, and it needs a server on the local machine plus a forwarded TCP port. OSC 52 needs neither, at the cost of remote paste.
