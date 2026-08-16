# Widget standards audit — 2026-08-16

Static audit of the shell's two widget populations against the eight design standards the project
has adopted. **No shell was run**: everything here is read out of the source, and every claim that
is an inference rather than a reading is marked *inferred*.

Populations:

- `modules/common/plugins/designsystem/widgets/**` — 97 `.qml` files
- `modules/common/plugins/bundled/*/**` — 41 `.qml` files across 14 packages

Paths below are relative to the theme root `dots/.config/quickshell/imi/`.

---

## 0. The finding that reframes the rest: most of the design system is not on screen

Before scoring anything it is worth knowing which files the shell actually builds, because a
standards gap in a file nothing instantiates has no user-visible symptom and belongs in a different
bucket from one in a file that is on the desktop right now.

`modules/common/plugins/designsystem/widgets/` has its own `qmldir`
(`module qs.modules.common.plugins.designsystem.widgets`), so nothing reaches into it implicitly.
Exactly **twelve** files in the shell import it, all with an `as Expressive` prefix:

```
bundled/calendar/Widget.qml              bundled/nandoroid-media/MediaSeeker.qml
bundled/clock/CookieClock.qml            bundled/nandoroid-media/MediaTransportButton.qml
bundled/clock/PixelClock.qml             bundled/nandoroid-system-monitor/Widget.qml
bundled/custom-image/Widget.qml          bundled/nandoroid-weather/Widget.qml
bundled/nandoroid-currency/Widget.qml    bundled/user-card/Widget.qml
bundled/nandoroid-media/Widget.qml       bundled/world-clock/Widget.qml
                                         modules/imi/regionSelector/Magnifier.qml
```

Sweeping every `Expressive.<Type>` reference in the tree yields eleven type names, and closing that
set transitively over the design system's own directory imports gives **17 live files**:

```
DesktopCurrencyWidget  DesktopMediaWidget  DesktopSystemMonitorWidget  DesktopWeatherWidget
WidgetCard  WidgetElevation  SpanTravel  SpanFade
MaterialShape  MaterialSymbol  StyledText  StyledSlider  StyledToolTip  StyledToolTipContent
CustomIcon  WavyLine  shapes/ShapeCanvas
```

The other **80** are vendored library code from `na-ive/nandoroid-shell` (see
`designsystem/ComponentRegistry.qml`, which is a catalogue and an attribution record, not an
instantiation surface — nothing reads its `categories`). Among them: `NandoClock.qml`,
`CavaWidget.qml`, `AtAGlance.qml`, `MediaCard.qml`, `DesktopContextMenu.qml` (which has *no*
reference anywhere in the tree, and is the only user of `DesktopWidgetsSubmenu.qml`),
`AccentPicker`, `SegmentedButton`, `DatePicker`, `NetworkSpeedMeter`, `PrivacyIndicator`,
`RecordIndicator`, `UserProfile`, all 19 files under `clock/`, and `widgetCanvas/` — a dead
duplicate of the live `modules/common/widgets/widgetCanvas/`.

**Thirty-nine file names collide between `modules/common/widgets/` and
`designsystem/widgets/`, and every one of the 39 pairs differs.** `StyledText.qml` is 96 lines in
one and 29 in the other; `StyledFlickable.qml` 215 vs 54; `MaterialShape.qml` 88 vs 200. This is
the failure AGENT.md names under *State propagation is reactive* — "two names for one thing let one
of them rot silently, and the one that rots is whichever is not on screen" (`ce41c4f9c`) — at a
scale of 39. It has already produced one confident-wrong conclusion during this audit: the
subagent that swept the design system nominated `ClippedProgressBar.qml`'s `AnchorChanges` as the
top fix "live in the bar", but `modules/imi/bar/BatteryIndicator.qml` imports
`qs.modules.common.widgets`, so it builds the *mainline* copy. The design-system copy is dead.

Nothing about this is a standards violation, and none of it is proposed for deletion here — the
vendored tree is attributed AGPL-3.0 source and `test_complete_widget_source_is_present` pins its
size deliberately. It is stated first so the rest of the report can be read correctly: **every gap
below is in a file the shell builds**, and design-system findings in the other 80 are listed
separately at the end as latent.

---

## 1. The table

`✓` = the standard applies and is met. `✗` = applies and is not met (numbered gap).
`—` = does not apply, with the reason in the last column.

| Widget | 1 morph | 2 span | 3 card/elev | 4 motion | 5 anchors | 6 two-way | 7 cursor | 8 popup | Not applicable, why |
|---|---|---|---|---|---|---|---|---|---|
| `nandoroid-weather` (+ `DesktopWeatherWidget`) | ✓ | ✓ | ✓ | — | ✓ | ✓ | — | — | 4/7: no controls of its own. 8: no Controls popup |
| `nandoroid-currency` (+ `DesktopCurrencyWidget`) | ✓ | ✓ | ✓ | ✓ | ✓ | **✗ G1** | ✓ | — | 8: no Controls popup |
| `nandoroid-media` (+ `MediaSeeker`, `MediaTransportButton`) | ✓ | ✓ | ✓ | **✗ G11** | ✓ | ✓ | ✓ | — | 8: no Controls popup |
| `nandoroid-system-monitor` | — | — | ✓ | ✓ | ✓ | ✓ | ✓ | — | 1/2: one size; the turn is `Grid.columns`, not a span |
| `calendar` | **✗ G3** | — | ✓ | **✗ G9** | ✓ | ✓ (documented trade) | ✓ | — | 2: no span; sizes are its own |
| `world-clock` | **✗ G3** | — | ✓ | **✗ G9** | ✓ | ✓ | ✓ | ✓ | 2: no span |
| `notes` | — | — | **✗ G2** | **✗ G10** | ✓ | ✓ | ✓ | — | 1/2: one fixed 2×2 span |
| `image-converter` | — | — | **✗ G2** | — | ✓ | ✓ | — | ✓ | 4: only shared controls. 7: no `MouseArea`, a `DropArea` takes no clicks |
| `custom-image` | — | — | ✓ | **✗ G5** | ✓ | ✓ (documented trade) | ✓ | — | 1/2: one size, freely scaled |
| `user-card` | — | — | ✓ | **✗ G9** | ✓ | ✓ | ✓ | — | 1/2: one size. 3 met via `WidgetElevation` (documented three-surface exemption) |
| `clock` (+ `CookieClock`, `PixelClock`, `CookieQuote`, hands/marks/date) | — | — | **✗ G6** | — | ✓ | ✓ | — | — | 1/2: styles, not spans. 4/7: no controls |
| `visualizer` | — | — | — | — | ✓ | ✓ | — | — | 3: ambient graphic, `blurRegions: []`, no body to card or shadow |
| `discordVoice` (bar + overlay) | — | — | — | **✗ G4** | ✓ | ✓ | ✓ | ✓ | 3: overlay panel, not a desktop card. 1/2: not a desktop widget |
| `docker` (bar) | — | — | — | — | ✓ | ✓ | ✓ | ✓ | 3: bar item. 4: `hoverEnabled: false` deliberately (`DockerWidget.qml:26-29`) |

Live design-system files not covered above (`WidgetCard`, `WidgetElevation`, `SpanTravel`,
`SpanFade`, `MaterialShape`, `MaterialSymbol`, `StyledText`, `StyledSlider`, `StyledToolTip`,
`StyledToolTipContent`, `CustomIcon`, `WavyLine`, `shapes/ShapeCanvas`) are primitives and the
standards themselves; none of the eight reaches them except 8, covered in §3.

---

## 2. Real gaps

### G1 — currency's quote cells feed the fallback that feeds them (standard 6)

`designsystem/widgets/DesktopCurrencyWidget.qml:355`, with `:363-366`:

```qml
readonly property var lastSlot: slot ?? ({ x: x, y: y, width: width, height: height, stacked: true })
x: lastSlot.x
y: lastSlot.y
width: lastSlot.width
height: lastSlot.height
```

`lastSlot` reads `x`/`y`/`width`/`height`; those four are bound to `lastSlot.*`. The fallback branch
is reachable — `currency_geometry.js:50-51` returns `null` for `index >= 2` at the `1x1` span, which
is quote cells 3 and 4.

The same file already documents this exact loop being found and fixed, fifty lines above, for the
`basePrefix` element (`:288-302`):

> `slot ?? ({ ..., size: font.pixelSize })` looks like the same thing, but while the slot is null
> the fallback reads the very property it feeds — QML reported the loop on `font.pixelSize`.

The fix there was to hold the last settled values in plain unbound `heldX`/`heldY`/`heldSize`
properties written from `onSlotChanged`. It was not applied to the sibling with the identical shape.

**Symptom:** `Binding loop detected for property "x"` in `log.log` every time the widget settles at
1x1, and the two cells that have no home at 1x1 fade out from wherever Qt last managed to write
rather than from where they stood. Low amplitude on screen — the cells are `opacity: 0` by the end —
but it is a live binding loop on a widget that is on the desktop.

**Size of fix:** small, ~10 lines, and the pattern is already in the file.

*A subagent sweep called this "survivable because `quoteCellRect` apparently never returns null,
inferred". I read `currency_geometry.js`; it does return null. The finding stands.*

### G2 — `notes` and `image-converter` are the two desktop widgets with no shadow at all (standard 3)

**Fixed.** Both widgets are an `Item` root composing one `Expressive.WidgetCard` now, with the
frost record taken from that card and the host's drag and box-motion forwarded to it, and the lint
below has been rescoped so the spelling that hid them cannot hide the next one
(fix(notes): draw the widget's surface on the shared card,
fix(image-converter): draw the widget's surface on the shared card,
test(lint): the card-tint carve-out is scoped to content, not to a spelling). The reading that
follows is what was there.

`bundled/notes/Widget.qml:13,36-40` and `bundled/image-converter/Widget.qml:11,51-54` are both a
`Rectangle` root painting their own surface:

```qml
radius: Appearance.rounding.verylarge
color: root.blurEnabled
    ? ColorUtils.transparentize(Appearance.colors.colSecondaryContainer, 1 - root.backgroundOpacity)
    : Appearance.colors.colSecondaryContainer
```

Neither file contains `WidgetCard`, `WidgetElevation`, or `hostDragging` — so neither casts a shadow,
and neither could lift on hover or drag even if one were added, because the host's drag never reaches
them.

Why the existing guard misses them: `tests/lint_widget_card_tint.py:41` matches
`useBlurBackground\s*\?\s*[\w.]*applyAlpha\s*\(` and nothing else. These two spell the property
`blurEnabled` and the helper `transparentize`. The `transparentize` carve-out is deliberate and
documented (`b362d8c80`, AGENT.md) — it exists for calendar's *content* tints, which scale an alpha
`colLayer1` already carries. `colSecondaryContainer` and `colPrimaryContainer` carry none; these two
widgets are using a content-tint escape hatch for their *card*.

**Symptom:** on a desktop of twelve widgets, these two sit flat on the wallpaper while every other
one casts the tuned `Appearance.elevation` shadow and rises under the pointer.

**Size of fix:** medium each — compose `WidgetCard`, route children into its content item (which is
the "anchor to `parent`, not to the card by id" trap `486272dbe` records for calendar), and declare
`hostDragging`/`hostBoxInMotion`. Tightening the lint afterwards is small.

### G3 — calendar and world-clock resize by destroy-and-rebuild (standard 1)

**Fixed.** Both widgets morph in one tree now, off a geometry module each
(`calendar_geometry.js`, `world_clock_geometry.js`), and both animate their own box; the line
numbers below describe the code as it was. What closed it is recorded under §8.
feat(calendar): morph the calendar in one tree instead of rebuilding it,
feat(world-clock): morph the world clock in one tree instead of rebuilding it.

`bundled/calendar/Widget.qml:236-245` dispatches three whole `Component`s through one `Loader`:

```qml
Loader {
    anchors.fill: parent
    sourceComponent: {
        if (root.sizeMode === "1x1") return oneByOneContent;
        if (root.sizeMode === "2x1") return twoByOneContent;
        return twoByTwoContent;
    }
}
```

`bundled/world-clock/Widget.qml` does the `visible` variant: `:153` (`sizeMode === "2x2" &&
!showingSettings`), `:310` (`&& showingSettings`), `:396` (`sizeMode !== "2x2"`) are three subtrees
switched on the span.

Both are the shape `test_the_media_tree_answers_the_blur_contract_itself` explicitly retired for
media ("the per-span `Loader` dispatch must not return") and that weather and currency never had.
The card itself is shared in both cases — calendar's `Expressive.WidgetCard` is outside the Loader
(`:226`), and its shadow therefore survives — but everything inside it is destroyed and rebuilt.

Aggravating, and easy to miss: **neither widget's box animates either.** The host's
`Behavior on width`/`height` is `enabled: rootWidget.gridResizeAnimated`
(`PluginWidget.qml:191-205`), which is `gridSized && PluginState.ready` (`:173`), and `gridSized` is
`gridSize !== null` (`:149`). Both manifests deliberately declare no `grid`
(`test_calendar_draws_its_surface_on_the_shared_card` pins calendar's absence), so `gridSized` is
false and the box snaps.

**Symptom:** calendar's corner handle re-lays out the entire content in one frame at each
breakpoint, mid-drag, against a card that jumps to its new size; world-clock's month/week button
cuts. The three widgets beside them morph.

**Size of fix:** large per widget — this is the rebuild weather and currency already had.

### G4 — discordVoice applies the interaction model twice (standard 4)

`bundled/discordVoice/Widget.qml:127-128`, repeated at `:148-149`:

```qml
scale: parent?.down ? 0.88 : (parent?.hovered ? 1.08 : 1)
Behavior on scale { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutBack } }
```

`parent` here is a `RippleButton`, which already drives an `InteractionMotion` and applies
`interactionMotion.scale` through its own `Scale` transform
(`modules/common/widgets/RippleButton.qml:57-62, 71-79`). `Item.scale` composites with an ancestor
transform, so the two multiply:

| | model (`Appearance.qml:345-346`) | with the hand-rolled layer |
|---|---|---|
| hover | 1.02 | 1.02 × 1.08 = **1.10** |
| press | 0.97 | 0.97 × 0.88 = **0.85** |

Five times the intended excursion in both directions, on `OutBack` instead of the model's curve, and
with one duration for all five transitions rather than the five tiers `interaction_motion.js:52-72`
exists to distinguish — including the `pressed -> rest` release the comment there says must not be
treated as a hover-out.

This is `8f83b2e16`'s finding ("the disabled dim is expressed at exactly one layer, because
`opacity` composites") with `scale` in place of `opacity`. `tests/lint_disabled_opacity.py` cannot
see it: it recognises the doubled dim by its opacity expression, and this is a scale.

The same two buttons in the same package's popup (`DiscordVoicePopup.qml:183-191, 202-210`) are
drawn without the ternary, so the bar/overlay copy and the popup copy already disagree about how
hard a mute button squishes.

**Symptom:** the overlay's mute and deafen buttons balloon and collapse noticeably harder than every
other control in the shell, and overshoot on release.

**Size of fix:** small — delete two lines in each of two blocks.

**Fixed**, and mechanised: `tests/lint_interaction_motion_double.py` fails the suite on a
scale-family property written from a raw hover/press flag anywhere inside a control that applies
`interactionMotion.scale`. Its sweep of both populations and the rest of the shell found no second
copy of the *transform* form — but two neighbours in the same family, neither fixed here:
`modules/imi/sessionScreen/SessionActionButton.qml:14` keys `buttonRadius` on `button.down`, which
doubles the model's press tightening in the radius channel and is tangled with a `focus` shape the
model has no state for; and the design system's own `RippleButton.qml:208` hand-rolls a state layer
beside the model it drives (already recorded in §6).

**Update — the first of those two is fixed, and the lint that named it now fails on it.** Recording
a neighbour in prose beside a check that cannot see it is how this survived: the lint knew only the
`scale` channel, on the reasoning that a `pressProgress`-driven radius "composites with nothing",
which is true of the scene graph and false of the control — `RippleButton.buttonEffectiveRadius` is
computed *from* `buttonRadius`, so the button's own jump to `size / 2` on `down` was then
multiplied by `pressRadiusScale`. Measured on the real component, a press took the corner **30 →
51** where every other control tightens; it is 30 → 25.5 now, and the `focus` shape (this grid's
keyboard cursor, which the model has no state for) stayed. The lint is per *channel* now and reddens
on the pre-fix line. The design-system state layer at `RippleButton.qml:208` is still open: it is
the tint/opacity channel rather than a geometry one, and it lives in the vendored population §6
covers. fix(sessionScreen): let RippleButton own the session button's press,
test(lint): fail on a hover/press radius inside a control that already tightens.

### G5 — custom-image's resize animates a target that moves every frame (standard 4, *unverified at runtime*)

`bundled/custom-image/Widget.qml:92-101`:

```qml
Item {
    id: contentItem
    implicitWidth: root.widgetSize
    implicitHeight: root.widgetSize
    Behavior on implicitWidth  { animation: Appearance.animation.elementResize.numberAnimation.createObject(this) }
    Behavior on implicitHeight { animation: Appearance.animation.elementResize.numberAnimation.createObject(this) }
```

and `:219-224`:

```qml
onPositionChanged: (mouse) => {
    if (!pressed) return
    var globalPos = mapToItem(null, mouse.x, mouse.y)
    var delta = Math.max(globalPos.x - startX, globalPos.y - startY)
    root.widgetSize = Math.max(80, startSize + delta)
}
```

Every mouse move of the resize drag writes a **different** `widgetSize`, so the Behavior is
retargeted every frame. That is the failure `b710ef731` documents — "a `Behavior` whose target moves
every frame restarts every frame and never ticks — the property freezes" — and it is distinct from
the mirror-image case `fa1e2a8b5` records, where the *binding* re-evaluates per frame but the
*value* it produces changes only at a span boundary, and `QQuickBehavior::write` returns early.
Here the value changes on every event.

I could not drive the grip, so this is a static match to a documented failure mode, not an observed
one. **What would settle it:** the technique from `4e33a332a` — sample `contentItem.width` partway
through a synthetic drag and require it to track the pointer rather than sit at its press value. The
`WidgetResizeMotionRuntimeTest.qml` harness already does exactly this for grid widgets and reaches
`PluginWidget` on a real `WidgetCanvas`; custom-image drives its own size and would need its own
probe. Note `4e33a332a`'s own lesson applies to writing it: a harness that assigns the size instead
of delivering mouse events switches off the interaction it exists to score.

Related, and certain from the source: this is the one widget with a self-animated size whose
`Expressive.WidgetElevation` (`:110-113`) is handed `dragging` and **never `motionActive`**, so the
shadow's blurred copy of the body re-renders into a resizing layer for the whole gesture — the
non-card half of what `e5d243c5e` fixed for `WidgetCard`.

**Size of fix:** small once diagnosed (`b710ef731`'s answer was to stop animating and say why);
the probe is medium.

### G6 — two hand-rolled shadows survived the elevation consolidation (standard 3)

`bundled/clock/CookieQuote.qml:19-28`:

```qml
DropShadow {
    source: quoteBox
    anchors.fill: quoteBox
    verticalOffset: 2
    radius: Appearance.rounding.small
    color: Appearance.colors.colShadow
```

`bundled/clock/Widget.qml:169-173`:

```qml
StyledRectangularShadow {
    target: statusTextBg
    visible: statusTextBg.visible && root.clockStyle === "cookie"
```

`test_the_elevation_is_spelled_in_exactly_one_place` bans the *file* `StyledDropShadow.qml` and any
file reading `Appearance.elevation.*`. Neither of these does either, so both passed the sweep that
folded the other five. The CookieQuote one is a Qt5Compat `DropShadow`, a different type name again.

**Symptom:** the quote chip and the status pill on the clock widget cast a shadow at a different
radius, colour and alpha from every other surface on the desktop, and neither lifts on hover or
drag while the cookie they sit under does.

**Size of fix:** small each — wrap in `Expressive.WidgetElevation`, which is already imported by two
siblings in the same package.

### G7 — currency's settings button ignores the host's lock

`designsystem/widgets/DesktopCurrencyWidget.qml:118`:

```qml
visible: cfg ? !cfg.locked : true
```

`cfg` is `Config.options.appearance.currencyWidget` (`:17`). The key is declared
(`Config.qml:680`), so this is not the undeclared-key trap — it is worse in one respect: the only
writer of `appearance.currencyWidget.locked` in the whole tree is
`designsystem/widgets/DesktopWidgetsSubmenu.qml:138`, and nothing instantiates
`DesktopWidgetsSubmenu` except `DesktopContextMenu.qml`, which nothing instantiates at all (§0). The
gate is therefore permanently `true`.

The host's resolved lock is published as `hostInteractionLocked`
(`PluginWidget.qml:675` → `PluginNode.qml:174-175`, duck-typed) and consumed by
`bundled/calendar/Widget.qml:20`, `bundled/world-clock/Widget.qml:20` and
`bundled/custom-image/Widget.qml:18`. The currency wrapper never declares it, so the widget cannot
see it.

This is the residue of `test_weather_and_currency_resize_through_the_host_not_their_own_grip`, whose
own docstring gives the reason: the widget's grip "gated on a legacy `cfg.locked` rather than the
host's resolved lock, so it stayed live on a pinned widget". The grip was removed on that reasoning;
the settings button beside it was left on the same dead gate.

**Symptom:** locking the currency widget from Settings > Widgets still leaves its settings button
fading in on hover and answering clicks.

**Size of fix:** small — one property on the wrapper, one on the component, one binding.

### G8 — the settled-span check was vacuous for the largest tree it named

Fixed in this PR; see §5.

### G9 — five controls answer a press with nothing (standard 4)

`bundled/user-card/Widget.qml:142-169` (`lockButton`), `:171-190` (`settingsButton`), `:192-211`
(`sessionButton`), and `bundled/world-clock/Widget.qml:179-195` (`settingsButton`), `:326-342`
(`backButton`). Each is a `Rectangle` with a constant `color` plus a bare `MouseArea`. They set a
cursor (standard 7 is met) and nothing else changes on hover or press.

**Symptom:** five buttons in the shell acknowledge a click only by whatever they do afterwards. The
`InteractionMotion` model exists precisely so a press is acknowledged before anything else.

**Size of fix:** small each — root on `RippleButton`, or drive an `InteractionMotion`.

### G10 — a hover colour with no transition (standard 4)

`bundled/notes/Widget.qml:182-184`:

```qml
color: noteRowArea.containsMouse
    ? Appearance.colors.colLayer2Hover
    : Appearance.colors.colLayer2
```

No `Behavior`, so the note row snaps between two colours. Not the wrong tier — no tier at all.

**Size of fix:** trivial.

### G11 — the seek stroke gives no press feedback (standard 4)

`bundled/nandoroid-media/MediaSeeker.qml` has an `onPressed` seek (`:240-246`) and a drag (`:247`)
and declares no `InteractionMotion`; nothing thickens, washes or grows. Its cursor handling is the
most careful in either population — `:230-233` tests the distance to the stroke rather than the
bounding rectangle, so it does not claim the whole square as interactive — which makes the absence
of any visual acknowledgement more conspicuous, not less.

**Size of fix:** small.

### Partial: `MediaTransportButton` adopts the model and then works around it

`bundled/nandoroid-media/MediaTransportButton.qml:72-75` is the reference adoption
(`readonly property InteractionMotion motion`, applied at `:128` and `:210-211` via
`hoverProgress`/`pressProgress` — exactly the plain-0..1 channels `interaction_motion.js:31-35`
describes). Three sites in the same file then read the raw flags instead: `:159-164` (glyph colour
off `hoveredNow`, one `ColorAnimation` duration for all transitions), `:419-420` (artwork dim), and
`:432-435` (`hitArea.pressed` with a literal `duration: 100`). Cosmetic rather than a defect, but it
is how the next file learns the wrong pattern from the right one.

---

## 3. Not applicable, and why

**Standard 1 (one-tree morphing) does not reach ten of the fourteen packages.** `nandoroid-weather`,
`nandoroid-currency` and `nandoroid-media` are the only manifests declaring a `grid` with more than
one entry; everything else has a single size and nothing to morph between. `nandoroid-system-monitor`
turns, but the turn is `Grid { columns: root.isVertical ? 1 : 3 }`
(`DesktopSystemMonitorWidget.qml:62-64`) — one tree reflowing, which is what the standard asks for.
`clock`'s `FadeLoader` per style (`clock/Widget.qml:104-155`) is a preference change, not a span, and
it cross-fades. `custom-image`'s placeholder/image swap and `image-converter`'s converting/idle swap
are empty-state changes with no shared elements to travel. `notes`'s list/edit swap
(`notes/Widget.qml:119, 240`) is the closest to the standard's shape without being a span; if the
one-tree treatment ever comes to `notes` this is where it applies.

**Standard 2 (settled span) has exactly three subjects**, and after §5 the check finds them by
sweeping rather than by name. Nothing else in the shell declares a `spanW`/`spanH`.

**Standard 3 does not mean "everything is a card".** `visualizer` is an ambient graphic that draws
straight onto the wallpaper and says so (`visualizer/Widget.qml:24-28`, `blurRegions: []`); a shadow
on individual spectrum bars would be wrong and there is nothing else to shadow.
`clock/CookieClock.qml:105-118` and `clock/PixelClock.qml:62-72` correctly take `WidgetElevation`
without a card, and the files state why — a fourteen-lobed dial and four punched-out numerals need a
shadow that follows *painted alpha*, which is the split `WidgetElevation.qml:8-22` was extracted for.
`custom-image` does the same for a shape-masked photograph (`:104-113`: a card clips to a rounded
rectangle, so a `Heart` would be cut square). `user-card` documents the sharpest case
(`:68-78`): three surfaces under one shadow, where taking the card would mean three cards, two
shadows, and no shadow at all under the avatar bubble that straddles the top edge. The clock's
hands, tick marks, numerals and date chips draw on a cookie the parent already elevated. The three
`nandoroid-*` wrappers own no visual and delegate. `discordVoice` and `docker` are an overlay panel
and a bar item, neither of which is a desktop card.

**Standard 5 has zero violations in either population.** This is worth stating explicitly because a
naive grep suggests otherwise. The rule as `tests/test_dock_position_contract.py` defines it covers
the six anchor *lines* (`top/bottom/left/right/horizontalCenter/verticalCenter`) and deliberately
excludes margins and centre offsets — `:52-54`: "they are numbers and a whole-item shorthand, and
neither can put two anchors on one axis". So `clock/SecondHand.qml:34`
(`leftMargin: ... + (root.style === "dot" ? root.dotSize : 0)`),
`clock/dateIndicator/DateIndicator.qml:31` (`rightMargin: 40 - rectLoader.opacity * 30`) and
`discordVoice/ParticipantAvatar.qml:110-112` (`anchors.margins: root.speaking ? ... : ...`) are all
exempt by the rule's own terms, not gaps. A sweep of the two populations for a conditional anchor
*line* returns hits only in `RoundCorner.qml`, `ScrollHint.qml`, `ScrollEdgeFade.qml` and
`NotificationGroup.qml` — all four in the vendored, non-instantiated half of the design system
(§0, §6).

**Standard 7 has zero offenders in the bundled population.** I ported `tests/lint_clickable_cursor.py`'s
exact algorithm over both populations. Every `MouseArea` with a click handler accepting `LeftButton`
across all 41 bundled files sets a `cursorShape`, and there are no `TapHandler`s at all. The nine
hits are all in `designsystem/widgets/` and all in files the shell never builds — and four of those
are exempt on the lint's own terms anyway (two event blockers, a full-screen dismissal scrim, and a
reusable drag surface that is not a button). One caveat for anyone extending that lint: its
brace-depth block extractor mis-attributes in a file whose *root* is a `MouseArea` — it charged
`NotificationGroup.qml:14` with a nested `DragManager`'s handlers.

**Standard 8 is met by the host windows, which is not obvious and is the reason to write it down.**
`RecordingRegionPanel.qml`'s header explains that a Controls `Popup` renders in the overlay of *its
own window*, so inside a toolbar-sized window it lands on top of the thing it describes and swallows
clicks. Every popup-bearing widget in these populations is hosted in a full-screen window:

- desktop widgets → `modules/imi/background/Background.qml:79`, a `PanelWindow` anchored on all four
  edges (`:545-550`);
- the discordVoice overlay → `modules/imi/overlay/Overlay.qml:23,40-45`, likewise;
- `docker/DockerPopup.qml` and `discordVoice/DiscordVoicePopup.qml` → `StyledPopup`, which since
  `b22a923a5` owns no window at all and is hosted on `BarPopupOverlay`'s full-screen card.

So the tooltips at `discordVoice/Widget.qml:130,151`, `DiscordVoicePopup.qml:192,211` and
`DockerPopup.qml:84,91` all have room. Two caveats that are worth knowing but are not gaps:

1. The background window is `WlrLayershell.layer: WlrLayer.Bottom` (`Background.qml:540`), so a
   desktop widget's dropdown paints *beneath* every application window. `image-converter`'s format
   picker (`:312`, a `StyledComboBox` whose `popup` is up to 300px tall,
   `modules/common/widgets/StyledComboBox.qml:176-179`) and `world-clock`'s four timezone pickers
   (`:355,363,370,377`, `StyledComboBoxSearch`, up to 320px,
   `StyledComboBoxSearch.qml:188-196`) both exceed the 228px card they sit in, so they rely on that
   window entirely. On a bare desktop they are fine; with anything on screen they open behind it.
   Whether that reads as broken in practice **cannot be settled statically** — see §4.
2. `StyledComboBoxSearch.qml:198-200` calls `searchField.forceActiveFocus()` on open, and the
   background window's keyboard focus is gated on `GlobalStates.desktopWidgetKeyboardFocus`
   (`Background.qml:542`), which `WidgetCanvas.qml:22` raises from
   `keyboardFocusRequesters.length > 0`. Whether a combo box's focus request registers as a
   requester is not answerable from the source.

`StyledSlider.qml:199-207`'s tooltip is a non-issue on the one path that ships:
`DesktopMediaWidget.qml:327` replaces the slider's `handle` wholesale (`:344-352`), and the whole
block is `visible: !root.chromeless` while the only instantiation of `DesktopMediaWidget` is
`nandoroid-media/Widget.qml:120-124`, which passes `chromeless: true`.

---

## 4. What could not be determined statically

1. **G5, whether custom-image's resize drag actually freezes.** Static shape only. Settled by a
   `WidgetResizeMotionRuntimeTest`-style probe that delivers real mouse events and samples the width
   mid-gesture (`4e33a332a`), never by assigning the size.
2. **G1's amplitude.** That the loop exists is certain from the source; whether Qt drops the
   re-evaluation early enough for the fade to visibly land wrong needs the widget at 1x1 and a look
   at `log.log`.
3. **Whether the two desktop dropdowns (§3 caveat 1) read as broken.** The layer ordering is certain;
   how often a user has the desktop bare enough for it not to matter is not a source question.
4. **Whether `StyledComboBoxSearch`'s `forceActiveFocus()` reaches a focused window** on the
   background surface (§3 caveat 2). Needs the widget on screen; the layer-shell keyboard-focus path
   is also invisible to the weston harnesses, which implement no wlr-layer-shell.
5. **Whether any of the 80 vendored design-system files is reachable by a route I did not model** —
   a plugin manifest naming a component type, for instance. `PluginValidator.js`'s
   `componentWhitelist` names only `Row`, `Column`, `Item`, `Rectangle` and `AtAGlance`, so a
   manifest cannot reach the rest; but a future manifest capability could. *Inferred* from that one
   list.
6. **Nothing about rendered pixels.** No screenshots were taken and no shell was started, per the
   audit's constraints. Every claim about what something *looks* like is an argument from the
   source and is labelled as such.

---

## 5. Ranked: what to fix first, by user-visible impact

1. ~~**G3 — calendar and world-clock resize by destroy-and-rebuild.**~~ **Done** — see §8. Two of
   twelve desktop widgets cut where the other three morph, on the most-used interaction those
   widgets have, and their box snapped as well because nothing animated it. Largest fix in the
   list and still first: it is the one gap a user sees every time they touch the widget.
2. **G2 — `notes` and `image-converter` cast no shadow.** Always on screen, no interaction needed.
   Two widgets sit flat on the wallpaper beside ten that do not.
3. **G4 — discordVoice's doubled scale.** Every mute and deafen click, at five times the intended
   excursion and on the wrong curve. Small fix, high visibility.
4. **G9 + G10 + G11 — eight controls that answer a press with nothing** (five buttons, one note row
   with no transition, one seek stroke). Individually small, collectively the difference between the
   shell feeling built and feeling assembled.
5. **G5 — custom-image's resize.** Potentially the worst single interaction in the set if the
   diagnosis holds, ranked below the certain ones because it is not yet confirmed. Confirming it is
   cheap; do that before scheduling the fix.
6. **G6 — the clock's two odd shadows.** Visible on every desktop with the cookie clock, but as
   inconsistency rather than absence.
7. **G7 — currency's settings button ignores the lock.** Small, real, and only reachable by a user
   who locks widgets.
8. **G1 — currency's binding loop.** A live loop with a small visible cost, on a span most users do
   not choose. Ranked last on impact and near-first on cost/benefit — it is ten lines and the fix is
   already written in the same file.

Not on the list, and deliberately: the 80 vendored design-system files (§6). Fixing standards in
code nothing builds spends review on nothing.

---

## 6. Latent: gaps in files the shell does not build

Recorded so a future adopter of any of these does not inherit a surprise. None has a user-visible
symptom today.

| File | Standard | What is wrong |
|---|---|---|
| `designsystem/widgets/ClippedProgressBar.qml:58-75` | 5 | An `AnchorChanges` state that both drops `top` and adds `right`, while a sibling `PropertyChanges` also writes `width` — two writers for one property. **The mainline twin `modules/common/widgets/ClippedProgressBar.qml:72-90` carries the same shape and IS live** (the bar's `BatteryIndicator`), which is the highest-value standard-5 item in the shell and sits outside both audited populations. Note `AnchorChanges` is Qt's sanctioned atomic mechanism, so the "QQuickAnchors refuses the whole update" half of the dock lesson does not apply; the double-write half does. Unverified. |
| `designsystem/widgets/ScrollEdgeFade.qml:41-56`, `ScrollHint.qml:38-39`, `RoundCorner.qml:34-39` | 5 | The anchor *set* follows a runtime property. Mainline twins are live; whether their conditions ever turn at runtime is per-call-site and not audited. |
| `designsystem/widgets/RippleButton.qml:208-209` | 4 | The adopter hand-rolls its own state layer (`opacity: root.down ? 0.12 : ...`, `duration: 150`) beside the `InteractionMotion` it drives. The **mainline** `RippleButton.qml` does not — it is clean. |
| `designsystem/widgets/DatePicker.qml:22` vs `:213,:326` | 6 | `pendingDateStr` carries a binding on `currentDateStr` and is then assigned imperatively, destroying the binding permanently — the #158 shape. |
| `designsystem/widgets/AndroidToggle.qml:44,54-73` | 4 | Press feedback as a stretch, with two private durations (320/160) and a bezier literal that appears nowhere in `Appearance`. |
| `designsystem/widgets/NotificationGroup.qml:260-262` | 8 | A `StyledToolTip` on the expand button of a notification card. The mainline twin's host (`NotificationPopup.qml`) is a narrow strip sized to the card — a genuine repeat of the `RecordingRegionPanel` situation *if* the mainline copy has it. Not checked; out of the audited populations. |
| `designsystem/widgets/WeatherCard.qml:212`, `MediaCard.qml:103,136`, `DesktopWidgetsSubmenu.qml:81` | 7 | Clickable `MouseArea` with no `cursorShape`. The submenu one is layered over an `AndroidToggle` that *does* set a hand cursor, so it would actively replace a correct cursor with an arrow. |
| `designsystem/widgets/ColorPickerButton.qml:28-48` | 4 | A 44×44 clickable swatch with `hoverEnabled: true` and nothing reading `containsMouse`. |
| `designsystem/widgets/NandoClock.qml:90` | — | `Behavior on opacity { NumberAnimation { duration: 300 } }` — a literal where `Appearance.animation` has a token. |

---

## 7. What this PR mechanises

One rule, chosen because it is the only one of the eight whose guard was demonstrably not doing its
job, and whose extension is green on `main` today.

`test_geometry_rects_come_from_the_settled_span_not_the_animating_box` (standard 2) named three
files by hand and inspected only the *line* carrying each `spanW`/`spanH` declaration. Both halves
leave a hole, and the second one made the check vacuous for the largest of the three trees it did
name: `DesktopWeatherWidget.qml:74` writes the span as a block, so the text the check read was
`readonly property real spanW: {` and nothing else.

The check now sweeps every `.qml` outside `tests/` for a `spanW`/`spanH` declaration and reads the
whole declaration, brace-balanced when the value is a block, with the three known trees asserted to
still be among the swept files so the sweep cannot go quiet.

Proven to fail, in a clean tree, on two plants, each reverted:

| Plant | Old check | New check |
|---|---|---|
| `return root.implicitWidth;` inserted as the first line of `DesktopWeatherWidget`'s `spanW` block | **OK** | **FAILED** — `DesktopWeatherWidget.qml: spanW reads the animating box` |
| `readonly property real spanW: root.implicitWidth` added to `DesktopSystemMonitorWidget.qml` (a fourth tree) | **OK** | **FAILED** — `DesktopSystemMonitorWidget.qml: spanW reads the animating box` |

The rule this does **not** mechanise, and why: tightening `lint_widget_card_tint.py` to catch G2's
`blurEnabled ? transparentize(...)` spelling would redden the suite on two real files, and fixing
those is a refactor rather than an audit. It is the right second lint, immediately after G2 lands.

**That second lint has since landed with G2's fix**, and not as the wider spelling match this
paragraph imagined — matching `transparentize` everywhere would redden every legitimate content
tint (calendar's four, world-clock's, user-card's two, and `image-converter`'s own drop well). It
decides by position instead: the ROOT object of each desktop widget's entry point, enumerated from
the manifests declaring a `desktop-widget` capability, may not paint a blur-gated tint whichever
helper it names, while a tint on a surface *inside* the card stays free. Proven to fail on the two
widgets as they stood before the fix, and to pass after
(test(lint): the card-tint carve-out is scoped to content, not to a spelling).
---

## 8. What closed G3

Both widgets are one tree now. Elements are declared once and travel between the rects a geometry
module answers for, on the shared `SpanTravel`/`SpanFade` curves — no `Loader` keyed on the span,
no `visible`-swapped duplicate subtree, and no element that stops existing between one span and
the next.

**calendar** (`calendar_geometry.js`, unit-tested in `tests/tst_calendar_geometry.qml`):

| element | 1x1 | 2x1 | 2x2 |
|---|---|---|---|
| month surface | full-bleed band, card's top corners | pill | — (fades; the 2x2 title is plain) |
| short month + weekday | in the band | — | — |
| long month name | — | in the pill | on the card inset, a step larger |
| month steppers | — | — | right of the title |
| weekday letters | — | over the card's seven columns | over the day grid's seven |
| day-grid surface | — | — | the `colLayer1` panel |
| day cells (42) | today's alone, as the hero date | the current week's seven, in a row | all of them, in six rows |

**world-clock** (`world_clock_geometry.js`, `tests/tst_world_clock_geometry.qml`): the four city
tiles are the shared elements. A chip in the 2x2 grid and a dial in the 3x1 row are the same tile,
carrying its surface, its colour and its city name; the offset, the digital time and the day/night
glyph fade, and the hands fade in out of the chip's own box. The local place/time/date block and
the settings back are pinned to the 2x2 box while they fade rather than anchored to a card on its
way to 420x108.

Two things the audit named as aggravating are also gone. Both widgets animate their own box, which
the host does not do for a widget declaring no `grid` (see `docs/widget-grid.md`), and both publish
their own `boxInMotion` so the card stops re-blurring its body into a reallocating layer for the
length of the resize.

Verified frame by frame on the running shell (`grim` bursts at ~36ms across each transition):
every shared element stays on screen and travels, and nothing blinks out and reappears.

One thing those bursts exposed that is **not** this gap: the desktop frost drops out for the
length of any box animation, and the same burst on `nandoroid-weather` shows it identically. It
predates the one-tree work and was simply invisible while these two snapped. Recorded in AGENT.md
with the suspected mechanism and the way to settle it.

`test_a_widget_that_owns_its_span_morphs_in_one_tree` is the guard: any widget declaring its own
`sizeMode` may not let that name reach a `sourceComponent` or a `visible`.
