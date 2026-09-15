pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import "google_api.js" as G

/**
 * The Google account's calendars in the shell's calendar: the selected
 * calendars' events for the next `accounts.google.calendarDays` days, fetched
 * with `singleEvents` (recurrences expanded by Google - the ICS parser does
 * none) and handed to IcsCalendar as external sources, one per calendar, so
 * the sidebar dots, `list_events` and the modes engine see them like any ICS
 * feed. Refreshes every `refreshMinutes` and on every new token.
 */
Singleton {
    id: root

    readonly property bool enabled: (Config.options.accounts?.google?.calendar ?? false) && GoogleAccount.connected
    readonly property int refreshInterval: Math.max(1, Config.options.accounts?.google?.refreshMinutes ?? 5) * 60000
    readonly property int days: Math.max(1, Config.options.accounts?.google?.calendarDays ?? 14)

    // [{ id, name, primary, color }]
    property var calendars: []
    property int eventCount: 0
    property string lastError: ""
    property real lastSync: 0
    property var _pending: []

    function refresh() {
        if (!root.enabled || !GoogleAccount.tokenValid || listReq.running) return;
        listReq.url = G.calendarListUrl(GoogleAccount.apiBase);
        listReq.start();
    }

    function clear() {
        for (const c of root.calendars)
            IcsCalendar.setExternalEvents("google:" + c.id, []);
        root.calendars = [];
        root.eventCount = 0;
    }

    GoogleRequest {
        id: listReq
        onFinished: (json, error, status) => {
            if (error.length > 0) { root.lastError = error; return; }
            const next = G.parseCalendarList(json);
            // Calendars that vanished take their events with them.
            for (const old of root.calendars)
                if (!next.some(c => c.id === old.id))
                    IcsCalendar.setExternalEvents("google:" + old.id, []);
            root.calendars = next;
            root.lastError = "";
            root._pending = next.slice();
            root.fetchNext();
        }
    }

    // One calendar at a time: a dozen concurrent curls for a routine refresh
    // is not worth the burst.
    function fetchNext() {
        if (root._pending.length === 0) { root.lastSync = Date.now(); return; }
        const cal = root._pending.shift();
        const now = new Date();
        const end = new Date(now.getTime() + root.days * 86400000);
        eventsReq.calendarId = cal.id;
        eventsReq.calendarName = cal.name;
        eventsReq.url = G.eventsUrl(GoogleAccount.apiBase, cal.id, now.toISOString(), end.toISOString());
        eventsReq.start();
    }

    GoogleRequest {
        id: eventsReq
        property string calendarId: ""
        property string calendarName: ""
        onFinished: (json, error, status) => {
            if (error.length > 0) {
                root.lastError = error;
            } else {
                const events = G.parseEvents(json, eventsReq.calendarName);
                IcsCalendar.setExternalEvents("google:" + eventsReq.calendarId, events);
                root.eventCount = Object.keys(IcsCalendar._externalEvents)
                    .filter(k => k.indexOf("google:") === 0)
                    .reduce((n, k) => n + IcsCalendar._externalEvents[k].length, 0);
            }
            root.fetchNext();
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
    onEnabledChanged: if (!root.enabled) root.clear(); else root.refresh()
}
