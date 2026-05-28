#!/usr/bin/env bash
set -euo pipefail

# First-machine bootstrap for this chezmoi repo.
#
# Daily use: just `chezmoi apply`. This script exists only because
# chezmoi + sops are not yet installed on a clean machine.
#
# Prerequisite: the age identity at ~/.config/sops/age/keys.txt must already
# exist (restore it from your password manager). secrets.yaml is encrypted to
# that single recipient.

# log.sh needs $EPOCHREALTIME (bash 5+); macOS ships bash 3.2.
if [[ "${BASH_VERSINFO[0]}" -lt 5 ]]; then
  if [[ -x /opt/homebrew/bin/bash ]]; then
    exec /opt/homebrew/bin/bash "$0" "$@"
  else
    echo "Error: bash 5+ required. Install via: brew install bash" >&2
    exit 1
  fi
fi

SOURCE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export SOURCE_DIR
CACHE_DIR="$SOURCE_DIR/.cache"

# shellcheck source=scripts/lib/log.sh
source "$SOURCE_DIR/scripts/lib/log.sh"
# shellcheck source=scripts/lib/github.sh
source "$SOURCE_DIR/scripts/lib/github.sh"

TMP_CONFIG_HOME=$(mktemp -d)
export TMP_CONFIG_HOME
trap 'rm -rf -- "$TMP_CONFIG_HOME"' EXIT

configure_curl() {
  export CURL_HOME="$TMP_CONFIG_HOME"
  printf '%s\n' "--progress-bar" > "$CURL_HOME/.curlrc"
}

# NOTE: trust paths duplicate .chezmoidata/trust.yaml. They are kept in sync
# manually because apply.sh runs before chezmoi is available to render the
# data. If you change one, change the other.
TRUST_CERTS_SOURCE_DIR="$SOURCE_DIR/dot_local/share/certs"
TRUST_CERTS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/certs"
TRUST_BUNDLE_FILE="$TRUST_CERTS_DIR/trust-bundle.pem"

trust_build_bundle() {
  shopt -s nullglob
  local certs=("$TRUST_CERTS_SOURCE_DIR"/*.crt)
  shopt -u nullglob

  if (( ${#certs[@]} == 0 )); then
    rm -f "$TRUST_BUNDLE_FILE"
    return 0
  fi

  mkdir -p "$(dirname "$TRUST_BUNDLE_FILE")"
  # Trailing newline after each cert so PEM headers/footers never glue
  # together when a source file lacks one.
  {
    for cert in "${certs[@]}"; do
      cat "$cert"
      echo
    done
  } > "$TRUST_BUNDLE_FILE"
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

amend_bin_path
configure_curl

log_step "Build trust bundle..."
trust_build_bundle
if [[ -s "$TRUST_BUNDLE_FILE" ]]; then
  export SSL_CERT_FILE="$TRUST_BUNDLE_FILE"
  export NIX_SSL_CERT_FILE="$TRUST_BUNDLE_FILE"
  export CURL_CA_BUNDLE="$TRUST_BUNDLE_FILE"
  log_info "Using trust bundle at $TRUST_BUNDLE_FILE"
else
  log_info "No trust roots; using system CA bundle"
fi

log_step "Check for required bootstrap binaries..."
CHEZMOI=$(get_chezmoi)
SOPS=$(get_sops)
# SOPS isn't invoked by apply.sh itself anymore (run_onchange_after_gh_setup
# calls it at runtime), but we still need it on PATH because chezmoi-managed
# scripts will invoke it before the package manager installs it system-wide.
SOPS_BIN_DIR=$(dirname "$SOPS")
pathadd "$SOPS_BIN_DIR"

log_step "Initializing chezmoi config..."
"$CHEZMOI" --source "$SOURCE_DIR" init --force

log_step "chezmoi apply..."
export LOG_STEP_PREFIX="$LOG_STEP_NUM"
exec "$CHEZMOI" --source "$SOURCE_DIR" apply "$@"
