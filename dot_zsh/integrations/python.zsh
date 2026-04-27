_certs_bundle="${XDG_DATA_HOME:-$HOME/.local/share}/certs/certs-bundle.pem"
if [[ -f $_certs_bundle ]]; then
  export REQUESTS_CA_BUNDLE=$_certs_bundle
fi
unset _certs_bundle
