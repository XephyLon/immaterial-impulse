pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common
import "capture_control.js" as Cmd

/**
 * The acting half of the privacy panel. MediaCapture watches; this changes.
 *
 * Three kinds of action, in order of how much they can cost the target app:
 *
 * - Mute a recording stream (`pactl set-source-output-mute`). Reversible from
 *   the same row that set it, and scoped to one stream: other apps keep the
 *   microphone. The app is not told, which is the point - a call app that is
 *   asked to mute can decline.
 * - Force stop (`pw-cli destroy` on the stream's PipeWire node). The app loses
 *   the stream and keeps running, but it never asked to lose it and may handle
 *   that badly. Off unless `allowForceStop` is set in Settings.
 * - Revoke a portal permission (PermissionStore.DeletePermission). Only reaches
 *   apps that go through xdg-desktop-portal - in practice sandboxed ones. A
 *   native app opening PipeWire or /dev/video directly has no permission entry
 *   to revoke, and the panel says so rather than implying it was stopped.
 *
 * Every argv comes from capture_control.js, which validates its ids and returns
 * null for anything it will not build; a null here means the action is dropped,
 * never run with a fallback.
 */
Singleton {
    id: root

    readonly property bool allowForceStop: Config.options.bar.privacyIndicator?.allowForceStop ?? false

    // The portal's device permissions, as [{ id, apps: [{app, granted}] }].
    // Empty is the ordinary state on a machine with no sandboxed apps.
    property var permissions: []
    property bool permissionsLoaded: false
    readonly property string permissionTable: "devices"

    signal actionFailed(string what, string detail)

    // --- Mic streams -------------------------------------------------------

    function setStreamMuted(stream, muted): void {
        const argv = Cmd.muteStreamCommand(stream?.index, muted);
        if (!argv) {
            root.actionFailed("mute", `unusable stream index: ${stream?.index}`);
            return;
        }
        root._run(argv, "mute");
    }

    function toggleStreamMuted(stream): void {
        root.setStreamMuted(stream, !(stream?.muted === true));
    }

    /**
     * Destroys the app's capture node. Refuses unless Settings allows it, so
     * the destructive path cannot be reached by a stray binding.
     */
    function forceStopStream(stream): void {
        if (!root.allowForceStop) {
            root.actionFailed("forceStop", "force stop is off in Settings");
            return;
        }
        const argv = Cmd.destroyNodeCommand(stream?.nodeId);
        if (!argv) {
            root.actionFailed("forceStop", `unusable node id: ${stream?.nodeId}`);
            return;
        }
        root._run(argv, "forceStop");
    }

    // --- Portal permissions ------------------------------------------------

    function refreshPermissions(): void {
        const argv = Cmd.permissionIdsCommand(root.permissionTable);
        if (!argv) return;
        permissionIdsProc.command = argv;
        permissionIdsProc.running = true;
    }

    function revokePermission(id, app): void {
        const argv = Cmd.revokePermissionCommand(root.permissionTable, id, app);
        if (!argv) {
            root.actionFailed("revoke", `unusable permission target: ${id}/${app}`);
            return;
        }
        revokeProc.command = argv;
        revokeProc.running = true;
    }

    // --- Plumbing ----------------------------------------------------------

    function _run(argv, what): void {
        actionProc.pendingWhat = what;
        actionProc.command = argv;
        actionProc.running = true;
    }

    // Rebuilds `permissions` from one Lookup per id. The ids come from List,
    // so the set is whatever the portal actually has - not a hardcoded list
    // that would go stale when a portal grows a new device kind.
    property var _pendingIds: []
    property var _collected: []

    function _lookupNext(): void {
        if (root._pendingIds.length === 0) {
            root.permissions = root._collected;
            root.permissionsLoaded = true;
            return;
        }
        const id = root._pendingIds[0];
        const argv = Cmd.permissionLookupCommand(root.permissionTable, id);
        if (!argv) {
            root._pendingIds = root._pendingIds.slice(1);
            root._lookupNext();
            return;
        }
        lookupProc.currentId = id;
        lookupProc.command = argv;
        lookupProc.running = true;
    }

    Process {
        id: permissionIdsProc
        environment: ({ LANG: "C", LC_ALL: "C" })
        stdout: StdioCollector {
            onStreamFinished: {
                root._pendingIds = Cmd.parsePermissionIds(text);
                root._collected = [];
                root._lookupNext();
            }
        }
    }

    Process {
        id: lookupProc
        property string currentId: ""
        environment: ({ LANG: "C", LC_ALL: "C" })
        // A table with no entry makes busctl exit non-zero and print to stderr;
        // the parser reads that as "nothing granted", so the id is simply
        // recorded with no apps rather than dropped.
        stdout: StdioCollector {
            onStreamFinished: {
                const apps = Cmd.parsePermissionApps(text);
                root._collected = root._collected.concat([{ id: lookupProc.currentId, apps: apps }]);
                root._pendingIds = root._pendingIds.slice(1);
                root._lookupNext();
            }
        }
    }

    Process {
        id: revokeProc
        environment: ({ LANG: "C", LC_ALL: "C" })
        onExited: exitCode => {
            if (exitCode !== 0) root.actionFailed("revoke", `busctl exited ${exitCode}`);
            root.refreshPermissions();
        }
    }

    Process {
        id: actionProc
        property string pendingWhat: ""
        environment: ({ LANG: "C", LC_ALL: "C" })
        onExited: exitCode => {
            if (exitCode !== 0) root.actionFailed(actionProc.pendingWhat, `exited ${exitCode}`);
            // The panel reads MediaCapture, which polls; ask it now so the row
            // reflects the mute on the next frame instead of up to a poll later.
            MediaCapture.refreshMic();
        }
    }
}
