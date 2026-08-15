.pragma library

/**
 * The pure half of the privacy panel's actions: building the argv for each
 * action, and reading what the portal permission store says back.
 *
 * Everything here is fed by names other applications chose - PipeWire stream
 * ids, process names, D-Bus app ids - so every builder VALIDATES and returns
 * null rather than trusting its argument. A null means "do not run anything",
 * which the caller must honour; there is no shell involved, but an unvalidated
 * id would still let another application aim these commands at a node or a
 * permission entry of its choosing.
 */

const PERMISSION_STORE_BUS = "org.freedesktop.impl.portal.PermissionStore";
const PERMISSION_STORE_PATH = "/org/freedesktop/impl/portal/PermissionStore";

// Ids that name a thing on the bus: app ids, table names, permission ids.
// Deliberately narrower than the D-Bus spec - nothing legitimate here needs
// more than these characters.
const NAME_RE = /^[A-Za-z0-9._-]+$/;

function _isName(value) {
    return typeof value === "string" && NAME_RE.test(value);
}

// PipeWire and PulseAudio ids are non-negative integers. Accepts a number or
// its decimal string, and nothing else - "52; rm -rf ~" is a string that
// starts with an id, which is exactly the case this must reject.
function _asId(value) {
    if (typeof value === "number")
        return Number.isInteger(value) && value >= 0 ? String(value) : null;
    if (typeof value === "string" && /^\d+$/.test(value))
        return value;
    return null;
}

function _busctl(args) {
    return ["busctl", "--user", "--json=short", "call",
        PERMISSION_STORE_BUS, PERMISSION_STORE_PATH, PERMISSION_STORE_BUS].concat(args);
}

// Mutes one recording stream rather than the source: other apps keep the
// microphone, and the mute is reversible from the same row that set it.
function muteStreamCommand(index, muted) {
    const id = _asId(index);
    if (id === null) return null;
    return ["pactl", "set-source-output-mute", id, muted ? "1" : "0"];
}

// Destroys the app's capture NODE (properties["object.id"]), not its process:
// the app loses the stream it is holding and stays running. `object.serial`,
// which pactl reports as the stream index, is a different number and will
// destroy the wrong node if passed here.
function destroyNodeCommand(nodeId) {
    const id = _asId(nodeId);
    if (id === null) return null;
    return ["pw-cli", "destroy", id];
}

function permissionIdsCommand(table) {
    if (!_isName(table)) return null;
    return _busctl(["List", "s", table]);
}

function permissionLookupCommand(table, id) {
    if (!_isName(table) || !_isName(id)) return null;
    return _busctl(["Lookup", "ss", table, id]);
}

function revokePermissionCommand(table, id, app) {
    if (!_isName(table) || !_isName(id) || !_isName(app)) return null;
    return _busctl(["DeletePermission", "sss", table, id, app]);
}

function _replyData(text) {
    const raw = (text === null || text === undefined) ? "" : String(text).trim();
    if (raw.length === 0 || raw.charAt(0) !== "{") return null;
    try {
        const reply = JSON.parse(raw);
        return Array.isArray(reply.data) ? reply.data : null;
    } catch (e) {
        return null;
    }
}

/**
 * Reads a Lookup reply into one entry per app.
 *
 * `busctl` exits non-zero with "No entry for <id>" when nothing was ever
 * granted for that id. That is the ordinary state on a machine running no
 * sandboxed apps, not a failure, so it reads as an empty list - the panel says
 * "nothing granted" rather than "something went wrong".
 */
function parsePermissionApps(text) {
    const data = _replyData(text);
    if (data === null || data.length === 0) return [];
    const table = data[0];
    if (!table || typeof table !== "object") return [];
    const apps = [];
    for (const app of Object.keys(table)) {
        const permissions = Array.isArray(table[app]) ? table[app] : [];
        apps.push({
            app: app,
            permissions: permissions,
            // The portal writes "yes"/"no"; anything else (an app that was
            // asked and never answered) is not a grant.
            granted: permissions.indexOf("yes") !== -1,
        });
    }
    return apps;
}

// List replies wrap the array one level deeper than it looks: data[0] is the
// list of ids.
function parsePermissionIds(text) {
    const data = _replyData(text);
    if (data === null || data.length === 0) return [];
    return Array.isArray(data[0]) ? data[0] : [];
}
