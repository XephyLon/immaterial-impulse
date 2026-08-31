# AI Draft Store — Design

**Date:** 2026-08-31
**Status:** Approved (brainstorm 2026-08-31; the completion round's second half)

## Decision

Per-session drafts plus one slot for a not-yet-minted chat (user's call):
the composer's unsent text survives shell restarts and session switches,
keyed by session id with `""` as the new-chat slot.

## Pieces

- `services/ai/ai_drafts.js` (pure): the store as a fold over a plain map -
  `withDraft(map, key, text)` (empty text deletes the slot),
  `draftFor(map, key)`, `prune(map, validKeys)` (drop slots whose session
  no longer exists, the new-chat slot always kept).
- `services/AiDrafts.qml` (singleton, beside AiSessions): owns
  `Directories.aiSessions/drafts.json` through one FileView, a ~1s debounce
  (the sessions' pattern), `record(key, text)`, `take(key)` → text.
  Load-once on first use; a corrupt file starts empty rather than failing.
- Composer wiring (AiChat): every input text change records to the current
  slot (`AiSessions.currentId`); `acceptComposer` clears the slot on send;
  opening a session or starting a new chat restores that slot's draft into
  the composer (overwriting only an EMPTY composer, so a half-typed thought
  is never clobbered by a stale draft); the takeback edit mode records
  nothing while active.

## Testing

`tests/tst_ai_drafts.qml` over the fold: set/overwrite/clear-on-empty,
prune keeps the new-chat slot, unknown keys read "". Pin: AiDrafts never
touches the sessions index file.

## Out of scope

Draft history, cross-device sync, attachments in drafts.
