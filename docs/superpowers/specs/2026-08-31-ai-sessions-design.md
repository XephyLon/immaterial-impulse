# AI Sessions — Design

**Date:** 2026-08-31
**Status:** Approved (brainstorm 2026-08-31; sub-project 2 of the AI polish, after skeleton+motion)

## Problem

Chats are ephemeral unless the user types `/save NAME`, and the only browse
UI is the `/load ` suggestion chips. The maintainer's decisions: every chat
auto-saves by default; a browsable sessions view lives behind the tools
bar; the fork's SessionList grammar transfers on imi tokens - not its
staging/commit service machinery (schema versions, operation ids,
retention), which is more than this shell needs.

## Decisions

1. **Autosave.** Every chat persists without being asked. A session id is
   created lazily on the first message - empty chats never touch disk.
   Saves debounce (~1 s) off `Ai.responseFinished` and message-list growth.
2. **Titles** auto-fill from the first user prompt (trimmed, ~40 chars);
   inline rename in the list; `/save NAME` becomes rename-current.
3. **Commands become sugar.** `/load NAME` imports a legacy flat chat file
   as a session and opens it (original left in place); a "Legacy" section
   at the list's foot offers the same. One storage system.
4. **Keep everything.** No retention; delete is a row action.

## Storage

- `Directories.aiChats/sessions/<id>.json`:
  `{ "meta": { "id", "title", "createdAt", "updatedAt", "pinned" },
     "messages": [ ...the existing chatToJson shape... ] }`
- `Directories.aiChats/sessions-index.json`: the list rows
  (id/title/updatedAt/pinned) so the drawer never parses transcripts.
  Missing or corrupt → rebuilt by scanning session metas.
- Legacy `Directories.aiChats/*.json` (flat message arrays) stay readable
  through the import path only.

## Service: `services/ai/AiSessions.qml` (new, imi's own)

- State: `index` (list rows, pinned first then updatedAt desc),
  `currentId`, `loaded`.
- API: `ensureLoaded()`, `openSession(id)` (loads messages into Ai, sets
  currentId, emits `sessionOpened`), `newSession()` (finalize current,
  clear, blank currentId until the next first message), `rename(id,
  title)`, `setPinned(id, pinned)`, `remove(id)` (current → also clears
  the chat), `importLegacy(path)`, `scheduleSave()` (debounced),
  `saveNow()`.
- Wire points in `Ai.qml`: `responseFinished` → `scheduleSave()`; message
  add → `scheduleSave()`; first user message with no `currentId` → mint
  id + title; `saveChat(name)` → `rename(currentId, name)`;
  `loadChat(name)` → `importLegacy(...)`; `clearMessages` via the
  new-chat chip → finalize first (one flush) then clear.
- Pure arithmetic in `services/ai/ai_sessions.js`: `titleFrom(prompt)`
  (trim, collapse whitespace, cap ~40 with ellipsis), `sortedIndex(rows)`
  (pinned first, updatedAt desc), `rowFor(meta)`, legacy-import mapping
  (messages → meta+messages with title from first user message),
  index-rebuild fold. Tested headless.

## View

- `AiChat`'s keys-view loader generalizes to one view switcher:
  `property string activeView: ""` ("keys" | "sessions"), same slide-in,
  same transcript step-back, one view at a time; the back arrow and the
  opening chip both close/toggle.
- A new history chip (`forum`) in `ChatControlBar` toggles "sessions"
  (signal `sessionsRequested`, mirroring `keysRequested`).
- Session rows (fork grammar, imi tokens): pin glyph when pinned, title
  (inline-rename via the row's edit action - StyledTextInput swap is the
  fork's shape; the InlineEditChip one-element rule applies: one text
  element, readOnly until editing), relative time, hover actions
  pin/rename/delete; current session highlighted; opening a session runs
  the transcript reveal. Legacy section at the foot lists un-imported
  flat files with an import-on-open row.
- Empty list: a quiet placeholder line, no hero.

## Error handling

- Corrupt session file on open: message via `Ai.interfaceRole`, session
  left in the index, nothing cleared.
- Index/meta drift: rebuild path is the same fold the tests pin.
- Delete is immediate (no undo stack on this surface); the confirm is the
  hover action being deliberate, matching the fork.

## Testing

- `tests/tst_ai_sessions.qml` over `ai_sessions.js`: title trim/cap,
  sort (pinned first, then recency), legacy mapping, index rebuild fold,
  rename/pin/remove folds.
- Python pins (`test_ai_skeleton_contract.py` grows or a sibling):
  `saveChat` routes through sessions (no second storage), the view
  switcher owns both views (one `activeView`, keys view not a separate
  loader), the history chip requests rather than renders.
- Named tests only; suite parked; maintainer visual pass.

## Out of scope

Prompt history stepping and edit/regenerate (sub-3), search-in-sessions,
export, personas, retention settings.
