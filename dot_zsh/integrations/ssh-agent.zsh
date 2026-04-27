if [[ -z "${SSH_CONNECTION}" && -n "${XDG_RUNTIME_DIR}" ]]; then
    export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"
fi
