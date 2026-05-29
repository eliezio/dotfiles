typeset -U path

if [[ -d "$HOME/go" ]]; then
    export GOPATH="$HOME/go"
    export GOBIN="$GOPATH/bin"
    path+=( "$GOBIN" )
fi
