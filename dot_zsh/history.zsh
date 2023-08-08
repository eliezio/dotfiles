# Keep 10,000,000 lines of history within the shell and save it to ~/.zsh_history:
HISTSIZE=10000000
SAVEHIST=10000000
HISTFILE=~/.zsh_history
HISTCONTROL=ignoredups:erasedups
HISTIGNORE="exit"

setopt inc_append_history # Update History in all windows on command execution
