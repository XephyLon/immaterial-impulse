#!/usr/bin/env bash
# A live SystemTrayItem.icon property is backed by StatusNotifierItem D-Bus
# properties. Binding it directly to an image source lets a broken provider
# continuously invalidate image requests, which can peg the QML thread and grow
# anonymous memory without bound. SysTrayItem must mediate it through the
# debounced stableIconSource cache.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET="$PROJECT_ROOT/modules/imi/bar/SysTrayItem.qml"

if grep -qP '^\s*source:\s*root\.item\.icon\s*$' "$TARGET"; then
    echo "System tray icon lint FAILED: do not bind IconImage.source directly to root.item.icon" >&2
    exit 1
fi

if ! grep -qP '^\s*source:\s*root\.stableIconSource\s*$' "$TARGET"; then
    echo "System tray icon lint FAILED: stable tray icon source binding is missing" >&2
    exit 1
fi

echo "System tray icon lint passed: provider icon updates are mediated"
