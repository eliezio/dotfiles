# Honored by ls, tree, cmake, and other tools
export CLICOLOR=1

# Provide pbcopy/pbpaste on platforms that lack them (Linux), backed by
# oh-my-zsh's clipcopy/clippaste from lib/clipboard.zsh.
if (( ! $+commands[pbpaste] )); then
  alias pbcopy=clipcopy
  alias pbpaste=clippaste
fi

# vim:ft=zsh
