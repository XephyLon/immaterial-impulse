pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import "./ai/ai_sessions.js" as Sessions

/**
 * Auto-saved chat sessions (spec 2026-08-31). Every chat persists without
 * being asked: Ai mints a session on the first user message and flushes
 * through the debounce here; this singleton owns the FILES and the TIMING
 * and nothing else - every decision is ai_sessions.js arithmetic.
 *
 * Storage: Directories.aiSessions/<id>.json holding { meta, messages },
 * and sessions-index.json holding the list rows. The index is a CACHE:
 * missing or corrupt, it is rebuilt from the session files' metas.
 */
Singleton {
    id: root

    property var index: []
    property string currentId: ""
    property bool loaded: false

    signal sessionOpened(string id)

    function newId() {
        return Date.now().toString(36) + "-" + Math.floor(Math.random() * 1e9).toString(36);
    }

    // ---- the index file ---------------------------------------------------
    FileView {
        id: indexFile
        path: `${Directories.aiSessions}/sessions-index.json`
        blockLoading: true
        onLoadFailed: root.rebuild()
        onLoaded: {
            try {
                const rows = JSON.parse(indexFile.text());
                if (!Array.isArray(rows)) throw new Error("not a list");
                root.index = Sessions.sortedIndex(rows);
                root.loaded = true;
            } catch (e) {
                root.rebuild();
            }
        }
    }
    function writeIndex(rows) {
        root.index = Sessions.sortedIndex(rows);
        indexFile.setText(JSON.stringify(root.index));
        root.loaded = true;
    }

    // The recovery path: one meta line per session file, folded by the
    // tested arithmetic. jq because the metas live inside the documents and
    // parsing every full transcript here would defeat the index.
    Process {
        id: rebuildProc
        command: ["bash", "-c",
            `for f in "${Directories.aiSessions}"/*.json; do [ "$(basename "$f")" = "sessions-index.json" ] && continue; jq -c '.meta // empty' "$f" 2>/dev/null; done`]
        stdout: StdioCollector {
            onStreamFinished: {
                root.writeIndex(Sessions.rebuildIndex(text.split("\n").filter(l => l.length > 0)));
            }
        }
    }
    function rebuild() {
        rebuildProc.running = true;
    }

    // ---- the session files ------------------------------------------------
    FileView {
        id: sessionFile
        property string sessionId: ""
        path: sessionId.length > 0 ? `${Directories.aiSessions}/${sessionId}.json` : ""
        blockLoading: true
    }

    // ---- autosave ----------------------------------------------------------
    // One debounce for every trigger: a mint, an interface line, a finished
    // answer. The flush snapshots Ai's live messages, so the last write in
    // a burst is the one that lands.
    Timer {
        id: flushTimer
        interval: 1000
        onTriggered: root.saveNow()
    }
    // Dirty gates every flush: opening another chat used to saveNow() the
    // previous one unconditionally, bumping its updatedAt - so the list
    // REORDERED under the pointer on every switch (recorded). Only a chat
    // that actually changed since its last flush earns a bump.
    property bool dirty: false
    function scheduleSave() {
        if (root.currentId.length === 0) return;
        root.dirty = true;
        flushTimer.restart();
    }
    function saveNow() {
        if (root.currentId.length === 0) return;
        if (!root.dirty) return;
        root.dirty = false;
        const entry = root.index.find(row => row.id === root.currentId);
        const now = Date.now();
        const meta = {
            id: root.currentId,
            title: entry?.title ?? "",
            createdAt: entry?.createdAt ?? now,
            updatedAt: now,
            pinned: entry?.pinned ?? false
        };
        sessionFile.sessionId = root.currentId;
        sessionFile.setText(JSON.stringify({ meta: meta, messages: Ai.chatToJson() }));
        root.writeIndex(Sessions.applyTouch(root.index, root.currentId, meta.title, now));
    }

    // Called by Ai on the FIRST user message of an unsaved chat.
    function mint(firstPrompt) {
        if (root.currentId.length > 0) return;
        root.currentId = root.newId();
        root.writeIndex(Sessions.applyTouch(root.index, root.currentId,
            Sessions.titleFrom(firstPrompt), Date.now()));
        root.scheduleSave();
    }

    // ---- the verbs the view and the commands speak -------------------------
    function openSession(id) {
        flushTimer.stop();
        if (root.currentId.length > 0) root.saveNow();
        sessionFile.sessionId = id;
        sessionFile.reload();
        try {
            const doc = JSON.parse(sessionFile.text());
            Ai.loadMessagesFromJson(doc.messages ?? []);
            root.currentId = id;
            root.dirty = false;
            root.sessionOpened(id);
        } catch (e) {
            Ai.addMessage(Translation.tr("Could not open that session - its file is unreadable."), Ai.interfaceRole);
        }
    }

    function newSession() {
        flushTimer.stop();
        if (root.currentId.length > 0) root.saveNow();
        root.currentId = "";
        Ai.clearMessages();
    }

    function rename(id, title) {
        root.writeIndex(Sessions.applyRename(root.index, id, title));
        if (id === root.currentId) root.scheduleSave();
    }

    function setPinned(id, pinned) {
        root.writeIndex(Sessions.applyPin(root.index, id, pinned));
    }

    function remove(id) {
        root.writeIndex(Sessions.applyRemove(root.index, id));
        Quickshell.execDetached(["rm", "-f", `${Directories.aiSessions}/${id}.json`]);
        if (id === root.currentId) {
            root.currentId = "";
            Ai.clearMessages();
        }
    }

    // A legacy flat chat file (Directories.aiChats/*.json) becomes a
    // session and opens; the original is left in place.
    FileView {
        id: legacyFile
        blockLoading: true
    }
    function importLegacy(path) {
        legacyFile.path = path;
        legacyFile.reload();
        try {
            const messages = JSON.parse(legacyFile.text());
            const session = Sessions.legacyToSession(messages, root.newId(), Date.now());
            sessionFile.sessionId = session.meta.id;
            sessionFile.setText(JSON.stringify(session));
            root.writeIndex(Sessions.applyTouch(root.index, session.meta.id,
                session.meta.title, session.meta.updatedAt));
            root.openSession(session.meta.id);
        } catch (e) {
            Ai.addMessage(Translation.tr("Could not import %1 - not a readable chat file.").arg(path), Ai.interfaceRole);
        }
    }
}
