# Arch / Manjaro installer adapter (pacman + yay).
#
#   install_packages CLI_REF GUI_REF
#     Both refs are merged into a single yay call.
#   install_system_packages
#     pacman -S over SYSTEM_PKGS (templated from .packages.system.arch).

SYSTEM_PKGS=({{ range .packages.system.arch }}{{ . }} {{ end }})

declare -A ARCH_NAME=(
{{ range concat .packages.cli .packages.gui -}}
{{ if hasKey . "arch" }}  [{{ .name }}]={{ .arch }}
{{ end -}}
{{ end -}}
)

CUSTOM_PACMAN_CONF=$(mktemp)
sed -Ee 's/^#?Color/Color\nILoveCandy/' < /etc/pacman.conf > $CUSTOM_PACMAN_CONF
trap "rm -f $CUSTOM_PACMAN_CONF" EXIT ERR INT


install_system_packages() {
  sudo pacman --config=$CUSTOM_PACMAN_CONF -S --refresh --needed --noconfirm --color=always "${SYSTEM_PKGS[@]}"
}

install_packages() {
  local -n _cli="$1"
  local -n _gui="$2"
  local arch_pkgs=()
  for pkg in "${_cli[@]}" "${_gui[@]}"; do
    arch_pkgs+=("${ARCH_NAME[$pkg]:-$pkg}")
  done
  yay --config=$CUSTOM_PACMAN_CONF -S --needed --noconfirm --answerdiff=None --answerclean=None --color=always "${arch_pkgs[@]}"
}
