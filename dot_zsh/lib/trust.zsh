# Trust roots / trust bundle module — runtime phase.
#
# Mirror of scripts/lib/trust.sh in zsh idioms. Source from .zsh integrations
# and standalone zsh utilities (e.g. jvm-import-pem-cacerts.zsh).
#
# Runtime only: reads trust roots from the deployed $XDG_DATA_HOME/certs.

trust_certs_dir()   { echo "${XDG_DATA_HOME:-$HOME/.local/share}/certs" }
trust_bundle_path() { echo "${XDG_DATA_HOME:-$HOME/.local/share}/certs/certs-bundle.pem" }

# Print one trust-root path per line; prints nothing if none exist.
trust_cert_files() {
  local dir; dir=$(trust_certs_dir)
  print -l -- "$dir"/*.crt(N)
}

# Export the bundle path under env-var names expected by RUNTIME.
# No-op if the bundle hasn't been built.
trust_export_bundle() {
  local bundle; bundle=$(trust_bundle_path)
  [[ -f $bundle ]] || return 0
  case "$1" in
    node)   export NODE_EXTRA_CA_CERTS=$bundle ;;
    python) export REQUESTS_CA_BUNDLE=$bundle ;;
    *)      echo "trust_export_bundle: unknown runtime '$1'" >&2; return 1 ;;
  esac
}
