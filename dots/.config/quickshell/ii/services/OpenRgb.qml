pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
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
    // Mode for the next apply: "static" for accent syncs, "direct" for the
    // ambient loop (transient streaming writes; also supported by devices
    // that have no static mode, and spares controller flash at Hz rates).
    property string pendingMode: "static"
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
        // While the ambient loop drives the hardware, accent changes must not
        // fight it; the loop's deactivation snaps back to the accent.
        if (root.ambientActive)
            return;
        const hex = root.hexOf(Appearance.m3colors.m3primary);
        if (hex === root.lastAppliedColor)
            return;
        root.pendingColor = hex;
        // "static" persists on-device where supported (the CLI counterpart of
        // upstream's SDK direct-mode writes); the ambient loop uses "direct".
        root.pendingMode = "static";
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
        // shell string.
        applyProc.command = ["openrgb", "--mode", root.pendingMode, "--color", hex];
        applyProc.running = true;
    }

    function startExclusionApply() {
        if (applyProc.running)
            return;
        const hex = root.pendingColor;
        root.pendingColor = "";
        if (hex === "")
            return;
        const cmd = root.buildDeviceCommand(hex, root.devices, root.excludedDevices, root.pendingMode);
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
    function buildDeviceCommand(hex, devices, excluded, mode = "static") {
        const cmd = ["openrgb"];
        let any = false;
        for (const dev of devices) {
            if (excluded.includes(dev.name))
                continue;
            cmd.push("--device", String(dev.index), "--mode", mode, "--color", hex);
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
            // Keep OpenRGB's detector toggles in step: an excluded device
            // must not even be *claimed* by our managed server. A change
            // restarts the server so it takes effect.
            if (root.monitorMode && !detectorSyncProc.running) {
                detectorSyncProc.thenStartServer = false;
                detectorSyncProc.running = true;
            }
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

    // --- Ambient (monitor color) sync ------------------------------------
    //
    // With colorSource "monitor", a low-rate loop samples the focused
    // monitor's dominant color and feeds it into the same apply machinery as
    // the accent path: grim captures a downscaled frame to the cache,
    // Quickshell's ColorQuantizer reduces it to one representative color, a
    // deadband drops near-identical samples and an optional half-way blend
    // smooths hard scene cuts. By default the loop only runs while a
    // fullscreen client is on the focused monitor (HyprlandData's derived
    // flag); leaving that state snaps the lights back to the accent.
    //
    // Continuous writes are only sane against a running OpenRGB SDK server:
    // without one every CLI call does a full hardware detection pass
    // (seconds, and it resets devices to their default color - the lights
    // just show white). So ambient activation probes the server port and
    // starts a managed `openrgb --server` when nothing answers; sampling
    // stays gated until the port accepts. The server is left running (the
    // accent path benefits from the fast client mode too) and dies with the
    // shell process.

    readonly property string colorSource: Config.options.appearance.openrgb.colorSource ?? "accent"
    readonly property bool monitorMode: root.enabled && root.colorSource === "monitor"
    readonly property bool ambientActive: root.monitorMode
        && !GlobalStates.screenLocked
        && (!(Config.options.appearance.openrgb.monitorFullscreenOnly ?? true)
            || HyprlandData.focusedMonitorHasFullscreen)
    property bool grimAvailable: false
    property bool serverReady: false
    property bool serverSpawnAttempted: false
    readonly property string ambientDir: FileUtils.trimFileProtocol(`${Directories.cache}/openrgb`)
    readonly property string ambientFramePath: `${root.ambientDir}/ambient-frame.jpg`
    readonly property string detectorSyncScript: `${Directories.scriptPath}/rgb/sync_openrgb_detectors.py`
    readonly property string detectorStatePath: FileUtils.trimFileProtocol(`${Directories.state}/user/openrgb-detectors.json`)

    onAmbientActiveChanged: {
        if (root.ambientActive) {
            Quickshell.execDetached(["mkdir", "-p", root.ambientDir]);
            grimProbeProc.running = false;
            grimProbeProc.running = true;
            // One spawn attempt per activation - a crash-looping server
            // should not be respawned every poll tick.
            root.serverSpawnAttempted = false;
            serverProbeProc.running = false;
            serverProbeProc.running = true;
        } else {
            // Snap back to the accent (debounced): clear the dedup color so
            // the accent re-applies even when it equals the last ambient write.
            root.lastAppliedColor = "";
            root.scheduleApply();
        }
    }

    function captureAmbientFrame() {
        if (grimProc.running)
            return;
        // The name comes straight from hyprctl's monitor list; no focused
        // monitor means nothing sensible to sample this tick.
        const name = HyprlandData.monitors.find(m => m.focused)?.name ?? "";
        if (name === "")
            return;
        // Monitor name and output path are their own argv elements - never
        // spliced into a shell string. -s 0.125 downscales in-compositor (the
        // quantizer rescales further), jpeg keeps the per-sample disk write
        // tiny (~30KB vs ~850KB png), and grim omits the cursor by default.
        grimProc.command = ["grim", "-o", name, "-s", "0.125", "-t", "jpeg", "-q", "80", root.ambientFramePath];
        grimProc.running = true;
    }

    function handleAmbientSample(color) {
        if (!root.ambientActive)
            return;
        let hex = root.hexOf(color);
        if (root.lastAppliedColor !== "") {
            const threshold = Config.options.appearance.openrgb.monitorColorDelta ?? 12;
            if (root.colorDelta(hex, root.lastAppliedColor) < threshold)
                return; // Deadband: near-static scene, skip the device write
            if (Config.options.appearance.openrgb.monitorSmooth ?? true)
                hex = root.mixHex(root.lastAppliedColor, hex, 0.5);
        }
        root.pendingColor = hex;
        // Transient streaming mode: no per-write mode persistence, and it
        // exists on devices that lack "static" (gamepads, some keyboards).
        root.pendingMode = "direct";
        availabilityProc.running = false;
        availabilityProc.running = true;
    }

    // Pure: summed per-channel absolute difference of two RRGGBB hex strings
    // (0-765). Malformed input counts as maximally different.
    function colorDelta(hexA, hexB) {
        const a = parseInt(hexA, 16), b = parseInt(hexB, 16);
        if (isNaN(a) || isNaN(b) || hexA.length !== 6 || hexB.length !== 6)
            return 765;
        return Math.abs((a >> 16) - (b >> 16))
            + Math.abs(((a >> 8) & 0xff) - ((b >> 8) & 0xff))
            + Math.abs((a & 0xff) - (b & 0xff));
    }

    // Pure: per-channel linear blend of two RRGGBB hex strings; t=0 keeps a,
    // t=1 lands on b. Malformed endpoints fall back to the other one.
    function mixHex(hexA, hexB, t) {
        const a = parseInt(hexA, 16), b = parseInt(hexB, 16);
        if (isNaN(a) || hexA.length !== 6)
            return hexB;
        if (isNaN(b) || hexB.length !== 6)
            return hexA;
        const ch = shift => Math.round(((a >> shift) & 0xff) * (1 - t) + ((b >> shift) & 0xff) * t);
        const hex = n => n.toString(16).padStart(2, "0");
        return (hex(ch(16)) + hex(ch(8)) + hex(ch(0))).toUpperCase();
    }

    Timer {
        id: ambientTimer
        running: root.ambientActive && root.grimAvailable && root.serverReady
        interval: Config.options.appearance.openrgb.monitorPollInterval ?? 200
        repeat: true
        triggeredOnStart: true
        onTriggered: root.captureAmbientFrame()
    }

    // Re-probes the SDK server port until it answers (covers both our own
    // server starting up and one the user runs themselves).
    Timer {
        id: serverPollTimer
        running: root.ambientActive && !root.serverReady
        interval: 1000
        repeat: true
        onTriggered: {
            if (!serverProbeProc.running)
                serverProbeProc.running = true;
        }
    }

    Process {
        id: grimProbeProc
        // Constant command string - no values are spliced in.
        command: ["bash", "-c", "command -v grim"]
        onExited: (exitCode, exitStatus) => {
            root.grimAvailable = exitCode === 0; // Graceful no-op without grim
        }
    }

    Process {
        id: serverProbeProc
        // Constant command string - no values are spliced in. Exit 0 iff the
        // local OpenRGB SDK server port accepts a connection.
        command: ["bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/6742"]
        onExited: (exitCode, exitStatus) => {
            root.serverReady = exitCode === 0;
            if (root.serverReady || !root.ambientActive)
                return;
            if (!root.serverSpawnAttempted && !serverProc.running && !detectorSyncProc.running) {
                root.serverSpawnAttempted = true;
                // Detector sync runs first so the server never claims an
                // excluded device; its completion starts the server.
                detectorSyncProc.thenStartServer = true;
                detectorSyncProc.running = true;
            }
        }
    }

    // Flips OpenRGB's own detector toggles off for excluded devices (and
    // restores the ones we disabled once un-excluded): exclusion must also
    // keep the server from *claiming* a device, which would override its
    // firmware lighting even without a single color write. Device names are
    // passed as their own argv elements - nothing is shell-spliced. Only a
    // server we manage can be restarted; a user-run server keeps its old
    // detector set until they restart it themselves.
    Process {
        id: detectorSyncProc
        property bool thenStartServer: false
        command: ["python3", root.detectorSyncScript, root.detectorStatePath].concat(root.excludedDevices)
        stdout: StdioCollector {
            onStreamFinished: {
                const changed = text.trim() === "changed";
                if (detectorSyncProc.thenStartServer) {
                    serverProc.running = true;
                } else if (changed && serverProc.running) {
                    serverProc.running = false;
                    serverProc.running = true;
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                console.warn("[OpenRgb] detector sync exited with code", exitCode);
        }
    }

    Process {
        id: serverProc
        // Constant argv - nothing is spliced in. One detection pass at
        // startup, then devices stay open for fast SDK-client writes.
        command: ["openrgb", "--server"]
        onExited: (exitCode, exitStatus) => {
            root.serverReady = false;
            if (exitCode !== 0)
                console.warn("[OpenRgb] openrgb --server exited with code", exitCode);
        }
    }

    Process {
        id: grimProc
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                return; // Transient capture failure; the next tick retries
            // The path never changes, so null the source first - the
            // quantizer re-reads the file instead of trusting an unchanged URL.
            ambientQuantizer.source = "";
            ambientQuantizer.source = "file://" + root.ambientFramePath;
        }
    }

    ColorQuantizer {
        id: ambientQuantizer
        depth: 0 // 2^0 = 1 color: the representative average
        rescaleSize: 64
        onColorsChanged: {
            if (colors.length > 0)
                root.handleAmbientSample(colors[0]);
        }
    }
}
