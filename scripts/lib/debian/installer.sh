# Debian / Ubuntu installer adapter (apt + mise.run).
#
#   install_system_packages
#     apt-get update + apt-get install over SYSTEM_PKGS
#     (templated from .packages.system.debian), then install_mise
#     (scripts/lib/mise_run.sh): Debian/Ubuntu do not package mise.
#   install_gui_packages GUI_REF
#     No source for the GUI list here; logs what is skipped.

SYSTEM_PKGS=({{ range .packages.system.debian }}{{ . }} {{ end }})

install_system_packages() {
  # Quiet apt; of dpkg's chatter keep one "Setting up" line per package.
  # Errors still reach stderr, and pipefail keeps apt-get's exit status.
  local -a apt=(sudo env DEBIAN_FRONTEND=noninteractive LC_ALL=C apt-get -qq)
  "${apt[@]}" update
  "${apt[@]}" install --yes --no-install-recommends "${SYSTEM_PKGS[@]}" |
    sed -un 's/^Setting up \([^ :]*\)[^ ]* (\([^)]*\)).*/\1 \2/p' |
    while read -r pkg version; do
      log_info "apt: $pkg $version"
    done
  install_mise
}

install_gui_packages() {
  local -n _gui="$1"
  log_info "No GUI package source on Debian; skipping: ${_gui[*]}"
}
