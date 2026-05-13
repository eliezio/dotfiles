if (( $+commands[fabric-ai] )); then
  alias fabric=fabric-ai
fi

# Loop through all files in the ~/.config/fabric/patterns directory
for pattern_file in $HOME/.config/fabric/patterns/*(N); do
    # Get the base name of the file using zsh's :t modifier
    local pattern_name=${pattern_file:t}
    local alias_name="${FABRIC_ALIAS_PREFIX:-}${pattern_name}"

    # Create an alias: alias pattern_name="fabric --pattern pattern_name"
    alias $alias_name="fabric --pattern $pattern_name"
done

yt() {
    if (( $# == 0 || $# > 2 )); then
        print -u2 "Usage: yt [-t | --timestamps] youtube-link"
        print -u2 "Use the '-t' flag to get the transcript with timestamps."
        return 1
    fi

    local transcript_flag="--transcript"
    if [[ "$1" == "-t" || "$1" == "--timestamps" ]]; then
        transcript_flag="--transcript-with-timestamps"
        shift
    fi

    local video_link="$1"
    fabric -y "$video_link" $transcript_flag
}
