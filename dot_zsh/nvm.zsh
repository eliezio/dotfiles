nvm_path=(/usr/share/nvm)
(( ${+commands[brew]} )) && nvm_path += $(brew --prefix)/opt/nvm

for path in nvm_path; do
  if [ -s "$path/nvm.sh" ]; then
    export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
    mkdir -p "$NVM_DIR"
    \. "$path/nvm.sh" # This loads nvm
    break
  fi
done

