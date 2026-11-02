# Arch / Manjaro installer adapter (pacman; no AUR).
#
#   install_system_packages
#     pacman -S over SYSTEM_PKGS (templated from .packages.system.arch),
#     then install_mise (scripts/lib/mise_run.sh): Manjaro's mise package lags
#     weeks behind upstream.
#   install_gui_packages GUI_REF
#     pacman -S over the GUI names, mapped through ARCH_NAME.

SYSTEM_PKGS=({{ range .packages.system.arch }}{{ . }} {{ end }})

declare -A ARCH_NAME=(
{{ range .packages.gui -}}
{{ if hasKey . "arch" }}  [{{ .name }}]={{ .arch }}
{{ end -}}
{{ end -}}
)

CUSTOM_PACMAN_CONF=$(mktemp)
sed -Ee 's/^#?Color/Color\nILoveCandy/' < /etc/pacman.conf > $CUSTOM_PACMAN_CONF
trap "rm -f $CUSTOM_PACMAN_CONF" EXIT ERR INT


install_system_packages() {
  sudo pacman --config=$CUSTOM_PACMAN_CONF -S --refresh --needed --noconfirm --color=always "${SYSTEM_PKGS[@]}"
  install_mise
}

install_gui_packages() {
  local -n _gui="$1"
  local arch_pkgs=()
  for pkg in "${_gui[@]}"; do
    arch_pkgs+=("${ARCH_NAME[$pkg]:-$pkg}")
  done
  sudo pacman --config=$CUSTOM_PACMAN_CONF -S --needed --noconfirm --color=always "${arch_pkgs[@]}"
}
