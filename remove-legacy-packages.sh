#!/usr/bin/env bash
set -euo pipefail

# Offer to remove packages installed by the platform package manager before
# CLI tools moved to mise: Homebrew (macOS), pacman/yay (Arch), Nix profile
# (Debian). One prompt per package; nothing is removed without a "y".
#
# A package is offered only if it is installed AND mise already has its
# replacement installed, so answering "y" never leaves you without the tool.
# It also offers tools the dotfiles dropped altogether (DROPPED_* below).
# Run after `chezmoi apply` has run `mise install`; chezmoi also runs it once
# per machine via run_once_after_10_remove_legacy_packages.sh.tmpl, passing
# LEGACY_OS_LIKE and LEGACY_TOOLS so it need not call chezmoi mid-apply.

if [[ "${BASH_VERSINFO[0]}" -lt 5 ]]; then
  echo "Error: bash 5+ required." >&2
  exit 1
fi

SOURCE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=scripts/lib/log.sh
source "$SOURCE_DIR/scripts/lib/log.sh"

# mise.run installs to ~/.local/bin, which may not be on a non-login PATH.
PATH="$HOME/.local/bin:$PATH"
required=(mise)
[[ -n "${LEGACY_OS_LIKE:-}" && -n "${LEGACY_TOOLS:-}" ]] || required+=(chezmoi)
for cmd in "${required[@]}"; do
  if ! command -v "$cmd" &>/dev/null; then
    log_error "$cmd not found; run apply.sh first"
    exit 1
  fi
done

# Package names the old setup used where they differ from the packages.cli
# name (frozen history: the per-platform keys removed from packages.yaml), plus
# the name Homebrew lists a formula under. Space-separated candidates.
declare -A LEGACY_BREW=(
  [delta]="git-delta"
  [kubectl]="kubernetes-cli"
  [nodejs]="node"
)
declare -A LEGACY_ARCH=(
  [delta]="git-delta"
  [gh]="github-cli"
  [herdr]="herdr-bin"
  [jd]="jd-tool-bin"
  [nodejs]="nodejs npm"
)
declare -A LEGACY_NIX=(
  [jd]="jd-diff-patch"
  [tree-sitter-cli]="tree-sitter"
  [yq]="yq-go"
)

# Tools the dotfiles no longer install at all: package name -> why.
declare -A DROPPED_BREW=(
  [curlie]="dropped"
  [httpie]="replaced by xh"
  [lemonade]="clip uses OSC 52 now"
  [tmux]="dropped"
)
declare -A DROPPED_ARCH=(
  [curlie]="dropped"
  [httpie]="replaced by xh"
  [lemonade-bin]="clip uses OSC 52 now"
  [tmux]="dropped"
)
declare -A DROPPED_NIX=(
  [curlie]="dropped"
  [httpie]="replaced by xh"
  [lemonade]="clip uses OSC 52 now"
  [tmux]="dropped"
)

os_like=${LEGACY_OS_LIKE:-$(chezmoi --source "$SOURCE_DIR" execute-template '{{ .os_like }}')}

case "$os_like" in
  macos)
    declare -n LEGACY=LEGACY_BREW DROPPED=DROPPED_BREW
    list_installed() { brew list --formula -1; }
    remove_pkg() { brew uninstall --formula "$1"; }
    ;;
  arch)
    declare -n LEGACY=LEGACY_ARCH DROPPED=DROPPED_ARCH
    list_installed() { pacman -Qq; }
    remove_pkg() { sudo pacman -Rs --noconfirm "$1"; }
    ;;
  debian)
    if ! command -v nix &>/dev/null; then
      log_info "Nix not installed; nothing to remove"
      exit 0
    fi
    declare -n LEGACY=LEGACY_NIX DROPPED=DROPPED_NIX
    list_installed() { nix profile list | awk '/^Name:/ { print $2 }'; }
    remove_pkg() { nix profile remove "$1"; }
    ;;
  *)
    log_info "No legacy package manager for os_like=$os_like; nothing to remove"
    exit 0
    ;;
esac

declare -A INSTALLED=()
while read -r pkg; do
  INSTALLED[$pkg]=1
done < <(list_installed)

# "name backend" per line, straight from packages.cli.
if [[ -n "${LEGACY_TOOLS:-}" ]]; then
  mapfile -t TOOLS <<< "$LEGACY_TOOLS"
else
  mapfile -t TOOLS < <(chezmoi --source "$SOURCE_DIR" execute-template \
    '{{ range .packages.cli }}{{ .name }} {{ .mise }}{{ "\n" }}{{ end }}')
fi

# confirm PROMPT — y removes, q stops the whole run, anything else skips.
confirm() {
  local reply
  read -r -p "$1 [y/N/q] " reply < /dev/tty
  case "$reply" in
    [Yy]*) return 0 ;;
    [Qq]*) log_info "Stopped; nothing further removed"; exit 0 ;;
    *)     return 1 ;;
  esac
}

offered=0 removed=0 failed=0

# offer PKG REASON
offer() {
  local pkg="$1" reason="$2"
  (( ++offered ))
  if ! confirm "Remove $pkg ($reason)?"; then
    return 0
  fi
  if remove_pkg "$pkg"; then
    (( ++removed ))
    log_success "Removed $pkg"
  else
    (( ++failed ))
    log_error "Could not remove $pkg (still needed by another package?)"
  fi
}

log_step "Checking $os_like packages replaced by mise..."
for line in "${TOOLS[@]}"; do
  read -r name backend <<< "$line"
  for pkg in ${LEGACY[$name]:-$name}; do
    [[ -n "${INSTALLED[$pkg]:-}" ]] || continue
    if ! mise where "$backend" &>/dev/null; then
      log_info "Keeping $pkg: mise has not installed $backend yet"
      continue
    fi
    offer "$pkg" "replaced by mise $backend"
  done
done

# Arch installs mise itself with mise.run now (scripts/lib/mise_run.sh).
if [[ "$os_like" == arch && -n "${INSTALLED[mise]:-}" && -x "$HOME/.local/bin/mise" ]]; then
  offer mise "replaced by $HOME/.local/bin/mise from mise.run"
fi

log_step "Checking $os_like packages for tools no longer used..."
for pkg in $(printf '%s\n' "${!DROPPED[@]}" | sort); do
  [[ -n "${INSTALLED[$pkg]:-}" ]] || continue
  offer "$pkg" "${DROPPED[$pkg]}"
done

if (( offered == 0 )); then
  log_success "No legacy packages left to remove"
else
  log_success "Removed $removed of $offered offered package(s)"
  if (( failed > 0 )); then
    log_error "$failed removal(s) failed"
  fi
fi
