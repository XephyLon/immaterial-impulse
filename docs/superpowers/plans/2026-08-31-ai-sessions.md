# AI Sessions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every chat auto-saves as a session; a browsable sessions view (open, rename, pin, delete, legacy import) lives behind a history chip in the AI tools bar.

**Architecture:** Pure arithmetic in `services/ai/ai_sessions.js` (titles, sorting, folds, legacy mapping) under a thin `AiSessions` singleton that owns the files and the debounce; `Ai.qml` gains three wire points (mint on first user message, flush on adds and on `markDone` - replacing the dead `saveChat("lastSession")` - and command sugar); `AiChat`'s keys-view loader generalizes into one `activeView` switcher hosting keys and the new `SessionListView`. Spec: `docs/superpowers/specs/2026-08-31-ai-sessions-design.md`.

**Tech Stack:** QML (Quickshell FileView/Process), qmltestrunner, python contract pins. Paths relative to `dots/.config/quickshell/imi/` unless starting with `docs/`.

**Conventions that bind every task:** commit with `git commit --only -F - -- <paths>` (new files need `git add -N` first); no Claude/agent attribution; comments explain *why*; run only the named tests, never `run_tests.sh` (suite is parked).

**Facts verified at plan time:** `Directories.aiChats` = `${Directories.state}/user/ai/chats`, mkdir'd at `Directories.qml:143`; the user message enters in `Ai.sendUserMessage` (Ai.qml:829) via `addMessage(message, "user")`; the assistant turn ends in `markDone()` (Ai.qml:695) which today calls `root.saveChat("lastSession")` - grep shows NO restore path reads it, so sessions replace it outright; `loadChat` rebuilds messages inline (Ai.qml:988) - Task 2 extracts that into `loadMessagesFromJson` so sessions and legacy import share it; `StringUtils.friendlyTimeForSeconds` formats DURATIONS, so the ago-label lives in the new js lib; the keys view is `keysViewLoader` gated on `keysViewOpen` (AiChat.qml:28/529) with the transcript step-back reading the same flag (416-419); `ChatControlBar` has `signal keysRequested()` (line 30) and the new-chat chip at line ~182.

---

### Task 1: the sessions arithmetic

**Files:**
- Create: `services/ai/ai_sessions.js`
- Test: `tests/tst_ai_sessions.qml`

- [ ] **Step 1: Write the failing test**

`tests/tst_ai_sessions.qml`:

```qml
import QtTest
import "../services/ai/ai_sessions.js" as Sessions

// The sessions system's decisions as arithmetic: what a session is called,
// how the list orders, how the folds edit it, and how a legacy flat chat
// file becomes a session. The service above this owns only files and
// debounce.
TestCase {
    name: "AiSessionsTest"

    function meta(id, title, updatedAt, pinned) {
        return { id: id, title: title, createdAt: updatedAt, updatedAt: updatedAt, pinned: pinned ?? false };
    }

    function test_title_from_first_prompt() {
        compare(Sessions.titleFrom("  How do I    tune the bar's margins?  "),
            "How do I tune the bar's margins?");
        const long = Sessions.titleFrom("x".repeat(80));
        verify(long.length <= 41, "capped");
        verify(long.endsWith("…"), "capped titles say so");
        compare(Sessions.titleFrom(""), "");
        compare(Sessions.titleFrom("/model gemini"), "/model gemini",
            "a command prompt is still a title; the caller decides what mints");
    }

    function test_sorted_index_pins_first_then_recency() {
        const rows = Sessions.sortedIndex([
            meta("a", "old", 100), meta("b", "new", 300),
            meta("c", "pinned-old", 50, true), meta("d", "mid", 200)
        ]);
        compare(rows.map(r => r.id).join(","), "c,b,d,a");
    }

    function test_ago_label_speaks_human() {
        const now = 1000000000000;
        compare(Sessions.agoLabel(now, now - 30 * 1000), "now");
        compare(Sessions.agoLabel(now, now - 5 * 60 * 1000), "5m");
        compare(Sessions.agoLabel(now, now - 3 * 3600 * 1000), "3h");
        compare(Sessions.agoLabel(now, now - 2 * 86400 * 1000), "2d");
    }

    function test_legacy_file_becomes_a_session() {
        const messages = [
            { role: "user", rawContent: "Explain the dock's magnify curve" },
            { role: "assistant", rawContent: "It is a gaussian..." }
        ];
        const session = Sessions.legacyToSession(messages, "id123", 42);
        compare(session.meta.id, "id123");
        compare(session.meta.title, "Explain the dock's magnify curve");
        compare(session.meta.createdAt, 42);
        compare(session.meta.pinned, false);
        compare(session.messages.length, 2);
        // No user message: falls back rather than titling from the answer.
        const odd = Sessions.legacyToSession([{ role: "assistant", rawContent: "hello" }], "x", 1);
        compare(odd.meta.title, "");
    }

    function test_folds_edit_the_index() {
        const rows = [meta("a", "one", 100), meta("b", "two", 200)];
        const renamed = Sessions.applyRename(rows, "a", "won");
        compare(renamed.find(r => r.id === "a").title, "won");
        compare(rows.find(r => r.id === "a").title, "one", "copy, not mutation");
        const pinned = Sessions.applyPin(renamed, "a", true);
        compare(Sessions.sortedIndex(pinned)[0].id, "a");
        const removed = Sessions.applyRemove(pinned, "b");
        compare(removed.length, 1);
        const touched = Sessions.applyTouch(rows, "a", "retitled", 999);
        compare(touched.find(r => r.id === "a").updatedAt, 999);
        compare(touched.find(r => r.id === "a").title, "retitled");
        const grown = Sessions.applyTouch(rows, "new-id", "fresh", 500);
        compare(grown.length, 3, "an unknown id is an insert");
    }

    function test_rebuild_folds_meta_lines() {
        const lines = [
            JSON.stringify(meta("a", "one", 100)),
            "not json at all",
            JSON.stringify(meta("b", "two", 200))
        ];
        const rows = Sessions.rebuildIndex(lines);
        compare(rows.length, 2, "a corrupt meta is dropped, not fatal");
        compare(rows[0].id, "b", "rebuilt sorted");
    }
}
```

- [ ] **Step 2: Run — must fail**

Run: `cd dots/.config/quickshell/imi && QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/mocks -import tests/imports -input tests/tst_ai_sessions.qml`
Expected: compile FAIL (ai_sessions.js missing).

- [ ] **Step 3: Write `services/ai/ai_sessions.js`**

```js
.pragma library

// The sessions system's arithmetic (spec 2026-08-31): everything here is a
// pure function over plain rows, so the decisions - titles, order, edits,
// legacy mapping, index rebuild - are testable without a scene, and the
// AiSessions service above owns only files and debounce.
//
// An index ROW is { id, title, createdAt, updatedAt, pinned }.

var TITLE_MAX = 40;

// The first prompt, made a title: whitespace collapsed, capped with an
// ellipsis so the row never wraps. Empty in, empty out - the CALLER
// decides whether an empty title mints anything.
function titleFrom(prompt) {
    var clean = String(prompt || "").replace(/\s+/g, " ").trim();
    if (clean.length <= TITLE_MAX) return clean;
    return clean.slice(0, TITLE_MAX) + "…";
}

// Pinned first, then most recently touched. Copy, never in place.
function sortedIndex(rows) {
    return (rows || []).slice().sort(function (a, b) {
        if (!!a.pinned !== !!b.pinned) return a.pinned ? -1 : 1;
        return (b.updatedAt || 0) - (a.updatedAt || 0);
    });
}

// "now", "5m", "3h", "2d" - the row's whole vocabulary. Times are ms.
function agoLabel(nowMs, thenMs) {
    var s = Math.max(0, Math.floor((nowMs - thenMs) / 1000));
    if (s < 60) return "now";
    if (s < 3600) return Math.floor(s / 60) + "m";
    if (s < 86400) return Math.floor(s / 3600) + "h";
    return Math.floor(s / 86400) + "d";
}

function _copyRows(rows) {
    return (rows || []).map(function (row) {
        return { id: row.id, title: row.title, createdAt: row.createdAt,
                 updatedAt: row.updatedAt, pinned: !!row.pinned };
    });
}

function applyRename(rows, id, title) {
    return _copyRows(rows).map(function (row) {
        if (row.id === id) row.title = title;
        return row;
    });
}

function applyPin(rows, id, pinned) {
    return _copyRows(rows).map(function (row) {
        if (row.id === id) row.pinned = !!pinned;
        return row;
    });
}

function applyRemove(rows, id) {
    return _copyRows(rows).filter(function (row) { return row.id !== id; });
}

// A flush's index update: bump the row, or insert it for a session the
// index has never seen (the mint, or a rebuilt file). Title only ever
// grows less empty - a flush without one keeps what stands.
function applyTouch(rows, id, title, nowMs) {
    var next = _copyRows(rows);
    for (var i = 0; i < next.length; i++) {
        if (next[i].id !== id) continue;
        next[i].updatedAt = nowMs;
        if (title && title.length > 0) next[i].title = title;
        return next;
    }
    next.push({ id: id, title: title || "", createdAt: nowMs,
                updatedAt: nowMs, pinned: false });
    return next;
}

// A legacy flat chat file (a bare message array) as a session document.
// Titled from its first USER message - an answer is not a title.
function legacyToSession(messages, id, nowMs) {
    var list = (messages || []);
    var firstUser = "";
    for (var i = 0; i < list.length; i++) {
        if (list[i] && list[i].role === "user") {
            firstUser = list[i].rawContent || "";
            break;
        }
    }
    return {
        meta: { id: id, title: titleFrom(firstUser), createdAt: nowMs,
                updatedAt: nowMs, pinned: false },
        messages: list
    };
}

// The recovery fold: one meta JSON line per session file (jq -c '.meta'),
// corrupt lines dropped, result sorted. This is what makes the index a
// cache rather than a source of truth.
function rebuildIndex(metaLines) {
    var rows = [];
    for (var i = 0; i < (metaLines || []).length; i++) {
        try {
            var meta = JSON.parse(metaLines[i]);
            if (meta && typeof meta.id === "string" && meta.id.length > 0)
                rows.push({ id: meta.id, title: meta.title || "",
                            createdAt: meta.createdAt || 0,
                            updatedAt: meta.updatedAt || 0,
                            pinned: !!meta.pinned });
        } catch (e) { /* a corrupt meta is dropped, not fatal */ }
    }
    return sortedIndex(rows);
}
```

- [ ] **Step 4: Run — must pass** (same command; expected `Totals: 6 passed`).

- [ ] **Step 5: Commit**

```bash
cd ~/dev/imi-unify
git add -N dots/.config/quickshell/imi/services/ai/ai_sessions.js \
  dots/.config/quickshell/imi/tests/tst_ai_sessions.qml
git commit --only -F - -- \
  dots/.config/quickshell/imi/services/ai/ai_sessions.js \
  dots/.config/quickshell/imi/tests/tst_ai_sessions.qml <<'MSG'
feat(ai): the sessions arithmetic

Titles from the first prompt, pinned-then-recency order, copy-on-write
folds for rename/pin/remove/touch, legacy flat files mapped to session
documents, and the index-rebuild fold that keeps the index a cache
rather than a source of truth. Pure functions, tested headless.
MSG
```

---

### Task 2: the service and the Ai wiring

**Files:**
- Create: `services/ai/AiSessions.qml`
- Modify: `services/Ai.qml` (sendUserMessage, addMessage, markDone, saveChat, loadChat, loadChat's body extraction)
- Modify: `modules/common/Directories.qml` (sessions dir property + mkdir)

- [ ] **Step 1: Directories** - beside the `aiChats` property (line ~84):

```qml
    property string aiSessions: FileUtils.trimFileProtocol(`${Directories.state}/user/ai/chats/sessions`)
```

and beside the aiChats mkdir (line ~143):

```qml
        Quickshell.execDetached(["mkdir", "-p", `${aiSessions}`])
```

- [ ] **Step 2: Write `services/ai/AiSessions.qml`**

```qml
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import "./ai_sessions.js" as Sessions

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
    function scheduleSave() {
        if (root.currentId.length === 0) return;
        flushTimer.restart();
    }
    function saveNow() {
        if (root.currentId.length === 0) return;
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
```

(Verify-before-trust: singleton registration - `services/` singletons register by directory; `services/ai/` holds components, not singletons, so if `AiSessions` does not resolve after a full restart, move the FILE to `services/AiSessions.qml` and change its js import to `"./ai/ai_sessions.js"` - the plan's pins reference it by name, not path.)

- [ ] **Step 3: Wire `services/Ai.qml`**

1. In `sendUserMessage` (line ~829), before `root.addMessage(message, "user")`:

```qml
        // The first user message of an unsaved chat mints its session -
        // lazily, so an empty chat never touches disk (spec 2026-08-31).
        AiSessions.mint(message);
```

2. At the end of `addMessage` (after `root.messageByID[id] = aiMessage;`):

```qml
        AiSessions.scheduleSave();
```

3. In `markDone()` (line ~695), REPLACE `root.saveChat("lastSession")` with:

```qml
            // The finished answer is the autosave's strongest trigger; the
            // old saveChat("lastSession") had no restore path and retires.
            AiSessions.scheduleSave();
```

4. Extract the message rebuild from `loadChat` into a shared function (the
body from `root.clearMessages()` through the end of the reconstruction
loop moves verbatim):

```qml
    /** Rebuilds the live chat from a saved message array - shared by the
        legacy /load path and AiSessions.openSession. */
    function loadMessagesFromJson(saveData) {
        root.clearMessages()
        root.messageIDs = saveData.map((_, i) => {
            return i
        })
        for (let i = 0; i < saveData.length; i++) {
            // ... the existing createObject loop from loadChat, unchanged ...
        }
    }
```

and `loadChat` becomes command sugar:

```qml
    function loadChat(chatName) {
        // Sugar over sessions now: a legacy flat file imports as a session
        // and opens (the original stays); see the sessions view's Legacy
        // section for the same door.
        AiSessions.importLegacy(`${Directories.aiChats}/${chatName.trim()}.json`)
    }
```

5. `saveChat(chatName)` keeps writing the flat file (other tools may read
those), and ALSO renames the current session - the "commands become
sugar" half:

```qml
    function saveChat(chatName) {
        chatSaveFile.chatName = chatName.trim()
        const saveContent = JSON.stringify(root.chatToJson())
        chatSaveFile.setText(saveContent)
        getSavedChats.running = true;
        if (AiSessions.currentId.length > 0)
            AiSessions.rename(AiSessions.currentId, chatName.trim())
    }
```

- [ ] **Step 4: Verify** - `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/mocks -import tests/imports -input tests/tst_ai_sessions.qml` still passes; qmllint `services/ai/AiSessions.qml` and `services/Ai.qml` (import-noise filter); grep `lastSession` returns nothing.

- [ ] **Step 5: Commit**

```bash
git add -N dots/.config/quickshell/imi/services/ai/AiSessions.qml
git commit --only -F - -- \
  dots/.config/quickshell/imi/services/ai/AiSessions.qml \
  dots/.config/quickshell/imi/services/Ai.qml \
  dots/.config/quickshell/imi/modules/common/Directories.qml <<'MSG'
feat(ai): chats save themselves

AiSessions owns the files and the debounce; every decision is the
tested arithmetic. The first user message mints a session lazily -
an empty chat never touches disk - adds and finished answers flush
through one debounce, /save renames the current session, /load
imports the legacy file it names, and markDone's write-only
saveChat("lastSession") retires.
MSG
```

---

### Task 3: the view switcher and the history chip

**Files:**
- Modify: `modules/imi/sidebarLeft/AiChat.qml` (keysViewOpen → activeView)
- Modify: `modules/imi/sidebarLeft/aiChat/ChatControlBar.qml` (sessionsRequested + history chip)

- [ ] **Step 1: `ChatControlBar.qml`** - beside `signal keysRequested()`:

```qml
    signal sessionsRequested()
```

and a history chip BEFORE the new-chat chip (line ~182):

```qml
        ControlChip {
            chipIcon: "forum"
            hint: Translation.tr("Chats")
            onClicked: root.sessionsRequested()
        }
```

The new-chat chip's action changes from `Ai.clearMessages()` to
`AiSessions.newSession()` (finalize, then clear).

- [ ] **Step 2: `AiChat.qml`** - the switcher. Replace:

```qml
    property bool keysViewOpen: false
    onKeysViewOpenChanged: if (!root.keysViewOpen) root.revealTranscript()
```

with:

```qml
    // One view over the transcript at a time: "" (the chat), "keys", or
    // "sessions". Closing any of them is an arrival, so the transcript
    // reveals; the step-back below reads the same emptiness.
    property string activeView: ""
    function toggleView(name) {
        root.activeView = (root.activeView === name) ? "" : name;
    }
    onActiveViewChanged: if (root.activeView === "") root.revealTranscript()
```

Then every `keysViewOpen` reader follows (exact spellings in the file today):
- `onKeysRequested: root.keysViewOpen = !root.keysViewOpen` → `onKeysRequested: root.toggleView("keys")`, and beside it `onSessionsRequested: root.toggleView("sessions")`.
- transcriptPage: `scale: root.activeView === "" ? 1 : 0.95`, `opacity: root.activeView === "" ? 1 : 0`, `enabled: root.activeView === ""`.
- The keys Loader: `active: root.activeView.length > 0`, and its `sourceComponent` becomes a chooser: keep the existing keys Rectangle as `Component { id: keysViewComponent ... }` and add `Component { id: sessionsViewComponent SessionListView { onClosed: root.activeView = "" } }` beside it, with the Loader's `sourceComponent: root.activeView === "keys" ? keysViewComponent : root.activeView === "sessions" ? sessionsViewComponent : null` (the slide-in Translate and back-arrow header stay inside each component; the sessions view carries its own, Task 4).
- The keys component's back arrow: `onClicked: root.activeView = ""`.
- The new-chat keyboard shortcut in `Keys.onPressed` (Ctrl+Shift+O calls `Ai.clearMessages()`) also moves to `AiSessions.newSession()`.

- [ ] **Step 3: qmllint both files** (import-noise filter), and the skeleton pins still pass: `python3 tests/test_ai_skeleton_contract.py`.

- [ ] **Step 4: Commit**

```bash
git commit --only -F - -- \
  dots/.config/quickshell/imi/modules/imi/sidebarLeft/AiChat.qml \
  dots/.config/quickshell/imi/modules/imi/sidebarLeft/aiChat/ChatControlBar.qml <<'MSG'
feat(ai): one view switcher over the transcript

keysViewOpen generalizes to activeView - keys or sessions, one at a
time, same slide-in and step-back - and the tools bar gains the
history chip; new-chat finalizes the current session before it
clears.
MSG
```

---

### Task 4: the session list

**Files:**
- Create: `modules/imi/sidebarLeft/aiChat/SessionListView.qml`

- [ ] **Step 1: Write it**

```qml
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../../../services/ai/ai_sessions.js" as Sessions
import QtQuick
import QtQuick.Layouts

/**
 * The sessions view (spec 2026-08-31): every auto-saved chat, pinned first
 * then most recent, with open/rename/pin/delete on the row - the fork's
 * SessionList grammar on imi tokens - and the un-imported legacy flat
 * files at the foot. Hosted by AiChat's view switcher; the back arrow and
 * the history chip both leave.
 */
Rectangle {
    id: root
    color: Appearance.colors.colLayer1
    radius: Appearance.rounding.large

    signal closed()

    // Arrives from the right, the switcher's going-deeper direction.
    transform: Translate { id: slideIn }
    Component.onCompleted: {
        slideIn.x = 24;
        slideAnim.start();
        AiSessions.loaded || AiSessions.rebuild();
    }
    NumberAnimation {
        id: slideAnim
        target: slideIn
        property: "x"
        to: 0
        duration: Appearance.animation.elementMoveEnter.duration
        easing.type: Easing.OutExpo
    }

    // The rows re-label ("5m" -> "6m") while the view is open; a minute is
    // the label's own resolution.
    property real nowMs: Date.now()
    Timer {
        interval: 60000
        running: root.visible
        repeat: true
        onTriggered: root.nowMs = Date.now()
    }

    // Legacy flat files that are not the index (they never are - sessions
    // live in their own subdir): offered for import at the foot.
    readonly property var legacyChats: Ai.savedChats
        .map(path => ({ path: path, name: path.split("/").pop().replace(".json", "") }))
        .filter(entry => entry.name !== "lastSession")

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Appearance.spacing.space150
        spacing: Appearance.spacing.space100

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space100
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                onClicked: root.closed()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                }
            }
            StyledText {
                text: Translation.tr("Chats")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
        }

        StyledText {
            visible: AiSessions.index.length === 0 && root.legacyChats.length === 0
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            Layout.topMargin: Appearance.spacing.space400
            text: Translation.tr("Nothing here yet - chats save themselves as you talk.")
            wrapMode: Text.WordWrap
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }

        StyledFlickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: sessionColumn.implicitHeight

            ColumnLayout {
                id: sessionColumn
                width: parent.width
                spacing: Appearance.spacing.space25

                Repeater {
                    model: AiSessions.index
                    delegate: SessionRow {}
                }

                StyledText {
                    visible: root.legacyChats.length > 0
                    Layout.topMargin: Appearance.spacing.space200
                    text: Translation.tr("Legacy saved chats")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }

                Repeater {
                    model: root.legacyChats
                    delegate: RippleButton {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 40
                        buttonRadius: Appearance.rounding.normal
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: {
                            AiSessions.importLegacy(modelData.path);
                            root.closed();
                        }
                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Appearance.spacing.space100
                            anchors.rightMargin: Appearance.spacing.space100
                            spacing: Appearance.spacing.space100
                            MaterialSymbol {
                                text: "history"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colSubtext
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: modelData.name
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                            StyledText {
                                text: Translation.tr("import")
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }
                    }
                }
            }
        }
    }

    component SessionRow: Rectangle {
        id: row
        required property var modelData
        readonly property bool current: row.modelData.id === AiSessions.currentId
        property bool renaming: false

        Layout.fillWidth: true
        implicitHeight: 48
        radius: Appearance.rounding.normal
        color: row.current ? Appearance.colors.colSecondaryContainer
             : rowHover.hovered ? Appearance.colors.colLayer2Hover : "transparent"
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        HoverHandler { id: rowHover }
        MouseArea {
            anchors.fill: parent
            enabled: !row.renaming
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                AiSessions.openSession(row.modelData.id);
                root.closed();
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Appearance.spacing.space150
            anchors.rightMargin: Appearance.spacing.space100
            spacing: Appearance.spacing.space100

            MaterialSymbol {
                visible: row.modelData.pinned
                text: "keep"
                fill: 1
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colPrimary
            }

            // ONE text element for the title: readOnly until the rename
            // action arms it (the InlineEditChip rule - no label/input
            // twins).
            TextInput {
                id: titleInput
                Layout.fillWidth: true
                readOnly: !row.renaming
                enabled: row.renaming || undefined
                text: row.modelData.title.length > 0 ? row.modelData.title
                                                     : Translation.tr("Untitled chat")
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.small
                color: row.current ? Appearance.colors.colOnSecondaryContainer
                                   : Appearance.colors.colOnLayer1
                clip: true
                selectionColor: Appearance.colors.colPrimary
                selectedTextColor: Appearance.m3colors.m3onPrimary
                function finish(commit) {
                    if (!row.renaming) return;
                    row.renaming = false;
                    if (commit && text.trim().length > 0)
                        AiSessions.rename(row.modelData.id, text.trim());
                    else
                        text = Qt.binding(() => row.modelData.title.length > 0
                            ? row.modelData.title : Translation.tr("Untitled chat"));
                }
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        titleInput.finish(true); event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        titleInput.finish(false); event.accepted = true;
                    }
                }
                onActiveFocusChanged: if (!activeFocus) titleInput.finish(false)
            }

            StyledText {
                visible: !row.renaming
                text: Sessions.agoLabel(root.nowMs, row.modelData.updatedAt)
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }

            component RowAction: RippleButton {
                property string glyph: ""
                property real glyphFill: 0
                visible: rowHover.hovered && !row.renaming
                implicitWidth: 28
                implicitHeight: 28
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: parent.parent?.glyph ?? ""
                    fill: parent.parent?.glyphFill ?? 0
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                }
            }

            RowAction {
                glyph: row.modelData.pinned ? "keep_off" : "keep"
                onClicked: AiSessions.setPinned(row.modelData.id, !row.modelData.pinned)
            }
            RowAction {
                glyph: "edit"
                onClicked: {
                    row.renaming = true;
                    titleInput.text = row.modelData.title;
                    titleInput.forceActiveFocus();
                    titleInput.selectAll();
                }
            }
            RowAction {
                glyph: "delete"
                onClicked: AiSessions.remove(row.modelData.id)
            }
        }
    }
}
```

(Verify-before-trust: `RowAction`'s `contentItem` parent chain for `glyph` -
if the `parent.parent?.glyph` reach reads wrong at runtime, give the glyph
to a `required property` on an inline component instance instead; the
compile will say so immediately.)

- [ ] **Step 2: qmllint** (import-noise filter), then run the whole named set:

```
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/mocks -import tests/imports -input tests/tst_ai_sessions.qml
python3 tests/test_ai_skeleton_contract.py
```

- [ ] **Step 3: Commit**

```bash
git add -N dots/.config/quickshell/imi/modules/imi/sidebarLeft/aiChat/SessionListView.qml
git commit --only -F - -- \
  dots/.config/quickshell/imi/modules/imi/sidebarLeft/aiChat/SessionListView.qml <<'MSG'
feat(ai): the sessions view

Pinned first, then recency; open on the row, pin/rename/delete on
hover; the title renames in place through one text element (readOnly
until armed - the InlineEditChip rule); un-imported legacy chats
offered at the foot. Hosted by the view switcher with its slide-in
and the transcript's step-back.
MSG
```

---

### Task 5: pins, receipts, deploy, eyes

**Files:**
- Modify: `tests/test_ai_skeleton_contract.py` (grow), `CHANGELOG.md`, `docs/tests-README.md`

- [ ] **Step 1: Grow the pins** - append to `tests/test_ai_skeleton_contract.py` (before the `__main__` guard - it must stay LAST, the lesson `5309227ee` already paid for):

```python
AI_SERVICE = ROOT / "services/Ai.qml"
SESSIONS = ROOT / "services/ai/AiSessions.qml"


def test_chats_save_themselves_through_one_storage():
    """The autosave replaced the write-only saveChat("lastSession"); a
    second storage path growing back is how two copies of a chat drift."""
    ai = AI_SERVICE.read_text(encoding="utf-8")
    assert 'saveChat("lastSession")' not in ai, "the dead autosave crept back"
    assert "AiSessions.mint(" in ai, "the first user message must mint"
    assert "AiSessions.scheduleSave()" in ai, "adds and answers must flush"
    assert SESSIONS.exists()


def test_one_view_switcher_owns_the_overlays():
    chat = CHAT.read_text(encoding="utf-8")
    assert 'property string activeView' in chat
    assert "keysViewOpen" not in chat, (
        "the keys view must ride the switcher, not a flag of its own")
    assert "SessionListView" in chat
    bar = BAR.read_text(encoding="utf-8")
    assert "sessionsRequested" in bar, "the history chip requests, never renders"
```

- [ ] **Step 2: Run** - `python3 tests/test_ai_skeleton_contract.py` → `7/7 contract checks passed`.

- [ ] **Step 3: CHANGELOG (top of `### Added`)**

```markdown
- **Chats save themselves.** Every conversation persists as a session
  the moment you send the first message - no /save needed. The tools
  bar's new history chip opens the list: pinned first, open on the row,
  rename in place, pin and delete on hover, and your old /save files
  waiting at the foot to be imported. /save now names the current
  session; /load imports the file it names.
```

- [ ] **Step 4: docs/tests-README.md** (beside the AI skeleton entry)

```markdown
* **AI sessions tests (`tst_ai_sessions.qml`)**: the sessions arithmetic - titles from the first prompt, pinned-then-recency order, copy-on-write folds, legacy flat files mapped to session documents, and the index-rebuild fold that keeps the index a cache. The skeleton contract grew the storage pins: the write-only saveChat("lastSession") stays retired, the first user message mints, and one view switcher owns the transcript overlays.
```

- [ ] **Step 5: Commit, deploy, restart**

```bash
git commit --only -F - -- dots/.config/quickshell/imi/tests/test_ai_skeleton_contract.py \
  CHANGELOG.md docs/tests-README.md <<'MSG'
docs: receipts and pins for AI sessions
MSG
cd ~/dev/imi-unify && ./deploy-shell
qs kill -c imi; sleep 1; setsid -f qs -c imi
```

(Full restart: a new singleton registers only on restart.)

- [ ] **Step 6: Maintainer visual pass.** Send a message → a session appears in the history chip's list, titled from the prompt; send more → updatedAt bumps; rename inline; pin (rises to top); new-chat chip → old session finalized, list shows it; open it back (transcript reveals); delete it; import a legacy chat from the foot; `/save name` renames; restart the shell → sessions survive. The maintainer drives; no captures without asking.

---

## Self-review notes

- Spec coverage: autosave + lazy mint (T2), debounce triggers (T2 wiring), titles + rename + /save sugar (T1/T2/T4), /load + legacy section import (T2/T4), storage layout + index cache + rebuild (T1/T2), view switcher + history chip + step-back reuse (T3), row grammar + one-element rename (T4), corrupt-file handling (T2 openSession/importLegacy catch), pins + receipts (T5).
- Type consistency: `mint(firstPrompt)`/`scheduleSave()`/`saveNow()`/`openSession(id)`/`newSession()`/`rename(id,title)`/`setPinned(id,pinned)`/`remove(id)`/`importLegacy(path)` spelled identically in T2's service, T3's wiring and T4's view; `Sessions.*` names match T1's lib; `activeView`/`toggleView` consistent across T3.
- Verify-before-trust, named inline: singleton registration location for `services/ai/` (T2 note), the `RowAction` glyph reach (T4 note), and `Translation` availability inside a `services/` singleton (Ai.qml already uses it there).
- Date.now()/Math.random() in QML runtime are fine (the Workflow-tool restriction does not apply to shell code).
