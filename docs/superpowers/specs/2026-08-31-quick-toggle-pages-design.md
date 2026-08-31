# Quick-Toggle Pages — Design

**Date:** 2026-08-31
**Status:** Approved (brainstorm 2026-08-31; explicit pages, swipe + dots, android style only, `+` in edit mode, drag-past-edge cross-page moves)

## Problem

The right sidebar's android-style quick-toggle grid is one flat, config-stored
list. 21 toggle types exist; a grid holding more than a handful grows tall and
pushes the rest of the sidebar down. The maintainer wants **pages**: several
deliberately-composed grids in the same footprint, navigated like a phone's
quick settings shade.

## Decisions (the brainstorm's answers)

1. **Explicit pages.** The user composes each page; tiles do not auto-flow.
2. **Swipe + dots.** Horizontal swipe/flick between pages, a dot indicator
   beneath the grid, dots clickable.
3. **Android style only.** Classic stays the hardcoded single cluster.
4. **`+` in edit mode.** Page count is implicit: a `+` beside the dots creates
   a blank page; a page emptied of toggles vanishes when edit mode exits.
5. **Drag past page edge.** Holding a dragged tile against the pager's edge
   (~300 ms) slides to the neighbouring page and the drag continues there.

## Config & model

- New key `sidebar.quickToggles.android.pages`: a list of pages, each a list
  of `{type, size}` entries — the same entry shape `android.toggles` holds
  today.
- `android.toggles` stays in the schema as the migration source and is not
  written to any more. On panel load: `pages` empty and `toggles` non-empty →
  treat as `pages = [toggles]` (write the migrated shape back once, so presets
  saved afterwards carry `pages`).
- **One home per toggle:** a type appears on at most one page. The unused pool
  is every available type on no page.
- **One `StableQuickToggleModel` per page.** The existing per-list machinery —
  `quick_toggle_layout.pack`, `syncPlan`, the signature-driven `requestSync` —
  is reused unchanged, one instance per page.
- Page-level operations live in a new pure-JS lib
  (`modules/common/functions/quick_toggle_pages.js`, beside `layout_ops.js`):
  migrate legacy list, add page, prune empty pages, move an entry from page A
  index i to page B index j (preserving one-home-per-toggle), plus a
  signature helper so the panel can observe the nested list the same way it
  observes the flat one. All testable without a scene.
- The `Columns` setting stays global (one value for all pages).

## View

- The grid area becomes a horizontal pager: a snap-per-page `ListView`
  (`snapMode: SnapOneItem`, `highlightRangeMode: StrictlyEnforceRange`,
  clipped), one delegate per page hosting that page's packed grid.
- Dot row beneath: one dot per page, current page emphasized, clickable.
  Hidden when there is exactly one page and edit mode is off.
- Panel height animates to the **current** page's grid height (the existing
  `Behavior on implicitHeight`), not the tallest page.
- The sidebar-open tile wave (`StaggerWave`, leadIn 80 / step 25) runs on the
  current page's grid only. A page flip is a slide; it does not re-run the
  wave.
- Toggle activation, right-click dialogs, and the classic panel are untouched.

## Edit mode

- The dot row gains a trailing `+` while `editMode` is true: creates a blank
  page after the last and slides to it.
- Exiting edit mode prunes empty pages (via the JS lib). The current-page
  index clamps.
- The unused section stays **one shared pool**, rendered under whichever page
  is current; enabling a tile from it inserts onto the current page.
- Cross-page move: while a tile drag is live and the pointer sits within an
  edge band of the pager for ~300 ms, the pager slides one page in that
  direction and the drag continues; the drop commits remove-from-A +
  insert-into-B through the JS lib. The delegate is re-created on the target
  page (different Repeater/model) and arrives with its entrance — accepted.
- Free swipe is disabled while a drag is live; dots stay clickable.
- Existing in-page gestures (LMB enable/disable, RMB size, scroll/drag
  reorder) unchanged.

## Error handling

- A malformed `pages` value (not a list, or holding non-list pages) falls back
  to the legacy `toggles` migration path; a malformed entry is normalised by
  the existing `sizeOf`/id machinery.
- A type named on two pages (hand-edited config, imported preset): the first
  occurrence wins, later ones are dropped by the lib's normalise step — same
  spirit as `idFor`'s occurrence counter.

## Testing

- `tests/tst_quick_toggle_pages.qml` against the JS lib: legacy migration
  wraps to one page; add/prune; cross-page move keeps one home per toggle and
  both pages' orders; duplicate-type normalisation; signature changes exactly
  when a sync would do something.
- Structural pins (python): the panel reads `pages` (not `toggles`) for
  rendering; the `+` renders only in edit mode; prune runs on edit-mode exit.
- Named tests only; the suite stays parked.

## Out of scope

- Classic-style pagination, per-page column counts, auto-overflow, page
  naming/reordering, quick-slider pagination.
