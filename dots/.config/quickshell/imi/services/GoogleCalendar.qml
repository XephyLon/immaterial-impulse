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
 * feed. Refreshes every `refreshMinutes` and on every new token; one cycle
 * at a time, one calendar at a time.
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
    // Events handed out per calendar id, for the count.
    property var _counts: ({})

    function refresh() {
        if (!root.enabled || !GoogleAccount.tokenValid || req.busy) return;
        req.request(G.calendarListUrl(GoogleAccount.apiBase), "GET", "", { kind: "list" });
    }

    function clear() {
        req.clear();
        for (const c of root.calendars)
            IcsCalendar.setExternalEvents("google:" + c.id, []);
        root.calendars = [];
        root._counts = {};
        root.eventCount = 0;
    }

    function recount() {
        let n = 0;
        for (const k in root._counts) n += root._counts[k];
        root.eventCount = n;
    }

    GoogleRequest {
        id: req
        onFinished: (json, error, status, tag) => {
            if (!root.enabled) return;
            if (error.length > 0) { root.lastError = error; return; }
            if (tag.kind === "list") {
                const next = G.parseCalendarList(json);
                // Calendars that vanished take their events with them.
                for (const old of root.calendars)
                    if (!next.some(c => c.id === old.id)) {
                        IcsCalendar.setExternalEvents("google:" + old.id, []);
                        delete root._counts[old.id];
                    }
                root.calendars = next;
                root.lastError = "";
                const now = new Date();
                const end = new Date(now.getTime() + root.days * 86400000);
                // One calendar at a time, each carrying its own identity.
                for (const cal of next)
                    req.request(G.eventsUrl(GoogleAccount.apiBase, cal.id, now.toISOString(), end.toISOString()),
                                "GET", "", { kind: "events", calendarId: cal.id, calendarName: cal.name });
                if (next.length === 0) { root.recount(); root.lastSync = Date.now(); }
                return;
            }
            const events = G.parseEvents(json, tag.calendarName);
            IcsCalendar.setExternalEvents("google:" + tag.calendarId, events);
            root._counts[tag.calendarId] = events.length;
            root.recount();
            root.lastError = "";
            if (!req.busy && req.queue.length === 0) root.lastSync = Date.now();
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
