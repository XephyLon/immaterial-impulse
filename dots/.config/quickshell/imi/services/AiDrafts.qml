pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import "./ai/ai_drafts.js" as Drafts

/**
 * Durable composer drafts (spec 2026-08-31): one JSON map beside the
 * sessions, one ~1s debounce, empty text deletes its slot. A corrupt file
 * starts empty rather than failing - a draft is never worth an error.
 */
Singleton {
    id: root

    property var drafts: ({})
    property bool loaded: false

    FileView {
        id: draftsFile
        path: `${Directories.aiSessions}/drafts.json`
        blockLoading: true
        onLoadFailed: root.loaded = true
        onLoaded: {
            try {
                const parsed = JSON.parse(draftsFile.text());
                if (parsed && typeof parsed === "object") root.drafts = parsed;
            } catch (e) { /* corrupt: start empty */ }
            root.loaded = true;
        }
    }

    Timer {
        id: flushTimer
        interval: 1000
        onTriggered: draftsFile.setText(JSON.stringify(root.drafts))
    }

    function record(key, text) {
        root.drafts = Drafts.withDraft(root.drafts, key, text);
        flushTimer.restart();
    }

    function take(key) {
        return Drafts.draftFor(root.drafts, key);
    }

    function clear(key) {
        root.record(key, "");
    }
}
