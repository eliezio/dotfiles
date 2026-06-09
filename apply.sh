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

SOURCE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export SOURCE_DIR
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

pathadd() {
  local path="$1"
  if [[ ":$PATH:" != *":$path:"* ]]; then
    PATH="$path${PATH:+:$PATH}"
  fi
}

amend_bin_path() {
  case "$(uname -s)" in
    Darwin) pathadd "$(brew --prefix)/bin" ;;
    Linux)  pathadd "$HOME/.nix-profile/bin" ;;
  esac
}

# Bootstrap eget (download release asset tool) if not already available.
bootstrap_eget() {
  if command -v eget &>/dev/null; then
    return
  fi
  if [[ -x "$PLATFORM_CACHE_DIR/eget" ]]; then
    pathadd "$PLATFORM_CACHE_DIR"
    return
  fi
  log_info "Bootstrapping eget..."
  curl -fsSL https://zyedidia.github.io/eget.sh | sh
  mv eget "$PLATFORM_CACHE_DIR/eget"
  pathadd "$PLATFORM_CACHE_DIR"
}

# Ensure a binary is available: use system PATH if present, otherwise
# download via eget into PLATFORM_CACHE_DIR.
# Remaining arguments are asset-filter substrings; each is expanded to
# `--asset FILTER`.
ensure_binary() {
  local name="$1"
  local repo="$2"
  local tag="$3"
  shift 3

  if command -v "$name" &>/dev/null; then
    echo "$name"
    return
  fi
  if [[ -x "$PLATFORM_CACHE_DIR/$name" ]]; then
    echo "$PLATFORM_CACHE_DIR/$name"
    return
  fi
  log_info "Downloading $name $tag via eget..."
  local -a asset_args=()
  for filter in "$@"; do
    asset_args+=(--asset "$filter")
  done
  eget --system "${os}/${arch}" --to "$PLATFORM_CACHE_DIR/" --tag "$tag" -q "$repo" "${asset_args[@]}"
  echo "$PLATFORM_CACHE_DIR/$name"
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
bootstrap_eget
CHEZMOI=$(ensure_binary chezmoi twpayne/chezmoi v2.70.3 ^.sbom ^glibc ^musl .tar.gz)
SOPS=$(ensure_binary sops getsops/sops v3.13.0 ^.sbom)
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
exec "$CHEZMOI" --source "$SOURCE_DIR" apply "$@"
