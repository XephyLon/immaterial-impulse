pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick

// Logic-only double of services/OpenRgb.qml. parseDeviceList() and
// buildDeviceCommand() are kept byte-for-byte in sync with the real service
// (pinned by test_openrgb_contract.py); the Process/Timer wiring around the
// openrgb CLI is omitted so tests stay deterministic and offline.
Singleton {
    id: root

    property var devices: []

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
}
