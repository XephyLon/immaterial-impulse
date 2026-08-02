# Desktop widget component grid

The **component grid** is the design standard for sizing desktop-widget plugins so they
tile cleanly in a bento layout with even gutters. It replaces ad-hoc pixel sizes with a
declarative cell/gap span a plugin states in its manifest.

The grid is not new: it is the same grid the bundled `nandoroid-*` design-system widgets
already use (the system-monitor's "Choice A" grid). Formalizing it as tokens lets new
plugins line up with those widgets instead of guessing pixel sizes.

> **The cell is 132 wide by 108 tall — the row is not 120.** A widget that is 120 or 252
> tall is on no span at all, however round the number looks. Both figures are multiples of
> 12, which is *not* the test (see [Position snapping](#position-snapping)); the test is
> whether the number comes out of `widgetGridSpanY(rows)`. One row is **108**, two rows are
> **228**. Two independent widget ports got this wrong by assuming a 120px cell, so if you
> are about to write a pixel height, write `Appearance.sizes.widgetGridSpanY(n)` instead.

## The grid model

A widget occupies a whole number of **cells** in each axis. Between adjacent cells sits one
**gap**. Cells are **not square** — they are wider than tall — so the two axes have separate
spans:

```
spanX(cols) = (cols * cellWidth  + (cols - 1) * gap) * effectiveScale
spanY(rows) = (rows * cellHeight + (rows - 1) * gap) * effectiveScale
```

The tokens live in `Appearance.sizes` (`modules/common/Appearance.qml`):

| Token | Value | Meaning |
| --- | --- | --- |
| `widgetGridCellWidth` | `132` | one cell wide, in px |
| `widgetGridCellHeight` | `108` | one cell tall, in px |
| `widgetGridGap` | `12` | gutter between cells, in px |
| `widgetGridSpanX(cols)` | function | horizontal span, scaled |
| `widgetGridSpanY(rows)` | function | vertical span, scaled |

Both helpers multiply by `Appearance.effectiveScale`, matching how the `nandoroid-*` widgets
scale (`132 * Appearance.effectiveScale`, etc.). Reference the helpers rather than hardcoding
pixels:

```qml
implicitWidth:  Appearance.sizes.widgetGridSpanX(2)   // 276
implicitHeight: Appearance.sizes.widgetGridSpanY(2)   // 228
```

### span -> pixels (at scale 1.0)

| cells | spanX px | spanY px |
| --- | --- | --- |
| 1 | 132 | 108 |
| 2 | 276 | 228 |
| 3 | 420 | 348 |
| 4 | 564 | 468 |

A `cols` x `rows` tile is `spanX(cols)` wide by `spanY(rows)` tall. Worked examples, with the
matching bundled widget:

| grid | pixels (w x h) | bundled reference |
| --- | --- | --- |
| `{ "cols": 1, "rows": 1 }` | 132 x 108 | currency (1x1) |
| `{ "cols": 2, "rows": 1 }` | 276 x 108 | currency (2x1) |
| `{ "cols": 3, "rows": 1 }` | 420 x 108 | system monitor (horizontal) |
| `{ "cols": 1, "rows": 3 }` | 132 x 348 | system monitor (vertical) |
| `{ "cols": 3, "rows": 2 }` | 420 x 228 | media |
| `{ "cols": 2, "rows": 2 }` | 276 x 228 | notes |

## Declaring a size

A desktop-widget plugin declares its span with a top-level, optional `grid` field in
`manifest.json`:

```json
{
  "id": "notes",
  "name": "Notes",
  "grid": { "cols": 2, "rows": 2 },
  "desktopWidget": { "component": "Widget.qml" }
}
```

- `cols` and `rows` are optional integers, each defaulting to `1`, in the range `1..12`.
- The plugin validator rejects non-integer, zero/negative, out-of-range, or non-object `grid`
  values (`PluginValidator.js`; covered by `tests/tst_plugin_validator.qml`).
- When `grid` is present, the host (`PluginWidget.qml`) sets the widget's pixel size to
  `spanX(cols) x spanY(rows)`, overriding content sizing, and stretches the loaded
  `Widget.qml` to fill it. When `grid` is absent, the widget keeps the legacy content-sized
  behaviour (its own implicit size).

## Position snapping

Grid widgets use the **same fine 12px drag snap** every desktop widget uses (`AbstractWidget`,
`gridSize: 12`) — there is no special coarse snap. That matters because a coarse per-cell snap
would let a widget only land on a sparse lattice and jump in big steps, making it impossible to
place where you want.

Flush tiling still works because every span is a whole multiple of 12: the cell is `132`
(`11×12`) by `108` (`9×12`), the gap is `12`, so a 2×2 tile is `276×228` (`23×12` by `19×12`).
Place a grid widget one 12px step away from its neighbour and the gutters line up exactly. This
keeps grid widgets and the content-sized `nandoroid-*` widgets on one shared lattice.

**Being a multiple of 12 is necessary, not sufficient.** The 12px snap only decides where a
widget can be *dropped*; it says nothing about whether its *size* matches its neighbours. A
252-tall widget snaps to the same positions as a 228-tall one and still refuses to line up
with it — its bottom edge lands 24px past every other tile's, on every row, forever. Read
"whole 12px step" as a property every span happens to have, never as a test a size can pass.
The only test is `size === widgetGridSpanX(cols)` / `widgetGridSpanY(rows)`.

## Guidance for authors

- **Design content to fill its declared span.** The `Widget.qml` root should `anchors.fill:
  parent` (or bind width/height to the host) rather than hardcoding pixels, so it always
  matches the grid size. Keep `implicitWidth: widgetGridSpanX(cols)` /
  `implicitHeight: widgetGridSpanY(rows)` only as a standalone fallback.
- **Prefer whole spans.** Pick the smallest `cols` x `rows` that fits your content at the
  cell/gap rhythm; do not fight the grid with fractional or off-rhythm sizes.
- **Cells are wider than tall.** A "2x2" tile is 276x228, not a square. Size for the real
  cell aspect rather than assuming equal width and height.
- **The `nandoroid-*` widgets already conform.** They define this grid (media = 3x2,
  system monitor = 3x1 / 1x3, currency = 1x1 / 2x1 via their internal `sizeMode`). They are
  content-sized rather than declaring `grid`, but their pixel sizes are exactly on it, so new
  `grid` widgets tile flush beside them. `clock` is exempt by decision: its shape places neatly
  without a span, so it stays content-sized behind `defaultWidth`/`defaultHeight`.

## Widgets that cannot use the grid

The grid caps at 12 columns, which is `spanX(12) = 1716px` — barely a third of a 5120px display.
A widget that must be **full-bleed** (screen-wide) therefore cannot express itself through `grid`
at all. Such a widget omits `grid` entirely, takes the host's content sizing, and binds its own
`implicitWidth` to its monitor:

```qml
property string screenName: ""   // bound by the host, see PLUGINS.md
readonly property var widgetScreen: Quickshell.screens.find(s => s.name === root.screenName) ?? null
implicitWidth: widgetScreen ? widgetScreen.width : Screen.width
```

The manifest's `defaultWidth`/`defaultHeight` then act only as a floor (the host takes
`Math.max(defaultWidth, content width)`). The bundled `visualizer` is the reference case.

**User-resizable widgets are the other exception.** A `grid` span is a fixed pixel size the host
assigns, so a widget the user resizes with a drag handle cannot declare one — the span would
overwrite the dragged size on every load. Such a widget omits `grid` too, keeps its own
`implicitWidth`/`implicitHeight` bound to a persisted option, and writes the new value back with
`PluginState.setOption(...)` when the drag ends. The bundled `custom-image` is the reference case:
it also stays square, which no span can be (the cell is 132x108), and its manifest sets
`defaultWidth`/`defaultHeight` to the *smallest* size the handle allows so the host's floor never
fights the user's choice.

**Omitting `grid` is not permission to hardcode pixels.** A widget that toggles or drags between
a fixed set of sizes — the bundled `world-clock` (2x2 / 3x1) and `calendar` (1x1 / 2x1 / 2x2) —
still has to name each of those sizes with `Appearance.sizes.widgetGridSpanX/Y`. Skipping the
helpers costs twice: the size drifts off the lattice, and it stops following `effectiveScale`,
so it is wrong on every scaled setup even if the unscaled number happens to be right. Only a
genuinely non-span shape (square, full-bleed, or a free-drag size the user chose) may be a
literal, and `tests/test_widget_grid_lattice.py` enforces exactly that, with the exceptions
named in one place. A manifest's `defaultWidth`/`defaultHeight` floor is a size too: make it
the smallest span the widget can actually take, or the floor pins the widget off-grid no
matter what the QML says.

**Name a size mode after the shape it really is.** `world-clock`'s wide mode was called `"4x1"`
while being 420px — which is `spanX(3)`, three columns — and `calendar`'s was `"1x2"` while
being two columns by one row. The name is persisted state, so renaming it strands whatever is
already on disk: normalise the value on read (`normalizeSizeMode`) so a legacy string maps onto
the mode it described, rather than falling through to a default or matching no branch at all.

Either way, a widget that omits `grid` must **not** `anchors.fill: parent`. The host derives its
own size from the widget's implicit size in that mode, so filling the parent is a binding loop —
`PluginNode.qml` leaves the `Loader` unanchored precisely to avoid it.

**Full-bleed is not anchoring.** The host has no edge-anchor or non-draggable mode: a full-bleed
widget is still draggable and still gets the generic `x: 100, y: 100` default position on first
enable, so it lands near the *top* rather than pinned to the bottom edge the way a hardcoded
built-in could be. Horizontal drift self-corrects — `PluginWidget.applyPersistedPosition()` clamps
x into `[0, screenWidth - width]`, which is `[0, 0]` for a full-bleed widget — but only on the next
load; within a session the widget stays wherever it was dragged, including partly off-screen.
