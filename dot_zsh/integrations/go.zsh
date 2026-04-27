if [[ -d "$HOME/go" ]]; then
    export GOPATH="$HOME/go"
    export GOBIN="$GOPATH/bin"
    export PATH="$PATH:$GOBIN"
fi
