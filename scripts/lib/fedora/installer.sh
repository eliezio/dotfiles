# Fedora installer adapter, targeting Aurora (atomic, image-based Fedora KDE).
# The OS image is read-only, so nothing goes through dnf or rpm-ostree:
# system packages come from the Homebrew that ships with the image.
#
#   install_system_packages
#     brew install over SYSTEM_PKGS (templated from .packages.system.fedora),
#     which includes mise.
#   install_gui_packages GUI_REF
#     No source for the GUI list here; logs what is skipped.

SYSTEM_PKGS=({{ range .packages.system.fedora }}{{ . }} {{ end }})

install_system_packages() {
  if ! command -v brew &>/dev/null; then
    log_error "Homebrew not found; Aurora ships it at /home/linuxbrew/.linuxbrew"
    return 1
  fi
  brew install "${SYSTEM_PKGS[@]}"
}

install_gui_packages() {
  local -n _gui="$1"
  log_info "No GUI package source on Fedora; skipping: ${_gui[*]}"
}
