_certs_bundle="${XDG_DATA_HOME:-$HOME/.local/share}/certs/certs-bundle.pem"
if [[ -f $_certs_bundle ]]; then
  export NODE_EXTRA_CA_CERTS=$_certs_bundle
fi
unset _certs_bundle
