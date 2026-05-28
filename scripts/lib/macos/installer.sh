# macOS installer adapter (Homebrew).
#
#   install_packages CLI_REF GUI_REF
#     Both refs are merged into one brewfile; cli/gui distinction is irrelevant
#     here — cask vs formula is determined by BREW_CASK map membership.
#   install_system_packages
#     No-op; Homebrew is user-level on macOS.

declare -A BREW_NAME=(
{{ range concat .packages.cli .packages.gui -}}
{{ if hasKey . "brew" }}  [{{ .name }}]={{ .brew }}
{{ end -}}
{{ end -}}
)

declare -A BREW_CASK=(
{{ range concat .packages.cli .packages.gui -}}
{{ if hasKey . "brew_cask" }}  [{{ .name }}]=1
{{ end -}}
{{ end -}}
)

install_system_packages() { :; }

install_packages() {
  local -n _cli="$1"
  local -n _gui="$2"
  local brewfile=""
  for pkg in "${_cli[@]}" "${_gui[@]}"; do
    local name="${BREW_NAME[$pkg]:-$pkg}"
    if [[ -n "${BREW_CASK[$name]:-}" ]]; then
      brewfile+="cask \"$name\""$'\n'
    else
      brewfile+="brew \"$name\""$'\n'
    fi
  done
  brew bundle --file=- <<< "$brewfile"
}
