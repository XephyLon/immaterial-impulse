pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import qs.modules.common

/**
 * Privacy-style capture activity (macOS/Android indicator dot).
 *
 * Mic: reliable via PipeWire-Pulse. `pactl -f json list source-outputs` lists
 * every recording stream; a stream counts as "recording" only when it is
 * RUNNING (not corked), is a real client stream (has a client / process, not a
 * filter-chain or virtual node), and is NOT capturing a sink monitor
 * (visualizers like cava capture `stream.capture.sink` and must not false-positive).
 *
 * Camera: best-effort. Processes holding a `/dev/video*` node open are found
 * with `fuser`, then mapped to comm names via `ps`. Over-reporting is possible:
 * a webcam commonly exposes several /dev/videoN nodes (capture + metadata), and
 * any open handle - including a probe that never streams frames - is treated as
 * "camera in use". Under-reporting is possible for cameras behind libcamera or
 * a portal that never opens the V4L2 node directly.
 *
 * Command injection: every command is an argv array. The pactl output is parsed
 * as JSON (no shell). The only shell use is the fixed `/dev/video*` glob literal
 * (no dynamic data spliced); the PIDs it yields are validated as integers and
 * passed to `ps` as individual argv, never string-spliced.
 */
Singleton {
    id: root

    readonly property bool enableService: Config.options.bar.privacyIndicator?.enable ?? true
    readonly property bool showMic: Config.options.bar.privacyIndicator?.showMic ?? true
    readonly property bool showCamera: Config.options.bar.privacyIndicator?.showCamera ?? true
    readonly property bool showScreencast: Config.options.bar.privacyIndicator?.showScreencast ?? true
    readonly property bool ignoreAmbientCapture: Config.options.bar.privacyIndicator?.ignoreAmbientCapture ?? true
    readonly property int pollInterval: Config.options.bar.privacyIndicator?.pollInterval ?? 2000

    property bool micActive: false
    property var micApps: []
    property bool cameraActive: false
    property var cameraApps: []
    // Screen sharing/recording via xdg-desktop-portal. Hyprland fires a
    // `screencast` event with "STATE,OWNER" (STATE 1 = a cast is active, 0 =
    // none). Event-driven, so a cast already running before the shell started
    // isn't reflected until it next toggles.
    property bool screencastActive: false

    // Parses `pactl -f json list source-outputs`. Returns { active, apps }.
    // Falls back to text-block parsing when the JSON path is unavailable.
    function parseSourceOutputs(text: string): var {
        const raw = (text ?? "").trim();
        if (raw.length === 0) return { active: false, apps: [] };
        try {
            const arr = JSON.parse(raw);
            if (Array.isArray(arr)) return root._fromJsonSourceOutputs(arr);
        } catch (e) {
            // Older pactl without `-f json`: fall through to text parsing.
        }
        return root._fromTextSourceOutputs(raw);
    }

    // Electron/WebRTC apps all report a generic application.name ("Chromium",
    // "WEBRTC VoiceEngine"); the process binary carries the real identity
    // (e.g. Vesktop). Verified live: Vesktop's stream is
    // application.name="Chromium", application.process.binary="vesktop".
    readonly property var genericAppNames: ["chromium", "chromium input", "electron", "webrtc voiceengine", "chrome input"]
    function resolveAppName(name: var, binary: var): var {
        if (binary && (!name || root.genericAppNames.indexOf(name.toLowerCase()) !== -1))
            return binary.charAt(0).toUpperCase() + binary.slice(1);
        return name;
    }

    function _fromJsonSourceOutputs(arr: var): var {
        const apps = [];
        for (const item of arr) {
            if (!item || item.corked === true) continue; // corked == not RUNNING
            const props = item.properties ?? {};
            if (props["stream.capture.sink"] === "true") continue; // monitor/visualizer
            const isClientStream = (item.client !== null && item.client !== undefined)
                || (props["application.process.id"] !== undefined);
            if (!isClientStream) continue; // filter-chain / virtual node, not an app
            const rawName = props["application.name"] ?? props["media.name"] ?? props["node.name"];
            const name = root.resolveAppName(rawName, props["application.process.binary"]);
            if (name && apps.indexOf(name) === -1) apps.push(name);
        }
        return { active: apps.length > 0, apps: apps };
    }

    function _fromTextSourceOutputs(text: string): var {
        const apps = [];
        const blocks = text.split(/Source Output #/).slice(1);
        for (const block of blocks) {
            if (!/Corked:\s*no/i.test(block)) continue; // not RUNNING
            if (/stream\.capture\.sink\s*=\s*"true"/.test(block)) continue; // monitor
            const clientMatch = block.match(/Client:\s*(.+)/);
            const hasClient = clientMatch !== null && !/^n\/a\s*$/i.test(clientMatch[1].trim());
            const hasProc = /application\.process\.id\s*=/.test(block);
            if (!hasClient && !hasProc) continue;
            const nameMatch = block.match(/application\.name\s*=\s*"([^"]*)"/)
                || block.match(/media\.name\s*=\s*"([^"]*)"/)
                || block.match(/node\.name\s*=\s*"([^"]*)"/);
            const binaryMatch = block.match(/application\.process\.binary\s*=\s*"([^"]*)"/);
            const name = root.resolveAppName(nameMatch ? nameMatch[1] : null,
                binaryMatch ? binaryMatch[1] : null);
            if (name && apps.indexOf(name) === -1) apps.push(name);
        }
        return { active: apps.length > 0, apps: apps };
    }

    // Extracts unique integer PIDs from `fuser` stdout.
    function parsePids(text: string): var {
        const pids = [];
        for (const tok of (text ?? "").trim().split(/\s+/)) {
            if (/^\d+$/.test(tok) && pids.indexOf(tok) === -1) pids.push(tok);
        }
        return pids;
    }

    // Extracts unique trimmed process names from `ps -o comm=` stdout.
    function parseComm(text: string): var {
        const names = [];
        for (const line of (text ?? "").split("\n")) {
            const name = line.trim();
            if (name.length > 0 && names.indexOf(name) === -1) names.push(name);
        }
        return names;
    }

    function refreshMic(): void {
        if (!root.enableService || !root.showMic) return;
        micProc.running = true;
    }

    function refreshCamera(): void {
        if (!root.enableService || !root.showCamera) return;
        cameraProc.running = true;
    }

    onShowMicChanged: if (!showMic) { micActive = false; micApps = []; }
    onShowCameraChanged: if (!showCamera) { cameraActive = false; cameraApps = []; }
    onShowScreencastChanged: if (!showScreencast) screencastActive = false;

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "screencast") return;
            if (!root.showScreencast) { root.screencastActive = false; return; }
            const active = String(event.data ?? "").split(",")[0].trim() === "1";
            // The ambient RGB sampler (OpenRgb) grims a frame every poll
            // tick, firing a millisecond on/off screencast pulse each time -
            // shown raw, the dot blinks once a second for the shell's own
            // capture. While the sampler runs, only report a cast that still
            // holds its state after the pulse window; a real share or
            // recording stays up, a grim pulse is long gone.
            if (root.ignoreAmbientCapture && OpenRgb.ambientActive) {
                if (active) {
                    ambientPulseFilter.restart();
                } else {
                    ambientPulseFilter.stop();
                    root.screencastActive = false;
                }
                return;
            }
            ambientPulseFilter.stop();
            root.screencastActive = active;
        }
    }

    Timer {
        id: ambientPulseFilter
        interval: 700
        onTriggered: root.screencastActive = true
    }

    Timer {
        interval: root.pollInterval
        running: root.enableService
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.refreshMic();
            root.refreshCamera();
        }
    }

    Process {
        id: micProc
        environment: ({ LANG: "C", LC_ALL: "C" })
        command: ["pactl", "-f", "json", "list", "source-outputs"]
        stdout: StdioCollector {
            onStreamFinished: {
                const result = root.parseSourceOutputs(text);
                root.micActive = result.active;
                root.micApps = result.apps;
            }
        }
    }

    Process {
        id: cameraProc
        environment: ({ LANG: "C", LC_ALL: "C" })
        // The /dev/video* glob is a fixed literal - no dynamic data is spliced.
        command: ["sh", "-c", "fuser /dev/video* 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const pids = root.parsePids(text);
                root.cameraActive = pids.length > 0;
                if (pids.length === 0) {
                    root.cameraApps = [];
                } else {
                    // PIDs validated as integers above; passed as individual argv.
                    commProc.command = ["ps", "-o", "comm=", "-p"].concat(pids);
                    commProc.running = true;
                }
            }
        }
    }

    Process {
        id: commProc
        environment: ({ LANG: "C", LC_ALL: "C" })
        stdout: StdioCollector {
            onStreamFinished: root.cameraApps = root.parseComm(text)
        }
    }
}
