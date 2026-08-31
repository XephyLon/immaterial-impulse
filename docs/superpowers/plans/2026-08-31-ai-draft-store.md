# AI Draft Store Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The composer's unsent text survives restarts and session switches, per session plus a new-chat slot.

**Architecture:** A fold (`ai_drafts.js`) under a debounced singleton owning one `drafts.json`; the composer records on change, clears on send, restores on open. Spec: `docs/superpowers/specs/2026-08-31-ai-draft-store-design.md`.

**Tech Stack / Conventions:** as the catalog plan.

---

### Task 1: fold + test (TDD)

`tests/tst_ai_drafts.qml`:

```qml
import QtTest
import "../services/ai/ai_drafts.js" as Drafts

TestCase {
    name: "AiDraftsTest"

    function test_set_read_clear() {
        let map = Drafts.withDraft({}, "abc", "half a thought");
        compare(Drafts.draftFor(map, "abc"), "half a thought");
        compare(Drafts.draftFor(map, "other"), "");
        map = Drafts.withDraft(map, "abc", "");
        verify(!("abc" in map), "empty text deletes the slot");
    }

    function test_new_chat_slot() {
        let map = Drafts.withDraft({}, "", "unminted");
        compare(Drafts.draftFor(map, ""), "unminted");
        const pruned = Drafts.prune(map, ["x", "y"]);
        compare(Drafts.draftFor(pruned, ""), "unminted", "the new-chat slot survives pruning");
    }

    function test_prune_drops_dead_sessions() {
        let map = Drafts.withDraft({}, "dead", "gone soon");
        map = Drafts.withDraft(map, "alive", "stays");
        const pruned = Drafts.prune(map, ["alive"]);
        verify(!("dead" in pruned));
        compare(Drafts.draftFor(pruned, "alive"), "stays");
    }
}
```

`services/ai/ai_drafts.js`:

```js
.pragma library

// Composer drafts as a fold over a plain map { sessionId|"": text } - ""
// is the not-yet-minted chat's slot. Empty text deletes: a cleared
// composer is not a draft.

function withDraft(map, key, text) {
    var next = {};
    for (var k in (map || {})) next[k] = map[k];
    var clean = String(text ?? "");
    if (clean.length === 0) delete next[String(key ?? "")];
    else next[String(key ?? "")] = clean;
    return next;
}

function draftFor(map, key) {
    return String((map || {})[String(key ?? "")] ?? "");
}

// Sessions get deleted; their drafts follow. The new-chat slot always
// survives - it belongs to no session.
function prune(map, validKeys) {
    var keep = {};
    var valid = validKeys || [];
    for (var k in (map || {})) {
        if (k === "" || valid.indexOf(k) !== -1) keep[k] = map[k];
    }
    return keep;
}
```

Commit gated on `0 failed`: `feat(ai): drafts as a fold`.

---

### Task 2: singleton + composer wiring

`services/AiDrafts.qml`:

```qml
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
```

Composer wiring (AiChat):
- input `onTextChanged` head gains: `if (root.editingMessageIndex < 0) AiDrafts.record(AiSessions.currentId, messageInputField.text);`
- `acceptComposer` head gains `AiDrafts.clear(AiSessions.currentId);` (before the send mints a new id).
- restore arm:

```qml
    Connections {
        target: AiSessions
        function onSessionOpened(id) {
            // Only an EMPTY composer takes the stored draft - a half-typed
            // thought is never clobbered by a stale one.
            if (messageInputField.text.length === 0)
                messageInputField.text = AiDrafts.take(id);
        }
    }
```

plus the same restore after `AiSessions.newSession()` call sites?  No - newSession clears the transcript, not the composer; restore the new-chat slot in the SAME Connections via a `currentId` watch:

```qml
        function onCurrentIdChanged() {
            if (AiSessions.currentId === "" && messageInputField.text.length === 0)
                messageInputField.text = AiDrafts.take("");
        }
```

and startup restore in the chat's `Component.onCompleted`: `if (messageInputField.text.length === 0) messageInputField.text = AiDrafts.take(AiSessions.currentId);`

Pin (skeleton contract): `AiDrafts` never names the sessions index (`"sessions-index" not in services/AiDrafts.qml`), and the composer records drafts (`AiDrafts.record` in CHAT).

Receipts: CHANGELOG "**Drafts survive.** ..." + tests-README line. Deploy + full restart. Commit: `feat(ai): the composer keeps its drafts` + `docs: receipts`.

## Self-review

Coverage complete against the spec; edit-takeback records nothing (guard), send clears, open/new/startup restore into empty composers only. Names uniform: `record/take/clear`, `withDraft/draftFor/prune`.
