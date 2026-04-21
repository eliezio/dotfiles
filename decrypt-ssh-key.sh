#!/bin/bash

set -euo pipefail

# Usage: ./decrypt-ssh-key.sh <path_to_encrypted_key>
KEY_PATH="$1"

# 1. Create a secure temporary directory
# On macOS, mktemp -d creates a directory in $TMPDIR
if [ "$(uname -s)" = "Linux" ]; then
  TMP_KEY=$(mktemp -p /dev/shm)
else
  TMP_KEY=$(mktemp)
fi

# 2. Ensure cleanup happens on exit (success or failure)
# SIGINT (Ctrl+C), SIGTERM (Kill), and EXIT (End of script)
trap 'rm -f "$TMP_KEY"' EXIT SIGINT SIGTERM

# 3. Setup key file in the temp directory
cp "$KEY_PATH" "$TMP_KEY"
chmod 600 "$TMP_KEY"

# 4. Strip passphrase in-place
# -P: current passphrase, -N "": new empty passphrase
ssh-keygen -p -N "" -f "$TMP_KEY" > /dev/null

# 5. Output the unencrypted key to stdout for SOPS
cat "$TMP_KEY"
