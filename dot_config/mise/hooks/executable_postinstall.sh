#!/usr/bin/env bash
set -euo pipefail

tools_json="${MISE_INSTALLED_TOOLS:-[]}"
helper="$HOME/.local/bin/jvm-import-pem-cacerts.zsh"

# Extract install_path for every just-installed Java. Fall back to deriving
# from name+version if install_path isn't in the schema.
mise_data_dir="${MISE_DATA_DIR:-$HOME/.local/share/mise}"

java_homes=$(jq -r --arg base "$mise_data_dir" '
  .[]
  | select((type == "string" and . == "java") or (type == "object" and .name == "java"))
  | if type == "object" then
      (.install_path // (if (.version // null) != null then "\($base)/installs/java/\(.version)" else empty end))
    else
      empty
    end
' <<<"$tools_json" 2>/dev/null || true)

[ -n "$java_homes" ] || exit 0

while IFS= read -r java_home; do
  [ -n "$java_home" ] && [ -d "$java_home" ] || continue
  zsh "$helper" --java-home "$java_home"
done <<<"$java_homes"
