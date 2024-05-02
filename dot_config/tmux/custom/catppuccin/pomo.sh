show_pomo() {
  local index data icon color text module

  index=$1
  icon="$(  get_tmux_option "@catppuccin_pomo_icon"  "🍅")"
  color="$( get_tmux_option "@catppuccin_pomo_color" "$thm_red" )"
  text="$(  get_tmux_option "@catppuccin_pomo_text"  "#(pomo | cut -c2-)")"

  module=$( build_status_module "$index" "$icon" "$color" "$text" )

  echo "$module"
}

