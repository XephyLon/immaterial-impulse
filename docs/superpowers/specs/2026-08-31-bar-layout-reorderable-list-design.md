# Bar Layout Reorderable List — Design

**Date:** 2026-08-31
**Status:** Approved (brainstorm 2026-08-31; modelled on p3drovfx's ConfigListView/ConfigListViewEntry, rebuilt on imi tokens and machinery)

## Problem

Settings > Bar & Dock > "Bar layout" is three chip Flows (`LayoutSection`)
with a `+` FAB and a chip dropdown - dense, unlabeled, visually flat
("This is ugly"). The fork configures the same lists as a draggable grouped
LIST: one row per widget with a drag handle, icon, name and actions, M3E
motion throughout. Reproduce that grammar on imi's tokens; the fork's own
numbers are hand-typed and do not transfer.

## Decisions

1. **Rows, not chips.** Each bar widget is a 48-ish px grouped row.
2. **Cross-group drag.** A row drags between Left/Center/Right, not only
   within its group.
3. **Add flow:** a dropdown of available widgets + a filled Add button at
   each group's foot (fork grammar), replacing the `+` FAB chip dropdown.
4. **Dumb component first**, then the Bar layout section consumes it.

## The dumb component: `modules/common/widgets/ReorderableList.qml`

Presentational only - `lint_dumb_widgets.py` applies in full: no
`Config.options`, no service singletons, no `GlobalStates`, no processes.

**API:**
- `model: list<var>` - opaque entries (the bar hands plain string ids).
- `property var rowFor: (entry) => ({ icon, title })` - caller resolves
  catalogue lookups.
- `property var available: []` - `{ id, name, icon }` entries for the add
  dropdown (empty list disables the add row).
- `property string addButtonText`
- Signals: `addRequested(var id)`, `removeRequested(int index)`,
  `moveRequested(int from, int to)` (same-list reorder),
  plus the cross-list drag protocol below. The component commits NOTHING;
  the caller owns the store.

**Row grammar** (GroupedList's plate vocabulary, not a copy of the fork's
hand-typed numbers):
- Plates on `colLayer1`, first/last row big radius
  (`Appearance.rounding.normal`), inner rows `unsharpenmore`, corners
  re-rounding live as rows move - the same first/last-on-screen rule
  GroupedList documents.
- Row content: `drag_indicator` handle glyph (colOutline), catalogue icon
  (colPrimary), title (StyledText), spacer, trailing close RippleButton.
  Spacing/padding from `Appearance.spacing.*` only.
- Add row at the foot: dropdown + filled Add button in
  `colSecondaryContainer`. The dropdown reuses an existing imi selector
  widget; if none fits, a minimal one is built beside this component
  (verify-before-trust point for the plan - the fork's `StyledComboBox`
  does not exist here).

**Motion:**
- Press-and-hold ~200 ms on the handle lifts the row: scale ~1.02, opacity
  ~0.85, closed-hand cursor; before the hold it is a plain row (the close
  button still clicks).
- The lifted row follows the pointer; the SIBLINGS PART LIVE - rows are
  explicitly positioned with animated `y` (the quick-toggle grid's
  settled-slot technique), so the insertion gap opens where the row would
  land. No bare indicator line.
- Release travels the row into its slot and emits the move; a cancel
  (Escape / the gesture's cancel path) springs every row back and commits
  nothing - the ReorderDragArea cancel-not-commit rule.

## Cross-group coordination (BarConfig's, not the component's)

- Each `ReorderableList` exposes `rowRects()` (scene-space centres with the
  dragged row as a hole) and an `anchor` point for when it is empty - the
  exact bucket shape `layout_ops.dropTarget` takes.
- The Bar layout section in `modules/imi/settings/pages/BarConfig.qml`
  wires three lists (Left/Top, Center, Right/Bottom titles follow
  `Config.options.bar.vertical` as today) into one drag space: while a row
  from any list is lifted, the coordinator resolves
  `layout_ops.dropTarget(buckets, pointer, "y")` per move, tells each list
  where the gap sits (so a foreign list parts too), and on drop commits:
  same bucket via `layout_ops.move`, cross bucket via `layout_ops.remove` +
  `layout_ops.insert`. All writes go through `layout_ops` and land on
  `Config.options.bar.layouts.{left,middle,right}Layout` as NEW arrays
  (the stored lists stay `list<string>`; no schema change).
- `availableFor()` / `BarWidgets.offerFor` / `nameFor` stay the one
  catalogue and offer policy; the add dropdowns share one available list.
- `LayoutSection.qml` loses its only consumer and is deleted with the
  rewiring commit (grep first; if another consumer appeared, it stays and
  only this page moves off it).

## Error handling

- An id the catalogue no longer knows renders with a fallback icon and the
  raw id as title, and can still be removed or dragged - a stale config
  must stay editable.
- A drop outside every bucket cancels (no commit), same as Escape.
- Empty group: keeps its add row and a one-row-high drop zone so it can be
  dragged back into.

## Testing

- `layout_ops` arithmetic is already pinned (`tst_layout_ops.qml`),
  including `dropTarget` buckets/anchors - no new arithmetic is added.
- `lint_dumb_widgets.py` automatically holds `ReorderableList` to the
  presentational rule (new file in the scanned folder).
- New structural pins (python): the Bar layout section commits only through
  `layout_ops`; `ReorderableList` never names `Config` (belt beside the
  lint's braces); `LayoutSection` is gone or unconsumed.
- Named tests only; the suite stays parked. Visual pass by the maintainer.

## Out of scope

- Fork extras: per-row inline style pickers, per-widget settings/page
  buttons, `centered`/`visible` per-entry state (imi entries are plain
  ids), performance-mode switches. The dock strip and Edit Mode drawer keep
  their own editors.
