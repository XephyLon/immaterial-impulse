#!/usr/bin/env bash
set -euo pipefail

xdg_config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
xdg_state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_file="$xdg_config_home/matugen/config.toml"
generated_dir="$xdg_state_home/quickshell/user/generated/apps"
begin_marker="# BEGIN immaterial-impulse application themes"
end_marker="# END immaterial-impulse application themes"

mkdir -p "$(dirname "$config_file")" "$generated_dir"
touch "$config_file"

tmp="${config_file}.immaterial-impulse.$$"
awk -v begin="$begin_marker" -v end="$end_marker" '
    $0 == begin { managed = 1; next }
    $0 == end { managed = 0; next }
    !managed { print }
' "$config_file" > "$tmp"

if ! grep -q '^\[config\][[:space:]]*$' "$tmp"; then
    bootstrap="${tmp}.bootstrap"
    printf '[config]\nversion_check = false\n\n' > "$bootstrap"
    cat "$tmp" >> "$bootstrap"
    mv "$bootstrap" "$tmp"
fi

{
    printf '\n%s\n' "$begin_marker"
    printf '[templates.end4_cava]\ninput_path = %c%s%c\noutput_path = %c%s/cava.ini%c\n\n' "'" "$script_dir/templates/cava.ini" "'" "'" "$generated_dir" "'"
    printf '[templates.end4_btop]\ninput_path = %c%s%c\noutput_path = %c%s/btop.theme%c\n\n' "'" "$script_dir/templates/btop.theme" "'" "'" "$generated_dir" "'"
    printf '[templates.end4_tmux]\ninput_path = %c%s%c\noutput_path = %c%s/tmux.conf%c\n' "'" "$script_dir/templates/tmux.conf" "'" "'" "$generated_dir" "'"
    printf '%s\n' "$end_marker"
} >> "$tmp"

mv "$tmp" "$config_file"
