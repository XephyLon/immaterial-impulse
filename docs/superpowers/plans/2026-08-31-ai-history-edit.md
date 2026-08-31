# AI Prompt History & Edit-Resend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Up/Down steps the composer through this chat's past prompts, and any user question can be taken back into the composer, reworded, and resent as a forked session - the old branch stays in Chats.

**Architecture:** The stepping state is a pure fold (`prompt_history.js`) the composer applies; `Ai.ownPromptHistory` derives from the transcript; `Ai.editAndResend` forks by flushing the current session, clearing `currentId`, rebuilding the transcript before the edited question and re-sending (mint titles the new session). Spec: `docs/superpowers/specs/2026-08-31-ai-history-edit-design.md`.

**Tech Stack:** QML, qmltestrunner, python pins. Paths relative to `dots/.config/quickshell/imi/`.

**Conventions:** `git commit --only -F - -- <paths>` (new files `git add -N` first); no attribution; run only named tests; VERIFY test/pin output before the commit line runs - do not chain past a failure.

**Facts verified at plan time:** the input's `Keys.onPressed` arms run suggestions' Up/Down first (gated `suggestions.visible`), then Enter, then Ctrl+V, then Escape (detach-file); `inputWrapper.implicitHeight` is one arithmetic line the banner must join; root `Keys.onPressed` holds PageUp/Down + Ctrl+Shift+O; `AiMessage`'s buttons live in a `ButtonGroup` at ~line 216 with `regenButton` first; `Ai.regenerate(messageIndex)` exists; `chatToJson()` maps `root.messageIDs`; delegates receive `messageIndex`/`messageData` and `root.inputField` as `messageInputField`.

---

### Task 1: the stepping fold

**Files:**
- Create: `services/ai/prompt_history.js`
- Test: `tests/tst_prompt_history.qml`

- [ ] **Step 1: Write the failing test**

`tests/tst_prompt_history.qml`:

```qml
import QtTest
import "../services/ai/prompt_history.js" as PromptHistory

// Shell-style prompt recall as a fold: the composer holds {index, backup}
// and applies step() per keypress. Pure, so every rule the spec states is
// checked here and the composer only wires keys.
TestCase {
    name: "PromptHistoryTest"

    readonly property var history: ["first", "second", "third"]

    function test_idle_down_is_unhandled() {
        const r = PromptHistory.step(PromptHistory.idle(), history, "draft", 1);
        verify(!r.handled);
    }

    function test_empty_history_is_unhandled() {
        const r = PromptHistory.step(PromptHistory.idle(), [], "", -1);
        verify(!r.handled);
    }

    function test_up_from_idle_backs_up_the_draft_and_lands_newest() {
        const r = PromptHistory.step(PromptHistory.idle(), history, "half a thought", -1);
        verify(r.handled);
        compare(r.index, 2);
        compare(r.backup, "half a thought");
        compare(r.text, "third");
    }

    function test_walk_up_and_oldest_consumes_further_ups() {
        let s = PromptHistory.step(PromptHistory.idle(), history, "", -1);
        s = PromptHistory.step(s, history, history[s.index], -1);
        compare(s.text, "second");
        s = PromptHistory.step(s, history, history[s.index], -1);
        compare(s.text, "first");
        const stuck = PromptHistory.step(s, history, "first", -1);
        verify(stuck.handled, "the key is consumed at the oldest");
        compare(stuck.index, 0);
        compare(stuck.text, null, "no rewrite when nothing moves");
    }

    function test_down_past_newest_restores_the_draft_and_resets() {
        let s = PromptHistory.step(PromptHistory.idle(), history, "my draft", -1);
        const r = PromptHistory.step(s, history, "third", 1);
        verify(r.handled);
        compare(r.text, "my draft");
        compare(r.index, -1);
        compare(r.backup, "");
    }

    function test_round_trip_up_up_down_down() {
        let s = PromptHistory.step(PromptHistory.idle(), history, "wip", -1);
        s = PromptHistory.step(s, history, "third", -1);
        s = PromptHistory.step(s, history, "second", 1);
        compare(s.text, "third");
        s = PromptHistory.step(s, history, "third", 1);
        compare(s.text, "wip");
        compare(s.index, -1);
    }
}
```

- [ ] **Step 2: Run — must fail** (compile FAIL, file missing):
`cd dots/.config/quickshell/imi && QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/mocks -import tests/imports -input tests/tst_prompt_history.qml`

- [ ] **Step 3: Write `services/ai/prompt_history.js`**

```js
.pragma library

// Shell-style prompt recall (spec 2026-08-31), as a fold over
// { index, backup }: -1/"" is idle (the live draft). The composer applies
// the result verbatim; every decision is here, testable headless.
//
// step() returns { index, backup, text, handled }: `handled` says whether
// the key belonged to the history at all, and `text` is the composer's new
// content - null when nothing rewrites (unhandled, or Up at the oldest).

function idle() {
    return { index: -1, backup: "" };
}

function step(state, history, draft, delta) {
    var list = history || [];
    var unhandled = { index: state.index, backup: state.backup, text: null, handled: false };
    if (list.length === 0) return unhandled;
    if (state.index === -1) {
        // At the live draft: only Up enters the history, and the draft is
        // backed up so walking back down returns exactly what was typed.
        if (delta > 0) return unhandled;
        return { index: list.length - 1, backup: draft, text: list[list.length - 1], handled: true };
    }
    if (delta < 0) {
        if (state.index === 0)
            return { index: 0, backup: state.backup, text: null, handled: true };
        var older = state.index - 1;
        return { index: older, backup: state.backup, text: list[older], handled: true };
    }
    if (state.index >= list.length - 1)
        return { index: -1, backup: "", text: state.backup, handled: true };
    var newer = state.index + 1;
    return { index: newer, backup: state.backup, text: list[newer], handled: true };
}
```

- [ ] **Step 4: Run — must pass** (`Totals: 6 passed`).

- [ ] **Step 5: Commit**

```bash
cd ~/dev/imi-unify
git add -N dots/.config/quickshell/imi/services/ai/prompt_history.js \
  dots/.config/quickshell/imi/tests/tst_prompt_history.qml
git commit --only -F - -- \
  dots/.config/quickshell/imi/services/ai/prompt_history.js \
  dots/.config/quickshell/imi/tests/tst_prompt_history.qml <<'MSG'
feat(ai): prompt recall as a fold

Shell-style history stepping over {index, backup}: Up from the live
draft backs it up and lands on the newest prompt, the oldest consumes
further Ups, and walking back down past the newest restores exactly
what was typed. Pure, tested headless; the composer only wires keys.
MSG
```

---

### Task 2: the service verbs

**Files:**
- Modify: `services/Ai.qml` (`chatToJson` signature, `ownPromptHistory`, `editAndResend`)

- [ ] **Step 1: `chatToJson` takes an optional slice** - change its first line:

```qml
    function chatToJson(ids = root.messageIDs) {
        return ids.map(id => {
```

(the rest of the body is unchanged; `AiSessions.saveNow` keeps calling it bare.)

- [ ] **Step 2: Add beside `pickerModelList`:**

```qml
    // What the composer's Up key recalls: the prompts someone actually
    // typed into THIS chat - user role, visible, non-empty - in order.
    // Hidden carriers (tool outputs, silent instructions) are not prompts.
    readonly property var ownPromptHistory: {
        const list = [];
        for (let i = 0; i < root.messageIDs.length; i++) {
            const message = root.messageByID[root.messageIDs[i]];
            if (message?.role !== "user" || message.visibleToUser === false)
                continue;
            const text = String(message.rawContent ?? message.content ?? "").trim();
            if (text.length > 0)
                list.push(text);
        }
        return list;
    }
```

- [ ] **Step 3: Add after `regenerate`:**

```qml
    /**
     * Sends a rewritten question as a FORK (spec 2026-08-31): everything
     * after the old wording answered the old wording, so the current
     * session is flushed and left behind - still openable in Chats - and
     * the edit continues in a fresh transcript truncated at the edited
     * question. Never a removeMessage loop: nothing is destroyed.
     */
    function editAndResend(messageIndex, newText) {
        const text = String(newText ?? "").trim();
        if (text.length === 0) return;
        if (messageIndex < 0 || messageIndex >= root.messageIDs.length) return;
        if (root.messageByID[root.messageIDs[messageIndex]]?.role !== "user") return;
        if (root.isGenerating) {
            root.addMessage(Translation.tr("Wait for the current answer to finish before editing."), root.interfaceRole);
            return;
        }
        AiSessions.saveNow();
        AiSessions.currentId = "";
        const kept = root.chatToJson(root.messageIDs.slice(0, messageIndex));
        root.loadMessagesFromJson(kept);
        root.sendUserMessage(text);
    }
```

(Verify-before-trust: `Ai.isGenerating` - the reveal guard already reads it in AiChat; if the property is spelled differently in Ai.qml, use that spelling and note it in the commit.)

- [ ] **Step 4: qmllint + existing suites**

```
/usr/lib/qt6/bin/qmllint -I . -I /usr/lib/qt6/qml services/Ai.qml 2>&1 | grep -iE "error"
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/mocks -import tests/imports -input tests/tst_ai_sessions.qml
python3 tests/test_ai_catalog_contract.py
```

- [ ] **Step 5: Commit**

```bash
git commit --only -F - -- dots/.config/quickshell/imi/services/Ai.qml <<'MSG'
feat(ai): ownPromptHistory and the forking editAndResend

The composer's recall list derives from the transcript's typed
prompts, and a rewritten question forks: the current session flushes
and stays behind in Chats, the transcript rebuilds from before the
edited question, and the resend mints the new session titled by the
new wording. chatToJson takes an optional id slice for the rebuild.
MSG
```

---

### Task 3: the composer

**Files:**
- Modify: `modules/imi/sidebarLeft/AiChat.qml`

- [ ] **Step 1: Root state + import** - beside the other function imports at the top:

```qml
import "../../../services/ai/prompt_history.js" as PromptHistory
```

after `property string commandPrefix: "/"`:

```qml
    // Prompt recall (Task 1's fold) and the edit takeback. Reset on every
    // send so a recalled prompt does not leak into the next stepping run.
    property var promptHistoryState: PromptHistory.idle()
    property int editingMessageIndex: -1

    function stepPromptHistory(delta) {
        const r = PromptHistory.step(root.promptHistoryState,
            Ai.ownPromptHistory, messageInputField.text, delta);
        if (!r.handled) return false;
        root.promptHistoryState = { index: r.index, backup: r.backup };
        if (r.text !== null) {
            messageInputField.text = r.text;
            messageInputField.cursorPosition = messageInputField.text.length;
        }
        return true;
    }

    function beginEdit(messageIndex, content) {
        root.editingMessageIndex = messageIndex;
        messageInputField.text = String(content ?? "");
        messageInputField.cursorPosition = messageInputField.text.length;
        messageInputField.forceActiveFocus();
    }

    function cancelEdit() {
        if (root.editingMessageIndex < 0) return;
        root.editingMessageIndex = -1;
        messageInputField.clear();
    }

    function acceptComposer(inputText) {
        root.promptHistoryState = PromptHistory.idle();
        if (root.editingMessageIndex >= 0) {
            const at = root.editingMessageIndex;
            root.editingMessageIndex = -1;
            Ai.editAndResend(at, inputText);
            return;
        }
        root.handleInput(inputText);
    }
```

- [ ] **Step 2: Route every accept through it.** Three call sites send today; all become `root.acceptComposer(...)`:
- the input's Enter arm: `root.handleInput(inputText);` → `root.acceptComposer(inputText);`
- `messageInputField.accept()`: `root.handleInput(text);` → `root.acceptComposer(text);`
- the send button's `onClicked`: `root.handleInput(inputText);` → `root.acceptComposer(inputText);`

- [ ] **Step 3: The key arms.** In the input's `Keys.onPressed`, extend the suggestion arms' conditions and add the history arms - the block becomes:

```qml
                            } else if (event.key === Qt.Key_Up && suggestions.visible) {
                                suggestions.selectedIndex = Math.max(0, suggestions.selectedIndex - 1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Down && suggestions.visible) {
                                suggestions.selectedIndex = Math.min(root.suggestionList.length - 1, suggestions.selectedIndex + 1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Up && event.modifiers === Qt.NoModifier
                                    && root.editingMessageIndex < 0
                                    && (messageInputField.text.length === 0 || root.promptHistoryState.index !== -1)) {
                                // Shell-style recall - only from an empty
                                // draft, so cursor movement in a real
                                // multi-line message is never hijacked.
                                if (root.stepPromptHistory(-1)) event.accepted = true;
                            } else if (event.key === Qt.Key_Down && event.modifiers === Qt.NoModifier
                                    && root.editingMessageIndex < 0
                                    && root.promptHistoryState.index !== -1) {
                                if (root.stepPromptHistory(1)) event.accepted = true;
                            } else if ((event.key === Qt.Key_Enter || event.key === Qt.Key_Return)) {
```

and the Escape arm gains the edit-cancel FIRST:

```qml
                            } else if (event.key === Qt.Key_Escape) {
                                if (root.editingMessageIndex >= 0) {
                                    // Cancel the takeback before Escape can
                                    // mean detach-file.
                                    root.cancelEdit();
                                    event.accepted = true;
                                } else if (Ai.pendingFilePath.length > 0) {
                                    Ai.attachFile("");
                                    event.accepted = true;
                                } else {
                                    event.accepted = false;
                                }
                            }
```

- [ ] **Step 4: The banner.** Inside `inputWrapper`, after the `AttachedFileIndicator` block:

```qml
            RowLayout { // The takeback banner: says the mode, names the exit.
                id: editBanner
                visible: root.editingMessageIndex >= 0
                anchors {
                    top: attachedFileIndicator.bottom
                    left: parent.left
                    right: parent.right
                    topMargin: visible ? Appearance.spacing.space50 : 0
                    leftMargin: Appearance.spacing.space150
                    rightMargin: Appearance.spacing.space150
                }
                spacing: Appearance.spacing.space50
                MaterialSymbol {
                    text: "edit_note"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: Translation.tr("Editing a question - Enter resends as a new chat, Esc cancels")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
```

and the wrapper's `implicitHeight` line gains one term - append at its end:

```qml
                + (editBanner.visible ? editBanner.implicitHeight + spacing : 0)
```

(also change `inputFieldRowLayout`'s `anchors.bottom` chain nothing - it anchors to `commandButtonsRow.top` and is unaffected; the banner occupies the attachment indicator's band.)

- [ ] **Step 5: Root shortcuts** - in the root `Keys.onPressed`, after the Ctrl+Shift+O arm:

```qml
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_R) {
            // Redo the last answer with the same wording.
            for (let at = Ai.messageIDs.length - 1; at >= 0; at--) {
                if (Ai.messageByID[Ai.messageIDs[at]]?.role === "assistant") {
                    Ai.regenerate(at);
                    break;
                }
            }
            event.accepted = true;
        }
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Up
                && messageInputField.text.length === 0) {
            // Take the last question back for another go.
            for (let at = Ai.messageIDs.length - 1; at >= 0; at--) {
                const m = Ai.messageByID[Ai.messageIDs[at]];
                if (m?.role === "user" && m.visibleToUser !== false) {
                    root.beginEdit(at, String(m.rawContent ?? m.content ?? ""));
                    break;
                }
            }
            event.accepted = true;
        }
```

- [ ] **Step 6: Delegate wiring** - the message list's `delegate: AiMessage { ... }` gains:

```qml
                    onEditResendRequested: (messageIndex, content) => root.beginEdit(messageIndex, content)
```

- [ ] **Step 7: qmllint + skeleton pins** (`python3 tests/test_ai_skeleton_contract.py` - still green; the new pins land in Task 4).

- [ ] **Step 8: Commit**

```bash
git commit --only -F - -- dots/.config/quickshell/imi/modules/imi/sidebarLeft/AiChat.qml <<'MSG'
feat(ai): the composer recalls prompts and takes questions back

Up/Down applies the tested fold - empty-draft gate, suggestions keep
priority, the live draft survives the round trip - and a takeback
fills the composer under a banner that names the mode: Enter resends
as a forked chat, Esc cancels before it can mean detach-file. Ctrl+R
redoes the last answer; Ctrl+Up takes the last question back.
MSG
```

---

### Task 4: the message action, pins, receipts

**Files:**
- Modify: `modules/imi/sidebarLeft/aiChat/AiMessage.qml`
- Modify: `tests/test_ai_skeleton_contract.py` (grow, before the `__main__` guard), `CHANGELOG.md`, `docs/tests-README.md`

- [ ] **Step 1: The signal + button.** In `AiMessage.qml`, beside the other root properties:

```qml
    /** Asks the composer to take this question back for another go. */
    signal editResendRequested(int messageIndex, string content)
```

and in the `ButtonGroup` (before `regenButton`):

```qml
                    AiMessageControlButton {
                        id: editResendButton
                        visible: messageData?.role === 'user'
                        enabled: messageData?.done ?? false
                        buttonIcon: "edit_note"
                        onClicked: root.editResendRequested(root.messageIndex,
                            String(root.messageData?.rawContent ?? root.messageData?.content ?? ""))
                        StyledToolTip {
                            text: Translation.tr("Edit & resend")
                        }
                    }
```

- [ ] **Step 2: Grow the pins** - append before the `__main__` guard:

```python
def test_the_history_arm_keeps_the_empty_draft_gate():
    """Recall only from an empty draft: without the gate, Up in a
    multi-line message jumps the transcript into the composer."""
    chat = CHAT.read_text(encoding="utf-8")
    assert "stepPromptHistory(-1)" in chat
    up_arm = chat.split("stepPromptHistory(-1)")[0].rsplit("} else if", 1)[1]
    assert "text.length === 0" in up_arm, "the Up arm lost its empty-draft gate"


def test_edit_and_resend_forks_and_never_truncates_in_place():
    ai = (ROOT / "services/Ai.qml").read_text(encoding="utf-8")
    body = ai.split("function editAndResend")[1].split("\n    }")[0]
    assert "AiSessions.saveNow()" in body, "the old branch must flush first"
    assert "removeMessage" not in body, (
        "editAndResend deletes nothing - the fork rule")
    assert "editResendRequested" in (ROOT / "modules/imi/sidebarLeft/aiChat/AiMessage.qml").read_text(encoding="utf-8")
```

Run: `python3 tests/test_ai_skeleton_contract.py` → `9/9 contract checks passed`.

- [ ] **Step 3: CHANGELOG (top of `### Added`)**

```markdown
- **The composer remembers, and questions get second drafts.** Up/Down
  steps through this chat's past prompts shell-style (your unsent draft
  survives the round trip), and any question can be taken back - the
  edit_note action on the message, or Ctrl+Up for the last one -
  reworded, and resent as a fresh chat; the old branch stays in Chats.
  Ctrl+R redoes the last answer.
```

- [ ] **Step 4: docs/tests-README.md** (beside the AI sessions entry)

```markdown
* **Prompt history tests (`tst_prompt_history.qml`)**: the recall fold - Up from the live draft backs it up and lands newest, the oldest consumes further Ups, Down past newest restores the draft exactly. The skeleton contract pins the composer's empty-draft gate and that editAndResend forks (flush first, delete nothing).
```

- [ ] **Step 5: Commit, deploy, restart**

```bash
git commit --only -F - -- \
  dots/.config/quickshell/imi/modules/imi/sidebarLeft/aiChat/AiMessage.qml \
  dots/.config/quickshell/imi/tests/test_ai_skeleton_contract.py \
  CHANGELOG.md docs/tests-README.md <<'MSG'
feat(ai): edit & resend on the question, pins and receipts

User rows carry the takeback action; the pins hold the empty-draft
gate and the fork rule - flush first, delete nothing.
MSG
cd ~/dev/imi-unify && ./deploy-shell
qs kill -c imi; sleep 1; setsid -f qs -c imi
```

(Full restart: prompt_history.js is a new module file.)

- [ ] **Step 6: Maintainer visual pass.** Type nothing, press Up - last prompt appears; Up/Up/Down/Down - draft returns; type half a line, Up - cursor moves, no hijack. Hover a question → edit_note → banner appears, reword, Enter → new chat sends, old one intact in Chats; Esc mid-edit cancels; Esc with a file attached still detaches when not editing. Ctrl+R regenerates; Ctrl+Up takes the last question back. The maintainer drives; no captures without asking.

---

## Self-review notes

- Spec coverage: fold + rules (T1), ownPromptHistory + editAndResend + guards incl. isGenerating (T2), composer arms with suggestion priority + empty-draft gate + reset-on-send + banner + Escape order + Ctrl+R/Ctrl+Up (T3), message action + signal (T4), pins + receipts (T4). Out-of-scope list respected.
- Type consistency: `stepPromptHistory(delta)`/`beginEdit(messageIndex, content)`/`cancelEdit()`/`acceptComposer(inputText)` spelled identically in T3's definitions and every call; `editResendRequested(int messageIndex, string content)` matches T3 Step 6's handler; `PromptHistory.idle()/step()` match T1.
- Verify-before-trust, inline: `Ai.isGenerating` spelling (T2 note); the Enter-arm and accept() and send-button call-site spellings are quoted from the live file at plan time - if `accept()` was refactored, route whatever sends through `acceptComposer`.
- Process note honored: every Step's run is checked BEFORE its commit line - twice this session a chained commit ran past a red test.
