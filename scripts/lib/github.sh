# GitHub release helpers. Depends on log.sh (for log_info / log_error) and on
# the caller having defined $CACHE_DIR.
#
# get_github_release [--min-version VERSION] ORG NAME VERSION FORMAT ASSET_TYPE
#   Ensures a binary named NAME is available and prints the path to use.
#
#   Resolution order:
#     1. If NAME is already on PATH, print `NAME` and return (after an optional
#        --min-version check; fails if the installed version is older).
#     2. If a cached copy exists at $CACHE_DIR/<archive_basename>, print that.
#     3. Otherwise download from
#        github.com/ORG/NAME/releases/download/vVERSION/<archive_basename><ext>,
#        cache it, chmod +x, and print the cached path.
#
#   FORMAT is a printf-style template applied as
#   `printf FORMAT NAME VERSION OS ARCH`, producing <archive_basename>. Examples:
#     "%s_%s_%s_%s"          -> chezmoi_2.70.2_darwin_arm64
#     "%s-%s-%s_%s"          -> fzf-0.72.0-darwin_arm64
#     "%1$s-v%2$s.%3$s.%4$s" -> sops-v3.12.2.linux.amd64
#
#   ASSET_TYPE is required and must be one of:
#     tgz  - asset is a .tar.gz containing a binary named NAME; extracted.
#     bin  - asset is a raw binary; downloaded as-is.
#
#   --min-version VERSION (optional, must come first): if NAME is already on
#   PATH, verify its `--version` output is >= VERSION; otherwise log an error
#   and return 1. Has no effect when the binary is downloaded fresh.

check_version() {
  local name="$1"
  local min_version="$2"
  local current_version=$("$name" --version | head -1 | grep -oE '([0-9]+\.[0-9]+(\.[0-9]+)?)')
  local lowest_version=$(echo "$current_version\n$min_version" | sort --version-sort --reverse | tail -1)
  if [[ "$lowest_version" == "$min_version" ]]; then
    log_error "$name version $current_version is older than the required minimum version $min_version"
    return 1
  fi
  log_info "Found $name version $current_version"
  return 0
}

get_github_release() {
  local min_version=""
  if [[ "$1" == "--min-version" ]]; then
    min_version="$2"
    shift 2
  fi
  local org="$1"
  local name="$2"
  local version="$3"
  local format="$4"
  local asset_type="$5"

  if command -v "$name" &>/dev/null; then
    if [[ -n "$min_version" ]]; then
      check_version "$name" "$min_version" || return 1
    fi
    echo "$name"
    return
  fi


  local os arch
  case "$(uname -s)" in
    Darwin) os=darwin ;;
    Linux)  os=linux ;;
    *)      log_error "Unsupported OS: $(uname -s)"; return 1 ;;
  esac
  case "$(uname -m)" in
    x86_64)        arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *)             log_error "Unsupported arch: $(uname -m)"; return 1 ;;
  esac
  local archive_basename
  archive_basename=$(printf "$format" "$name" "$version" "$os" "$arch")

  local cached="$CACHE_DIR/$archive_basename"
  if [[ -x "$cached" ]]; then
    echo "$cached"
    return
  fi

  case "$asset_type" in
    tgz) archive_ext=".tar.gz" ;;
    bin) archive_ext="" ;;
    *) log_error "Unsupported asset_type: $asset_type"; return 1 ;;
  esac

  mkdir -p "$CACHE_DIR"
  local url="https://github.com/${org}/${name}/releases/download/v${version}/${archive_basename}${archive_ext}"
  log_info "Downloading $url"
  case "$asset_type" in
    tgz)
      curl -fsSL "$url" | tar xz -C "$CACHE_DIR" "$name"
      mv "$CACHE_DIR/$name" "$cached"
      ;;
    bin)
      curl -fsSL "$url" -o "$cached"
      ;;
  esac
  chmod +x "$cached"
  echo "$cached"
}
