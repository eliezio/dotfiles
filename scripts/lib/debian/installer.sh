# Debian / Ubuntu installer (apt + Nix single-user). Expects CLI_PKGS,
# resolve_name, log_step, log_success in scope.

SYSTEM_PKGS=({{ range .packages.system.debian }}{{ . }} {{ end }})

declare -A NIX_NAME=(
{{ range .packages.cli -}}
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
  if ! command -v nix &>/dev/null; then
    install_nix
  fi

  ensure_nix_feature

  local nix_pkgs=()
  for pkg in "${CLI_PKGS[@]}"; do
    local resolved
    resolved=$(resolve_name "$pkg" NIX_NAME)
    if [[ "$resolved" != "__SKIP__" ]]; then
      nix_pkgs+=("nixpkgs#$resolved")
    fi
  done

  log_step "Installing Nix packages..."
  nix profile add "${nix_pkgs[@]}"
  log_success "Nix packages installed"
}
