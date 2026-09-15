pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import "google_api.js" as G

/**
 * Google Tasks in the to-do widget: the task lists and their open tasks,
 * with add / complete / delete written through, queued behind one another
 * (two ticks in one round trip both land). Kept apart from the local
 * to-do file on purpose - the local list has no stable ids to merge on, so
 * the widget shows a source row instead (Local | Google).
 */
Singleton {
    id: root

    readonly property bool enabled: (Config.options.accounts?.google?.tasks ?? false) && GoogleAccount.connected
    readonly property int refreshInterval: Math.max(1, Config.options.accounts?.google?.refreshMinutes ?? 5) * 60000

    // [{ id, title }]
    property var lists: []
    property string currentListId: ""
    readonly property var currentList: root.lists.find(l => l.id === root.currentListId) ?? null
    // [{ id, listId, content, done, due, notes }]
    property var tasks: []
    readonly property bool busy: req.busy
    property string lastError: ""

    function refresh() {
        if (!root.enabled || !GoogleAccount.tokenValid) return;
        req.request(G.taskListsUrl(GoogleAccount.apiBase), "GET", "", { kind: "lists" });
    }

    function selectList(id) {
        root.currentListId = String(id ?? "");
        root.fetchTasks();
    }

    function fetchTasks() {
        if (!root.enabled || !GoogleAccount.tokenValid || root.currentListId.length === 0) return;
        req.request(G.tasksUrl(GoogleAccount.apiBase, root.currentListId), "GET", "", { kind: "tasks", listId: root.currentListId });
    }

    function addTask(title) {
        const text = String(title ?? "").trim();
        if (text.length === 0) return;
        root.write("POST", G.tasksCollectionUrl(GoogleAccount.apiBase, root.currentListId), JSON.stringify({ title: text }));
    }

    function completeTask(id) {
        root.write("PATCH", G.taskUrl(GoogleAccount.apiBase, root.currentListId, id), JSON.stringify({ status: "completed" }));
    }

    function deleteTask(id) {
        root.write("DELETE", G.taskUrl(GoogleAccount.apiBase, root.currentListId, id), "");
    }

    function write(method, url, body) {
        if (!root.enabled || !GoogleAccount.tokenValid || root.currentListId.length === 0) return;
        req.request(url, method, body, { kind: "write", method: method, listId: root.currentListId });
    }

    GoogleRequest {
        id: req
        onFinished: (json, error, status, tag) => {
            if (!root.enabled) return;
            if (error.length > 0) {
                root.lastError = error;
                if (tag.kind === "write") {
                    console.warn(`[GoogleTasks] ${tag.method} failed: ${error} (${status})`);
                    root.fetchTasks();
                }
                return;
            }
            root.lastError = "";
            switch (tag.kind) {
            case "lists":
                root.lists = G.parseTaskLists(json);
                if (root.lists.length === 0) { root.tasks = []; return; }
                if (!root.lists.some(l => l.id === root.currentListId))
                    root.currentListId = root.lists[0].id;
                root.fetchTasks();
                break;
            case "tasks":
                if (tag.listId === root.currentListId)
                    root.tasks = G.parseTasks(json, tag.listId);
                break;
            case "write":
                // Re-read after the LAST queued write, not after each.
                if (!req.queue.some(q => q.tag && q.tag.kind === "write"))
                    root.fetchTasks();
                break;
            }
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
    onEnabledChanged: if (!root.enabled) { req.clear(); root.lists = []; root.tasks = []; } else root.refresh()
}
