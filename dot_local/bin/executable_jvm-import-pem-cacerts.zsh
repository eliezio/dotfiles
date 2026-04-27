#!/usr/bin/env zsh
# jvm-import-pem-cacerts.zsh — Sync ${certs_dir}/*.crt into a JVM's cacerts
# truststore. Idempotent: matches certs by SHA-1 fingerprint. Default
# certs_dir: ${XDG_DATA_HOME:-$HOME/.local/share}/certs.

emulate -L zsh
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_step()    { echo -e "${BLUE}➜${NC} $1" >&2; }
log_success() { echo -e "${GREEN}✓${NC} $1" >&2; }
log_error()   { echo -e "${RED}✗${NC} $1" >&2; }
log_info()    { echo -e "${YELLOW}ℹ${NC} $1" >&2; }

normalize_fp() {
  # Strip colons, uppercase.
  printf '%s' "${(U)${1//:/}}"
}

cert_fingerprint() {
  local cert_path="$1"
  local raw
  raw=$(openssl x509 -in "$cert_path" -noout -fingerprint -sha1 | sed 's/^[^=]*=//')
  normalize_fp "$raw"
}

find_java_home() {
  local explicit="$1"
  if [[ -n "$explicit" ]]; then
    printf '%s' "$explicit"
    return 0
  fi
  local java_bin
  java_bin=$(command -v java) || return 1
  local java_real="${java_bin:A}"  # resolve symlinks
  printf '%s' "${java_real:h:h}"
}

find_cacerts() {
  local java_home="$1" candidate
  for candidate in "$java_home/lib/security/cacerts" "$java_home/jre/lib/security/cacerts"; do
    if [[ -e "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

find_keytool() {
  local java_home="$1"
  local candidate="$java_home/bin/keytool"
  if [[ -x "$candidate" ]]; then
    printf '%s' "$candidate"
    return 0
  fi
  command -v keytool
}

# Globals populated by parse_keystore_fingerprints.
typeset -gA KEYSTORE_FP_TO_ALIAS=()
typeset -gA KEYSTORE_ALIAS_SET=()

parse_keystore_fingerprints() {
  local keytool="$1" cacerts="$2" storepass="$3"
  KEYSTORE_FP_TO_ALIAS=()
  KEYSTORE_ALIAS_SET=()

  local output
  if ! output=$("$keytool" -list -v -keystore "$cacerts" -storepass "$storepass" 2>&1); then
    log_error "$output"
    return 1
  fi

  local current_alias="" line fp
  while IFS= read -r line; do
    if [[ "$line" =~ '^Alias name:[[:space:]]*(.+)$' ]]; then
      current_alias="${match[1]}"
      KEYSTORE_ALIAS_SET[$current_alias]=1
    elif [[ "$line" =~ '^[[:space:]]*SHA1:[[:space:]]*([0-9A-Fa-f:]+)$' ]] && [[ -n "$current_alias" ]]; then
      fp=$(normalize_fp "${match[1]}")
      KEYSTORE_FP_TO_ALIAS[$fp]="$current_alias"
    fi
  done <<< "$output"
}

unique_alias() {
  local base="$1" fp="$2"
  local suffix="${(L)fp[1,4]}"
  local candidate="${base}-${suffix}"
  if [[ -z "${KEYSTORE_ALIAS_SET[$candidate]:-}" ]]; then
    printf '%s' "$candidate"
    return 0
  fi
  local n=1 extended
  while true; do
    extended="${candidate}-${n}"
    if [[ -z "${KEYSTORE_ALIAS_SET[$extended]:-}" ]]; then
      printf '%s' "$extended"
      return 0
    fi
    (( ++n ))
  done
}

import_cert() {
  local keytool="$1" cacerts="$2" storepass="$3" alias_name="$4" cert_path="$5" use_sudo="$6"
  local cmd=("$keytool" -importcert -noprompt -trustcacerts
             -alias "$alias_name" -file "$cert_path"
             -keystore "$cacerts" -storepass "$storepass")
  if [[ "$use_sudo" == "1" ]]; then
    cmd=(sudo "${cmd[@]}")
  fi
  "${cmd[@]}"
}

main() {
  local java_home_arg=""
  local certs_dir="${XDG_DATA_HOME:-$HOME/.local/share}/certs"

  while (( $# > 0 )); do
    case "$1" in
      --java-home) java_home_arg="$2"; shift 2 ;;
      --certs-dir) certs_dir="$2"; shift 2 ;;
      *) log_error "Unknown arg: $1"; return 2 ;;
    esac
  done

  local cert_files=("$certs_dir"/*.crt(N))
  cert_files=("${(o)cert_files[@]}")  # sort

  if (( ${#cert_files[@]} == 0 )); then
    log_info "Skipping JVM truststore import; no .crt files in $certs_dir."
    return 0
  fi

  local java_home
  java_home=$(find_java_home "$java_home_arg") || {
    log_error "Skipping JVM truststore import; java is not available in PATH."
    return 0
  }

  local cacerts
  cacerts=$(find_cacerts "$java_home") || {
    log_error "Skipping JVM truststore import; could not find cacerts under $java_home"
    return 0
  }

  local keytool
  keytool=$(find_keytool "$java_home") || {
    log_error "Skipping JVM truststore import; keytool not found for $java_home"
    return 0
  }

  local storepass="${JVM_CACERTS_STOREPASS:-changeit}"
  local use_sudo=0
  [[ -w "$cacerts" ]] || use_sudo=1

  parse_keystore_fingerprints "$keytool" "$cacerts" "$storepass"

  local imported=0 skipped=0
  local cert_path fingerprint base alias_name
  log_step "Adding certificates to JVM truststore for $java_home..."
  for cert_path in "${cert_files[@]}"; do
    fingerprint=$(cert_fingerprint "$cert_path")
    if [[ -n "${KEYSTORE_FP_TO_ALIAS[$fingerprint]:-}" ]]; then
      (( ++skipped ))
      continue
    fi
    base="${cert_path:t:r}"
    alias_name=$(unique_alias "$base" "$fingerprint")
    import_cert "$keytool" "$cacerts" "$storepass" "$alias_name" "$cert_path" "$use_sudo"
    KEYSTORE_ALIAS_SET[$alias_name]=1
    KEYSTORE_FP_TO_ALIAS[$fingerprint]="$alias_name"
    (( ++imported ))
  done

  local summary="JVM truststore sync complete for $java_home: imported=$imported, skipped=$skipped"
  if (( imported > 0 )); then
    log_success "$summary"
  else
    log_info "$summary"
  fi
}

main "$@"
