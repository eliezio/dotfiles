#!/usr/bin/env bash
set -euo pipefail

# Reset secrets.yaml for a new age key.
# For contributors who do not own the original age identity.

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

pathadd() {
  local path="$1"
  if [[ ":$PATH:" != *":$path:"* ]]; then
    PATH="$path${PATH:+:$PATH}"
  fi
}

amend_bin_path() {
  case "$(uname -s)" in
    Darwin) pathadd "$(brew --prefix)/bin" ;;
  esac
}
amend_bin_path

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

log_step "Install eget..."
bootstrap_eget

log_step "Install sops..."
ensure_sops() {
  if command -v sops &>/dev/null; then
    echo "sops"
    return
  fi
  if [[ -x "$PLATFORM_CACHE_DIR/sops" ]]; then
    echo "$PLATFORM_CACHE_DIR/sops"
    return
  fi
  log_info "Downloading sops v3.13.0..."
  eget --system "${os}/${arch}" --to "$PLATFORM_CACHE_DIR/" --tag v3.13.0 -q getsops/sops --asset ^.sbom
  echo "$PLATFORM_CACHE_DIR/sops"
}
SOPS=$(ensure_sops)
SOPS_BIN_DIR=$(dirname "$SOPS")
if [[ ":$PATH:" != *":$SOPS_BIN_DIR:"* ]]; then
  PATH="$SOPS_BIN_DIR${PATH:+:$PATH}"
fi

log_step "Install age + age-keygen..."
ensure_age() {
  if command -v age &>/dev/null && command -v age-keygen &>/dev/null; then
    AGE="age"
    AGE_KEYGEN="age-keygen"
    return
  fi
  if [[ -x "$PLATFORM_CACHE_DIR/age" && -x "$PLATFORM_CACHE_DIR/age-keygen" ]]; then
    AGE="$PLATFORM_CACHE_DIR/age"
    AGE_KEYGEN="$PLATFORM_CACHE_DIR/age-keygen"
    return
  fi
  log_info "Downloading age v1.2.1..."
  eget --system "${os}/${arch}" --all --to "$PLATFORM_CACHE_DIR/" --tag v1.2.1 -q FiloSottile/age --asset ^.proof
  # eget preserves archive directory structure; flatten age/age → age
  if [[ -f "$PLATFORM_CACHE_DIR/age/age" ]]; then
    mv "$PLATFORM_CACHE_DIR"/age/* "$PLATFORM_CACHE_DIR/"
    rmdir "$PLATFORM_CACHE_DIR/age"
  fi
  AGE="$PLATFORM_CACHE_DIR/age"
  AGE_KEYGEN="$PLATFORM_CACHE_DIR/age-keygen"
}
ensure_age

AGE_BIN_DIR=$(dirname "$AGE")
if [[ ":$PATH:" != *":$AGE_BIN_DIR:"* ]]; then
  PATH="$AGE_BIN_DIR${PATH:+:$PATH}"
fi

SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
export SOPS_AGE_KEY_FILE

log_step "Check age identity..."

if [[ -f "$SOPS_AGE_KEY_FILE" ]]; then
  read -r -p "Use existing age key at $SOPS_AGE_KEY_FILE? [Y/n] " reply
  if [[ "$reply" =~ ^[Nn] ]]; then
    log_error "Aborted"
    exit 1
  fi
else
  read -r -p "Generate a new age key at $SOPS_AGE_KEY_FILE? [Y/n] " reply
  if [[ "$reply" =~ ^[Nn] ]]; then
    log_error "Aborted — age key required to encrypt secrets"
    exit 1
  fi
  mkdir -p "$(dirname "$SOPS_AGE_KEY_FILE")"
  "$AGE_KEYGEN" -o "$SOPS_AGE_KEY_FILE"
fi

log_step "Extract public key..."
PUB_KEY=$("$AGE_KEYGEN" -y "$SOPS_AGE_KEY_FILE")
log_info "Public key: $PUB_KEY"

log_step "Update .sops.yaml..."
OLD_RECIPIENT="age18lgrr5wlp2lzjskstmm9d7xqh2n09aq7dza3gmg876f3usg7pvvs4e66y9"
if grep -qF "$PUB_KEY" "$SOURCE_DIR/.sops.yaml"; then
  log_info ".sops.yaml already contains your age key — skipping"
else
  sed "s/$OLD_RECIPIENT/$PUB_KEY/" "$SOURCE_DIR/.sops.yaml" > "$SOURCE_DIR/.sops.yaml.tmp"
  mv "$SOURCE_DIR/.sops.yaml.tmp" "$SOURCE_DIR/.sops.yaml"
  log_success ".sops.yaml updated"
fi

log_step "Clean secrets.yaml..."
awk '
  /^sops:/ { exit }
  /^[A-Z_]+: .*/ { $0 = $1 " \"\"" }
  { print }
' "$SOURCE_DIR/secrets.yaml" > "$SOURCE_DIR/secrets.yaml.tmp"
mv "$SOURCE_DIR/secrets.yaml.tmp" "$SOURCE_DIR/secrets.yaml"
log_success "secrets.yaml cleaned"

log_step "Encrypt secrets.yaml..."
"$SOPS" encrypt --in-place "$SOURCE_DIR"/secrets.yaml
log_success "secrets.yaml encrypted"

log_step "Stage changes..."
(cd "$SOURCE_DIR" && git add secrets.yaml .sops.yaml)
log_success "Done! secrets.yaml and .sops.yaml updated with your age key."
log_info "Review and commit when ready."
