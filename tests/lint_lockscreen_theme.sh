#!/usr/bin/env bash
# Lock colors are transient shell state. MaterialThemeLoader must be their only
# owner; launching switchwall on lock/unlock races the loader and overwrites the
# persisted desktop theme. The venv wrapper is also required because the Python
# generator's legacy shebang does not preserve wallpaper paths containing spaces.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCK_SCREEN="$PROJECT_ROOT/modules/common/panels/lock/LockScreen.qml"
LOCK="$PROJECT_ROOT/modules/ii/lock/Lock.qml"
THEME_LOADER="$PROJECT_ROOT/services/MaterialThemeLoader.qml"
WRAPPER="$PROJECT_ROOT/scripts/colors/generate-colors-venv.sh"
APPEARANCE="$PROJECT_ROOT/modules/common/Appearance.qml"
BACKGROUND="$PROJECT_ROOT/modules/ii/background/Background.qml"

if grep -q 'applyColorsOnly' "$LOCK_SCREEN"; then
    echo "Lockscreen theme lint FAILED: LockScreen must not launch persistent color generation" >&2
    exit 1
fi

if grep -qE '2147483647|savedWorkspaces|restoreTimer' "$LOCK"; then
    echo "Lockscreen theme lint FAILED: locking must not mutate Hyprland workspaces" >&2
    exit 1
fi

if ! grep -q 'scripts/colors/generate-colors-venv.sh' "$THEME_LOADER"; then
    echo "Lockscreen theme lint FAILED: MaterialThemeLoader must use the argument-safe venv wrapper" >&2
    exit 1
fi

if ! grep -q 'cachedLockColors' "$THEME_LOADER"; then
    echo "Lockscreen theme lint FAILED: lock colors must be precomputed instead of generated during entry" >&2
    exit 1
fi

if ! grep -q 'interval: Appearance.animation.elementMoveFast.duration' "$THEME_LOADER"; then
    echo "Lockscreen theme lint FAILED: palette animation must not overlap lock movement" >&2
    exit 1
fi

if ! grep -q 'exec python3 .*generate_colors_material.py.*"\$@"' "$WRAPPER"; then
    echo "Lockscreen theme lint FAILED: generator wrapper must preserve argument boundaries" >&2
    exit 1
fi

if ! grep -qP '^import qs\s*$' "$APPEARANCE"; then
    echo "Lockscreen theme lint FAILED: Appearance must import GlobalStates from qs" >&2
    exit 1
fi

if ! grep -q 'transitionAnim.stop()' "$BACKGROUND" \
        || ! grep -q 'wallpaperTransitionGeneration' "$BACKGROUND" \
        || ! grep -q 'Qt.callLater(function()' "$BACKGROUND"; then
    echo "Lockscreen theme lint FAILED: cached wallpaper transitions must be restarted safely" >&2
    exit 1
fi

if ! grep -q 'wallpaperPath: bgRoot.wallpaperPath' "$BACKGROUND"; then
    echo "Lockscreen theme lint FAILED: plugin blur must share the background wallpaper source" >&2
    exit 1
fi

echo "Lockscreen theme lint passed: transient colors have one argument-safe owner"
