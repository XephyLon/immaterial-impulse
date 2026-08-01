pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import "ics_parser.js" as IcsParser
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Aggregates calendar events from ICS sources - local .ics files and remote ICS
 * URLs - and exposes them to the sidebar calendar.
 *
 * Sources come from config (both default empty):
 *   Config.options.calendar.ics.files           list of local .ics paths
 *   Config.options.calendar.ics.urls            list of remote ICS URLs
 *   Config.options.calendar.ics.refreshInterval remote refresh, minutes (default 30)
 *
 * Remote URLs are fetched with `curl -fsSL <url>`, the URL passed as an argv
 * element (never spliced into a shell). The ICS payload is untrusted and parsed
 * by the pure ics_parser.js (no eval). Recurrence and named time zones are not
 * handled in v1 - see ics_parser.js.
 */
Singleton {
    id: root

    readonly property var files: Config.options.calendar.ics?.files ?? []
    readonly property var urls: Config.options.calendar.ics?.urls ?? []
    readonly property int refreshInterval: (Config.options.calendar.ics?.refreshInterval ?? 30) * 60 * 1000

    // All events, sorted by start. See ics_parser.js parseIcs for element shape.
    property var events: []
    // "YYYY-M-D" -> true, for O(1) day-dot indicator lookups.
    property var daysWithEvents: ({})

    // Per-source parsed arrays, keyed by source index, kept apart so one source
    // reloading does not clobber another's events.
    property var _localEvents: ({})
    property var _remoteEvents: ({})

    function eventsForDay(year, month, day) {
        return root.events.filter(e => e.year === year && e.month === month && e.day === day);
    }

    function hasEventsOn(year, month, day) {
        return root.daysWithEvents[`${year}-${month}-${day}`] === true;
    }

    function _rebuild() {
        let all = [];
        for (const k in root._localEvents)
            all = all.concat(root._localEvents[k]);
        for (const k in root._remoteEvents)
            all = all.concat(root._remoteEvents[k]);
        all.sort((a, b) => a.start - b.start);
        const days = {};
        for (const e of all)
            days[`${e.year}-${e.month}-${e.day}`] = true;
        root.events = all;
        root.daysWithEvents = days;
    }

    function _storeLocal(index, parsed) {
        let m = root._localEvents;
        m[index] = parsed;
        root._localEvents = m;
        root._rebuild();
    }

    function _storeRemote(index, parsed) {
        let m = root._remoteEvents;
        m[index] = parsed;
        root._remoteEvents = m;
        root._rebuild();
    }

    // Local .ics files: FileView reloads on disk changes.
    Instantiator {
        model: root.files
        delegate: FileView {
            id: localSource
            required property var modelData
            required property int index
            path: String(modelData).startsWith("file://") ? modelData : Qt.resolvedUrl(modelData)
            watchChanges: true
            onFileChanged: reload()
            onLoaded: root._storeLocal(index, IcsParser.parseIcs(localSource.text()))
            onLoadFailed: (error) => {
                console.warn("[IcsCalendar] Failed to load", localSource.path, error);
                root._storeLocal(index, []);
            }
        }
    }

    // Remote ICS URLs: curl at startup and on the refresh timer.
    Instantiator {
        model: root.urls
        delegate: QtObject {
            id: remoteSource
            required property var modelData
            required property int index

            property Process fetcher: Process {
                // URL is an argv element, never shell-spliced: config/preset data
                // is untrusted. -f fails on HTTP errors, -sSL is silent-with-errors
                // and follows redirects.
                command: ["curl", "-fsSL", remoteSource.modelData]
                stdout: StdioCollector {
                    onStreamFinished: {
                        if (text.length === 0)
                            return;
                        root._storeRemote(remoteSource.index, IcsParser.parseIcs(text));
                    }
                }
            }

            property Timer timer: Timer {
                running: true
                repeat: true
                triggeredOnStart: true
                interval: root.refreshInterval
                onTriggered: remoteSource.fetcher.running = true
            }
        }
    }
}
