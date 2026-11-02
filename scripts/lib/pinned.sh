# shellcheck shell=bash
# Bootstrap binaries for apply.sh and reset-secrets.sh: pinned version +
# pinned SHA-256 per asset, fetched with curl, which honors CURL_CA_BUNDLE on
# every OS (Go/rustls downloaders use the Keychain on macOS and miss a proxy CA
# that only lives in the trust bundle).
#
# Needs: log.sh sourced, and $os, $arch, $PLATFORM_CACHE_DIR set.
#
# Bump: change the tag, then print the new pins on a machine with gh:
#   gh api repos/twpayne/chezmoi/releases/tags/TAG --jq '.assets[]|select(.name|test("_(darwin|linux)_(amd64|arm64)\\.tar\\.gz$"))|"  [\(.name)]=\(.digest|ltrimstr("sha256:"))"'
#   gh api repos/getsops/sops/releases/tags/TAG --jq '.assets[]|select(.name|test("\\.(darwin|linux)\\.(amd64|arm64)$"))|"  [\(.name)]=\(.digest|ltrimstr("sha256:"))"'
#   gh api repos/FiloSottile/age/releases/tags/TAG --jq '.assets[]|select(.name|test("-(darwin|linux)-(amd64|arm64)\\.tar\\.gz$"))|"  [\(.name)]=\(.digest|ltrimstr("sha256:"))"'
CHEZMOI_TAG=v2.74.0
SOPS_TAG=v3.13.3
AGE_TAG=v1.3.2
declare -A PIN_SHA256=(
  [chezmoi_2.74.0_darwin_amd64.tar.gz]=3d30cb05efae2f4a68519d6d0e8856765f2b21a0686e66498ee6d2de7707e5e6
  [chezmoi_2.74.0_darwin_arm64.tar.gz]=9d89672a597a9333ab47ea5173fcececb85c04864205686a7aa5699c3d8bd98c
  [chezmoi_2.74.0_linux_amd64.tar.gz]=1b98a567f726f41540414aea4caf912699d53e248b29ccf8369cf553657b2374
  [chezmoi_2.74.0_linux_arm64.tar.gz]=bf89495d1aab5e4fa0fc1ba9457837b34ee8dec9b787570f2de3e1c12a5835a5
  [sops-v3.13.3.darwin.amd64]=42162d5cef10b74fcf80a045a70e658d7ce6e63d6ea1be6f347e44015714468d
  [sops-v3.13.3.darwin.arm64]=b97c0d434aab577dc40310e8d22ff9e45eef4c80638ab978daae9b4681c59286
  [sops-v3.13.3.linux.amd64]=e5bec3346a873ae91d871550f3e698c1aad962aff462a080e40f25fde17fef6b
  [sops-v3.13.3.linux.arm64]=53b0abacd38ef1b12a66d6c100956691b9cefce018d91f81e73ddf7438b94d77
  [age-v1.3.2-darwin-amd64.tar.gz]=1d1e4bc66e1427edad7739ae7616157de0e79db8b6d2a1497d7d9925fb06a539
  [age-v1.3.2-darwin-arm64.tar.gz]=e2020b073c44f692685a24d6abc378817eb81ffaaf49fd0531ef8565f767f2f5
  [age-v1.3.2-linux-amd64.tar.gz]=cbe24006683f8eb669266162894b9a522a1af52f2665fbc63a4bb032ed26ac10
  [age-v1.3.2-linux-arm64.tar.gz]=6b8dc4333c53a5a57c9e5834e3a48f92605d7154014cd07269ff3327db5d37f4
)

sha256_of() {
  if command -v sha256sum &>/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}

# Download URL to DEST; fail unless its SHA-256 matches the pin recorded for
# the URL's basename.
fetch_pinned() {
  local url="$1" dest="$2" asset="${1##*/}" want got
  want="${PIN_SHA256[$asset]:-}"
  if [[ -z "$want" ]]; then
    log_error "No pinned sha256 for $asset"
    return 1
  fi
  curl -fsSL --retry 3 -o "$dest" "$url" || return
  got=$(sha256_of "$dest")
  if [[ "$got" != "$want" ]]; then
    log_error "sha256 mismatch for $asset (got $got)"
    rm -f "$dest"
    return 1
  fi
}

download_chezmoi() {
  local tmp
  tmp=$(mktemp -d)
  fetch_pinned "https://github.com/twpayne/chezmoi/releases/download/${CHEZMOI_TAG}/chezmoi_${CHEZMOI_TAG#v}_${os}_${arch}.tar.gz" "$tmp/chezmoi.tar.gz" || return
  tar -xzf "$tmp/chezmoi.tar.gz" -C "$PLATFORM_CACHE_DIR" chezmoi || return
  rm -rf -- "$tmp"
}

download_sops() {
  fetch_pinned "https://github.com/getsops/sops/releases/download/${SOPS_TAG}/sops-${SOPS_TAG}.${os}.${arch}" "$PLATFORM_CACHE_DIR/sops" || return
  chmod +x "$PLATFORM_CACHE_DIR/sops"
}

# Installs age and age-keygen; the archive also carries plugins we don't need.
download_age() {
  local tmp
  tmp=$(mktemp -d)
  fetch_pinned "https://github.com/FiloSottile/age/releases/download/${AGE_TAG}/age-${AGE_TAG}-${os}-${arch}.tar.gz" "$tmp/age.tar.gz" || return
  tar -xzf "$tmp/age.tar.gz" -C "$PLATFORM_CACHE_DIR" --strip-components=1 age/age age/age-keygen || return
  rm -rf -- "$tmp"
}

# Ensure a binary is available: use system PATH if present, otherwise
# download it (download_NAME) into PLATFORM_CACHE_DIR.
ensure_binary() {
  local name="$1"

  if command -v "$name" &>/dev/null; then
    echo "$name"
    return
  fi
  if [[ -x "$PLATFORM_CACHE_DIR/$name" ]]; then
    echo "$PLATFORM_CACHE_DIR/$name"
    return
  fi
  log_info "Downloading $name..."
  # errexit is off inside $(...), so propagate failures by hand.
  "download_$name" || return
  echo "$PLATFORM_CACHE_DIR/$name"
}
