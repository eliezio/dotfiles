# Debian / Ubuntu installer adapter (apt + Nix single-user).
#
#   install_packages CLI_REF GUI_REF
#     Both refs are merged into a single `nix profile add` call.
#     Packages mapped to "__SKIP__" in NIX_NAME are omitted.
#   install_system_packages
#     apt-get update + apt-get install over SYSTEM_PKGS
#     (templated from .packages.system.debian).

SYSTEM_PKGS=({{ range .packages.system.debian }}{{ . }} {{ end }})

declare -A NIX_NAME=(
{{ range concat .packages.cli .packages.gui -}}
{{ if hasKey . "nix" }}  [{{ .name }}]={{ .nix }}
{{ end -}}
{{ end -}}
)

install_nix() {
    log_step "Installing Nix..."
    curl -fsSL https://nixos.org/nix/install | sh -s -- --no-daemon --no-modify-profile
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
    log_success "Nix installed"
}

ensure_nix_feature() {
  local nix_conf="$HOME/.config/nix/nix.conf"
  mkdir -p "$(dirname "$nix_conf")"
  touch "$nix_conf"

  if ! grep -Eq '^experimental-features\s*=.*\bnix-command\b.*\bflakes\b' "$nix_conf"; then
    echo "experimental-features = nix-command flakes" >> "$nix_conf"
  fi
}

install_system_packages() {
  sudo apt-get update
  sudo apt-get install --yes --no-install-recommends "${SYSTEM_PKGS[@]}"
}

install_packages() {
  local -n _cli="$1"
  local -n _gui="$2"

  if ! command -v nix &>/dev/null; then
    install_nix
  fi

  ensure_nix_feature

  local nix_pkgs=()
  for pkg in "${_cli[@]}" "${_gui[@]}"; do
    local name="${NIX_NAME[$pkg]:-$pkg}"
    if [[ "$name" != "__SKIP__" ]]; then
      nix_pkgs+=("nixpkgs#$name")
    fi
  done

  log_step "Installing Nix packages..."
  nix profile add "${nix_pkgs[@]}"
  log_success "Nix packages installed"
}
