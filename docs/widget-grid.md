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

## Offering more than one size

A manifest may offer several spans instead of one. `cols`/`rows` stay, and become
the **default**; the spans on offer go in an optional `sizes` array:

```json
"grid": {
  "cols": 3, "rows": 2,
  "sizes": [ { "cols": 3, "rows": 2 }, { "cols": 2, "rows": 2 }, { "cols": 2, "rows": 1 } ]
}
```

The host then draws a **resize grip** in the widget's bottom-right corner, visible on
hover: dragging it previews the nearest offered span live, releasing stores it, and
Escape cancels back to the span the drag started from. None of that is the plugin's
code — a manifest opts in by declaring `sizes` and writes no QML for it.

It also draws a **Size row** in Settings > Widgets, under "Widget behaviour". The row
and the grip are two faces of one value, not two settings: both read and write
`__gridSize`, and the row's chips are spelled by `gridSizes.formatSize` so there is one
string format rather than two. The grip is what makes a resize quick; the row is what
makes it discoverable and reachable from the keyboard. The row is **omitted** — not
shown disabled — for a manifest naming a single span.

**Only declare `sizes` for a widget that has a design per size.** Most widgets have one
layout, and the host swaps the pixel size and nothing else: offering a span a widget has
no layout for is worse than offering no choice at all. `nandoroid-weather` (1x1 / 2x1 /
3x1 / 3x2), `nandoroid-currency` (1x1 / 2x1) and `nandoroid-media` (3x2 / 2x2 / 2x1) qualify
because each span is a different layout inside the widget; nothing else bundled does.

Such a widget reads the resolved span back from the host as `hostGridSize`
(`"<cols>x<rows>"`, declared as a `property string` on its `Widget.qml` root and bound
by `PluginNode`), and switches its layout on it. **The host owns which size a widget is;
the widget owns what that size looks like.** It tracks the grip's live preview, so a
drag reshapes the content as it goes rather than on release — half a resize behind the
box, which is where the swap is invisible; see [Resizing is animated](#resizing-is-animated).
A widget must not persist a size of its own alongside this — that is what `sizeMode` was,
and it is retired
(db3a7d009 ("refactor(plugins): retire sizeMode in favour of the host's __gridSize")).

The rules, all of them refusals to guess (`modules/common/plugins/gridSizes.js`,
covered by `tests/tst_grid_sizes.qml`):

- **`sizes` absent, or offering a single span, means one size and no grip.** That is
  every plugin shipping today, which is why none of them changed.
- **`cols`/`rows` must appear in `sizes`.** A default that is not on offer is a
  manifest bug, and the whole list is rejected rather than honoured — honouring it
  would resize a widget the user already placed, on upgrade, with nothing reporting
  why. One unusable entry (a zero, a fraction, an axis above 12) rejects the list the
  same way, for the same reason: repairing it silently offers a set of spans the
  author never wrote.
- **Order is the resize order**, so write them smallest-to-largest or the reverse.
- **The chosen span is per placed widget**, stored by the host as `"<cols>x<rows>"`
  under the reserved `__gridSize` key in `plugin-state.json`. A stored span the
  manifest no longer offers falls back to the default rather than being honoured.
- **`__` is the host's option-key prefix.** A manifest's `options` and the host's own
  per-plugin state are one PluginState namespace, so a manifest declaring a
  `__`-prefixed key would ship a settings control writing over host state. The
  validator rejects such a manifest and `tests/lint_plugin_option_keys.py` fails the
  suite on a bundled one.
- **The grip honours the widget's lock.** A resize changes geometry exactly as a drag
  does, so a pinned widget, a click-through one, and the global "Lock widget
  positions" each disarm it — the same resolved `interactionLocked` the bundled
  widgets' own grips read.
- **`Array.isArray(manifest.grid.sizes)` is not the test, and assuming it was made
  this whole feature inert.** A JS array reaching a delegate through a `Repeater`'s
  `model` has crossed into QVariant and back: its indices and `length` survive,
  `Array.isArray` does not. `Background.qml` builds every desktop widget from exactly
  such a model, so a manifest declaring three spans arrived at the host offering one —
  no grip, no row, no error. `gridSizes.asSizeList` accepts anything array-*like* (and
  still rejects a number, a string or a plain object, so a malformed `sizes` cannot be
  read as an empty list of spans). The reason nobody saw it: the runtime harness
  declared its synthetic manifests inline on the harness root, a path that never
  crosses a model, so it now also builds one widget through a `Repeater`.
  109e6d897 ("fix(plugins): a manifest's grid.sizes survives the model boundary").

### A layout per span

`nandoroid-weather` and `nandoroid-currency` switch on `hostGridSize` inside one file.
`nandoroid-media` has three genuinely different designs - a 3x2 with lyrics and a wavy
seek bar, a 2x2 whose album art sits inside an audio-reactive cookie, a 2x1 of three
controls whose centre button's border *is* the seek bar - so its `Widget.qml` is a shell
that loads one of `LayoutLarge.qml` / `LayoutCookie.qml` / `LayoutCompact.qml`. Four
things that costs, all of them one-time:

- **The span-to-file mapping is one table, read twice** (`media_layouts.js`): once for
  the file and once for the cell counts behind the widget's own implicit size. Two
  lookups over one table is what stops a layout being drawn at another span's pixels.
- **Anything unrecognised resolves to the default entry, never to nothing.**
  `hostGridSize` is empty until the host answers, and stays empty for a bare `qs -p`
  probe of `Widget.qml`; a span a later manifest stops offering is still sitting in
  `plugin-state.json`. A lookup returning nothing for either leaves the widget drawing
  nothing at all, which on screen is indistinguishable from a layout that failed to
  compile. That fallback must be the *manifest's* default, since that is the span the
  host will resolve in the same situation.
- **The manifest's `sizes` and the table are two lists in two files**, which is the
  drift AGENT.md's validator/renderer note describes: a span offered with no layout of
  its own does not fail, it silently draws the default layout squeezed into a box it was
  never designed for, and the grip goes on offering that size forever.
  `tests/test_media_layouts_contract.py` pins them together and
  `tests/tst_media_layouts.qml` drives the lookup itself.
- **A layout loaded by URL escapes `DesignSystemCompile`'s sweep**, which takes a bundled
  package through its `Widget.qml` only - so each layout is named in that file's explicit
  list, or it compiles for the first time on the user's desktop.

The wrapper must also answer the blur contract for whichever layout is loaded
(`blurRegions`, `managesBlurTint`), and every layout must therefore declare both: an
empty region list means "blur the whole widget", so a layout that declared neither would
frost its own shadow rather than error - at one span only.
61e2f723c ("refactor(media): move the media widget's content into LayoutLarge"),
b4113ecd6 ("feat(media): offer the media widget three spans, and pick a layout from it").

**Measure a content-sized widget before pinning it to a span.** Adopting the grid replaces
whatever the content happened to measure with exactly `spanX(cols) x spanY(rows)`, and if
those differ every placed copy resizes on upgrade with nothing reporting why. Media
measured 420x228 through a `qs -p` probe both before and after, which is exactly
`spanX(3) x spanY(2)` - the design-system widget already declared the span's pixels. Where
they do differ, adjust the layout to the span rather than picking the span that flatters
the current content.

## Resizing is animated

A span change is a **spatial move**, and the host draws it as one — there is no snap
between spans and no plugin opts into this. The tokens are `Appearance`'s expressive
spatial curves, and which one is running is decided by whether the grip is still
previewing (`modules/common/plugins/gridResize.js`, covered by
`tests/tst_grid_resize.qml`):

| what changed the span | duration | curve |
| --- | --- | --- |
| a grip drag, previewing | `elementMoveSmall` (350ms) | `expressiveFastSpatial` |
| a release, the Size row, an Escape | `elementMove` (500ms) | `expressiveDefaultSpatial` |

The split is the whole answer to "responsive or smooth": the grip previews live, so
during a drag the widget is chasing the pointer and the full curve reads as lag when a
fast drag crosses two thresholds. Everything else is a destination rather than tracking.
Escape falls out of it for free — clearing the preview is what changes the size, and by
then nothing is previewing, so the return to the span the drag started from is a move and
not a snap back.

**A `Behavior` is right here and wrong on the same widget's `x`/`y`, and the difference is
the whole trap.** A Behavior handed a target that moves every frame restarts every frame,
never ticks, and leaves the property frozen — that is how the parallax opt-out shipped
inert (AGENT.md, b710ef731 ("fix(plugins): stop the position Behavior swallowing the
parallax cancellation")). A span is discrete: it moves when the *resolved span* moves and
at no other time. The grip does re-evaluate the width binding on every mouse move — it
hands `previewGridSize` a fresh object each time — but the value that binding produces
changes only at a span boundary, and Qt does not restart a running Behavior for a write of
the value it is already animating to. Both gates on `enabled` matter from the other side:
a content-sized widget's width follows its content, which may well move every frame, and
the first span the store answers with is not a resize anybody just made.

**The content swaps at the midpoint, under a fade.** A widget offering several spans has a
design per span by construction (see above), so the content has to change identity
somewhere in the move, and both ends of it are a pop: hand the new span name down at the
start and the incoming layout is drawn inside the outgoing box for the whole animation;
hand it down at the end and the outgoing one is. So the host keeps two spans — the one the
widget *is* and the one the content is *showing* — and moves the second at the midpoint
with `PluginNode`'s opacity faded out and back in around it. `hostGridSize` is that second
one. Meanwhile the node is sized to the host's *animating* width rather than to the target
span, so the layout on either side of the swap fills the box on every frame instead of
overflowing it while the box grows.

None of that is per plugin: the host cannot know whether the widget it is holding swaps a
whole file (media) or a branch inside one (weather, currency), and a fade it did not need
is indistinguishable from the resize it sits inside.

**Everything that tracks the widget's rect keeps up on its own, because it is bound to the
animating size**: the frost surface's default region is the widget's own `width`/`height`
(and a custom `blurRegions` list belongs to content that is being stretched with the box),
and the grip is anchored to the corner. The frost costs no extra decode while it moves —
the slice is a `ShaderEffectSource` `sourceRect` over a shared cached wallpaper `Image`,
which is free to move (AGENT.md's shared-decode note) — and the surface itself is not
rebuilt, even though the region list handed to its `Repeater`'s `model` is a new array on
every frame of the resize: a replacement list of the same length reaches the delegate as a
change rather than a reset. That is Qt behaviour rather than a decision here, so the motion
harness scores the surface's identity across a resize instead of trusting it. The grip's *gesture* is measured in
scene coordinates from the press for the same reason it always was, plus one: it captures
the span being animated **to**, so pressing the grip again mid-animation does not measure
from a size the widget is leaving.

**Growing past the screen edge is the one thing the animation does not handle by itself.**
Committing a span writes plugin state, which re-evaluates the widget's persisted position,
so the existing clamp (`PluginWidget.applyPersistedPosition`) pulls it back inside — but it
runs while the widget is still the size it is *leaving*, and nothing runs again once the
animation lands. So the clamp measures the widget by
`AbstractBackgroundWidget.clampWidth`/`clampHeight`, which `PluginWidget` binds to the span
it is resizing to; the widget then slides in while it grows, in one motion, and cannot
settle outside the screen. The stored position is repaired on the same clamp, one turn of
the event loop later (the repair writes the state the handler is reading), so the store
does not keep a number the widget is no longer drawn at — 705e9006d ("fix(plugins): stop a
widget's stored position disagreeing with where it is drawn") reached from the other side.

The motion is scored by `WidgetResizeMotionRuntimeTest.qml`
(`tests/test_widget_resize_motion_runtime.py`), which samples the size 80ms and 240ms into
a change and fails if it was already at its destination. Its sibling
`WidgetResizeGripRuntimeTest.qml` deliberately reads only settled sizes, and so passes
whether the resize is animated or instant — which is why the in-flight harness exists at
all.
fa1e2a8b5 ("feat(plugins): animate a resizable widget's size between its offered spans"),
9f6cc1de7 ("feat(plugins): swap a resized widget's content at the middle of the move").

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
- **A widget offering several spans has to fill each of them.** The host swaps the pixel
  size and nothing else, so a layout that only reads well at the largest span looks
  broken at the smallest. Switch on the resolved span if the content needs to differ,
  rather than scaling one layout down.
- **The `nandoroid-*` widgets already conform.** They define this grid (media = 3x2,
  system monitor = 3x1 / 1x3). The system monitor is content-sized rather than declaring
  `grid`, but its pixel sizes are exactly on it, so new `grid` widgets tile flush beside
  it; weather (1x1 / 2x1 / 3x1 / 3x2), currency (1x1 / 2x1) and media (3x2 / 2x2 / 2x1) declare
  `grid.sizes` and take their size from the host. `clock` is exempt by decision: its shape
  places neatly without a span, so it stays content-sized behind
  `defaultWidth`/`defaultHeight`.

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

**Freely-resizable widgets are the other exception.** A widget the user resizes to *any* size
cannot declare a `grid` — the span would overwrite the dragged size on every load. (A widget
resizing between a fixed set of spans is not this case: that is what `sizes` above is for, and
the host stores the choice for it.) Such a widget omits `grid` too, keeps its own
`implicitWidth`/`implicitHeight` bound to a persisted option, and writes the new value back with
`PluginState.setOption(...)` when the drag ends. The bundled `custom-image` is the reference case:
it also stays square, which no span can be (the cell is 132x108), and its manifest sets
`defaultWidth`/`defaultHeight` to the *smallest* size the handle allows so the host's floor never
fights the user's choice.

**Omitting `grid` is not permission to hardcode pixels.** A widget that toggles or drags between
a fixed set of sizes —
still has to name each of those sizes with `Appearance.sizes.widgetGridSpanX/Y`. Skipping the
helpers costs twice: the size drifts off the lattice, and it stops following `effectiveScale`,
so it is wrong on every scaled setup even if the unscaled number happens to be right. Only a
genuinely non-span shape (square, full-bleed, or a free-drag size the user chose) may be a
literal, and `tests/test_widget_grid_lattice.py` enforces exactly that, with the exceptions
named in one place. A manifest's `defaultWidth`/`defaultHeight` floor is a size too: make it
the smallest span the widget can actually take, or the floor pins the widget off-grid no
matter what the QML says.

**Omitting `grid` also opts the widget out of the host's resize animation, so it has to bring
its own.** `PluginWidget`'s `Behavior on width`/`height` is `enabled: gridResizeAnimated`
(`gridSized && PluginState.ready`), and `boxInMotion` compares the drawn box with
`settledWidth`/`settledHeight` — which for a content-sized widget *are* the widget's current
width and height, so it never reports motion. A `grid`-less widget that changes size therefore
snapped between its modes, and its card kept a live drop shadow through the change, until each
of them animated its own implicit size towards the settled span and published its own
`boxInMotion`:

```qml
readonly property real spanW: root.spanWidthOf(root.sizeMode)   // the settled span
property real widgetWidth: root.spanW                            // the box travelling to it
Behavior on widgetWidth { Expressive.SpanTravel {} }
readonly property bool boxInMotion: Math.abs(root.widgetWidth - root.spanW) > 0.5 || ...
implicitWidth: root.widgetWidth
```

The split matters beyond the animation: everything a one-tree widget places reads the **settled**
span and never the travelling box, or the Behaviors carrying each element chase a target that
moves every frame and never converge
(`test_geometry_rects_come_from_the_settled_span_not_the_animating_box`).

**A widget-owned `sizeMode` is not the same thing as the retired manifest option, and a
migration keyed on the name alone destroys it.** `world-clock` and `calendar` declared no
`grid` and drove a `sizeMode` of their own from their own toggles, so for them the key was
a live setting; weather and currency declared one as a manifest *option*, which is what
`__gridSize` took over. Both of the first camp have since crossed to the second — the manifest
grew `grid.sizes`, and the same gate that once protected their options is what folds them in.
The `sizeMode` → `__gridSize` migration therefore acts only where
the manifest offers more than one span — measured against a real shell, a pass keyed on
the key name emptied world-clock's and calendar's options and reset both widgets, which is
the migration's own failure mode aimed at the wrong widgets. The migration maps the stored
value onto `__gridSize` (dropping a mode the manifest does not offer, exactly as
`resolveSize` refuses a stored span no longer on offer), deletes the old key so it is
idempotent on its own, and runs whenever any multi-span manifest still has a `sizeMode`
stored — the data is the gate, not the `migrations.migratedSizeMode` marker (which is still
written, as a record): the marker gated it once, and stranded calendar's and world-clock's
options when they adopted `grid.sizes` after the first wave had burned it. It is driven by
`PluginManager` on a settle timer rather than fired on the first non-empty manifest list,
because a marker records that a pass *ran*, not that it saw anything, and manifests load
one FileView at a time.
db3a7d009 ("refactor(plugins): retire sizeMode in favour of the host's __gridSize").

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
