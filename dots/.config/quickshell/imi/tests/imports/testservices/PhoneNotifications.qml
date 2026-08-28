pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick

// Logic-only double of services/PhoneNotifications.qml. The parser/derivation
// functions between the sync markers are kept byte-for-byte in sync with the
// real service (tests/test_phone_notifications_contract.py enforces it); the
// busctl Process/Timer I/O and the Persistent cache are omitted so tests stay
// deterministic and offline. It reads the PhoneConnect double beside it for
// the busctl reply helpers, as the service reads the real one.
Singleton {
    id: root

    property string activeDeviceId: ""
    property bool mirrorActive: false
    // [{ publicId, deviceId, internalId, package, appName, title, text, ticker,
    //    iconPath, dismissable, replyId, actions, receivedAt }]
    property var notifications: []
    readonly property int count: root.notifications.length
    readonly property var groupsByAppName: root.groupsForList(root.notifications)
    readonly property list<string> appNameList: root.appNameListForGroups(root.groupsByAppName)

    // BEGIN phone-notifications parser logic (synced with services/PhoneNotifications.qml)
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
    // An absolute path kdeconnectd wrote, as a URL an Image can load.
    function iconUrl(path: string): string {
        if (!path || path.length === 0)
            return "";
        return "file://" + path.split("/").map(encodeURIComponent).join("/");
    }

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
            receivedAt: receivedAt,
            // ---- the same notification, in the shared card's vocabulary ----
            //
            // The shell's notification card reads `summary`, `body`, `image`
            // and `urgency`; this model's own names stay above because the
            // daemon's fields are what the service is a mirror OF, and its
            // tests pin them. Carrying both is what lets the phone draw the
            // shell's card instead of a second one written against these
            // names - which is how the copy drifted from the original.
            //
            // `image` and not `appIcon`: the appIcon slot resolves through the
            // icon THEME, and this is an absolute path kdeconnectd wrote, so
            // it is spelled as a URL the way every other file source is.
            summary: str("title"),
            body: str("text"),
            image: root.iconUrl(str("iconPath")),
            // KDE Connect relays no urgency. Normal is what a phone
            // notification is, and it keeps the card off its critical
            // colours.
            //
            // The literal, not `NotificationUrgency.Normal`: that enum comes
            // from Quickshell.Services.Notifications, whose plugin the bare
            // qmltestrunner cannot load - importing it here took the WHOLE
            // testservices module down with it, and every test that reaches
            // any service in it reported "Type Battery unavailable".
            urgency: 1
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
    }
}
