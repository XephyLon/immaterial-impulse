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
 *
 * Devices can be excluded from the sync via
 * Config.options.appearance.openrgb.excludedDevices (a list of device names
 * as reported by `openrgb --list-devices`). With exclusions set, every apply
 * re-enumerates devices first - names are the stable key, indices shift when
 * devices (dis)connect - and writes the color per non-excluded device index.
 */
Singleton {
    id: root

    property bool available: false
    property string lastAppliedColor: ""
    property string pendingColor: ""
    // [{ index: int, name: string, type: string }] from the last device scan.
    // Names repeat for identical hardware (e.g. two RAM sticks); exclusion is
    // name-keyed, so excluding one excludes all of its kind.
    property var devices: []
    property bool applyAfterScan: false
    readonly property bool scanning: listProc.running

    readonly property bool enabled: Config.options.appearance.openrgb.enable ?? false
    readonly property list<string> excludedDevices: Config.options.appearance.openrgb.excludedDevices ?? []

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
        if (root.excludedDevices.length > 0) {
            // Per-device apply needs fresh indices; the scan's completion
            // hands off to startExclusionApply().
            root.applyAfterScan = true;
            root.rescanDevices();
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

    function startExclusionApply() {
        if (applyProc.running)
            return;
        const hex = root.pendingColor;
        root.pendingColor = "";
        if (hex === "")
            return;
        const cmd = root.buildDeviceCommand(hex, root.devices, root.excludedDevices);
        if (cmd === null) {
            // Every device excluded, or the scan came back empty: nothing to
            // write. Leave the dedup color cleared so re-including a device
            // (or a later successful scan) triggers a fresh apply.
            root.lastAppliedColor = "";
            return;
        }
        root.lastAppliedColor = hex;
        applyProc.command = cmd;
        applyProc.running = true;
    }

    // Pure: argv for a per-device apply, or null when no device remains.
    // Color and indices are separate argv elements - nothing is shell-spliced.
    function buildDeviceCommand(hex, devices, excluded) {
        const cmd = ["openrgb"];
        let any = false;
        for (const dev of devices) {
            if (excluded.includes(dev.name))
                continue;
            cmd.push("--device", String(dev.index), "--mode", "static", "--color", hex);
            any = true;
        }
        return any ? cmd : null;
    }

    // Pure: parses `openrgb --list-devices` output. Device headers look like
    // "0: Corsair Dominator Titanium RGB DDR5"; the indented "Type:" line
    // that follows is kept for the settings UI.
    function parseDeviceList(text) {
        const devices = [];
        let current = null;
        for (const line of (text ?? "").split("\n")) {
            const header = line.match(/^(\d+): (.+)$/);
            if (header) {
                current = {
                    index: parseInt(header[1], 10),
                    name: header[2].trim(),
                    type: ""
                };
                devices.push(current);
                continue;
            }
            const type = line.match(/^\s+Type:\s+(.+)$/);
            if (type && current)
                current.type = type[1].trim();
        }
        return devices;
    }

    // Kicks a device enumeration (also used by the settings page). Without a
    // running OpenRGB server this does a full hardware detection pass, so it
    // is only ever triggered on demand, never at startup.
    function rescanDevices() {
        if (listProc.running)
            return;
        listProc.running = true;
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
        function onExcludedDevicesChanged() {
            if (!root.enabled)
                return;
            // Re-included devices never got the current color - force a
            // fresh apply (debounced, so rapid toggling coalesces).
            root.lastAppliedColor = "";
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
        id: listProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        // Constant argv - nothing is spliced in.
        command: ["openrgb", "--list-devices"]
        stdout: StdioCollector {
            // The stream closes on process exit, so the parse (and the
            // handed-off apply) always sees the complete listing.
            onStreamFinished: {
                root.devices = root.parseDeviceList(text);
                if (root.applyAfterScan) {
                    root.applyAfterScan = false;
                    root.startExclusionApply();
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                console.warn("[OpenRgb] openrgb --list-devices exited with code", exitCode);
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
