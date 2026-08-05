pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick

// Logic-only double of services/PhoneConnect.qml. The parser/normalization
// functions between the sync markers are kept byte-for-byte in sync with the
// real service (tests/test_phone_connect_contract.py enforces it); the busctl
// Process/Timer I/O is omitted so tests stay deterministic and offline.
Singleton {
    id: root

    property bool installed: false // busctl found on PATH
    property string backend: "none" // "kdeconnect" | "valent" | "none"
    readonly property bool available: root.backend !== "none"
    // [{ id, name, type, reachable, paired, batteryAvailable, batteryCharge, batteryCharging }]
    property var devices: []

    readonly property var activeDevice: root.devices.find(d => d.paired && d.reachable && d.type === "phone")
        ?? root.devices.find(d => d.paired && d.reachable)
        ?? null
    readonly property string materialSymbol: (root.available && root.activeDevice) ? "mobile" : "mobile_off"

    // BEGIN phone-connect parser logic (synced with services/PhoneConnect.qml)
    // Parses one `busctl --json=short` reply. Returns the payload ("data")
    // array, or null when the text is not a busctl JSON document (empty
    // output, "Call failed: ..." error text, malformed JSON).
    function parseBusctlReply(text: string): var {
        const trimmed = (text ?? "").trim();
        if (trimmed.length === 0) return null;
        let doc;
        try {
            doc = JSON.parse(trimmed);
        } catch (e) {
            return null;
        }
        if (!doc || typeof doc !== "object" || !Array.isArray(doc.data)) return null;
        return doc.data;
    }

    // GetAll replies carry a{sv}: { key: { type, data } }. Flattens the
    // variant cells to plain values.
    function unwrapVariants(dict: var): var {
        const out = {};
        for (const key in (dict ?? {})) {
            const cell = dict[key];
            out[key] = (cell && typeof cell === "object" && "data" in cell) ? cell.data : cell;
        }
        return out;
    }

    // Maps a ListNames reply to the backend it implies. KDE Connect wins a
    // tie: it is the incumbent, and running both daemons at once double-pairs
    // phones anyway.
    function backendFromNames(names: var): string {
        const list = names ?? [];
        if (list.includes("org.kde.kdeconnect.daemon")) return "kdeconnect";
        if (list.includes("ca.andyholmes.Valent")) return "valent";
        return "none";
    }

    // Normalizes one org.kde.kdeconnect.device GetAll reply (plus its
    // battery GetAll, or null when the battery object does not exist - it is
    // absent for unpaired devices) onto the shared device model.
    function normalizeKdeconnectDevice(id: string, rawProps: var, rawBatteryProps: var): var {
        const props = root.unwrapVariants(rawProps);
        const battery = rawBatteryProps === null || rawBatteryProps === undefined
            ? null : root.unwrapVariants(rawBatteryProps);
        return {
            id: id,
            name: props.name ?? "",
            type: props.type ?? "",
            reachable: props.isReachable === true,
            paired: props.isPaired === true,
            batteryAvailable: battery !== null && typeof battery.charge === "number",
            batteryCharge: (battery !== null && typeof battery.charge === "number") ? battery.charge : -1,
            batteryCharging: battery !== null && battery.isCharging === true
        };
    }

    // Valent device State flags (valent-device.h): 1 = connected, 2 = paired.
    function normalizeValentObjects(managedObjects: var): var {
        const objects = (managedObjects ?? [])[0] ?? {};
        const devices = [];
        for (const path in objects) {
            const ifaces = objects[path];
            const raw = ifaces?.["ca.andyholmes.Valent.Device"];
            if (!raw) continue;
            const props = root.unwrapVariants(raw);
            const state = Number(props.State ?? 0);
            devices.push({
                id: props.Id ?? "",
                name: props.Name ?? "",
                type: props.Type ?? "",
                reachable: (state & 1) !== 0,
                paired: (state & 2) !== 0,
                objectPath: path,
                batteryAvailable: false,
                batteryCharge: -1,
                batteryCharging: false
            });
        }
        return devices;
    }

    // Decodes an org.gtk.Actions DescribeAll reply (a{s(bgav)}) into battery
    // state via the stateful `battery.state` action's vardict.
    function decodeValentBattery(describeAllData: var): var {
        const none = { available: false, charge: -1, charging: false };
        const actions = (describeAllData ?? [])[0] ?? {};
        const batteryAction = actions["battery.state"];
        if (!Array.isArray(batteryAction) || batteryAction.length < 3) return none;
        const stateCells = batteryAction[2];
        if (!Array.isArray(stateCells) || stateCells.length === 0) return none;
        const state = root.unwrapVariants(stateCells[0]?.data ?? null);
        if (typeof state.percentage !== "number") return none;
        return {
            available: state["is-present"] !== false,
            charge: Math.round(state.percentage),
            charging: state.charging === true
        };
    }

    // Reachable-and-paired devices first, then paired, then by name/id.
    function sortDevices(list: var): var {
        const rank = d => (d.paired && d.reachable) ? 0 : d.paired ? 1 : 2;
        return [...(list ?? [])].sort((a, b) => rank(a) - rank(b)
            || String(a.name || a.id).localeCompare(String(b.name || b.id)));
    }

    // Object paths and argv both splice the id in; keep it boring.
    function validDeviceId(id: var): bool {
        return typeof id === "string" && /^[A-Za-z0-9_-]+$/.test(id);
    }
    // END phone-connect parser logic

    function applyBackend(newBackend: string): void {
        root.backend = newBackend;
        if (newBackend === "none") root.devices = [];
    }

    function applyDevices(list: var): void {
        root.devices = root.sortDevices(list);
    }
}
