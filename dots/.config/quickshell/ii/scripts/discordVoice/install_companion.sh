#!/usr/bin/env bash
# One-shot installer for the End4DiscordVoice Vencord companion.
#
# Vesktop's arRPC socket has no authenticated voice RPC, so the shell's
# Discord voice integration needs a Vencord user plugin publishing voice
# state over a local socket (background: docs/vencord-companion-README.md in
# the repo root). User plugins only exist in source builds of Vencord, so
# this script:
#
#   1. clones (or updates) Vencord into ~/.local/share/immaterial-impulse/Vencord
#   2. copies the companion into src/userplugins/end4DiscordVoice
#   3. builds it with pnpm and stages package.json into dist/
#   4. points Vesktop's "Vencord Location" (state.json) at that dist,
#      backing the original file up first
#
# Then fully restart Vesktop (quit from the tray, not just the window).
#
# Official Discord needs none of this - the shell talks native RPC there.
# Legcord is NOT supported: it bundles its own Vencord with no custom-build
# picker, and the companion needs Vencord's native plugin helpers.
set -euo pipefail

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
VENCORD_DIR="$DATA_HOME/immaterial-impulse/Vencord"
VENCORD_REPO="https://github.com/Vendicated/Vencord.git"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPANION_SRC="$SCRIPT_DIR/vencord-companion"
VESKTOP_STATE="${XDG_CONFIG_HOME:-$HOME/.config}/vesktop/state.json"

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

echo "==> Vencord source: $VENCORD_DIR"
if [[ -d "$VENCORD_DIR/.git" ]]; then
    git -C "$VENCORD_DIR" pull --ff-only
else
    mkdir -p "$(dirname "$VENCORD_DIR")"
    git clone --depth 1 "$VENCORD_REPO" "$VENCORD_DIR"
fi

echo "==> Installing companion user plugin"
mkdir -p "$VENCORD_DIR/src/userplugins"
rm -rf "$VENCORD_DIR/src/userplugins/end4DiscordVoice"
cp -r "$COMPANION_SRC" "$VENCORD_DIR/src/userplugins/end4DiscordVoice"

echo "==> Building Vencord (this takes a minute on first run)"
cd "$VENCORD_DIR"
pnpm install --frozen-lockfile
pnpm build
# Vesktop resolves the mod's version from package.json next to the bundle.
cp package.json dist/

if [[ -f "$VESKTOP_STATE" ]]; then
    echo "==> Pointing Vesktop at the custom build"
    # Vesktop must not be running while its state file is rewritten, or it
    # overwrites the change on exit.
    if pgrep -x vesktop >/dev/null || pgrep -f "vesktop --" >/dev/null; then
        echo "    Vesktop is running - close it fully (tray icon too), then re-run this script."
        exit 1
    fi
    [[ -f "$VESKTOP_STATE.pre-end4-discord" ]] || cp "$VESKTOP_STATE" "$VESKTOP_STATE.pre-end4-discord"
    python3 - "$VESKTOP_STATE" "$VENCORD_DIR/dist" <<'PY'
import json, sys
path, dist = sys.argv[1], sys.argv[2]
state = json.load(open(path))
state["vencordDir"] = dist
with open(path, "w") as handle:
    json.dump(state, handle, indent=4)
    handle.write("\n")
PY
    echo "    done - start Vesktop and the End4DiscordVoice plugin is active."
else
    echo "==> Vesktop config not found ($VESKTOP_STATE)"
    echo "    In Vesktop: Settings -> Vencord Location -> $VENCORD_DIR/dist, then fully restart."
    echo "    (Flatpak Vesktop keeps its config under ~/.var/app - set the location in its UI.)"
fi

echo "==> Done. Re-run this script any time to update Vencord + the companion."
