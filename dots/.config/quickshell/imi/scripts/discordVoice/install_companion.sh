#!/usr/bin/env bash
# One-shot installer for the End4DiscordVoice client-mod companion.
#
# Vesktop/Equibop's arRPC socket has no authenticated voice RPC, so the
# shell's Discord voice integration needs a user plugin publishing voice
# state over a local socket (background: docs/vencord-companion-README.md in
# the repo root). User plugins only exist in source builds of the client
# mod, so per detected client this script:
#
#   1. clones (or updates) the mod source into ~/.local/share/immaterial-impulse
#      (Vencord for Vesktop, Equicord for Equibop - same plugin API)
#   2. copies the companion into src/userplugins/end4DiscordVoice
#   3. builds it with pnpm and stages package.json into dist/
#   4. points the client's custom-mod location (state.json) at that dist,
#      backing the original file up first
#
# Then fully restart the client (quit from the tray, not just the window).
#
# Usage: install_companion.sh [--client auto|vesktop|equibop]
# Default auto: install for every client with a config directory present.
#
# Official Discord needs none of this - the shell talks native RPC there.
# Legcord is NOT supported: it bundles its own Vencord with no custom-build
# picker, and the companion needs Vencord's native plugin helpers.
set -euo pipefail

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPANION_SRC="$SCRIPT_DIR/vencord-companion"

CLIENT="auto"
if [[ "${1:-}" == "--client" ]]; then
    CLIENT="${2:?--client needs a value (auto|vesktop|equibop)}"
fi

die() { echo "error: $*" >&2; exit 1; }

[[ -d "$COMPANION_SRC" ]] || die "companion source not found at $COMPANION_SRC"
command -v git >/dev/null || die "git is required"
command -v node >/dev/null || die "node is required (install nodejs)"
if ! command -v pnpm >/dev/null; then
    if command -v corepack >/dev/null; then
        echo "pnpm not found; enabling it via corepack..."
        corepack enable pnpm 2>/dev/null || die "pnpm is required (corepack enable pnpm failed)"
    else
        die "pnpm is required (install pnpm, or nodejs with corepack)"
    fi
fi

install_for() {
    local client="$1" repo dir state key proc
    case "$client" in
        vesktop)
            repo="https://github.com/Vendicated/Vencord.git"
            dir="$DATA_HOME/immaterial-impulse/Vencord"
            state="$CONFIG_HOME/vesktop/state.json"
            key="vencordDir"
            proc="vesktop"
            ;;
        equibop)
            repo="https://github.com/Equicord/Equicord.git"
            dir="$DATA_HOME/immaterial-impulse/Equicord"
            state="$CONFIG_HOME/equibop/state.json"
            key="equicordDir"
            proc="equibop"
            ;;
        *) die "unknown client '$client' (auto|vesktop|equibop)" ;;
    esac

    echo "==> [$client] mod source: $dir"
    if [[ -d "$dir/.git" ]]; then
        git -C "$dir" pull --ff-only
    else
        mkdir -p "$(dirname "$dir")"
        git clone --depth 1 "$repo" "$dir"
    fi

    echo "==> [$client] installing companion user plugin"
    mkdir -p "$dir/src/userplugins"
    rm -rf "$dir/src/userplugins/end4DiscordVoice"
    cp -r "$COMPANION_SRC" "$dir/src/userplugins/end4DiscordVoice"

    echo "==> [$client] building (this takes a minute on first run)"
    (cd "$dir" && pnpm install --frozen-lockfile && pnpm build)
    # The client resolves the mod's version from package.json next to the bundle.
    (cd "$dir" && cp package.json dist/)

    if [[ -f "$state" ]]; then
        echo "==> [$client] pointing the client at the custom build"
        # The client must not be running while its state file is rewritten,
        # or it overwrites the change on exit.
        if pgrep -x "$proc" >/dev/null || pgrep -f "$proc --" >/dev/null; then
            echo "    $client is running - close it fully (tray icon too), then re-run this."
            return 1
        fi
        [[ -f "$state.pre-end4-discord" ]] || cp "$state" "$state.pre-end4-discord"
        python3 - "$state" "$key" "$dir/dist" <<'PY'
import json, sys
path, key, dist = sys.argv[1], sys.argv[2], sys.argv[3]
state = json.load(open(path))
state[key] = dist
with open(path, "w") as handle:
    json.dump(state, handle, indent=4)
    handle.write("\n")
PY
        echo "    done - start $client and the End4DiscordVoice plugin is active."
    else
        echo "==> [$client] config not found ($state)"
        echo "    In the client's settings, set the custom mod location to: $dir/dist"
        echo "    then fully restart it. (Flatpak keeps its config under ~/.var/app.)"
    fi
}

clients=()
if [[ "$CLIENT" == "auto" ]]; then
    [[ -d "$CONFIG_HOME/vesktop" ]] && clients+=(vesktop)
    [[ -d "$CONFIG_HOME/equibop" ]] && clients+=(equibop)
    [[ ${#clients[@]} -gt 0 ]] || die "no supported client found (Vesktop or Equibop); install one, or pass --client"
else
    clients=("$CLIENT")
fi

failed=0
for client in "${clients[@]}"; do
    install_for "$client" || failed=1
done
[[ "$failed" -eq 0 ]] || exit 1

echo "==> Done. Re-run this script any time to update the mod + companion."
