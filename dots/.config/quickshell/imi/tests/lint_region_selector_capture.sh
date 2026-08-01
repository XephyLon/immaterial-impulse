#!/usr/bin/env bash
# The selector preview and the eventual crop must use the same grim output.
# A separate frozen ScreencopyView may return a stale compositor buffer.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET="$PROJECT_ROOT/modules/imi/regionSelector/RegionSelection.qml"

if grep -qP '^\s*ScreencopyView\s*\{' "$TARGET"; then
    echo "Region selector capture lint FAILED: preview must not use an independent screencopy" >&2
    exit 1
fi

if ! grep -q 'source: root.screenshotSource' "$TARGET" || ! grep -q 'cache: false' "$TARGET"; then
    echo "Region selector capture lint FAILED: preview must load the uncached fresh grim output" >&2
    exit 1
fi

if ! grep -q 'status === Image.Ready' "$TARGET"; then
    echo "Region selector capture lint FAILED: selector must wait for the fresh image to decode" >&2
    exit 1
fi

echo "Region selector capture lint passed: preview and crop share one fresh frame"
