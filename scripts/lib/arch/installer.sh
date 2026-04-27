# Arch / Manjaro installer (pacman + yay). Expects CLI_PKGS, GUI_PKGS,
# resolve_name in scope.

SYSTEM_PKGS=({{ range .packages.system.arch }}{{ . }} {{ end }})

declare -A ARCH_NAME=(
{{ range concat .packages.cli .packages.gui -}}
{{ if hasKey . "arch" }}  [{{ .name }}]={{ .arch }}
{{ end -}}
{{ end -}}
)

CUSTOM_PACMAN_CONF=$(mktemp)
sed -e 's/^#Color/Color\nILoveCandy/' < /etc/pacman.conf > $CUSTOM_PACMAN_CONF
trap "rm -f $CUSTOM_PACMAN_CONF" EXIT ERR INT


install_system_packages() {
  sudo pacman --config=$CUSTOM_PACMAN_CONF -S --refresh --needed --noconfirm --color=always "${SYSTEM_PKGS[@]}"
}

install_packages() {
  local arch_pkgs=()
  for pkg in "${CLI_PKGS[@]}" "${GUI_PKGS[@]}"; do
    local resolved
    resolved=$(resolve_name "$pkg" ARCH_NAME)
    arch_pkgs+=("$resolved")
  done
  yay --config=$CUSTOM_PACMAN_CONF -S --needed --noconfirm --answerdiff None --answerclean None --color=always "${arch_pkgs[@]}"
}
