pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import "google_api.js" as G

/**
 * The Gmail inbox's unread count (`labels/INBOX`), for the bar's mail
 * indicator. Read-only; one small request per refresh.
 */
Singleton {
    id: root

    readonly property bool enabled: (Config.options.accounts?.google?.mail ?? false) && GoogleAccount.connected
    readonly property int refreshInterval: Math.max(1, Config.options.accounts?.google?.refreshMinutes ?? 5) * 60000

    property int unread: 0
    property bool synced: false
    property string lastError: ""

    function refresh() {
        if (!root.enabled || !GoogleAccount.tokenValid || req.busy) return;
        req.request(G.inboxLabelUrl(GoogleAccount.apiBase), "GET", "", null);
    }

    function openInbox() {
        Quickshell.execDetached(["xdg-open", "https://mail.google.com/"]);
    }

    GoogleRequest {
        id: req
        onFinished: (json, error, status, tag) => {
            if (!root.enabled) return;
            if (error.length > 0) { root.lastError = error; return; }
            root.unread = G.parseUnread(json);
            root.synced = true;
            root.lastError = "";
        }
    }

    Timer {
        running: root.enabled
        interval: root.refreshInterval
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
    Connections {
        target: GoogleAccount
        function onTokenRefreshed() { root.refresh(); }
    }
    onEnabledChanged: if (!root.enabled) { req.clear(); root.unread = 0; root.synced = false; } else root.refresh()
}
