# Standardise on the XDG path across all OSes; sops's default on macOS is
# ~/Library/Application Support/sops/age/keys.txt. Exporting it here also lets
# chezmoi's [secret] sops subprocess find the key during template rendering.
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
