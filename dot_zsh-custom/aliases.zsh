alias gw=./gradlew
alias gwp="gw --console=plain"
alias mw=./mvnw

open() {
    for arg in "$@"; do
        xdg-open "$arg" &> /dev/null
    done
}
alias pbcopy='xclip -sel cl -i'
alias pbpaste='xclip -sel cl -o'
