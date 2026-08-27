pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common

/**
 * The paired phone's notifications, mirrored off KDE Connect
 * (docs/superpowers/specs/2026-08-27-phone-tab-design.md, W2).
 *
 * Reads and writes are `busctl --json=short` argv arrays through a serialized
 * queue built like PhoneConnect's, and there is no monitor here: the four
 * notification signals are on PhoneConnect's allowlist, so its coalesced
 * deviceChangeSettled() is what triggers a refetch, beside a change of the
 * active device and a slow reconcile. A sweep is the device's
 * activeNotifications (a list of PUBLIC ids, not of notifications) and one
 * GetAll per notification leaf - measured shapes, see the fixtures in
 * tests/tst_phone_notifications.qml.
 *
 * Dismiss is the LEAF method, notification.dismiss on
 * <device>/notifications/<publicId>: the device-level sendAction(key,
 * "cancel") the fork once used invokes a named Android action button, and
 * "cancel" is not one, so the phone kept the notification while the sidebar
 * dropped its card (the fork's KdeConnectService.qml:892-901 records it).
 * A reply is device-level sendReply(replyId, text) followed by a refetch
 * `replyRefetchDelay` later, because the daemon's notificationUpdated can
 * land before the phone has rewritten the body.
 *
 * The list is cached per device in Persistent.states.phone (saved
 * `cacheSaveDelay` after a change) and restored when the active device is
 * known, so the tab is not empty between boot and the first sweep.
 *
 * Everything between the sync markers is kept byte-for-byte in sync with the
 * logic-only double (tests/imports/testservices/PhoneNotifications.qml);
 * tests/test_phone_notifications_contract.py enforces it.
 */
Singleton {
    id: root

    // The key is declared by the Phone tab's workstream; until then the
    // optional chain reads undefined and the tab defaults on.
    readonly property bool tabEnabled: Config.options.sidebar?.phone?.enable ?? true
    readonly property bool serviceEnabled: root.tabEnabled && PhoneConnect.enableService
    readonly property string activeDeviceId: PhoneConnect.activeDevice?.id ?? ""
    // The gate services/Notifications.qml drops the daemon's own desktop
    // notifications behind: only while this tab is showing them. Off, the
    // daemon's copy is the only one the user would get.
    readonly property bool mirrorActive: root.tabEnabled && (PhoneConnect.activeDevice?.reachable ?? false)

    // [{ publicId, deviceId, internalId, package, appName, title, text, ticker,
    //    iconPath, dismissable, replyId, actions, receivedAt }]
    property var notifications: []
    readonly property int count: root.notifications.length
    readonly property var groupsByAppName: root.groupsForList(root.notifications)
    readonly property list<string> appNameList: root.appNameListForGroups(root.groupsByAppName)

    // How long after sendReply the list is re-read (the fork measured the
    // daemon's own update as racy; 800ms is what it settled on).
    readonly property int replyRefetchDelay: 800
    readonly property int reconcileInterval: 60000
    readonly property int cacheSaveDelay: 2000

    // BEGIN phone-notifications parser logic (synced with tests/imports/testservices/PhoneNotifications.qml)
    // A public id is spliced into an object path. The daemon mints them as
    // decimal counters ("70"); anything else is refused rather than escaped.
    function validPublicId(id: var): bool {
        return typeof id === "string" && /^[A-Za-z0-9_]+$/.test(id);
    }

    // internalId is the Android notification key the daemon relays:
    // "0|<package>|<id>|<tag>|<uid>" ("0|com.truecaller|2131366136|null|10553"
    // off the live daemon). The package is the second field, and only of a
    // zero-prefixed key.
    function packageFromInternalId(internalId: var): string {
        const parts = String(internalId ?? "").split("|");
        return (parts.length >= 2 && parts[0] === "0") ? parts[1].trim() : "";
    }

    // One notification leaf's GetAll (a{sv}) onto the model. Every field the
    // leaf may omit degrades to its empty value; `dismissable` defaults to
    // true because a leaf that does not say is one the daemon will dismiss.
    function normalizeNotification(publicId: string, deviceId: string, rawProps: var, receivedAt: real): var {
        const props = PhoneConnect.unwrapVariants(rawProps);
        const str = key => typeof props[key] === "string" ? props[key] : "";
        return {
            publicId: publicId,
            deviceId: deviceId,
            internalId: str("internalId"),
            package: root.packageFromInternalId(props.internalId),
            appName: str("appName"),
            title: str("title"),
            text: str("text"),
            ticker: str("ticker"),
            iconPath: str("iconPath"),
            dismissable: props.dismissable !== false,
            replyId: str("replyId"),
            actions: Array.isArray(props.actions) ? props.actions.filter(a => typeof a === "string") : [],
            receivedAt: receivedAt
        };
    }

    // A refetch replaces the list, but a notification already shown keeps the
    // time it first arrived: the groups sort on it, and a sweep that stamped
    // every entry "now" would reshuffle the tab on every signal.
    function carryReceivedAt(previous: var, fresh: var): var {
        const seen = {};
        for (const n of (previous ?? [])) seen[n.publicId] = n.receivedAt;
        return (fresh ?? []).map(n => seen[n.publicId] === undefined
            ? n : Object.assign({}, n, { receivedAt: seen[n.publicId] }));
    }

    // The same derivation as services/Notifications.qml's groupsForList /
    // appNameListForGroups, on this model's fields: one group per app,
    // carrying the app's icon and the newest arrival in it.
    function groupsForList(list: var): var {
        const groups = {};
        (list ?? []).forEach(n => {
            if (!groups[n.appName]) {
                groups[n.appName] = {
                    appName: n.appName,
                    appIcon: n.iconPath,
                    notifications: [],
                    time: 0
                };
            }
            groups[n.appName].notifications.push(n);
            groups[n.appName].time = Math.max(groups[n.appName].time, n.receivedAt || 0);
        });
        return groups;
    }

    function appNameListForGroups(groups: var): var {
        return Object.keys(groups ?? {}).sort((a, b) => groups[b].time - groups[a].time);
    }

    // Whether a desktop notification is the daemon's own copy of something
    // this tab already shows: posted under one of kdeconnectd's app names,
    // or under a paired device's name (the daemon posts relayed
    // notifications as the phone).
    function mirrorsAppName(appName: var, deviceNames: var): bool {
        const lower = String(appName ?? "").toLowerCase();
        if (lower === "") return false;
        if (["kdeconnect", "kde connect", "org.kde.kdeconnect"].includes(lower)) return true;
        return (deviceNames ?? []).some(name => String(name ?? "").toLowerCase() === lower);
    }

    // The persisted cache is one JSON document keyed by device id:
    // { "<deviceId>": { savedAt, notifications } }. An entry whose public id
    // would not pass validPublicId is dropped on the way back in, since
    // nothing could dismiss it.
    function cachedNotificationsFor(json: var, deviceId: string): var {
        let doc;
        try {
            doc = JSON.parse(String(json ?? ""));
        } catch (e) {
            return [];
        }
        const entry = (doc && typeof doc === "object") ? doc[deviceId] : null;
        if (!entry || !Array.isArray(entry.notifications)) return [];
        return entry.notifications.filter(n => n && typeof n === "object" && root.validPublicId(n.publicId));
    }

    function cacheWith(json: var, deviceId: string, list: var, savedAt: real): string {
        let doc;
        try {
            doc = JSON.parse(String(json ?? ""));
        } catch (e) {
            doc = null;
        }
        if (!doc || typeof doc !== "object" || Array.isArray(doc)) doc = {};
        doc[deviceId] = { savedAt: savedAt, notifications: list ?? [] };
        return JSON.stringify(doc);
    }
    // END phone-notifications parser logic

    function applyNotifications(list: var, deviceId: string): void {
        if (deviceId !== root.activeDeviceId) return;
        root.notifications = root.carryReceivedAt(root.notifications, list);
        cacheSave.restart();
    }

    // Whether a desktop notification arriving at services/Notifications.qml
    // is the daemon's copy of something this tab shows.
    function mirrorsDesktopNotification(appName: var): bool {
        return root.mirrorActive
            && root.mirrorsAppName(appName, PhoneConnect.devices.filter(d => d.paired).map(d => d.name));
    }

    function notificationsPath(deviceId: string): string {
        return `/modules/kdeconnect/devices/${deviceId}/notifications`;
    }

    // ---- reads ----

    // The public entry: every trigger lands here and coalesces on the settle,
    // which re-arms while a sweep is in flight rather than dropping the
    // change that asked for it.
    function refresh(): void {
        sweepSettle.restart();
    }

    function sweep(): void {
        if (!root.serviceEnabled || !PhoneConnect.installed) return;
        const deviceId = root.activeDeviceId;
        if (PhoneConnect.backend !== "kdeconnect" || !PhoneConnect.validDeviceId(deviceId)) return;
        const path = root.notificationsPath(deviceId);
        root.enqueue(PhoneConnect.busctlCall("org.kde.kdeconnect.daemon", path, "org.kde.kdeconnect.device.notifications", "activeNotifications", []), text => {
            const data = PhoneConnect.parseBusctlReply(text);
            // "Call failed" (no notifications plugin, device gone) parses to
            // null and reads as nothing to show.
            const ids = (data?.[0] ?? []).filter(id => root.validPublicId(id));
            if (ids.length === 0) { root.applyNotifications([], deviceId); return; }
            const collected = [];
            let answered = 0;
            const receivedAt = Date.now();
            for (const publicId of ids) {
                root.enqueue(PhoneConnect.busctlCall("org.kde.kdeconnect.daemon", `${path}/${publicId}`, "org.freedesktop.DBus.Properties", "GetAll", ["s", "org.kde.kdeconnect.device.notifications.notification"]), leafText => {
                    const leaf = PhoneConnect.parseBusctlReply(leafText);
                    // A leaf dismissed between the two reads answers nothing
                    // and is simply not in this sweep.
                    if (leaf !== null) collected.push(root.normalizeNotification(publicId, deviceId, leaf[0] ?? {}, receivedAt));
                    if (++answered === ids.length) root.applyNotifications(collected, deviceId);
                });
            }
        });
    }

    Timer {
        id: sweepSettle
        interval: 120
        onTriggered: {
            if (busProc.running || root.callQueue.length > 0) {
                sweepSettle.restart();
                return;
            }
            root.sweep();
        }
    }

    // ---- writes ----

    function dismiss(publicId: string): void {
        const deviceId = root.activeDeviceId;
        if (PhoneConnect.backend !== "kdeconnect" || !PhoneConnect.validDeviceId(deviceId) || !root.validPublicId(publicId)) return;
        root.runAction(PhoneConnect.busctlCall("org.kde.kdeconnect.daemon", `${root.notificationsPath(deviceId)}/${publicId}`, "org.kde.kdeconnect.device.notifications.notification", "dismiss", []));
        // The card goes at once; the daemon's notificationRemoved reconciles.
        root.notifications = root.notifications.filter(n => n.publicId !== publicId);
        cacheSave.restart();
    }

    function dismissAll(): void {
        for (const n of root.notifications.slice())
            if (n.dismissable !== false) root.dismiss(n.publicId);
    }

    function reply(publicId: string, text: string): void {
        const deviceId = root.activeDeviceId;
        const n = root.notifications.find(entry => entry.publicId === publicId) ?? null;
        if (!n || n.replyId === "" || String(text ?? "") === "") return;
        if (PhoneConnect.backend !== "kdeconnect" || !PhoneConnect.validDeviceId(deviceId)) return;
        root.runAction(PhoneConnect.busctlCall("org.kde.kdeconnect.daemon", root.notificationsPath(deviceId), "org.kde.kdeconnect.device.notifications", "sendReply", ["ss", n.replyId, text]));
        replyRefetch.restart();
    }

    // The daemon's sendAction(key, action) is keyed on the notification's
    // internalId - the Android key it relays, and what its own KNotification
    // path hands back on an action - not on the public id. The daemon does
    // not expose action names over D-Bus, so `actions` is what the leaf
    // happens to carry.
    function sendAction(publicId: string, key: string): void {
        const deviceId = root.activeDeviceId;
        const n = root.notifications.find(entry => entry.publicId === publicId) ?? null;
        if (!n || n.internalId === "" || String(key ?? "") === "") return;
        if (PhoneConnect.backend !== "kdeconnect" || !PhoneConnect.validDeviceId(deviceId)) return;
        root.runAction(PhoneConnect.busctlCall("org.kde.kdeconnect.daemon", root.notificationsPath(deviceId), "org.kde.kdeconnect.device.notifications", "sendAction", ["ss", n.internalId, key]));
    }

    // Writes share the serialized queue: dismissAll is one call per leaf,
    // and a second exec on a running Process is refused, not queued.
    function runAction(argv: var): void {
        root.enqueue(argv, (text, exitCode, errorText) => {
            if (exitCode !== 0) {
                Quickshell.execDetached(["notify-send",
                    Translation.tr("Phone Connect"),
                    errorText.trim() || Translation.tr("Phone Connect command failed"),
                    "-a", "Shell"
                ]);
            }
        });
    }

    Timer {
        id: replyRefetch
        interval: root.replyRefetchDelay
        onTriggered: root.refresh()
    }

    // ---- serialized busctl queue ----

    property var callQueue: []
    property var activeCallback: null

    function enqueue(argv: var, callback: var): void {
        root.callQueue.push({ argv: argv, callback: callback });
        root.pump();
    }

    function pump(): void {
        if (busProc.running || root.callQueue.length === 0) return;
        const next = root.callQueue.shift();
        root.activeCallback = next.callback;
        busProc.exec(next.argv);
    }

    Process {
        id: busProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            id: busOut
        }
        // "Call failed: ..." is expected for a leaf that went away mid-sweep;
        // the text is handed to the callback, which decides.
        stderr: StdioCollector {
            id: busErr
        }
        onExited: (exitCode, exitStatus) => {
            const callback = root.activeCallback;
            root.activeCallback = null;
            callback?.(busOut.text, exitCode, busErr.text);
            root.pump();
        }
    }

    // ---- triggers ----

    Connections {
        target: PhoneConnect
        function onDeviceChangeSettled(): void {
            root.refresh();
        }
    }

    onActiveDeviceIdChanged: {
        // The device that walked away keeps its list on screen (the footer
        // says it is offline); a different device gets its own cache back
        // before the sweep replaces it.
        if (root.activeDeviceId === "") return;
        root.restoreCache();
        root.refresh();
    }

    onServiceEnabledChanged: {
        if (!root.serviceEnabled) {
            root.callQueue = [];
            root.activeCallback = null;
        } else {
            root.refresh();
        }
    }

    Timer {
        interval: root.reconcileInterval
        running: root.serviceEnabled && PhoneConnect.installed && root.activeDeviceId !== ""
        repeat: true
        onTriggered: root.refresh()
    }

    // ---- the per-device cache ----

    function restoreCache(): void {
        if (!Persistent.ready) return;
        const deviceId = root.activeDeviceId;
        if (deviceId === "") return;
        // A list already fetched for this device is newer than any cache.
        if (root.notifications.length > 0 && root.notifications[0].deviceId === deviceId) return;
        root.notifications = root.cachedNotificationsFor(Persistent.states.phone?.cachedNotificationsJson ?? "", deviceId);
    }

    Connections {
        target: Persistent
        function onReadyChanged(): void {
            if (Persistent.ready) root.restoreCache();
        }
    }

    Timer {
        id: cacheSave
        interval: root.cacheSaveDelay
        onTriggered: {
            const deviceId = root.activeDeviceId;
            if (!Persistent.ready || !PhoneConnect.validDeviceId(deviceId)) return;
            // Every entry on the list is this device's or the list is stale
            // for it; only the former is worth writing.
            if (root.notifications.some(n => n.deviceId !== deviceId)) return;
            Persistent.states.phone.cachedNotificationsJson = root.cacheWith(
                Persistent.states.phone.cachedNotificationsJson, deviceId, root.notifications, Date.now());
        }
    }

    Component.onCompleted: {
        root.restoreCache();
        root.refresh();
    }
}
