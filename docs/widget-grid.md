# Desktop widget component grid

The **component grid** is the design standard for sizing desktop-widget plugins so they
tile cleanly in a bento layout with even gutters. It replaces ad-hoc pixel sizes with a
declarative cell/gap span a plugin states in its manifest.

The grid is not new: it is the same grid the built-in `nandoroid-*` design-system widgets
already use (the system-monitor's "Choice A" grid). Formalizing it as tokens lets new
plugins line up with those widgets instead of guessing pixel sizes.

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
matching built-in widget:

| grid | pixels (w x h) | built-in reference |
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
  `grid` widgets tile flush beside them. `clock` predates the grid and is left content-sized.

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

Either way, a widget that omits `grid` must **not** `anchors.fill: parent`. The host derives its
own size from the widget's implicit size in that mode, so filling the parent is a binding loop —
`PluginNode.qml` leaves the `Loader` unanchored precisely to avoid it.

**Full-bleed is not anchoring.** The host has no edge-anchor or non-draggable mode: a full-bleed
widget is still draggable and still gets the generic `x: 100, y: 100` default position on first
enable, so it lands near the *top* rather than pinned to the bottom edge the way a hardcoded
built-in could be. Horizontal drift self-corrects — `PluginWidget.applyPersistedPosition()` clamps
x into `[0, screenWidth - width]`, which is `[0, 0]` for a full-bleed widget — but only on the next
load; within a session the widget stays wherever it was dragged, including partly off-screen.
