#!/usr/bin/env bash
# presets.sh - manage shell config presets | just for fun I could have done it from quickshell directly =P
# Usage:
#   presets.sh --save <name>
#   presets.sh --remove <name>
#   presets.sh --apply <name>

CONFIG_DIR="$HOME/.config/immaterial-impulse"
CONFIG_FILE="$CONFIG_DIR/config.json"
PLUGIN_STATE_FILE="$CONFIG_DIR/plugin-state.json"
PRESETS_DIR="$CONFIG_DIR/presets"
# Derive locations from the script itself, so this works regardless of where the
# shell config is installed (no hardcoded config-dir name).
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
SHELL_ROOT="$(dirname "$SCRIPT_DIR")"
SWITCHWALL="$SCRIPT_DIR/colors/switchwall.sh"

mkdir -p "$PRESETS_DIR"

# FileView reacts to every replacement of these files. Avoid replacing an
# identical document: doing so needlessly rebuilds plugin delegates and their
# (potentially monitor-sized) blur textures while a preset is being applied.
replace_if_changed() {
    local candidate="$1"
    local destination="$2"

    if [ -f "$destination" ] && cmp -s "$candidate" "$destination"; then
        rm -f "$candidate"
        return 1
    fi
    mv "$candidate" "$destination"
    return 0
}

action="$1"
name="$2"

if [ -z "$name" ]; then
    echo "Error: missing preset name" >&2
    exit 1
fi

case "$action" in
    --save)
        description="$3"
        plugin_state_snapshot="${4:-}"
        if [ -n "$plugin_state_snapshot" ]; then
            plugin_state="$(printf '%s' "$plugin_state_snapshot" | jq -ce '{
                version: (.version // 2),
                desktopPositions: (.desktopPositions // {}),
                pluginOptions: (.pluginOptions // {})
            }' 2>/dev/null)" || plugin_state=""
        else
            plugin_state=""
        fi
        if [ -z "$plugin_state" ]; then
            plugin_state="$(jq -c '{
            version: (.version // 2),
            desktopPositions: (.desktopPositions // {}),
            pluginOptions: (.pluginOptions // {})
        }' "$PLUGIN_STATE_FILE" 2>/dev/null \
            || printf '{"version":2,"desktopPositions":{},"pluginOptions":{}}')"
        fi
        # A preset is a document people SHARE, and `config.json` holds the
        # user's own OpenWeatherMap key. Saving one used to copy it verbatim,
        # so posting a preset published your key with it. Stripped here rather
        # than on apply: apply merges the preset over the user's config, so a
        # key left in the file would also overwrite the recipient's own.
        # (The AI provider keys are not affected - those live in the keyring,
        # never in this document.)
        jq --argjson pluginState "$plugin_state" \
            'del(._presetMeta, ._pluginState)
             | ._pluginState = $pluginState
             | if .bar.weather.apiKey? then .bar.weather.apiKey = "" else . end' \
            "$CONFIG_FILE" > "$PRESETS_DIR/${name}.json"
        if [ -n "$description" ]; then
            jq --arg desc "$description" '._presetMeta = {"description": $desc}' \
                "$PRESETS_DIR/${name}.json" > "$PRESETS_DIR/${name}.json.tmp" \
                && mv "$PRESETS_DIR/${name}.json.tmp" "$PRESETS_DIR/${name}.json"
        fi
        ;;
    --remove)
        rm -f "$PRESETS_DIR/${name}.json"
        ;;
    --apply)
        preset_file="$PRESETS_DIR/${name}.json"
        if [ ! -f "$preset_file" ]; then
            echo "Error: preset not found: $name" >&2
            exit 1
        fi
        preset_plugin_state="$(jq -c '._pluginState // empty' "$preset_file")"
        # Plugins flagged presetPersist keep their CURRENT options, desktop
        # positions and enabled state through preset application. The flag map
        # itself lives only in the live plugin-state (never captured into a
        # preset's _pluginState snapshot).
        persist_ids="$(jq -c '[(.presetPersist // {}) | to_entries[] | select(.value == true) | .key]' \
            "$PLUGIN_STATE_FILE" 2>/dev/null || printf '[]')"
        if [ -n "$preset_plugin_state" ]; then
            current_plugin_state="$(jq -c '{
                version: (.version // 2),
                desktopPositions: (.desktopPositions // {}),
                pluginOptions: (.pluginOptions // {}),
                presetPersist: (.presetPersist // {})
            }' "$PLUGIN_STATE_FILE" 2>/dev/null \
                || printf '{"version":2,"desktopPositions":{},"pluginOptions":{},"presetPersist":{}}')"
            # Top-level merging keeps fields omitted by older position-only
            # presets, while a new preset's complete maps replace current state.
            jq -n --argjson current "$current_plugin_state" --argjson preset "$preset_plugin_state" \
                --argjson persistIds "$persist_ids" \
                '$current * $preset
                    | .version = 2
                    | .desktopPositions = (if ($preset | has("desktopPositions"))
                        then ($preset.desktopPositions // {})
                        else ($current.desktopPositions // {}) end)
                    | .pluginOptions = (if ($preset | has("pluginOptions"))
                        then ($preset.pluginOptions // {})
                        else ($current.pluginOptions // {}) end)
                    | .presetPersist = ($current.presetPersist // {})
                    | reduce $persistIds[] as $id (.;
                        (if ($current.pluginOptions // {}) | has($id)
                         then .pluginOptions[$id] = $current.pluginOptions[$id]
                         else .pluginOptions |= del(.[$id]) end)
                        | ($current.desktopPositions // {}) as $cpos
                        | .desktopPositions = (reduce (((.desktopPositions // {}) + $cpos) | keys_unsorted[]) as $screen (.desktopPositions // {};
                            if ($cpos[$screen] // {}) | has($id)
                            then .[$screen] = ((.[$screen] // {}) + {($id): $cpos[$screen][$id]})
                            else .[$screen] = ((.[$screen] // {}) | del(.[$id]))
                            end)))' \
                > "${PLUGIN_STATE_FILE}.tmp" \
                && replace_if_changed "${PLUGIN_STATE_FILE}.tmp" "$PLUGIN_STATE_FILE" || true

            # Cancel a pending in-memory debounce and publish the preset state
            # immediately. Without this, a just-edited option can overwrite the
            # externally restored file before FileView reloads it.
            restored_plugin_state="$(jq -c '.' "$PLUGIN_STATE_FILE" 2>/dev/null || true)"
            if [ -n "$restored_plugin_state" ]; then
                qs -p "$SHELL_ROOT" ipc call pluginState replace \
                    "$restored_plugin_state" >/dev/null 2>&1 || true
            fi
        fi
        current_enabled="$(jq -c '.plugins.enabled // []' "$CONFIG_FILE" 2>/dev/null || printf '[]')"
        jq -s --argjson persistIds "$persist_ids" --argjson curEnabled "$current_enabled" \
            '.[0] * .[1] | del(._presetMeta, ._pluginState)
                | if (.plugins.enabled? != null) and ($persistIds | length > 0) then
                    .plugins.enabled = (
                        (.plugins.enabled | map(select(. as $x | ($persistIds | index($x)) | not)))
                        + ($persistIds | map(select(. as $x | ($curEnabled | index($x)) != null))))
                  else . end' \
            "$CONFIG_FILE" "$preset_file" \
            > "${CONFIG_FILE}.tmp" \
            && replace_if_changed "${CONFIG_FILE}.tmp" "$CONFIG_FILE" || true
        engine_path="$(jq -r '.wallpaperSelector.wallpaperEngine.activePath // empty' "$CONFIG_FILE")"
        engine_preview="$(jq -r '.wallpaperSelector.wallpaperEngine.activePreview // empty' "$CONFIG_FILE")"
        if [ -n "$engine_path" ] && [ -d "$engine_path" ] && [ -n "$engine_preview" ]; then
            # A Wallpaper Engine project is selected: theme from its preview. The
            # wallpaper surface renders it off the config on its own.
            "$SWITCHWALL" --noswitch --coloronly --image "$engine_preview"
        else
            "$SWITCHWALL" --noswitch
        fi
        ;;
    *)
        echo "Error: unknown action: $action" >&2
        exit 1
        ;;
esac
