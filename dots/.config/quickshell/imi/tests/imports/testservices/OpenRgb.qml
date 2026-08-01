pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick

// Logic-only double of services/OpenRgb.qml. parseDeviceList(),
// buildDeviceCommand(), colorDelta() and mixHex() are kept byte-for-byte in
// sync with the real service (pinned by test_openrgb_contract.py); the
// Process/Timer wiring around the openrgb CLI is omitted so tests stay
// deterministic and offline.
Singleton {
    id: root

    property var devices: []

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

    // Pure: argv for a per-device apply, or null when no device remains.
    // Color and indices are separate argv elements - nothing is shell-spliced.
    function buildDeviceCommand(hex, devices, excluded, mode = "static", excludedTypes = []) {
        const cmd = ["openrgb"];
        let any = false;
        for (const dev of devices) {
            if (excluded.includes(dev.name) || excludedTypes.includes(dev.type))
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
}
