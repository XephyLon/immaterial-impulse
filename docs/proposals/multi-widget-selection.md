# Proposal: drag-select multiple widgets to move together

> Draft / tracking proposal. Not scheduled.

## Goal

Draw a marquee on the desktop to select several widgets at once, then drag the
selection as a unit — every selected widget keeps its relative offset and they
all persist their new positions on release.

## Current state

Desktop widgets move one at a time, and the machinery is deliberately
single-widget all the way down.

`modules/imi/background/widgets/AbstractBackgroundWidget.qml` is the host every
desktop widget sits inside. It owns the drag:

```qml
draggable: placementStrategy === "free" && !Config.options.background.widgetsLocked
scale: (draggable && containsPress) ? 1.05 : 1
```

and on release it writes its own position and nothing else's. There are two
release paths, because there are two persistence backends:

- Built-ins wrote through `configEntry` (`background.widgets.<key>.x/y`). As of
  the widgets-as-plugins work there are **no built-ins left** — this path is
  vestigial.
- Plugins write through `PluginState.setPosition(manifest.id, screenName, …)`
  in `modules/common/plugins/PluginWidget.qml`, keyed per plugin *and per
  monitor*, because plugin ids and monitor names are dynamic and cannot live in
  `Config`'s fixed `JsonAdapter` schema.

Position is a plain `targetX`/`targetY` pair clamped into the screen:

```qml
function clampX(v) { return Math.max(0, Math.min(v, scaledScreenWidth - width)); }
```

Dragging assigns `x`/`y` directly and so **intentionally breaks their
bindings**; `restoreXYBinding()` puts them back on release. The clock overrides
that function because its `forceCenter` needs a different expression. Any
group-move has to respect this — a naive "set x on each selected widget" would
leave several widgets with dead bindings and no way back.

There is a global `background.widgetsLocked` toggle (the last surviving row in
`modules/common/widgets/WidgetsSubmenu.qml`), but it is all-or-nothing: there is
no per-widget lock, and no concept of a widget being *selected* at all.

The desktop itself — `modules/imi/background/Background.qml` — has no
press/drag handler of its own. Its only child is now the plugin `Repeater`. So
the marquee has somewhere to live, but nothing to build on.

## Why

- Arranging a dozen widgets one at a time is the actual cost of the plugin
  system's flexibility. Nudging a column of four to make room means four drags
  and four chances to break the alignment you had.
- The grid work (`docs/widget-grid.md`) made widgets *tile* — 132x108 cell, 12px
  gap — which makes clusters visually meaningful. A cluster you cannot move as a
  cluster is a half-finished idea.
- It is the natural home for other multi-select operations later: align, distribute,
  lock together, enable/disable as a set.

## Sketch

Rough shape, not a design:

1. **Selection state** — a set of plugin ids (or id+screen pairs) held on the
   background, not on the widgets. Widgets read "am I selected" from it.
2. **Marquee** — a `DragHandler` on `Background.qml` that draws a rubber-band
   rectangle and hit-tests widget bounds on release. Must not fight the widgets'
   own drag handlers; a press that starts *on* a widget is a widget drag, a press
   that starts on empty wallpaper is a marquee.
3. **Group drag** — dragging any selected widget moves all of them by the same
   delta. Clamping becomes a group operation: the group stops when the *first*
   member hits an edge, otherwise the cluster deforms.
4. **Persist** — one `PluginState.setPosition` per member on release. Worth
   checking whether `PluginState` should grow a batch write; today each call
   rewrites the state file.
5. **Selection affordance** — the existing `scale: 1.05` on press is the only
   current feedback. Selected-but-not-dragging needs something distinct.

## Open questions

- Does selection survive a reload, or is it session state? (Session, probably —
  but presets complicate it.)
- Do full-bleed widgets participate? The visualizer spans the whole monitor, so
  any marquee that touches it selects it. Possibly they should be unselectable,
  which overlaps with the per-widget lock idea (see the "independently lockable
  and click-through" work).
- Multi-monitor: `PluginState` keys position per screen. A marquee cannot cross
  monitors, so a selection is implicitly single-screen — worth asserting rather
  than discovering.
- Keyboard modifiers: shift-to-add, ctrl-to-toggle? The desktop has no key focus
  today.

## Prior art in-tree

`modules/imi/regionSelector/` already draws a drag rectangle over the screen for
screenshots, including `TargetRegion.qml`. Different lifecycle (it is a modal
overlay, not an in-place interaction) but the geometry and the visual treatment
are worth reading before inventing a second rubber-band.
