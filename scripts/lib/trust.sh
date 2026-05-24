# Trust roots / trust bundle module — apply phase.
#
# Single source of truth for where the *.crt files live and where the
# concatenated bundle goes. Sourceable from apply.sh; included via
# {{ include }} into chezmoi-managed scripts (e.g. run_once_*.sh.tmpl).
#
# Apply phase: $CERTS_SOURCE_DIR points at the chezmoi source state.
# Runtime phase: falls back to $XDG_DATA_HOME/certs (deployed location).

trust_certs_dir() {
  echo "${CERTS_SOURCE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/certs}"
}

trust_bundle_path() {
  echo "${XDG_DATA_HOME:-$HOME/.local/share}/certs/certs-bundle.pem"
}

# Print one trust-root path per line; prints nothing if none exist.
trust_cert_files() {
  local dir
  dir=$(trust_certs_dir)
  shopt -s nullglob
  local files=("$dir"/*.crt)
  shopt -u nullglob
  if (( ${#files[@]} )); then
    printf '%s\n' "${files[@]}"
  fi
}

# Build the concatenated bundle from the trust roots. Idempotent. No-op if
# there are no trust roots.
trust_build_bundle() {
  local files=()
  while IFS= read -r f; do files+=("$f"); done < <(trust_cert_files)
  (( ${#files[@]} == 0 )) && return 0
  local bundle
  bundle=$(trust_bundle_path)
  mkdir -p "$(dirname "$bundle")"
  # Newline after each block so PEM headers/footers never glue together when
  # a source file lacks a trailing newline.
  {
    for cert in "${files[@]}"; do
      cat "$cert"
      echo
    done
  } > "$bundle"
}

# Export the bundle path under env-var names expected by RUNTIME.
# No-op if the bundle hasn't been built.
#   curl-nix -> SSL_CERT_FILE, NIX_SSL_CERT_FILE, CURL_CA_BUNDLE
#   node     -> NODE_EXTRA_CA_CERTS
#   python   -> REQUESTS_CA_BUNDLE
trust_export_bundle() {
  local bundle
  bundle=$(trust_bundle_path)
  [[ -f "$bundle" ]] || return 0
  case "$1" in
    curl-nix)
      export SSL_CERT_FILE="$bundle"
      export NIX_SSL_CERT_FILE="$bundle"
      export CURL_CA_BUNDLE="$bundle"
      ;;
    node)
      export NODE_EXTRA_CA_CERTS="$bundle"
      ;;
    python)
      export REQUESTS_CA_BUNDLE="$bundle"
      ;;
    *)
      echo "trust_export_bundle: unknown runtime '$1'" >&2
      return 1
      ;;
  esac
}
