typeset -U path

if (( ! $+commands[psql] )) && [[ -d "/opt/homebrew/opt/libpq/bin" ]]; then
  path+=( "/opt/homebrew/opt/libpq/bin" )
fi
