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

export TMP_CONFIG_HOME=$(mktemp -d)
trap "rm -rf $TMP_CONFIG_HOME" EXIT ERR INT

configure_curl() {
  export CURL_HOME=$TMP_CONFIG_HOME
  echo "--progress-bar" > $CURL_HOME/.curlrc
}

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

get_chezmoi() {
  local -A _cfg=(
    [org]="twpayne"
    [name]="chezmoi"
    [version]="2.70.3"
    [asset_basename]="{name}_{version}_{os}_{arch}"
    [asset_type]="tgz"
    [min_version]="2.36"
  )
  get_github_release _cfg
}

get_sops() {
  local -A _cfg=(
    [org]="getsops"
    [name]="sops"
    [version]="3.13.0"
    [asset_basename]="{name}-v{version}.{os}.{arch}"
    [asset_type]="bin"
    [min_version]="3.10"
  )
  get_github_release _cfg
}

get_yq() {
  local -A _cfg=(
    [org]="mikefarah"
    [name]="yq"
    [version]="4.53.2"
    [asset_basename]="{name}_{os}_{arch}"
    [asset_type]="tgz"
    [bin_name]="./{name}_{os}_{arch}"
  )
  get_github_release _cfg
}

get_micro() {
  local -A _cfg=(
    [org]="micro-editor"
    [name]="micro"
    [version]="2.0.15"
    [asset_basename]="{name}-{version}-{os}-{arch}"
    [asset_type]="tgz"
    [bin_name]="{name}-{version}/{name}"
  )
  local -A _aliases=(
    [darwin]="macos"
  )
  get_github_release _cfg _aliases
}

configure_micro() {
  export MICRO_CONFIG_HOME=$TMP_CONFIG_HOME/micro
  mkdir -p $MICRO_CONFIG_HOME
  echo '{ "Ctrl-k": "SelectToEndOfLine,Delete" }' > $MICRO_CONFIG_HOME/bindings.json
  echo '{ "statusformatr": "Ctrl-s: Save, Ctrl-q: Exit, Ctrl-k: Cut to end of line, $(bind:ToggleHelp): Help" }' > $MICRO_CONFIG_HOME/settings.json
}

amend_bin_path

configure_curl

setup_ssl_bundle

log_step "Check for required bootstrap applications..."
CHEZMOI=$(get_chezmoi)
SOPS=$(get_sops)
YQ=$(get_yq)
MICRO=$(get_micro)

configure_micro

log_step "Initializing chezmoi config..."
"$CHEZMOI" --source "$SOURCE_DIR" init --force

log_step "chezmoi apply (with secrets)..."
LOG_STEP_PREFIX="$LOG_STEP_NUM" \
SOPS_AGE_SSH_PRIVATE_KEY_CMD="$SOURCE_DIR/scripts/bin/decrypt-ssh-key.sh $SSH_KEY" \
  "$SOPS" exec-env --same-process "$SOURCE_DIR/secrets.yaml" "$CHEZMOI --source \"$SOURCE_DIR\" apply $*"

log_success "Apply complete"
