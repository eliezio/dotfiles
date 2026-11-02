# mise via its official installer, for platforms whose package (if any) lags
# behind the settings in dot_config/mise/config.toml. Checks only the path
# mise.run installs to, so an older distro-packaged mise does not satisfy it;
# ~/.local/bin comes first on PATH, so this one wins.
install_mise() {
  if [[ -x "$HOME/.local/bin/mise" ]]; then
    log_info "mise already installed"
    return 0
  fi
  log_step "Installing mise..."
  curl -fsSL https://mise.run | sh
  log_success "mise installed"
}
