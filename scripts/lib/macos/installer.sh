# macOS installer (Homebrew). Expects CLI_PKGS, GUI_PKGS, resolve_name in scope.

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

install_packages() {
  local brewfile=""
  for pkg in "${CLI_PKGS[@]}" "${GUI_PKGS[@]}"; do
    local resolved
    resolved=$(resolve_name "$pkg" BREW_NAME)
    if [[ -n "${BREW_CASK[$resolved]:-}" ]]; then
      brewfile+="cask \"$resolved\""$'\n'
    else
      brewfile+="brew \"$resolved\""$'\n'
    fi
  done
  brew bundle --file=- <<< "$brewfile"
}
