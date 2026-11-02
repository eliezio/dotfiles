# macOS installer adapter (Homebrew).
#
#   install_system_packages
#     brew bundle over SYSTEM_PKGS (templated from .packages.system.brew),
#     which includes mise.
#   install_gui_packages GUI_REF
#     brew bundle; cask vs formula is determined by BREW_CASK map membership.

SYSTEM_PKGS=({{ range .packages.system.brew }}{{ . }} {{ end }})

declare -A BREW_NAME=(
{{ range .packages.gui -}}
{{ if hasKey . "brew" }}  [{{ .name }}]={{ .brew }}
{{ end -}}
{{ end -}}
)

declare -A BREW_CASK=(
{{ range .packages.gui -}}
{{ if hasKey . "brew_cask" }}  [{{ .name }}]=1
{{ end -}}
{{ end -}}
)

install_system_packages() {
  local brewfile=""
  for pkg in "${SYSTEM_PKGS[@]}"; do
    brewfile+="brew \"$pkg\""$'\n'
  done
  brew bundle --file=- <<< "$brewfile"
}

install_gui_packages() {
  local -n _gui="$1"
  local brewfile=""
  for pkg in "${_gui[@]}"; do
    local name="${BREW_NAME[$pkg]:-$pkg}"
    if [[ -n "${BREW_CASK[$name]:-}" ]]; then
      brewfile+="cask \"$name\""$'\n'
    else
      brewfile+="brew \"$name\""$'\n'
    fi
  done
  brew bundle --file=- <<< "$brewfile"
}
