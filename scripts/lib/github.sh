# GitHub release helpers. Depends on log.sh (for log_info / log_error) and on
# the caller having defined $CACHE_DIR.
#
# get_github_release CONFIG_NAMEREF [ALIAS_NAMEREF]
#   Ensures a binary is available and prints the path to use.
#
#   CONFIG_NAMEREF is the name of an associative array (local -A) in the
#   caller's scope. Required keys:
#     org            - GitHub org/owner
#     name           - binary / repo name
#     version        - semver to download (without leading "v")
#     asset_basename - template with {name}, {version}, {os}, {arch}
#                      placeholders. Examples:
#                        "{name}_{version}_{os}_{arch}"          -> chezmoi_2.70.2_darwin_arm64
#                        "{name}-{version}-{os}_{arch}"          -> fzf-0.72.0-darwin_arm64
#                        "{name}-v{version}.{os}.{arch}"         -> sops-v3.12.2.linux.amd64
#     asset_type     - "tgz" (tar.gz containing binary NAME) or "bin" (raw binary)
#   Optional keys:
#     min_version    - if name is already on PATH, verify --version >= this
#     bin_name       - binary name inside the archive (defaults to name)
#
#   ALIAS_NAMEREF (optional) is the name of an associative array mapping
#   auto-detected OS/arch values to alternate strings. Example:
#     local -A _aliases=([darwin]="macos")
#     get_github_release _cfg _aliases
#   This replaces "darwin" with "macos" in {os} without the caller needing
#   to know the current platform.
#
#   Resolution order:
#     1. If NAME is already on PATH, print `NAME` and return (after an optional
#        min_version check; fails if the installed version is older).
#     2. If a cached copy exists at $CACHE_DIR/<asset_basename>, print that.
#     3. Otherwise download from
#        github.com/ORG/NAME/releases/download/vVERSION/<asset_basename><ext>,
#        cache it, chmod +x, and print the cached path.

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
  local -n _gh_config="$1"
  local org="${_gh_config[org]:?get_github_release: org is required}"
  local name="${_gh_config[name]:?get_github_release: name is required}"
  local version="${_gh_config[version]:?get_github_release: version is required}"
  local asset_basename="${_gh_config[asset_basename]:?get_github_release: asset_basename is required}"
  local asset_type="${_gh_config[asset_type]:?get_github_release: asset_type is required}"
  local min_version="${_gh_config[min_version]:-}"
  local bin_name="${_gh_config[bin_name]:-${name}}"
  local -A _gh_aliases=()
  if [[ $# -ge 2 && -n "$2" ]]; then
    local -n _gh_aliases_ref="$2"
    for _gh_k in "${!_gh_aliases_ref[@]}"; do
      _gh_aliases[$_gh_k]="${_gh_aliases_ref[$_gh_k]}"
    done
  fi

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
  os="${_gh_aliases[$os]:-$os}"
  arch="${_gh_aliases[$arch]:-$arch}"
  asset_basename="${asset_basename//\{name\}/$name}"
  asset_basename="${asset_basename//\{version\}/$version}"
  asset_basename="${asset_basename//\{os\}/$os}"
  asset_basename="${asset_basename//\{arch\}/$arch}"
  bin_name="${bin_name//\{name\}/$name}"
  bin_name="${bin_name//\{version\}/$version}"
  bin_name="${bin_name//\{os\}/$os}"
  bin_name="${bin_name//\{arch\}/$arch}"

  local cached="$CACHE_DIR/${name}_${os}_${arch}"
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
  local url="https://github.com/${org}/${name}/releases/download/v${version}/${asset_basename}${archive_ext}"
  log_info "Downloading $url"
  case "$asset_type" in
    tgz)
      curl -fsSL "$url" | tar xz -C "$CACHE_DIR" "$bin_name"
      [[ "$bin_name" == "$cached" ]] || mv "$CACHE_DIR/$bin_name" "$cached"
      ;;
    bin)
      curl -fsSL "$url" -o "$cached"
      ;;
  esac
  chmod +x "$cached"
  echo "$cached"
}
