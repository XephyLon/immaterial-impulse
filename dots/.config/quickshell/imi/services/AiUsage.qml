pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import "./ai/ai_usage.js" as Fold

/**
 * Token accounting for the AI chat, one bucket per local day (the fork's
 * grammar, minus its hourly/model breakdowns). Ai.markDone hands each
 * finished response here; a response finishing before the file loads is
 * buffered and merged after, never lost. Days older than two years are
 * pruned on save; allTime keeps the whole story.
 */
Singleton {
    id: root

    readonly property string path: `${Directories.aiChats}/usage.json`
    property bool loaded: false
    property var data: ({})
    property var pending: []
    readonly property int retentionDays: 740

    readonly property var today: Fold.totalsSince(root.data, root.dayKey(0))
    readonly property var week: Fold.totalsSince(root.data, root.dayKey(6))
    readonly property var month: Fold.totalsSince(root.data, root.dayKey(29))
    readonly property var allTime: root.data.allTime ?? ({})

    function dayKey(daysBack) {
        const d = new Date(Date.now() - daysBack * 86400000);
        return Qt.formatDate(d, "yyyy-MM-dd");
    }

    function record(tokens, ok) {
        if (!root.loaded) {
            root.pending = [...root.pending, { "tokens": tokens, "ok": ok }];
            return;
        }
        root.data = Fold.withResponse(root.data, root.dayKey(0), tokens, ok);
        root.save();
    }

    function save() {
        usageFile.setText(JSON.stringify(
            Fold.pruned(root.data, root.dayKey(root.retentionDays))));
    }

    Component.onCompleted: usageFile.reload()

    FileView {
        id: usageFile
        path: Qt.resolvedUrl(root.path)
        onLoaded: {
            try { root.data = JSON.parse(usageFile.text()); }
            catch (e) { root.data = ({}); }
            root.loaded = true;
            const backlog = root.pending;
            root.pending = [];
            for (const r of backlog)
                root.data = Fold.withResponse(root.data, root.dayKey(0), r.tokens, r.ok);
            if (backlog.length > 0) root.save();
        }
        onLoadFailed: {
            root.data = ({});
            root.loaded = true;
            const backlog = root.pending;
            root.pending = [];
            for (const r of backlog)
                root.data = Fold.withResponse(root.data, root.dayKey(0), r.tokens, r.ok);
        }
    }
}
