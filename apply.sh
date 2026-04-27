#!/usr/bin/env bash
set -euo pipefail

# log.sh needs $EPOCHREALTIME (bash 5+); macOS ships bash 3.2.
if [[ "${BASH_VERSINFO[0]}" -lt 5 ]]; then
  if [[ -x /opt/homebrew/bin/bash ]]; then
    exec /opt/homebrew/bin/bash "$0" "$@"
  else
    echo "Error: bash 5+ required. Install via: brew install bash" >&2
    exit 1
  fi
fi

# SOURCE_DIR is the chezmoi source root; CERTS_SOURCE_DIR is exported so the
# chezmoi-managed run_once script can find ./certs (it runs from a temp dir).
export SOURCE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export CERTS_SOURCE_DIR="$SOURCE_DIR/dot_local/share/certs"
CACHE_DIR="$SOURCE_DIR/.cache"

SSH_KEY="${SOPS_SSH_KEY:-$HOME/.ssh/id_ed25519}"

# shellcheck source=scripts/lib/log.sh
source "$SOURCE_DIR/scripts/lib/log.sh"
# shellcheck source=scripts/lib/github.sh
source "$SOURCE_DIR/scripts/lib/github.sh"

export CURL_HOME=$(mktemp -d)
echo "--progress-bar" > $CURL_HOME/.curlrc
trap "rm -rf $CURL_HOME" EXIT ERR INT

# Concatenate $CERTS_SOURCE_DIR/*.crt and export the SSL/cURL/Nix env vars to
# point at it. Needed so the chezmoi self-download (and chezmoi externals) work
# behind an MITM proxy whose CA isn't in the system store.
# Returns early if no custom certs exist.
setup_ssl_bundle() {
  shopt -s nullglob
  local certs=("$CERTS_SOURCE_DIR"/*.crt)
  shopt -u nullglob

  [ "${#certs[@]}" -eq 0 ] && return 0

  local bundle="${XDG_DATA_HOME:-$HOME/.local/share}/certs/certs-bundle.pem"
  mkdir -p "$(dirname "$bundle")"
  # Newline after each block so PEM headers/footers never glue together when
  # a source file lacks a trailing newline.
  for cert in "${certs[@]}"; do
    cat "$cert"
    echo
  done > "$bundle"

  export SSL_CERT_FILE="$bundle"
  export NIX_SSL_CERT_FILE="$bundle"
  export CURL_CA_BUNDLE="$bundle"
}

pathadd() {
  local path="$1"
  if [[ ":$PATH:" != *":$path:"* ]]; then
    PATH="$path${PATH:+:$PATH}"
  fi
}

amend_bin_path() {
  case "$(uname -s)" in
    Darwin) pathadd "/opt/homebrew/bin" ;;
    Linux)  pathadd "$HOME/.nix-profile/bin" ;;
  esac
}

amend_bin_path

setup_ssl_bundle

get_chezmoi() {
  get_github_release --min-version "2.36" "twpayne" "chezmoi" "2.70.2" "%s_%s_%s_%s" "tgz"
}

get_sops() {
  get_github_release --min-version "3.10" "getsops" "sops" "3.12.2" '%s-v%s.%s.%s' "bin"
}

CHEZMOI=$(get_chezmoi)
SOPS=$(get_sops)

log_step "Initializing chezmoi config..."
"$CHEZMOI" --source "$SOURCE_DIR" init --force

log_step "chezmoi apply (with secrets)..."
LOG_STEP_PREFIX="$LOG_STEP_NUM" \
SOPS_AGE_SSH_PRIVATE_KEY_CMD="$SOURCE_DIR/scripts/bin/decrypt-ssh-key.sh $SSH_KEY" \
  "$SOPS" exec-env --same-process "$SOURCE_DIR/secrets.yaml" "$CHEZMOI --source \"$SOURCE_DIR\" apply $*"
log_success "Apply complete"
