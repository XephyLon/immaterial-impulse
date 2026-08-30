pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick

// Logic-only double of services/MediaCapture.qml. The parse functions are kept
// byte-for-byte in sync with the real service; the pactl/fuser/ps Process I/O is
// omitted so tests stay deterministic and offline.
Singleton {
    id: root

    property bool micActive: false
    property var micApps: []
    // Per-stream detail for the privacy panel's actions: name, pactl index,
    // PipeWire node id, pid, mute state.
    property var micStreams: []
    property bool cameraActive: false
    property var cameraApps: []

    function parseSourceOutputs(text: string): var {
        const raw = (text ?? "").trim();
        if (raw.length === 0) return { active: false, apps: [], streams: [] };
        try {
            const arr = JSON.parse(raw);
            if (Array.isArray(arr)) return root._fromJsonSourceOutputs(arr);
        } catch (e) {
        }
        return root._fromTextSourceOutputs(raw);
    }

    readonly property var genericAppNames: ["chromium", "chromium input", "electron", "webrtc voiceengine", "chrome input"]
    function resolveAppName(name: var, binary: var): var {
        if (binary && (!name || root.genericAppNames.indexOf(name.toLowerCase()) !== -1))
            return binary.charAt(0).toUpperCase() + binary.slice(1);
        return name;
    }

    function _fromJsonSourceOutputs(arr: var): var {
        const apps = [];
        const streams = [];
        for (const item of arr) {
            if (!item || item.corked === true) continue;
            const props = item.properties ?? {};
            if (props["stream.capture.sink"] === "true") continue;
            const isClientStream = (item.client !== null && item.client !== undefined)
                || (props["application.process.id"] !== undefined);
            if (!isClientStream) continue;
            const rawName = props["application.name"] ?? props["media.name"] ?? props["node.name"];
            const name = root.resolveAppName(rawName, props["application.process.binary"]);
            if (!name) continue;
            if (apps.indexOf(name) === -1) apps.push(name);
            streams.push({
                name: name,
                index: item.index,
                nodeId: props["object.id"] ?? null,
                pid: props["application.process.id"] ?? null,
                muted: item.mute === true,
            });
        }
        return { active: apps.length > 0, apps: apps, streams: streams };
    }

    function _fromTextSourceOutputs(text: string): var {
        const apps = [];
        const streams = [];
        const blocks = text.split(/Source Output #/).slice(1);
        for (const block of blocks) {
            if (!/Corked:\s*no/i.test(block)) continue;
            if (/stream\.capture\.sink\s*=\s*"true"/.test(block)) continue;
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
            if (!name) continue;
            if (apps.indexOf(name) === -1) apps.push(name);
            const indexMatch = block.match(/^\s*(\d+)/);
            const nodeMatch = block.match(/object\.id\s*=\s*"(\d+)"/);
            const pidMatch = block.match(/application\.process\.id\s*=\s*"(\d+)"/);
            streams.push({
                name: name,
                index: indexMatch ? parseInt(indexMatch[1], 10) : null,
                nodeId: nodeMatch ? nodeMatch[1] : null,
                pid: pidMatch ? pidMatch[1] : null,
                muted: /Mute:\s*yes/i.test(block),
            });
        }
        return { active: apps.length > 0, apps: apps, streams: streams };
    }

    function parsePids(text: string): var {
        const pids = [];
        for (const tok of (text ?? "").trim().split(/\s+/)) {
            if (/^\d+$/.test(tok) && pids.indexOf(tok) === -1) pids.push(tok);
        }
        return pids;
    }

    function parseComm(text: string): var {
        const names = [];
        for (const line of (text ?? "").split("\n")) {
            const name = line.trim();
            if (name.length > 0 && names.indexOf(name) === -1) names.push(name);
        }
        return names;
    }

    // Verbatim from services/MediaCapture.qml (video consumer graph).
    function parseVideoConsumers(raw: var): var {
        let arr;
        try {
            arr = JSON.parse(raw);
        } catch (e) {
            return { screen: [], camera: [] };
        }
        if (!Array.isArray(arr)) return { screen: [], camera: [] };
        const nodes = {};
        const sourceOf = {};
        for (const item of arr) {
            if (!item) continue;
            if (item.type === "PipeWire:Interface:Node") {
                const props = item.info?.props ?? {};
                nodes[item.id] = {
                    mediaClass: props["media.class"] ?? "",
                    api: props["device.api"] ?? "",
                    state: item.info?.state ?? "",
                    name: root.resolveAppName(
                        props["application.name"] ?? props["node.name"],
                        props["application.process.binary"]),
                };
            } else if (item.type === "PipeWire:Interface:Link") {
                const output = item.info?.["output-node-id"];
                const input = item.info?.["input-node-id"];
                if (output !== undefined && input !== undefined)
                    sourceOf[input] = output;
            }
        }
        const screen = [];
        const camera = [];
        for (const id in nodes) {
            const node = nodes[id];
            if (node.mediaClass !== "Stream/Input/Video") continue;
            if (node.state !== "running") continue;
            if (!node.name) continue;
            const source = nodes[sourceOf[id]];
            const list = (source && source.api === "v4l2") ? camera : screen;
            if (list.indexOf(node.name) === -1) list.push(node.name);
        }
        return { screen: screen, camera: camera };
    }
}
