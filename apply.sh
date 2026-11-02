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

# macOS requires Homebrew installed and configured (on PATH).
if [[ "$(uname -s)" == Darwin ]] && ! command -v brew &>/dev/null; then
  echo "Error: Homebrew must be installed and on PATH. See https://brew.sh" >&2
  exit 1
fi

# log.sh needs $EPOCHREALTIME (bash 5+); macOS ships bash 3.2.
if [[ "${BASH_VERSINFO[0]}" -lt 5 ]]; then
  if [[ "$(uname -s)" == Darwin ]]; then
    echo "Error: bash 5+ required. Install via: brew install bash" >&2
  else
    echo "Error: bash 5+ required." >&2
  fi
  exit 1
fi

# Never create group/world-writable files, even under a umask-0000 parent
# (e.g. OrbStack's `docker exec`); keeps stricter umasks such as 077.
umask "$(printf '%04o' $(( 8#$(umask) | 8#022 )))"

SOURCE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export SOURCE_DIR

# --skip-certs leaves the custom CAs out: no trust bundle, no system trust
# store, nothing in ~/.local/share/certs. chezmoi's config remembers it
# (skip_certs); `DOTFILES_SKIP_CERTS=0 ./apply.sh` turns certs back on.
# Every other argument goes to `chezmoi apply`.
APPLY_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --skip-certs) export DOTFILES_SKIP_CERTS=1 ;;
    *)            APPLY_ARGS+=("$arg") ;;
  esac
done
CACHE_DIR="$SOURCE_DIR/.cache"

# shellcheck source=scripts/lib/log.sh
source "$SOURCE_DIR/scripts/lib/log.sh"
# Platform detection for cache isolation across bind-mounted volumes.
case "$(uname -s)" in
  Darwin) os=darwin ;;
  Linux)  os=linux ;;
  *)      log_error "Unsupported OS: $(uname -s)"; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64)        arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  *)             log_error "Unsupported arch: $(uname -m)"; exit 1 ;;
esac
PLATFORM_CACHE_DIR="$CACHE_DIR/${os}_${arch}"
mkdir -p "$PLATFORM_CACHE_DIR"

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

# Explicit DOTFILES_SKIP_CERTS wins; otherwise keep what the last init chose.
skip_certs() {
  case "${DOTFILES_SKIP_CERTS:-}" in
    1) return 0 ;;
    0) return 1 ;;
  esac
  grep -qsx 'skip_certs = true' "${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi/chezmoi.toml"
}

pathadd() {
  local path="$1"
  if [[ ":$PATH:" != *":$path:"* ]]; then
    PATH="$path${PATH:+:$PATH}"
  fi
}

# shellcheck source=scripts/lib/pinned.sh
source "$SOURCE_DIR/scripts/lib/pinned.sh"

configure_curl

log_step "Build trust bundle..."
if skip_certs; then
  log_info "Skipping certificates (skip_certs); using system CA bundle"
else
  trust_build_bundle
  if [[ -s "$TRUST_BUNDLE_FILE" ]]; then
    export SSL_CERT_FILE="$TRUST_BUNDLE_FILE"
    export CURL_CA_BUNDLE="$TRUST_BUNDLE_FILE"
    log_info "Using trust bundle at $TRUST_BUNDLE_FILE"
  else
    log_info "No trust roots; using system CA bundle"
  fi
fi

log_step "Check for required bootstrap binaries..."
CHEZMOI=$(ensure_binary chezmoi)
SOPS=$(ensure_binary sops)
# chezmoi invokes sops at template-render time (via [secret] command = "sops"),
# so it must be on PATH before `chezmoi apply` and before the package manager
# installs it system-wide.
SOPS_BIN_DIR=$(dirname "$SOPS")
pathadd "$SOPS_BIN_DIR"
# sops needs the age identity; standardise on the XDG path (sops's default on
# macOS is ~/Library/Application Support/sops/age/keys.txt). chezmoi's sops
# subprocess inherits this during template rendering.
: "${SOPS_AGE_KEY_FILE:=$HOME/.config/sops/age/keys.txt}"
export SOPS_AGE_KEY_FILE

log_step "Initializing chezmoi config..."
"$CHEZMOI" --source "$SOURCE_DIR" init --force

log_step "chezmoi apply..."
export LOG_STEP_PREFIX="$LOG_STEP_NUM"
exec "$CHEZMOI" --source "$SOURCE_DIR" apply "${APPLY_ARGS[@]}"
