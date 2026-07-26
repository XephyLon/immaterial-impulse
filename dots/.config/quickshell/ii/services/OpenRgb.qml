pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Syncs RGB peripherals to the Material You accent color via the OpenRGB CLI.
 *
 * Logic ported from end-4/dots-hyprland PR #3415 (OpenRGB integration). The
 * upstream implementation shells into a Python SDK client (openrgb-python +
 * scipy fade interpolation) from applycolor.sh; here that is replaced by a
 * single `openrgb --mode static --color <hex>` invocation - no extra Python
 * dependencies, and the openrgb CLI already talks to a running OpenRGB
 * server instance when one exists.
 *
 * Trigger: upstream fires when applycolor.sh runs after matugen generates a
 * new palette. The equivalent moment in this shell is
 * Appearance.m3colors.m3primary changing after MaterialThemeLoader applies a
 * freshly generated palette; a debounce timer coalesces the per-frame color
 * animation steps and rapid preset/wallpaper switches into one device write.
 *
 * No-ops when Config.options.appearance.openrgb.enable is off (the default)
 * or the openrgb binary is missing. Availability is re-checked before every
 * apply, so installing OpenRGB mid-session needs no shell restart.
 */
Singleton {
    id: root

    property bool available: false
    property string lastAppliedColor: ""
    property string pendingColor: ""

    readonly property bool enabled: Config.options.appearance.openrgb.enable ?? false

    // Referenced from shell.qml's Component.onCompleted so this lazily-loaded
    // singleton is instantiated at startup and starts tracking palette changes.
    function load() {}

    function hexOf(color) {
        let hex = color.toString(); // "#rrggbb" or "#aarrggbb"
        if (hex.length === 9)
            hex = "#" + hex.slice(3); // Drop the alpha component
        return hex.slice(1).toUpperCase();
    }

    function scheduleApply() {
        if (!root.enabled)
            return;
        debounceTimer.restart();
    }

    function requestApply() {
        if (!Config.ready || !root.enabled)
            return;
        // The lockscreen can swap in a temporary palette (lockWall); like
        // upstream, only sync the real desktop palette. Unlocking animates
        // the desktop palette back, which re-triggers the debounce.
        if (GlobalStates.screenLocked)
            return;
        const hex = root.hexOf(Appearance.m3colors.m3primary);
        if (hex === root.lastAppliedColor)
            return;
        root.pendingColor = hex;
        availabilityProc.running = false;
        availabilityProc.running = true;
    }

    function startPendingApply() {
        if (applyProc.running)
            return; // Re-dispatched from applyProc.onExited
        if (root.pendingColor === "" || root.pendingColor === root.lastAppliedColor) {
            root.pendingColor = "";
            return;
        }
        const hex = root.pendingColor;
        root.pendingColor = "";
        root.lastAppliedColor = hex;
        // Color is passed as its own argv element - never spliced into a
        // shell string. "static" persists on-device where supported (the CLI
        // counterpart of upstream's SDK direct-mode writes).
        applyProc.command = ["openrgb", "--mode", "static", "--color", hex];
        applyProc.running = true;
    }

    Timer {
        id: debounceTimer
        interval: 1000
        repeat: false
        onTriggered: root.requestApply()
    }

    Connections {
        target: Appearance.m3colors
        function onM3primaryChanged() {
            root.scheduleApply();
        }
    }

    Connections {
        target: Config.options.appearance.openrgb
        function onEnableChanged() {
            if (!root.enabled)
                return;
            root.lastAppliedColor = ""; // Force a sync on (re-)enable
            root.scheduleApply();
        }
    }

    Process {
        id: availabilityProc
        // Constant command string - no values are spliced in.
        command: ["bash", "-c", "command -v openrgb"]
        running: true
        onExited: (exitCode, exitStatus) => {
            root.available = exitCode === 0;
            if (root.available)
                root.startPendingApply();
            else
                root.pendingColor = ""; // Graceful no-op: openrgb not installed
        }
    }

    Process {
        id: applyProc
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn("[OpenRgb] openrgb exited with code", exitCode);
                // Allow the next palette change to retry after a transient
                // failure (e.g. device busy) instead of deduping against a
                // color that never landed.
                root.lastAppliedColor = "";
            }
            root.startPendingApply();
        }
    }
}
