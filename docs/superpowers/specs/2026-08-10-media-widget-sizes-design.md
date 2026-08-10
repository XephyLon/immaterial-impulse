# Media widget sizes, and a resize handle for every grid widget — design

**Status:** design, not implemented
**Scope:** `modules/common/plugins/` (grid machinery, shapes), the bundled
`nandoroid-media` widget, `docs/widget-grid.md`

Paths are relative to the theme root `dots/.config/quickshell/imi/` unless written repo-relative.

## Problem

The desktop media widget has exactly one size. A widget's span comes from its manifest
(`grid: {cols, rows}`, see `docs/widget-grid.md`), which is a constant — so no placed widget can be
resized, and the media widget does not even declare a grid: it is content-sized, and its "3x2" is
whatever its content happens to measure.

The ask is three sizes for media — the existing large one, a 2x2, and a 2x1 — chosen by dragging a
resize handle. Sizes selectable per placed widget is machinery that does not exist, and it is not
media-specific: `notes`, `user-card` and `image-converter` all declare grids and all have the same
one-size limitation.

## Settled input (do not relitigate)

- **Per-lobe visualizer.** Each cookie lobe is driven by its own frequency band, so the shape
  ripples asymmetrically. Not a uniform pulse.
- **The handle is generic** — it lives in `PluginWidget`, so any grid widget that declares more than
  one span gets it.
- **2x2 is cookie-as-artwork**: album art inside the cookie, visualizer lobes around it, title and
  artist below.
- **2x1 is exactly the reference**: prev, cookie-shaped play/pause, next. No text and no artwork —
  but progress *is* shown, stroked around the centre button's own outline rather than as a separate
  track. See §5.

---

## 1. Declaring more than one size

`manifest.grid` gains an optional `sizes` array. The existing `cols`/`rows` stay and become the
default — every current manifest keeps working untouched, which matters because three plugins
already ship one.

```json
"grid": {
  "cols": 3, "rows": 2,
  "sizes": [ { "cols": 3, "rows": 2 }, { "cols": 2, "rows": 2 }, { "cols": 2, "rows": 1 } ]
}
```

Rules:

- `sizes` absent, or holding fewer than two entries → the widget has one size and **shows no
  handle**. This is every existing plugin.
- `cols`/`rows` must appear in `sizes` when `sizes` is present. A default that is not an offered
  size is a manifest bug and the parser rejects the `sizes` list rather than silently resizing
  someone's widget on upgrade.
- Order is the resize order. Dragging moves along this list, so it should read smallest to largest
  or the reverse, not arbitrary.

## 2. Remembering the choice

`PluginState.option(pluginId, key, fallback)` already stores per-plugin values and is written
through `setOption`. The chosen span is one more option under a reserved key, `__gridSize`, stored
as `"<cols>x<rows>"`.

Reserved because plugin options come from the manifest's own `options` array and are surfaced in
settings; this one is host state, not a plugin setting, and must not appear as a toggle. The double
underscore marks it as the host's, and a lint keeps manifests from declaring an option key starting
with `__`.

Resolution order, in `PluginWidget`:

1. `PluginState.option(id, "__gridSize")`, if it parses and is present in `sizes`
2. `manifest.grid.cols/rows`
3. content-sized (the legacy path, unchanged)

A stored size that is no longer offered — the manifest changed under an installed widget — falls
back to the manifest default rather than being honoured. Silently keeping a span the plugin no
longer supports is how a widget ends up laying out into a size its content cannot fill.

## 3. The handle

A grip in the widget's bottom-right corner, visible on hover and while dragging, only when the
widget offers more than one size.

- **Drag** updates a *preview* span live: the nearest offered size to the pointer's current
  distance, measured against `widgetGridSpanX/Y`. The widget resizes as you drag, so the size you
  see is the size you get.
- **Release** commits via `setOption`. **Escape** cancels back to the size at drag start.
- The widget's position is unchanged; it grows right and down from its top-left, which is where the
  drag started. A widget resized past the screen edge is clamped by the existing position
  clamping — no new rule.

`AbstractWidget` already owns drag-to-move with a 12px snap. The resize handle must claim the press
before the move handler sees it, or dragging the corner walks the widget instead of resizing it.

**This is the part with no test coverage.** Nothing about pointer grabs is reachable from
`qmltestrunner`; the *snapping arithmetic* is pure and is extracted so it can be, see §6.

## 4. A cookie whose lobes move independently

`MaterialCookie` builds `RoundedPolygon.star(sides, radius, innerRadius, rounding)` where
`innerRadius` is one scalar for the whole shape. Every lobe is therefore identical, and no amount
of animating that scalar produces a per-band visualizer — it only breathes.

So `shapes/rounded-polygon.js` gains a variant taking **an array of inner radii**, one per lobe,
falling back to the scalar behaviour when handed a number. The existing `star()` keeps its
signature; this is a sibling, not a change to it.

A new `widgets/VisualizerCookie.qml` wraps it:

| Property | Meaning |
| --- | --- |
| `lobes` | how many lobes, default 12 |
| `levels` | `list<real>` 0..1, one per lobe |
| `baseRadius` | lobe radius at silence (the resting cookie) |
| `reach` | how far a full-level lobe pushes out |

**Bands to lobes.** `CavaService` produces `barCount: 32` and is shared through a refcount, so it is
not reconfigured to 12 — that would change every other visualizer on screen. The widget aggregates:
32 bands fold to 12 lobes by averaging contiguous groups, so lobe 0 is bass and lobe 11 is treble,
travelling around the shape.

**Motion.** Raw cava values jitter at frame rate and would make the outline boil. Each lobe carries
an attack/decay envelope — fast attack so a beat reads immediately, slower decay so the shape
settles rather than flickering. Constants live beside the component, not in `Appearance`: they are
signal smoothing, not design tokens.

**Cost.** The shape is rebuilt per frame while audio plays. `ShapeCanvas` rebuilds already happen
for the cookie clock's rotation, but that animates a transform rather than regenerating geometry.
If per-frame regeneration measures badly, the fallback is to rebuild at a fixed rate (say 30Hz) and
interpolate — decided by measurement, not upfront.

## 5. The three layouts

`nandoroid-media/Widget.qml` becomes a switch on the resolved span, loading one of three layouts.
The existing content moves to `LayoutLarge.qml` unchanged, so the current widget is not a rewrite.

- **3x2 `LayoutLarge.qml`** — today's widget, moved. Adopting the grid pins it to
  `spanX(3) x spanY(2)` = 420x228, where today it is content-sized. **If its natural size is not
  already that, this is a visible change on upgrade** and is the one migration risk here; measure
  before committing to it, and if it differs, the honest fix is to adjust the layout to the span
  rather than to pick a span that flatters the current content.
- **2x2 `LayoutCookie.qml`** — 276x228. `VisualizerCookie` with album art clipped inside it, title
  and artist beneath. Tap the cookie to play/pause.
- **2x1 `LayoutCompact.qml`** — 276x108. Prev pill, cookie-shaped play/pause, next pill, centred.

  **The centre button's border is the seek bar.** Playback progress is stroked around the cookie's
  own outline rather than drawn as a separate track, which is what makes this layout read as one
  object instead of three controls with a line under them. There is still no text and no artwork.

  That changes what the shape has to support. A cookie outline is a run of cubic Beziers, so a
  partial stroke needs the path's arc length: sample the cubics once per geometry change to get the
  cumulative length, then stroke with `setLineDash([progress * total, total])`. Length only has to
  be recomputed when the shape changes, which for a static cookie is once.

  The cookie here is a static `MaterialCookie`-shaped path, not the visualizer — at this size a
  rippling outline would fight the progress it is also carrying, and the two would be
  indistinguishable. Both nonetheless stroke a rounded polygon, so the arc-length helper belongs
  beside `rounded-polygon.js` where `VisualizerCookie` can reach it if a future layout wants both.

All three read the same media state, so no new service work.

## 6. Testing

Honest about what is reachable. `qmltestrunner` cannot construct Quickshell types, and nothing about
pointer grabs, shapes or layout is testable here.

**Testable, and therefore extracted deliberately:**

- `gridSizes.js` — parsing `manifest.grid`, validating that the default appears in `sizes`,
  resolving stored → default → content-sized, and rejecting a stored size no longer offered. Pure
  functions over plain objects; a QML `TestCase` drives them.
- The nearest-size snap: given a pointer delta and a list of spans, which span wins. Pure.
- Band aggregation: 32 values to 12 lobes, including the short-array and empty cases that happen
  before cava has produced anything.
- A lint that no manifest declares an option key beginning with `__`.

**Not testable, needs the screen:** the handle claiming the press before drag-to-move, the cookie's
motion, and all three layouts.

## 7. Landing plan

Each step is a commit that leaves the tree working.

1. `gridSizes.js` + its tests. No caller yet.
2. `PluginWidget` resolves a stored size through it. No handle; behaviour unchanged for every
   existing plugin, which is the point at which "nothing regressed" is checkable.
3. The resize handle, gated on more than one offered size.
4. `rounded-polygon.js` per-lobe variant + `VisualizerCookie.qml`, with a static `levels` array. No
   audio yet.
5. Cava aggregation and the envelope.
6. Media manifest declares its three sizes; existing content moves to `LayoutLarge.qml` untouched.
7. `LayoutCookie.qml` (2x2).
8. `LayoutCompact.qml` (2x1).
9. `docs/widget-grid.md` gains the `sizes` contract; AGENT.md gains whatever the implementation
   turns up.

Steps 1-3 are the generic machinery and are worth reviewing before 4-8 exist, since they are what
every other widget inherits.
