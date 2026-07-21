#!/usr/bin/env bash
set -u

action="${1:-}"
project_path="${2:-}"
fps="${3:-30}"
scaling="${4:-fill}"
silent="${5:-true}"

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/user/wallpaper-engine"
restore_dir="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/custom/scripts"
restore_script="$restore_dir/__restore_video_wallpaper.sh"
log_file="$state_dir/runtime.log"

stop_engine() {
    # Match the full command line: Linux truncates comm names to 15 bytes, so
    # `pkill -x linux-wallpaperengine` cannot reliably find this executable.
    pkill -f '(^|/)[l]inux-wallpaperengine( |$)' 2>/dev/null || true
}

if [[ "$action" == "stop" ]]; then
    stop_engine
    exit 0
fi

if [[ "$action" != "apply" || ! -d "$project_path" ]]; then
    echo "Usage: $0 apply PROJECT_PATH [FPS] [SCALING] [SILENT]" >&2
    exit 2
fi

for tool in linux-wallpaperengine hyprctl jq; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "$tool is not installed" >&2
        exit 127
    }
done

[[ "$fps" =~ ^[0-9]+$ ]] || fps=30
case "$scaling" in fill|fit|stretch|default) ;; *) scaling=fill ;; esac

mapfile -t monitors < <(hyprctl monitors -j | jq -r '.[].name')
if (( ${#monitors[@]} == 0 )); then
    echo "No Hyprland monitors found" >&2
    exit 1
fi

args=(--fps "$fps")
[[ "$silent" == "true" ]] && args+=(--silent)
for monitor in "${monitors[@]}"; do
    args+=(--screen-root "$monitor" --scaling "$scaling")
done
args+=("$project_path")

mkdir -p "$state_dir" "$restore_dir"
stop_engine
pkill -x mpvpaper 2>/dev/null || true
setsid linux-wallpaperengine "${args[@]}" >>"$log_file" 2>&1 &

printf '%q ' linux-wallpaperengine "${args[@]}" >"$restore_script.tmp"
printf '>>%q 2>&1 &\n' "$log_file" >>"$restore_script.tmp"
{
    printf '#!/usr/bin/env bash\n'
    printf "pkill -f '(^|/)[l]inux-wallpaperengine( |$)' 2>/dev/null || true\n"
    cat "$restore_script.tmp"
} >"$restore_script"
rm -f "$restore_script.tmp"
chmod +x "$restore_script"
