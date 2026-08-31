# AI Prompt History & Edit-Resend — Design

**Date:** 2026-08-31
**Status:** Approved (brainstorm 2026-08-31; sub-project 3, the last of the AI polish decomposition)

## Problem

The composer forgets what was typed the moment it is sent, and rewording a
question means retyping it: there is no shell-style history stepping and no
way to take a question back, reword it, and resend without destroying the
answers that followed the old wording.

## Decisions

1. **History is the transcript** (fork's shape): `Ai.ownPromptHistory` is a
   derived readonly list of the current chat's visible user prompts -
   role "user", `visibleToUser !== false`, trimmed non-empty `rawContent`.
   No persistence, no new state, resets naturally with the session.
2. **Stepping only from an empty draft** (or while already navigating), so
   cursor movement inside a real multi-line message is never hijacked;
   the suggestion chips keep Up/Down priority while visible; the live
   draft is backed up on entry and restored walking back down past the
   newest entry; the oldest entry consumes further Ups.
3. **Edit & resend forks the session** (user's call): everything after the
   old wording answered the old wording, so the old branch is preserved -
   flushed as-is and left openable in Chats - and the edit continues in a
   fresh session truncated at the edited question.

## Pieces

### `services/ai/prompt_history.js` (new, pure)

The stepping state as a fold, testable headless:
`step(state, history, draft, delta)` → `{ index, backup, text, handled }`
where state is `{ index, backup }` (-1/"" idle). Rules: empty history →
unhandled; idle + Down → unhandled; idle + Up → backup draft, jump to
newest; Up at oldest → handled, no move; Down past newest → restore
backup, reset to idle. `reset()` returns the idle state.

### `services/Ai.qml`

- `readonly property var ownPromptHistory` (rule 1's filter, fork
  verbatim in spirit).
- `function editAndResend(messageIndex, newText)`:
  1. `AiSessions.saveNow()` - the old branch's last flush;
  2. `AiSessions.currentId = ""` (the fork: the old session stays);
  3. rebuild the transcript from `chatToJson()` of the messages BEFORE
     `messageIndex` via the existing `loadMessagesFromJson`;
  4. `sendUserMessage(newText)` - mints the new session, titled by the
     new wording, and requests.
  Guards: index out of range or not a user message → no-op; empty
  newText → no-op.

### `modules/imi/sidebarLeft/AiChat.qml` (composer)

- History state `{ index, backup }` + Up/Down arms in the input's
  `Keys.onPressed`, AFTER the suggestion arms (they already gate on
  `suggestions.visible`), gated on `text.length === 0 || index !== -1`
  and no edit in flight.
- Edit mode: `editingMessageIndex` (-1 idle); `beginEdit(index)` fills
  the composer with the question's rawContent and focuses; a slim banner
  row above the input names the mode ("Editing question - Esc cancels",
  `edit_note` glyph, imi tokens); Enter commits `Ai.editAndResend`,
  Escape cancels edit BEFORE it means detach-file; sending normally is
  impossible while editing (the accept path routes to commit).
- `Ctrl+Up` on an empty draft = edit last question; `Ctrl+R` =
  regenerate last answer (`Ai.regenerate` on the last assistant index).

### `modules/imi/sidebarLeft/aiChat/AiMessage.qml`

User-role rows gain an "Edit & resend" `AiMessageControlButton`
(`edit_note`, tooltip Translation.tr("Edit & resend")) that asks the chat
root via the existing `messageInputField`-style plumbing - a new
`signal editResendRequested(int messageIndex, string content)` wired at
the delegate, handled by `root.beginEdit`. The existing in-place edit,
regenerate, copy, markdown and delete buttons stay untouched.

## Error handling

- History with the transcript cleared mid-navigation: the fold's guards
  return unhandled and the state resets on send/clear (both call reset).
- editAndResend on a streaming answer: gated on `!Ai.isGenerating`
  (interface message says why, matching the reveal guard's spirit).

## Testing

- `tests/tst_prompt_history.qml` over the fold: idle-Down unhandled,
  backup/restore round trip, oldest-consumes-Up, empty history, reset.
- Pins (skeleton contract grows): the input's Up arm carries the
  empty-draft gate; `editAndResend` calls `saveNow` before clearing and
  never loops `removeMessage` (the fork rule, pinned by absence).
- Named tests only; suite parked; maintainer visual pass.

## Out of scope

Cross-session prompt history, editing non-last questions in flight
(any user question is editable - the fork point is wherever it sits),
model-picker-per-regenerate, response profiles.
