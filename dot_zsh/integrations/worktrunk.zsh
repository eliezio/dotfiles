if (( $+commands[wt] )); then
  eval "$(wt config shell init zsh)"

  alias wts='wt switch'
  alias wtl='wt switch -'
  alias wtls='wt list'
  alias wtrm='wt remove'
fi
