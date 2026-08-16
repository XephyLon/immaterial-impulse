# `P3DROVFX/ii-p3drovfx` — animation and motion technique

> Date: 2026-08-16. Research only; nothing was ported and nothing was fixed.
> Companion to [`p3drovfx-research-2026-08-16.md`](p3drovfx-research-2026-08-16.md),
> which surveyed the fork by *feature* and undersold this. This one is organised
> by *technique*: what they do with motion, what transfers, what conflicts with
> how we already animate, and where ours is already better.
>
> Their tree read at `2e318c18` (2026-08-16) — the same commit the first survey
> read — with its `shapes` submodule initialised. Their paths are relative to
> `dots/.config/quickshell/ii/`; ours to `dots/.config/quickshell/imi/`.
>
> **The first survey's §2 warning, obeyed.** That survey read their tree and
> *searched* ours, and recorded three things about our own code that were false.
> Every claim below about our side names a file and a line I opened. Where I
> could not confirm something it says "not found", not "none" — and the one
> instruction in the brief for this survey that turned out to be wrong ("we have
> no snapping at all") is corrected in the open, in §4.1, rather than quietly.

---

## 1. The two motion vocabularies

### 1.1 We are running the same catalogue

This is the fact everything else sits on. `modules/common/Appearance.qml`'s
`animationCurves` block is **the same in both trees** — the same twelve bezier
control-point lists and the same four durations, down to the `2 / 15` and
`5 / 24` fractions in `emphasized` and the trailing comments naming each curve's
nominal duration. Theirs at `Appearance.qml:512-529`, ours at
`Appearance.qml:314-331`:

```qml
readonly property list<real> expressiveFastSpatial:    [0.42, 1.67, 0.21, 0.90, 1, 1] // Default, 350ms
readonly property list<real> expressiveDefaultSpatial: [0.38, 1.21, 0.22, 1.00, 1, 1] // Default, 500ms
readonly property list<real> expressiveSlowSpatial:    [0.39, 1.29, 0.35, 0.98, 1, 1] // Default, 650ms
readonly property list<real> expressiveEffects:        [0.34, 0.80, 0.34, 1.00, 1, 1] // Default, 200ms
```

The `animation` block is the same shape too — `elementMove`, `elementMoveSmall`,
`elementMoveEnter`, `elementMoveExit`, `elementMoveFast`, `elementResize`,
`clickBounce`, `scroll`, `menuDecel` — each exposing `duration` / `type` /
`bezierCurve` / `velocity` plus a `Component` factory so a call site can write
`Behavior on x { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }`.
Both inherit it from end-4.

So this is not a comparison of two motion languages. It is a comparison of what
two forks did with one. **Nothing in this document is a disagreement about a
curve; every item is a structural decision.**

### 1.2 What each fork added

| | Theirs | Ours |
|---|---|---|
| Global speed multiplier | `Appearance.animMultiplier` (`Appearance.qml:510`) from `Config.options.appearance.animationMultiplier`; a slider 0.25–2.5 at `modules/settings/configs/InterfaceFontsConfig.qml:48-61`. Every token duration is `Math.round(base * animMultiplier)` | **not found.** `grep -rn "animationMultiplier\|animMultiplier"` over our shell returns nothing. Every duration is absolute |
| Rounding scale | `Appearance.rounding.scale = roundingValue / 24.0` (`Appearance.qml:215-235`); every radius is `Math.round(base * scale)`; slider 0–48 with a detent at 24 | **not found as a knob.** `Appearance.qml:227-239` is a fixed ladder of literals. The nearest thing, `Appearance.qml:13` `readonly property real effectiveScale: 1.0`, is a hardcoded constant (§4.3) |
| One spelling of "how a shared element travels" | **not found** — 1806 hand-written `NumberAnimation`s; one token-driven reusable transition (`FadeLoader.qml`, 18 lines) | `SpanTravel.qml` / `SpanFade.qml`, 140 uses, enforced by `test_expressive_design_system.py::test_the_trees_share_one_spelling_of_the_span_animations`. e62584f17 ("refactor(designsystem): the morph mechanics become one module") |
| A hover/press/focus interaction model | **not found** — the `scale: down ? k : (hovered ? k : 1)` ternary appears 68 times across 43 files with 15+ distinct constant pairs, and `RippleButton.qml:237-243` hardcodes its own `150ms OutQuad` | `Appearance.interaction` + `modules/common/interaction_motion.js` + `InteractionMotion.qml`: five states, a tier per *transition*. af09ed3b9 ("feat(widgets): one driver wires a control to the model"), enforced by `lint_interaction_motion_double.py` |
| Springs | `SpringAnimation` at 4 sites, with three named profiles in `Appearance.qml:664-686` | **none.** `grep -rn SpringAnimation` over our shell returns nothing |
| A motion *policy* object | `modules/welcome/WelcomeMotion.qml:40-44` — a singleton that grades the multiplier into four levels and collapses stagger to 0 at the bottom | **not found** |

### 1.3 The adoption numbers

Counted the same way over each tree's `modules/` directory.

| | Theirs | Ours |
|---|---|---|
| `.qml` files under `modules/` | 1257 | 634 |
| files containing a `NumberAnimation` | 308 (24.5%) | 108 (17.0%) |
| total `NumberAnimation` occurrences | 1806 | 293 |
| literal `duration: <N>` occurrences | 1728 in 272 files | 164 in 62 files |
| `Behavior on` declarations | 1727 across 444 files | 691 |
| `Appearance.animation.*` references | 1662 | 703 |
| `SpanTravel` / `SpanFade` uses | — | 109 / 31 |

Per file they hand-write **3.1×** as many `NumberAnimation`s and **5.3×** as
many hardcoded millisecond literals as we do. The consequence on their side is
concrete rather than aesthetic: because roughly half their motion is a literal,
**their `animationMultiplier` slider silently does nothing for about half the
shell** — including every `ShapeCanvas` morph, whose 350ms is hardcoded inside
the vendored submodule.

That is the comparison in one line. They built the knob and then wrote past it;
we never built the knob but we kept the call sites uniform enough that building
it would work.

---

## 2. Ranked list — what to take

Ordered by value per unit of work. Sizes are new-code estimates for *our* tree,
including the check each one needs under `CONTRIBUTING.md`'s "New features and
bugfixes need tests".

| # | Take | Why | Size |
|---|---|---|---|
| 1 | **Declare `Appearance.rounding.card` / `.extraLarge` / `.button`** (§4.3) | Six live call sites read tokens that do not exist. `radius: undefined` renders 0; `Carousel`'s `clipRadius` is `undefined - 10` = `NaN`, in three live surfaces. Probed, not reasoned | Tiny — 3 lines + one lint |
| 2 | **The single-scalar driver, and the hero-height unroll built on it** (§3.1) | Animate exactly one `real` 0→1 and bind everything else to it. Their best idea, and their popup's unroll — open at the *first card's* height, unfurl to full along the same progress the fade rides — is the best single motion in either tree. Our card already carries every ingredient | Small, ~60 lines in `BarPopupOverlay.qml` + a probe |
| 3 | **`StableQuickToggleModel`** (§3.2) | A keyed `ListModel` emitting real `move()` ops that pins a row's *type* to its id. It is the piece 81379796b worked around by rebuilding the row: it keeps the delegate **and** keeps `DelegateChooser` honest, which is what makes an animated reorder possible at all | Small-medium, ~130 lines + `tst_*` |
| 4 | **An animation multiplier, a *named* reduce-motion floor, and a stagger policy** (§3.6) | One `animMultiplier` threaded through eight token durations reaches 703 of our call sites plus all 140 `SpanTravel`/`SpanFade` sites. Ours is the tree where this actually works. Take `WelcomeMotion`'s graded policy, not their seven copies of a magic `<= 0.25` | Small, ~50 lines + settings row + a lint |
| 5 | **Animate the exclusive zone through a space-reserver window** (§3.4) | Our auto-hidden bar slides on an `anchors.topMargin` Behavior while its `exclusiveZone` snaps between two ints, so the windows behind it jump. Their fix is a second, invisible, fully-masked `PanelWindow` that owns the animated zone | Small, ~70 lines |
| 6 | **FLIP reposition for bar widgets** (§3.5) | Their `BarComponent` animates a widget's *reorder* with an inverse translate re-targeted from `onXChanged`. Our bar is a `Repeater` of `Loader`s with no motion at all, so the tray emptying teleports everything to its right | Medium, ~120 lines + a runtime harness |
| 7 | **A rounding scale knob** (§3.7) | `scale = roundingValue / 24`, every radius `Math.round(base * scale)`, `full` special-cased to 0 in sharp mode. Our ladder is already the base values theirs anchors on | Small, ~30 lines + migration + settings row |
| 8 | **The three stagger fixes** (§3.3) | Delay by *visible* rank so a hidden section leaves no gap; `Math.min(index, N)` so a long list does not cascade for ten seconds; stagger stored **in the model row** so it survives delegate recycling | Small, ~40 lines, arithmetic only |
| 9 | **`Behavior on <non-animatable>` with a trailing bare `PropertyAction {}`** (§3.8) | Makes a `url`/`string`/`Component` swap *wait* for the outgoing content's exit, with no state machine and no signal ping-pong. Our overlay does the same job today with two chained `Timer`s | Tiny, ~15 lines |
| 10 | **Snap hysteresis (a Schmitt trigger) for widget-edge alignment** (§3.9) | `_snapEnter: 18` / `_snapExit: 32` measured against an *unsnapped* shadow position. We have a lattice and guides; we do not have edge alignment or the two-threshold hold | Medium, ~200 lines + `tst_*` for the pure arithmetic |
| 11 | **A spring for pointer-following motion** (§3.10) | Their dock magnification uses `SpringAnimation` with three named profiles, and says why in a comment: a target that moves every frame must not restart a one-shot easing curve. We have zero springs, and AGENT.md already records the frozen-Behavior failure this avoids | Small, ~40 lines if a case arises |
| 12 | **An hourly forecast in the weather popup** (§5.2) | Not a motion technique, but the largest content gap Half 2 found: our bar weather popup has no forecast of any kind. Their grow-from-the-axis bar chart is the cheap half | Medium, ~250 lines + service work |
| 13 | **`MarqueeText`** (§3.11) | Overflow-gated, distance-proportional duration with a floor. We have no marquee anywhere; every long label in the shell elides | Small, ~40 lines |
| 14 | **The notch's derived clamped radii** (§3.12) | `topRadius: Math.min(wr, Math.max(0, animHeight * 0.8))` — corner geometry that can never outrun the box. Only if we ever build a concave-shouldered surface | Small, ~30 lines |
| 15 | **Counter-rotation desync, and rate-limited shape advance** (§3.13) | Two ten-line tricks: a glyph counter-rotating inside a spinning shape at a deliberately different duration, and a 220ms gate over a *visually coherent subset* of shapes so bursts coalesce | Tiny, ~35 lines total |

Explicitly **not** taken, with reasons in §3.14: their `Notch.qml` itself, their
`shapes` submodule, their per-popup `PanelWindow`, their live re-pack on every
mouse move, and their reset-and-replay entrance idiom as a general pattern.

---

## 3. The techniques

### 3.1 The single-scalar driver, and the hero-height unroll

**This is the technique the rest of their good motion is a special case of.**
Animate exactly one `real` from 0 to 1; bind every visual property to it. Four
independent examples:

- `topLayer/search/SearchDrop.qml:141-194` — a two-state machine whose only job
  is to set `openProgress`, with directional transitions giving open (450ms) and
  close (280ms) different durations. Clip height, corner radii and position are
  all bindings on it.
- `common/widgets/LyricScroller.qml:32-111` — one `scrollOffset` normalised to
  `animProgress`, then seven delegates × three properties lerped by hand off it.
  No `Behavior` anywhere; perfectly synchronised by construction.
- `common/widgets/TransitionImage.qml:115-168` — one `transitionProgress`
  feeding a GPU shader uniform, with both `ShaderEffectSource`s set
  `live: shaderProgressAnim.running` so the cost exists only during the
  transition.
- `common/widgets/MaterialLoadingIndicator.qml:38` — three summed rotation
  channels, `rotation: pullRotation + continuousRotation + leapRotation`.

The payoff in `bar/shared/StyledPopup.qml:488-494` is the **hero-height unroll**:

```qml
height: {
    if (!root.animateHeight) return targetHeight;
    if (!root.animate || !root.contentItem || !heroItem || targetHeight <= heroHeight + margin * 2)
        return _commitHeight;
    return (heroHeight + margin * 2) + (_commitHeight - (heroHeight + margin * 2)) * popupWindow.animProgress;
}
```

`heroItem` is discovered as the first visible child with `width > 0` (`:296-305`).
So a popup does not scale up from nothing and does not slide in whole: it appears
**already the size of its first card** and unrolls downward to reveal the rest,
along the same `animProgress` driving the fade and a 35px slide out of the bar.
For their clock popup the hero is the 200px `ClockHeaderCard`; for weather, the
180px `HeroCard`. The top edge never moves and the primary content is legible on
frame one, which is why it reads so much better than a scale.

It lands on our card. `BarPopupOverlay.qml:161-195` already computes
`cardHeight = content.implicitHeight + contentPadding * 2` and assigns
`card.height` through `Behavior on height` (`:504-512`). The change is to give
`StyledPopup` an optional hero item and, when entering from a park, target the
hero height first and the full height second.

Two of our own rules constrain it, and neither blocks it:

- **The card's geometry is assigned, never bound** (`:187-189`, a comment that
  exists because on the bottom and right edges the fixed axis is a function of
  the animating size). Two staged assignments are fine; a binding on a progress
  scalar would not be.
- **A `Behavior` whose target moves every frame restarts every frame and never
  ticks.** b710ef731 ("fix(plugins): stop the position Behavior swallowing the
  parallax cancellation"). So: either a progress scalar with `height` as a plain
  binding on it, or a staged `Behavior`. Not both.

### 3.2 `StableQuickToggleModel` — and what it repairs

The brief asks which quick-toggle approach is better. The honest answer is
**theirs, and specifically because it solves the exact bug ours worked around.**

Ours (`sidebarRight/quickToggles/AndroidQuickPanel.qml:106-136`) feeds each row a
**plain array** model, deliberately, with a 30-line comment:

> `DelegateChooser` picks a component when a delegate is *created* and never
> re-picks for one that survives. `ScriptModel` exists to keep delegates alive
> across model updates, so the two together mean a row entry that changes
> identity in place keeps the previous toggle's component […] A plain array model
> resets the `Repeater` instead.

That is 81379796b ("fix(sidebar): choose a delegate for the toggle each row entry
now holds"), and it is correct as a fix for the bug it names. Its cost is stated
in the same comment — "a layout edit recreates that row's delegates" — and
accepted because layout edits are deliberate. What the comment does not say,
because it was not the question then, is that recreating the delegates makes an
animated reorder **impossible by construction**.

Theirs takes the third option
(`sidebarDashboard/quickToggles/androidStyle/StableQuickToggleModel.qml:92-118`)
— a `ListModel` that diffs an incoming list by a stable `itemId` and emits exact
ops:

```qml
// Remove by stable id, never by the new list length.
for (var oldIndex = root.count - 1; oldIndex >= 0; oldIndex--) {
    if (!desiredIds[root.get(oldIndex).itemId])
        root.remove(oldIndex, 1);
}
...
    // An id is permanently bound to one functional component. If
    // malformed input violates that contract, rebuild only this row.
    if (root.get(existingIndex).toggleType !== wanted.toggleType) {
        root.remove(existingIndex, 1);
        root.insert(desiredIndex, wanted);
        continue;
    }
    if (existingIndex !== desiredIndex)
        root.move(existingIndex, desiredIndex, 1);
```

Three guarantees stack, and the middle one is what we lack: a reorder becomes
`move()` so the `Repeater` reuses the delegate; **an id is permanently bound to
one type, so `DelegateChooser` can never be asked to re-pick for a surviving
row**; and a payload write is gated on a real difference, so identical geometry
produces no churn. Its header states the motive in one sentence: *"ScriptModel
updates equal-key JS clones with dataChanged and removes only the trailing row,
which is unsafe for DelegateChooser."*

Their delegate model is then always the *persisted* order, and the draft supplies
only geometry — `QuickToggleLayout.js:150-179`:

> Keep the delegate model in its persisted order and attach only geometry from a
> packed preview. This is deliberately separate from `pack()`: reordering a draft
> must move existing delegates, never replace/retype them while a mouse grab is
> active.

The delegate binds
`Binding on x { when: hasExplicitGeometry; value: Number(buttonData.layoutX) }`
with `Behavior on x { enabled: hasExplicitGeometry && !isDragging; … elementMoveFast }`,
so displaced neighbours glide at 200ms on `expressiveEffects` while the dragged
tile's own Behavior is off and its *visual* is translated by a per-move
`dragOffsetX/Y` compensation computed with `mapFromItem`. The classic conflict —
packer and pointer both writing `x` — is dissolved rather than arbitrated: they
are different properties on different objects.

**Ours does not move anything at all during the drag.**
`androidStyle/AndroidQuickToggleButton.qml:162-247` is a
`DragHandler { target: null }`. The tile stays put; what moves is a 3px
`dropIndicator` with
`Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }`
(`AndroidQuickPanel.qml:166-167`), and the swap happens on release by exchanging
two array elements in place (`:216-220`).

For the record, because the first survey got this wrong once: **the in-place
mutation is not a defect.** 26b625905 (`Revert "fix(sidebar): make quick toggle
edits actually notify" and follow-ups`) measured against a real `Config` that
every mutation form notifies, and deleted the lint that had been added to forbid
it. Nothing here recommends changing that.

Take the *model*, not the editor. Their `QuickToggleEditController`'s
draft/commit boundary was already ranked in the first survey (§5 item 16) and
that ranking stands. `StableQuickToggleModel` is separable from it, is 125 lines,
and is the piece that makes an animated reorder possible for **any** keyed list
we draw with a `DelegateChooser`.

### 3.3 Stagger, done three ways better than the obvious one

Naive `index * delay` breaks in three ways, and they fixed all three in different
files.

**Hidden items leave a hole.** `bar/popups/clock/ClockWidgetPopup.qml:203-219`
ranks by *visible* position rather than model index — the comment even names the
symptom, "prevent stagger skipping":

```qml
function getDelay(index) {
    let visIndex = 0;
    for (let i = 0; i < index; i++) { if (_visList[i]) visIndex++; }
    const delays = [40, 100, 160, 220, 280];
    return delays[Math.min(visIndex, delays.length - 1)];
}
```

**Long lists cascade forever.** `sidebarDashboard/todo/TaskList.qml:72-79` clamps:
`PauseAnimation { duration: Math.min(Math.max(index, 0), 20) * 45 }`, and
`RemoteNotificationListView.qml:118` uses `120 + Math.min(250, index * 45)`.

**Delegate recycling loses it.** `background/widgets/WidgetStateManager.qml:70,93`
writes `"staggerDelay": addCount * 60` **into the ListModel row**, sets a
`staggerTransitionActive` flag, and clears every row's delay two seconds later
(`:18-27`). The stagger lives in the model, so a recycled delegate still knows
its place in the wave.

And the policy layer, `welcome/WelcomeMotion.qml:40-44`, which is the piece worth
taking whole:

```qml
readonly property int level: !root.motionEnabled ? 0
    : root.multiplier < 0.9 ? 1 : root.multiplier < 1.5 ? 2 : 3
readonly property bool staggerAllowed: root.level >= 3
function staggerFor(index: int): int {
    return root.staggerAllowed
        ? Math.round(index * Appearance.animation.elementMoveFast.duration * 0.18)
        : 0;
}
```

Stagger is expressed as a *fraction of a catalogued duration* rather than a
literal, and it collapses to zero when the user has turned motion down. That is
how §2 item 4 should be built rather than as the seven hand-copied
`animationMultiplier <= 0.25` checks their own tree carries elsewhere.

The `> 0.6` progress gate that fires their content cascade
(`ClockWidgetPopup.qml:222`) does not port directly — our card has no scalar
progress, it has four `Behavior`s. The equivalent is a `Timer` at
`elementMove.duration * 0.6`, or, better, introducing the progress scalar the
unroll wants anyway (§3.1) and gating on that.

Two cautions we would inherit. Their `_visList` (`ClockWidgetPopup.qml:207`) reads
`columnLayout.children[2].visible` — positional indexing into a layout's children,
so inserting a block silently breaks the cascade. And their entrance animations
**destroy the bindings they animate**: `HourlyForecast.qml:77` declares
`property real barHeightAnim: barHeight` and a `NumberAnimation` writes it on
open, so the chart animates on *open* and never on *data* — a refresh while the
popup is open pops the bars to their new heights with no motion at all.

### 3.4 Animating an exclusive zone without thrashing the compositor

`bar/core/BarWindow.qml:31-56` is a second, entirely invisible `PanelWindow`
(`id: barSpaceReserver`, `color: "transparent"`, `mask: Region {}`) under the
comment *"Space reserver (reserves space so windows don't overlap bar)"*, whose
only job is to hold the animated exclusive zone (`:46-51`) — while the real bar
window sets `exclusionMode: ExclusionMode.Ignore; exclusiveZone: 0` (`:126-127`).
The zone is not itself animated; it is a **binding on an already-animated
property** (`:121-124`):

```qml
property real hiddenAmount: (Config?.options.bar.autoHide.enable && !mustShow) ? Appearance.sizes.barHeight : 0
Behavior on hiddenAmount {
    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(barRoot)
}
```

so the compositor's reflow rides the same curve as the visual slide. Same split
in `verticalBar/VerticalBar.qml:58` and `sidebarPolicies/SidebarPolicies.qml:144`.

Ours does not do this. `bar/Bar.qml:63` is a bare conditional:

```qml
exclusiveZone: (Config?.options.bar.autoHide.enable && (!mustShow || !Config?.options.bar.autoHide.pushWindows))
    ? 0 : Appearance.sizes.baseBarHeight + (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
```

while the bar's own body slides on `Behavior on anchors.topMargin` /
`bottomMargin` (`:296-300`). So the bar glides and the windows behind it jump —
in opposite directions, at the two ends of the same gesture.

This belongs in AGENT.md's layer-shell section if it lands: it is a
compositor-visible behaviour with a non-obvious implementation, and the "one
surface holds the animated zone, the visible one ignores it" split is exactly the
kind of thing the next agent would otherwise re-derive.

### 3.5 FLIP reposition for a bar widget

`bar/BarComponent.qml:89-139`. Every bar widget sits in a wrapper that watches
its own `x`/`y` and, on a change, re-targets an inverse `Translate` back to zero:

```qml
NumberAnimation { id: moveXAnimation; target: moveTranslation; property: "x"; to: 0; duration: 350; easing.type: Easing.OutExpo }
```

armed only after a 100ms `readyTimer` (`:129-139`) so initial layout does not
animate. That is FLIP (First-Last-Invert-Play) with one translate and no
snapshotting: a widget appearing, disappearing or being reordered makes its
neighbours *slide*.

Ours does not. `bar/BarContent.qml:181-194` and its five sibling blocks are plain
`Repeater`s over `effectiveLeftLayout`/`effectiveMiddleLayout`/`effectiveRightLayout`
with `Loader` delegates, and `bar/BarGroup.qml` carries exactly one animation in
the whole file — `Behavior on color` at `:80`. So when `filterLayout()` drops
`sysTray` because the tray emptied, or a plugin is disabled, or the user reorders
the bar in Settings, everything to the right teleports.

`enabled: root._isInitialized` is the reusable half of the same idea, from
`common/widgets/NavigationRailButton.qml:102,194`: a `Transition` gated on a flag
set in `Component.onCompleted`, so the first frame snaps and every later change
animates. We have the same file
(`modules/common/widgets/NavigationRailButton.qml:73`, with an `AnchorAnimation`)
and would need the same guard.

### 3.6 An animation multiplier — because ours is the tree it would work in

One line, `Appearance.qml:510`:

```qml
readonly property real animMultiplier: Config.options?.appearance?.animationMultiplier ?? 1.0
```

then every token duration is `Math.round(base * root.animMultiplier)`.

On their side this is largely decorative — 1728 hardcoded `duration:` literals
never see it, and neither does the 350ms inside `ShapeCanvas.qml`. On ours it
would reach 703 `Appearance.animation.*` references plus all 140
`SpanTravel`/`SpanFade` sites, against 164 literals.

Two things to do better than they did. **Name the reduce-motion state**: theirs
is the magic threshold `animationMultiplier <= 0.25`, re-derived by hand as a
private `_animationsDisabled` at seven separate call sites — while
`WelcomeMotion.qml` (§3.3) shows they already knew how to express it properly and
did not generalise it. And **pair it with a lint**, because the value of the knob
is exactly the proportion of the tree that routes through it, and that proportion
only decays.

`ShapeCanvas.qml:32-36` is ours as well as theirs and carries the same hardcoded
350ms (§4.4). Fix that as part of this, not after.

### 3.7 A rounding scale

`Appearance.qml:215-235`:

```qml
rounding: QtObject {
    property real scale: {
        let rv = Config.options.appearance.roundingValue;
        if (rv > 0) return rv / 24.0;
        if (rv < 0) return 1.0; // not yet migrated, default to large
        return 0.0; // roundingValue === 0 → sharp
    }
    property int unsharpen: Math.round(2 * scale)
    ...
    property int full: scale === 0 ? 0 : 9999
}
```

Better than "multiply the radii". `24` is the anchor, so `roundingValue == 24`
reproduces the base ladder exactly — and **our ladder is already those numbers**
(`Appearance.qml:227-239`: 2, 6, 8, 12, 17, and `large: 23` against their 24).
Sharp mode falls out of the same arithmetic rather than needing a parallel token
set, with `full` special-cased from the 9999 sentinel to 0 — which is the detail
that would otherwise leave every pill in the shell a pill in sharp mode. Their
settings row puts `stopIndicatorValues: [24]` on the slider so the unscaled point
is visible to the user (`InterfaceFontsConfig.qml:24-41`); worth copying.

Two leaks of theirs not to copy: `Appearance.qml:19-30` pushes `windowRounding`
into the compositor with `hyprctl eval` on every change — which AGENT.md's
Hyprland section already explains does not survive a reload — and
`RippleButton.qml:190` reads `Appearance?.rounding?.scale === 0` directly as a
sharp-mode flag, leaking the raw scale to call sites.

If this lands, §4.3's three undeclared tokens must be declared as part of it, or
they stay `undefined` through the change.

### 3.8 `Behavior on <non-animatable>` with a trailing bare `PropertyAction {}`

The most genuinely novel construct in their tree, at
`waffle/onScreenDisplay/WaffleOSD.qml:125-140`. A `Behavior` on a `url` — which
QML cannot interpolate — whose animation calls the outgoing item's `close()`,
waits exactly that item's self-reported duration, and only then lets the
assignment through:

```qml
Behavior on source {
    id: switchBehavior
    SequentialAnimation {
        id: switchAnim
        // Animate close of current indicator
        ScriptAction { script: { osdIndicatorLoader.item.close(); } }
        // Wait for close anim
        PauseAnimation { duration: osdIndicatorLoader.item.closeAnimDuration }
        PropertyAction {} // The source change happens here
    }
}
```

The bare `PropertyAction {}` with no target and no property is the trick: inside
a `Behavior` it means "apply the pending write now". No state machine, no
`_pendingSource`, no signal ping-pong.

We solve the same problem — "do not swap content until the outgoing content has
finished leaving" — with two chained `Timer`s and a hand-written state machine in
`bar/BarPopupOverlay.qml:314-333, 405-438` (`exitShrinkTimer` at
`elementMoveExit.duration`, then `exitFadeTimer` at `elementMoveFast.duration`,
then `finishExit()`). That works and is well commented, but the durations are
duplicated between the timers and the animations, which is exactly the class of
drift the `SpanTravel` extraction exists to prevent.

Their sibling pattern is worth naming too: `common/widgets/DialogHostLoader.qml:19-47`
keeps a `Loader` alive through its own exit with `active: shown || closing`,
clearing `closing` only once `item.visible` goes false — so destruction never
truncates the outro. We have the same shape in `FadeLoader.qml`
(`visible: opacity > 0`), one level simpler.

### 3.9 Snap hysteresis — take the arithmetic, not the file

`background/widgets/AbstractBackgroundWidget.qml:182-192`, and they name it
correctly:

```qml
// ── Snap hysteresis state ─────────────────────────────────────────────────
// This is a Schmitt trigger: acquire close to a guide, release farther away.
readonly property int _snapEnter: 18
readonly property int _snapExit: 32
readonly property int _snapOrthogonalRange: 600
```

The mechanism is not the two numbers, it is what they are measured against.
`_rawDragX` is a shadow position in canvas coordinates that **only the pointer
ever writes** (`:329-330`); `root.x` is the pure output of `raw → grid → snap`.
Both the acquire test and the release test compare against `_rawDragX`, never
against the rendered position — had they fed the rendered position back in, the
hold condition would be trivially always true and the snap permanent.

With one threshold, snapping puts `root.x` on the target while the pointer sits
within `T` of it, so the next event re-snaps; pushing just past `T` unsnaps and
the widget jumps back to a position that may be within `T` again in the other
direction. That is a per-event flip-flop at the boundary, and it happens because
the decision boundary and the resulting position are the same number. Two
thresholds separate "close enough to grab" from "far enough to let go", and the
14px gap between them is what makes it feel like a detent.

`_snapOrthogonalRange: 600` is a relevance filter on the *perpendicular* axis
(`:427-429`): a widget more than 600px away across the axis being snapped
contributes no candidates, so nothing left-aligns to something in the opposite
corner. It compares corner to corner rather than overlapping spans, and uses
`>=`, so exactly 600 is excluded.

The candidate set is four relations per other widget per axis — my near edge to
their near edge, my far to their far, my near to their far, my far to their near
— each candidate carrying **two numbers**, `target` and `guide` (`:432-437`),
because the guide line is drawn at the *other* widget's edge while the widget
travels to a position derived from it. Their guide lines are not animated at all
(`WidgetCanvas.qml:52-69`: two `Rectangle`s, `visible: snapLineX >= 0`, no
`Behavior`), so they pop and teleport between guides. Only the dot grid fades.

Their grid mode is a *separate* hysteresis with a better justification than the
snap's, spelled out at `:194-212`: the anchor stores the raw pointer position at
the last cell commit, so a new cell needs a full `_gridStep` of movement from
*there* rather than from the cell boundary — which is the fix for jitter at a
boundary that distance-from-cell-centre hysteresis does not give you.

The comment the brief flagged is `:171-172`:

> Pointer coordinates and rendered coordinates are intentionally separate.
> `MouseArea.drag` must not write `root.x/y` because snap/grid also write them.

enforced by one line, `drag.target: undefined` (`:532`), overriding a base class
that sets `drag.target: draggable ? root : undefined`. **We reached the same
conclusion independently, for a different reason** — d2ebb5aeb
("fix(widgetCanvas): compute the drag by hand - MouseArea.drag cannot track it")
removed `drag.target` because QQuickDrag rebases its press origin and swallows
the arming move's delta, measured as half a gesture under a sparse synthetic
drag. Two trees, two arguments, one answer.

So what we would take is narrower than it looks: not the drag architecture (we
have it, §4.1), but the **edge-alignment candidate set** and the **two-threshold
hold**.

One detail to copy if it lands: their `settleTimer` (`:249-260`) holds the
position Behaviors off for 350ms *after* release, because the release
round-trips through `Config` and the arriving value would otherwise animate the
widget away from where it was dropped — and it clears the guard *before* writing
the corrective value, so the drop is instant and a late correction glides.

### 3.10 A spring for a target that moves every frame

`dock/DockContent.qml:2133-2140`:

```qml
Behavior on animatedMagScale {
    enabled: !root.dragging
    SpringAnimation {
        spring:  root.magnificationMotionProfile.spring
        damping: root.magnificationMotionProfile.damping
        mass:    root.magnificationMotionProfile.mass
        epsilon: root.magnificationMotionProfile.epsilon
    }
}
```

with three named profiles in `Appearance.qml:664-686` and the rationale stated in
the token file itself:

> Continuous magnification follows a moving pointer target, so it uses a spring
> instead of restarting a one-shot easing curve.

That is the same failure AGENT.md records twice — "a `Behavior` whose target
moves every frame restarts every frame and never ticks" (b710ef731) and its
mirror image "a `Behavior` *retriggered* every frame does tick, forever"
(a57cd00b2, the cava case). A `SpringAnimation` is the answer to the first that
neither of our fixes needed, because in both of our cases the right answer was to
stop animating. **The technique is the diagnosis, not the file**: when a target
genuinely does move every frame and the motion is wanted, a spring is the
construct, and `epsilon` is what stops it running forever.

The falloff kernel beside it is worth reading too (`DockContent.qml:591-602`):
raised-cosine and gaussian variants, both normalised to reach exactly 0 at the
influence radius so there is no discontinuity at the edge of the effect. Our
`common/widgets/DockIconMotion.qml` composes a hover lift and a launch bounce on
two separate offsets summed into one `Translate` (`:127-128`) — a good design,
and the file's own comment at `:130-133` records the tier-carry bug that
`InteractionMotion` exists to prevent — but there is no neighbour magnification
at all.

One smaller sibling: their OSD gates a velocity-limited animation off during
drag, `onScreenDisplay/OnScreenDisplay.qml:505-512`,
`Behavior on displayValue { enabled: !osdRoot.isDragging; SmoothedAnimation { velocity: 4.0 } }`.
Ours uses `SmoothedAnimation` in four places including
`common/widgets/StyledSlider.qml:67-71` — and ours is better in one respect, in
that the velocity comes from `Appearance.animation.elementMoveFast.velocity`
rather than a literal — but none of ours is gated off during a drag.

### 3.11 Text motion, where we have none

- **`common/widgets/MarqueeText.qml:24-37`** — overflow-gated
  (`readonly property bool overflows: implicitWidth > root.width + 1`), with a
  duration proportional to the overflow and a 3500ms floor:
  `duration: Math.max(3500, (innerText.implicitWidth - root.width) * 28)`. We
  have no marquee anywhere; `find -name '*Marquee*'` over our shell returns
  nothing, and every long label elides.
- **`common/widgets/StyledText.qml:37-92`** ships an `animateChange` mode — a
  complete slide-out / `PropertyAction` swap / slide-in over `x`, `y` and
  `opacity` at 150ms `InSine`/`OutSine`. It is never set true anywhere in their
  weather or clock features, so their bar temperature and their 48px hero
  temperature both hard-cut on refresh. **A shipped transition nobody turned on**
  is worth noting as a failure mode in its own right.
- **`dock/DockMediaWidget.qml:300-312`** — the split-flap song change: old text
  exits upward, `PropertyAction` swaps the string mid-flight, position teleports
  below, new text enters. Mirrored in two other files. Our media widgets change
  text by assignment.
- **`common/widgets/LyricsSyllable.qml:159-223`** — a karaoke sweep built from a
  `LinearGradient` whose *start and end points* animate, masked by the text
  itself through an `OpacityMask`, so colour moves through the letterforms.
  Inventive; niche; noted rather than recommended.

### 3.12 The notch: one animated scalar, derived clamped radii

`common/widgets/Notch.qml` is 98 lines of hand-written `Shape`/`ShapePath` with
eight `PathCubic` segments and the circle-approximation constants
`0.5523`/`0.4477` inlined. It has nothing to do with their shape submodule.

Its own animation block is **dead twice over**. All five `Behavior`s (`:92-96`)
set `easing.bezierCurve` without `easing.type: Easing.BezierSpline`, and Qt
refuses a custom curve unless the type is already a spline — so the easing
silently stays Linear. And all three live call sites
(`dynamicIsland/DynamicIslandPanel.qml:1256`, `topLayer/osd/OsdDrop.qml:173`,
`topLayer/search/SearchDrop.qml:215`) pass `disableBehaviors: true`. The fourth
instantiation, `NotchShadow.qml:27`, leaves them enabled and is referenced by
zero files.

The real technique is in the parent (`SearchDrop.qml:220-223`):

```qml
// Grow topRadius from 0 immediately — no dead zone threshold.
// animHeight * 0.8 reaches windowRounding quickly without overshoot.
topRadius: Math.min(_wr, Math.max(0, root.animHeight * 0.8))
bottomRadius: Math.min(_wr, Math.max(0, root.animHeight))
```

**One animated scalar; every radius a clamped function of it** — §3.1 again. The
corner geometry can never outrun the box, so there is no frame at which the
shoulders expose a gap, which is exactly what a separate `Behavior on topRadius`
racing a `Behavior on height` produces. The bottom-bar case is a
`transform: Scale { yScale: -1 }` flip rather than a second path.

The island drives width/height/y with `Easing.OutBack` and **asymmetric
overshoot** — 0.9 when hiding, 0.3 when showing
(`DynamicIslandPanel.qml:1230-1237`) — with a source comment explaining that
`centerInBar` cannot use it because "the notch grows and shrinks in place, so no
bounce can expose a gap".

### 3.13 Two ten-line shape tricks

**Counter-rotation with deliberate desync.**
`common/widgets/MaterialShapeWrappedMaterialSymbol.qml:20-29` spins the shape on
`elementMoveFast` (200ms) while the glyph takes `rotation: 360 - root.rotation`
so it stays upright — and the shape's *morph* runs at `ShapeCanvas`'s 350ms, so
the silhouette is still settling after the rotation lands. We ship a file of the
same name (`modules/common/plugins/designsystem/widgets/MaterialShapeWrappedMaterialSymbol.qml`,
used at `bar/ClockWidgetPopup.qml:124` and `bar/WeatherPopup.qml:74`) and do not
spin it.

**Rate-limited stochastic advance over a coherent subset.**
`modules/settings/SearchBar.qml:126-156` advances the search icon's shape and
adds 45° on every keystroke, behind a 220ms timer that coalesces bursts and
re-fires once if anything was pending. The shape list is deliberately restricted
to 14 roughly-circular members of the 35, so consecutive morphs stay coherent at
any interruption point. Note the limit they did not solve: 220ms is *shorter*
than the 350ms morph, and `ShapeCanvas`'s restart snaps to the last committed
shape rather than to the outline on screen, so fast typing visibly teleports.

### 3.14 What not to take

- **`Notch.qml` itself** — §3.12. A hand-inlined bezier rectangle with a dead
  animation block; the idea is one line of arithmetic.
- **The `shapes` submodule** — §4.2. We left that lineage deliberately, and their
  version has no endpoint short-circuit and no Morph cache.
- **Their per-popup `PanelWindow`** — §5.3. This is the architecture b22a923a5
  ("refactor(bar): delete the per-popup layer surface") removed.
- **Live re-pack on every mouse move.** Their quick-toggle drag calls
  `previewReorderAt` from `onPositionChanged` and re-packs the draft each time.
  They contain the cost carefully (early return when the target index is
  unchanged, cross-page drags skip the repack, `samePayload` swallows no-op
  writes), but the cheaper answer for us is to preview the destination and pack
  once.
- **Reset-and-replay entrance choreography, as a general pattern** — §6.1. It
  looks superb once, destroys the bindings it animates, needs a generation
  counter to survive a fast close→open (`ClockWidgetPopup.qml:221, 254-266`), and
  needs `cardAnim.stop(); cardAnim.start()` because starting a running animation
  is a no-op that "leaves the card stuck invisible" (`InDayForecast.qml:82-87`).
  Take the stagger arithmetic; express the motion as `Behavior`s on declarative
  state.

---

## 4. Where ours is already better

### 4.1 We do have snapping — the brief was wrong, and so was I until I opened the file

The brief for this survey said "We have no snapping at all". That is false, and
recording it is the whole point of the first survey's §2 warning.

`modules/common/widgets/widgetCanvas/AbstractWidget.qml` — the live base class of
every desktop widget, reached through
`modules/imi/background/widgets/AbstractBackgroundWidget.qml:9` — carries:

- a **12px lattice** with per-axis offsets so a subclass can move the lattice
  into the frame its coordinate means something in (`:142-162`), plus the comment
  explaining that `gridSize` is *shadowed* by `PluginWidget`'s span object, so a
  snap written in a subclass silently applies no lattice at all
  (8a534a7da ("fix(plugins): snap a widget's drag to the lattice it is stored on"));
- **snap-then-clamp ordering**, spelled out at `:196-198` because clamp-then-snap
  would round a group-drag leader back off its bound by up to half a cell;
- a **centre-line highlight** with animated colour, width and opacity
  (`WidgetCanvas.qml:246-284`, three `Behavior`s on `elementMoveFast`);
- a **grid overlay** while dragging (`:224-244`);
- **flash lines** on release — created objects fading `0.9 → 0` over 2000ms
  `OutCubic` that destroy themselves (`:303-331`), gated on
  `Config.options.background.showSnapLines` with a settings row at
  `PluginsPage.qml:111`;
- a **marquee rubber band** and group drag with shared clamp bounds (`:286-301`,
  and `AbstractWidget.qml:58-61`).

What we genuinely lack is **widget-to-widget edge alignment** and the
**hysteresis**. That is the accurate version of the gap, and it is what §3.9 is
scoped to.

One wrinkle deserves its own line. A **stale duplicate** of this base class sits
at `modules/common/plugins/designsystem/widgets/widgetCanvas/AbstractWidget.qml`,
and it *does* have widget-to-widget edge snap, gap hints and Photoshop-style live
guides (`:99-276`). It is dead: nothing imports
`qs.modules.common.plugins.designsystem.widgets.widgetCanvas`, that directory has
no `qmldir`, and the design system's `qmldir` does not name it. Its last commit
is f43485e86 ("refactor: rename the shell from \"ii\" to \"imi\""), so it has
missed d2ebb5aeb, b710ef731 and 8a534a7da; it still uses `drag.target` and a
`dragProxy { x: root.x }` binding, the exact pair d2ebb5aeb removed. It also
reads `Config.options.appearance.background.showSnapLines` (`:45`) where the
declared key is `Config.options.background.showSnapLines` (`Config.qml:817`), so
its gate would be `undefined` even if it ran. **Do not resurrect it. Port the
candidate arithmetic into the live file.**

### 4.2 One morph cache, one endpoint short-circuit

The comparison the brief asks for — their `MaterialShape`/`ShapeCanvas` lineage
against our `shape_morph.js` — comes down to three lines.

Theirs (`common/widgets/shapes/`, a git submodule of
`end-4/rounded-polygon-qmljs` pinned at `e31ec4cb`, Apache-2.0, whose README
describes it as a QML port of a TypeScript port of AndroidX's shape library):

- `ShapeCanvas.qml:22` — `property var morph: new Morph.Morph(roundedPolygon, roundedPolygon)`.
  **Every `MaterialShape` in the shell builds an identity Morph at
  construction**, paying the full `match()` pre-pass — measure both polygons,
  feature-map, cut, shift, merge-walk — to interpolate a shape with itself. 245
  of their 1375 files instantiate one.
- `onRoundedPolygonChanged` rebuilds the Morph on **every** shape change with no
  memoisation, so a shape oscillating between two values rebuilds the same
  correspondence every time.
- `asCubics(1.0)` runs the whole 8-way lerp per cubic per frame, with two array
  allocations each; there is no endpoint short-circuit.

Ours (`designsystem/widgets/shapes/shape_morph.js:66-74`):

```js
function at(fromName, toName, t) {
    var clamped = Math.max(0, Math.min(1, t));
    if (fromName === toName || clamped >= 0.999)
        return bounded(shapeOf(toName).cubics);
    var key = fromName + ">" + toName;
    if (morphs[key] === undefined)
        morphs[key] = new MorphLib.Morph(shapeOf(fromName), shapeOf(toName));
    return bounded(morphs[key].asCubics(clamped));
}
```

A Morph is built once **per ordered pair**, both endpoints short-circuit to the
target polygon's own cubics, and both caches live in the returned container so
two widgets calling a shape "panel" never share a Morph keyed on names that mean
different things in each. Beside it, `pinned()` (`:42-46`) exists because the
interpolated cubics' *measured* bounds wobble by a hair at a settle threshold and
a hair of scale reads as a flicker — a failure their per-frame
`calculateBounds()` on the *target* polygon does not have, but only because it
never measures the morph at all, which is why their implicit size snaps while the
outline tweens. e62584f17, enforced by
`test_expressive_design_system.py::test_the_morphing_containers_share_their_mechanics`,
which additionally forbids a widget's shape table from building its own Morphs.

The dependency shape differs in kind. Theirs is a **hard submodule**:
`ShapeCanvas.qml` absent means `MaterialShape.qml` cannot resolve its base type,
which means `Type MaterialShape unavailable` in 241 files including the bar, the
settings window and the whole welcome flow — the shell does not come up, and
there is no `qmldir` shim to make it optional. Ours is vendored in-tree with the
three files that never should have lived upstream added beside it
(`shape_morph.js`, `shape-fit.js`, `path-length.js` — the last from 08341739f
("fix(shapes): Qt measures a dash pattern in line widths, not in path length")).
Vendoring was the right call and is worth keeping: the submodule buys
feature-matched morphing and charges a load-bearing network dependency for it.

### 4.3 …but three of our rounding tokens do not exist

Found by doing the `rounding.scale` comparison. Six live call sites read tokens
`Appearance.qml:227-239` never declares:

| Site | Reads |
|---|---|
| `designsystem/widgets/RippleButton.qml:35` | `Appearance.rounding.button` |
| `designsystem/widgets/MediaCard.qml:19` | `Appearance.rounding.card` |
| `designsystem/widgets/DatePicker.qml:62` | `Appearance.rounding.card` |
| `designsystem/widgets/WeatherCard.qml:18` | `Appearance.rounding.card` |
| `designsystem/widgets/DesktopContextMenu.qml:116` | `Appearance.rounding.extraLarge` |
| `designsystem/widgets/Carousel.qml:27` | `Appearance.rounding.extraLarge - (10 * Appearance.effectiveScale)` |

Measured with a `qml6` probe rather than reasoned about: an undeclared read is
`undefined`, `radius: undefined` renders **0**, and Qt logs one
`Unable to assign [undefined] to double` at binding evaluation — so it is not
entirely silent, but the warning only appears when the component is built and
sits among the shell's ordinary reload noise.

`Carousel` is the worst of the six, because it *arithmetics* on the undefined
value — `undefined - 10` is `NaN` — and `Carousel` is live in three places
(`desktopMenu/DesktopMenu.qml:199`, `dropShelf/DropShelfPanel.qml:169`,
`settings/pages/BackgroundConfig.qml:72`), so its `_listMask` corner radius has
never been rounded.

This is the family AGENT.md already records under "A gate on a `Config.options`
key that was never declared reads as `undefined` and takes the `??` fallback for
ever". Cheap to fix and cheap to lint: sweep for `Appearance.rounding.<name>` and
require the name to be declared.

### 4.4 One spelling of the travel, and checks that hold it

`SpanTravel.qml` and `SpanFade.qml` are four and three lines of body, and their
headers state the count they replaced:

> One spelling, because there were twenty-three: the media tree alone wrote this
> animation out twenty times, and weather and currency each declared a private
> `component TravelBehavior` saying the same thing.

140 uses, and the check that holds them **sweeps rather than enumerates**,
because its first version named three files and five verbatim copies survived in
the package it was written for.

Their tree has no counterpart. `FadeLoader.qml` (18 lines) is the only
token-driven reusable transition in 1257 files; `ErrorShakeAnimation.qml` is the
only other file whose root is an animation type, and every duration in it is a
literal with no easing at all.

The honest caveat: `ShapeCanvas.qml:32-36` is **ours as well as theirs**, with
the same hardcoded `duration: 350` and the same `[0.42, 1.67, 0.21, 0.90, 1, 1]`
copied out of `expressiveFastSpatial` instead of read from it. Our one-tree
widgets route around it — `designsystem/widgets/DesktopWeatherWidget.qml:349`
drives its own `morphT` through `SpanTravel` — but the component still carries a
private copy of a catalogued curve.

### 4.5 A shared interaction model, and two lints that know why

`Appearance.interaction` (`Appearance.qml:341-379`) publishes five states and a
tier per *transition* rather than per state, with the rule written out:

> The press tier is the fastest one there is because a press must be acknowledged
> before anything else; the release is longer AND lands on the spatial curve
> whose control points leave the unit box, so it springs back rather than
> deflating.

`InteractionMotion.qml` writes the tier onto the animation *before* the target in
the same handler, because selecting the tier through a binding on the animation's
`duration` hands the `Behavior` whichever tier was current before the state
changed. Two lints guard the composition rules that follow —
`lint_interaction_motion_double.py`, which is per *channel* so a control that
scales but does not tighten is not held to the radius rule, and
`lint_disabled_opacity.py`.

Against that: 68 copies of `scale: down ? k : (hovered ? k : 1)` across 43 of
their files, no two agreeing, with `tilingAssistant/ZoneIndicator.qml:31`
inverting the convention entirely (rest 0.985, hover 1.0).

### 4.6 One card, one surface, one morph

§5.3 covers this in the bar-widget context. In technique terms: they animate
**ten popup windows**, each with its own open/close animation on a scalar, its
own shadow and its own compositor map/unmap. We animate **one `Rectangle` on one
permanently-mapped masked surface**, and popup contents are reparented into it
(d29cd6e45 ("feat(bar): add the static overlay surface the popup card will live
on"), b22a923a5, 31493a21a). The four properties that make that safe are written
out in AGENT.md's layer-shell section and none is optional.

Our cross-fade also has a detail theirs cannot express, because their two popups
never coexist: the incoming content's fade is preceded by
`PauseAnimation { duration: elementMove.duration - elementMoveEnter.duration }`
(`BarPopupOverlay.qml:405-422`), so the enter lands exactly as the travel
settles, and the outgoing tree is `enabled: false` for the whole cross-fade so a
click mid-morph is aimed at the content the pointer moved toward.

### 4.7 Positioner transitions — shared ancestry, and theirs is slightly ahead

Both trees ship a `StyledListView` with the full set of `ListView` transition
slots, from the same end-4 origin, both built from
`Appearance.animation.elementMove`'s factory, both carrying
`removeOvershoot: 20 // Account for gaps and bouncy animations` and the same
clarifying comment on the most-confused slot:

```qml
// This is movement when something is removed, not removing animation!
removeDisplaced: Transition { ... }
```

Ours (`modules/common/widgets/StyledListView.qml:71-152`) has seven slots and two
enable flags (`animateAppearance`, `animateMovement`), and its `add` is an
opacity/scale fade from 0. **Theirs has eight slots and three flags**
(`StyledListView.qml:12,17,19,97-244`) — it adds `populate` with its own
`animatePopulate`, and a `dismissToLeft` that flips both the entry `from` and the
exit `to`, sizing the overshoot against `Appearance.sizes.notificationPopupWidth`
when the view is narrower than 100px, so a row slides in and out sideways rather
than fading. Their tree also
*uses* positioner transitions more widely: reorder animation on live search
results (`overview/SearchWidget.qml:847-890`), the workspace strip
(`bar/widgets/workspaces/ExpressiveWorkspaces.qml:292-336`), the dock's list with
a three-way suppression guard so a drag reorder cannot fight the view's own move
animation (`dock/widgets/DockListView.qml:36-38`), and two `GridView`s.

I had this the wrong way round in a first draft, and the correction is the point:
this is not somewhere we are ahead. It is somewhere we own the vocabulary and use
it in fewer places — which is worth knowing when reading §3.2 and §3.5, because
**the quick-toggle panel and the bar simply do not draw with a view that speaks
it.**

---

## 5. Half 2 — the time and weather bar widgets

### 5.1 Clock

| | Theirs | Ours |
|---|---|---|
| Files | `bar/widgets/clock/ClockWidget.qml` (207) + `ExpressiveClockWidget.qml` (352); vertical is a third file, `verticalBar/VerticalClockWidget.qml` | `bar/ClockWidget.qml` (198) — one file, four `Component`s inside a `BarWidgetSwitcher` |
| Styles | three: `default`, `material` (a sub-style *inside* `ClockWidget.qml`), `expressive` (a separate file). `Config.options.bar.styles.clock`, shipped default `"expressive"` | two: default and material, on `Config.options.bar.cornerStyle === 3` |
| Orientation | `ClockWidget` is horizontal-only, `BarComponent` routes vertical elsewhere; `ExpressiveClockWidget` carries both | one file: `colDefault` / `colMaterial` / `rowDefault` / `rowMaterial`, picked by `BarWidgetSwitcher` |
| Extras on the widget | a LocalSend attach chip; a `DropArea` for `text/uri-list` with a breathing drop overlay | none |
| Widget-level motion | attach-chip `scale` pop (250ms `OutBack`), drop-overlay fade (150ms `OutQuad`), drop-icon 1.0↔1.25 breathing loop | **none.** No `Behavior` anywhere in the file |
| Style switch | `Loader.sourceComponent` swap, no cross-fade; the consequential width change is absorbed by `BarComponent.qml:167-174` (250ms `OutCubic`) | `Loader.sourceComponent` swap, no cross-fade, and **no width Behavior either** — `common/widgets/BarWidgetSwitcher.qml` has no animation at all |

**Their popup** is a different order of ambition: a 200px decorative analog
header whose 90 tick marks rotate once per minute
(`RotationAnimation on rotation { from: 0; to: 360; duration: 60000; loops: Animation.Infinite }`,
`ClockHeaderCard.qml:137-142`) and which blurs only its top-left corner with two
`RadialGradient`s feeding a `MaskedBlur`; a horizontally scrolling world-clock
strip with per-zone offsets fetched by shelling out to `TZ='…' date`; a
timer/stopwatch/pomodoro pill; a LocalSend transfer card; and a full alarms
section with an inline add/edit form, a ringing pulse, and `ListView`
add/remove/displaced transitions.

**Ours** (`bar/ClockWidgetPopup.qml`, 224 lines) is a month/year header, a
seven-day week strip with today highlighted, a `MaterialShapeWrappedMaterialSymbol`
task badge, up to two pending-todo cards, and an uptime line. It is a good, dense
card. It contains **zero animation declarations** — all of its motion is the
shared card morphing around it.

Where each is better:

- **Theirs, content:** world clocks, alarms, and a pomodoro/stopwatch control are
  three things our clock popup does not have. (Our timer surfaces separately, as
  `bar/TimerPill.qml`.)
- **Theirs, motion:** the header's minute-long tick rotation is the only
  *ambient* motion in either clock popup — a clock that is visibly running rather
  than one that redraws. It costs one `RotationAnimation`.
- **Ours, correctness:** their `WorldClocksCard.qml:198` ships
  `text: "18°" // Mock placeholder temperature` — hardcoded fake weather in a
  released card. Their `WorldClocksCard.qml:52-72` declares a `Connections`
  handler for `onPopupOpenProgressChanged` on an `Item` that has no such
  property, so that reset never fires. Their `ClockWidget.qml:13` yields `NaN` if
  its `Loader` is inactive, saved only by the routing. Their
  `ClockWidget.qml:65-68` writes an exit `Behavior on scale` that can never play,
  because `visible: false` removes the item first.
- **Ours, structure:** one file for four layouts against their three files for
  three styles plus a fourth for vertical — and their `styles.clock` is read in
  three separate places (`BarWidgetRegistry.qml:16`, `BarComponent.qml:262`,
  `:274`) plus inside the widget, which is the "one derivation" rule AGENT.md
  already pins for the dock's edge.

### 5.2 Weather

| | Theirs | Ours |
|---|---|---|
| Widget files | `bar/widgets/weather/WeatherBar.qml` (60) + `ExpressiveWeatherBar.qml` (160) | `bar/WeatherBar.qml` (142), one file |
| Provider | Open-Meteo, keyless, one request for current + daily + 3-hourly | two: OpenWeatherMap (needs a key) or wttr.in (keyless), `services/Weather.qml:22` |
| Forecast in the bar popup | daily (7 cards) **and** hourly (a 5-bar chart) | **none.** `bar/WeatherPopup.qml` is current conditions plus six metric cards; `Weather.forecast` is read only by `designsystem/widgets/DesktopWeatherWidget.qml:126` |
| Popup metrics | 4 (sunrise, sunset, precipitation, humidity); UV, wind, pressure, visibility and feels-like are fetched and never shown | 6 (rain, wind, precipitation, humidity, visibility, pressure) plus sunrise and sunset in the hero |
| Condition glyph | a static Google Weather SVG; `getWeatherIcon(code, false)` — `isNight` is hardcoded false, so the night variants are dead | `Icons.getProviderWeatherIcon(Weather.provider, wCode, Icons.isNight())` — provider-aware *and* night-aware (`WeatherPopup.qml:82`, with the comment recording why) |
| Widget motion | none beyond the shared chrome | none |
| Popup motion | a four-level nested choreography, ~1.4s end to end | none of its own |

**Their choreography, measured.** Surface: 50ms pause, then `animProgress` 0→1
over 380ms `OutQuart`, driving a fade, a 35px slide out of the bar, and the
hero-height unroll of §3.1. Content gate at 60% of that. Section stagger
40/100/160/220ms by *visible* index. Then inside each section: the hero blob
unwinds −15° over **1120ms** `OutCubic` while scaling 0.8→1.0 `OutBack`; the five
hourly bars grow from zero height, 450ms `OutCubic`,
`transformOrigin: Item.Bottom`, 60ms apart; the seven day cards slide 50px from
the right 120ms apart with a 200ms head start, each with its shape blob popping
0.7→1.0 `OutBack`; the four metric tiles cascade 0/60/120/180ms with a further
internal 60/120/180ms icon/title/value ladder.

It is the most elaborate motion in either tree, and its two flaws are structural
rather than tuning: the bar chart animates on *open* and never on *data* (§3.3),
and `StyledText.animateChange` is never switched on anywhere in the feature
(§3.11), so both the bar temperature and the 48px hero temperature hard-cut on
every refresh.

**Ours.** `bar/WeatherBar.qml` is a `MouseArea` with a `Loader` picking
`rowContent` or `colContent`, right-click to refresh, and no animation. Its popup
is a gradient hero card (`colPrimaryContainer` → `colSurfaceContainerLow`), a
`MaterialShapeWrappedMaterialSymbol` at `MaterialShape.Shape.Sunny`, sunrise and
sunset rows, and a 2-column `GridLayout` of six `WeatherCard`s
(`bar/WeatherCard.qml`, 54 lines). Again: no animation declarations. Everything
moves because the card underneath it morphs.

Note where our weather motion actually lives, since it is not in the bar.
`designsystem/widgets/DesktopWeatherWidget.qml` (663 lines) is a one-tree
morphing widget across four spans, with a sun-arc curve whose `horizonY` and
`apexRise` travel on `SpanTravel`, a sun marker riding
`SunArc.curveY(u, window, horizonY, apexRise, tailFlatten)` — which becomes
`bedtime` below its own horizon and has two separate reasons to be invisible,
deliberately kept separate (`:307-321`) — and a glyph container morphing between
three named shapes (`leaf`, `panel`, `ghostish`) through the gated `morphT` idiom
(`:340-395`). Nothing in their tree is comparable. **The gap Half 2 found is the
bar popup specifically, not weather motion.**

Where each is better:

- **Theirs:** the hourly chart, the daily strip, the entrance choreography, and a
  keyless single-request provider.
- **Ours:** provider-aware and night-aware icon selection; two providers, one of
  them keyless; six metrics rather than four; no hardcoded mock data. And ours
  has an *hourly-shaped hole* rather than a wrong one — their
  `hourlyData[i].time` is `(i % 24) * 100`, derived from the array index rather
  than from the API's own `hourly.time`.

### 5.3 The popup host — the real difference in Half 2

Both trees name the type `StyledPopup`. They are opposite designs.

**Theirs** (`bar/shared/StyledPopup.qml`, 667 lines) is a `LazyLoader` whose
component is a `PanelWindow`. Every popup is its own layer surface, created on
hover and destroyed on close, with content reparented in at
`Component.onCompleted` and explicitly detached at `Component.onDestruction`
because the `LazyLoader` outlives the window. Because each surface is sized to
its own content, the hero unroll and the shrink-toward-the-bar close
(`contentContainer.closeScale`, origin travelling to the bar edge, `:502-547`)
are natural. The input region is deliberately decoupled from the animation via a
separate `maskRect`, because `Region` does not observe a `Translate` — the same
fact AGENT.md records from the other side, that `PendingRegion::setItem` connects
only x/y/width/height.

**Ours** (`common/widgets/StyledPopup.qml`, 138 lines) owns no surface at all: it
is a declaration plus a hover state machine claiming `GlobalStates.activeBarPopup`.
`bar/BarPopupOverlay.qml` (537) is one always-mapped `Overlay` surface per screen
carrying a single `Rectangle` that every popup morphs into. Ten surfaces, ten
shadows and ten compositor map animations became one of each.

The trade, plainly:

- **Ours wins on the transition *between* popups.** Moving the pointer from the
  clock to weather morphs one card — position, size, and a cross-fade timed so
  the enter lands as the travel settles (§4.6). On their side that is a window
  destroy and a window create, each with its own 380ms open.
- **Theirs wins on the transition *within* one popup.** A per-popup surface makes
  the unroll, the origin-travelling close contraction and per-card choreography
  straightforward. On a shared card they are harder, because the card's geometry
  is assigned rather than bound (`:187-189`) and the content is centred in a
  clipped host (`:528-533`).

That is Half 2's motion story in one line: **we morph between popups; they
choreograph inside them.** Both are worth having, and §3.1 and §3.3 are the two
cheapest steps toward the second without giving up the first.

---

## 6. Conflicts with one-tree morphing

Our vocabulary, for reference: shared elements are declared **once** and travel
between per-span geometry rects on `Behavior`s (`SpanTravel` for what exists on
both sides, `SpanFade` for what does not — a `null` rect means a fade, never a
morph, `weather_geometry.js:8-9`); geometry derives from the span **name**, never
from an animating `implicitWidth` (189caa6ff ("fix(weather): geometry reads the
settled span, not the animating box")); and there is exactly one spelling of the
travel.

Four of their techniques cannot be expressed in it. These are conflicts to name,
not defects to fix.

### 6.1 Reset-and-replay entrance choreography

Their whole popup idiom: on a state edge, imperatively slam every child's
`opacity`, `scale` and `Translate.y` to a start value, then fire a
`SequentialAnimation` from `Qt.callLater`.

One-tree motion is the opposite premise. Elements are *continuously* somewhere,
and where they are is a pure function of the settled span. An imperative reset
writes over the property a `SpanTravel` owns, which destroys the binding — which
is exactly the failure their own `barHeightAnim` demonstrates (§3.3). **These do
not compose.** If we want an entrance, it has to be expressed as a span: an
"entering" state whose rects are the offset ones, with the travel to the real
rects doing the work. That is more code than their version, and it is the only
version that survives an interruption — which their own tree pays for with a
generation counter and a `stop(); start()` workaround.

### 6.2 `ShapeCanvas`'s Behavior-toggle restart, as a general primitive

Their four-line idiom —

```qml
morphBehavior.enabled = false;
root.progress = 0;
morphBehavior.enabled = true;
root.progress = 1;
```

— is genuinely reusable, and **we already use it, deliberately, in exactly one
place**: `DesktopWeatherWidget.qml:354-364`, with a comment naming it as "the
ShapeCanvas idiom, cited and then not copied" and spelling out why the gate is
load-bearing (written through a live Behavior, `morphT = 0` *retargets* toward 0
instead of resetting, and the shape flips at nearly full `morphT` — a snap
wearing a morph's clothes).

The conflict is with adopting it *generally*, because interrupting it teleports:
the new `Morph` is built from the last **committed** shape, not from the outline
on screen. Inside a one-tree widget every other channel retargets from where it
actually is, so a morph that snaps while its container travels smoothly is the
one element that reads wrong. Keep it scoped to a shape's `t`, gated, and nowhere
else.

### 6.3 Per-style widget files

Their bar has `ClockWidget` / `ExpressiveClockWidget` / `VerticalClockWidget` as
three files a `Loader` swaps between, and the same for weather. That is the
pattern one-tree morphing exists to replace — the same reasoning as
"feat(calendar): morph the calendar in one tree instead of rebuilding it". A
destroyed subtree cannot travel.

Our `BarWidgetSwitcher` is only half a step better: one file, but still a
`Component` swap, so a style change is still a rebuild. Adopting their split
would be a step backwards, and it is why none of §5's style machinery is in the
ranked list.

### 6.4 Their morph cannot be a card body

`WidgetCard`'s `shapeName` already turns our card into a stretched
`MaterialShape`, and it morphs on any shape change because `ShapeCanvas` does
(b362d8c80 ("feat(widgets): one card component for the surface every widget
redrew")). Their `Notch` is a hand-written `Shape` with a `CurveRenderer`, not a
polygon, so it cannot be a `shapeName` and cannot morph into or out of any of the
35. A notch in our tree would be a **second, parallel outline mechanism** — a
real cost, and the main argument against §3.12 beyond the arithmetic.

### 6.5 One near-conflict that is not one

**Their snap does not fight one-tree.** Both trees already hold the same rule for
the same reason — a `Behavior` on a property something else writes every frame
must be off. Theirs sets `isDraggingOrSettling` at *press*, before the first move
(`:291`); ours gates on `animatePosition && !dragging && !groupDragging`
(`AbstractWidget.qml:245,250`), with the reason written out at `:12-21`. Their
350ms `settleTimer` exists because their release round-trips the position through
`Config`, which we do differently — but the pattern of clearing the guard *before*
writing the corrective value, so the drop is instant and a late correction glides,
is worth copying if §3.9 lands.

---

## 7. Findings in our tree, surfaced by the comparison

None of these were fixed here — this is a research branch. Each is worth its own
issue. All four were verified by opening the file.

1. **Three undeclared rounding tokens, six call sites** (§4.3). `Carousel`'s is
   `NaN`, and `Carousel` is live in three surfaces.
2. **A stale duplicate of the desktop-drag base class** in the design system
   (§4.1) — three fixes behind the live one, still using the `drag.target` +
   `dragProxy { x: root.x }` pair d2ebb5aeb removed, and gated on an undeclared
   config path. It is unreachable; the risk is someone finding its richer snap
   code and assuming it runs.
3. **`Appearance.effectiveScale` is a hardcoded `1.0`** (`Appearance.qml:13`),
   multiplied through dozens of call sites in the design system and the bundled
   widgets. Its comment gives a fair reason for the *value* — the shell already
   applies compositor scaling — but it is exactly the *shape* their
   `rounding.scale` has, sitting inert. §3.7 should decide whether it becomes
   real or goes.
4. **`ShapeCanvas.qml:32-36` carries a private copy of a catalogued curve**
   (§4.4): `duration: 350` and `[0.42, 1.67, 0.21, 0.90, 1, 1]` are
   `expressiveFastSpatialDuration` and `expressiveFastSpatial` written out by
   hand, so a shape morph is the one animation in the shell that cannot be
   retimed from `Appearance`. Fix it as part of §3.6, not after.

---

## Appendix — method, and what was verified how

Read in full before starting, per their own instruction: `AGENT.md` (2,259 lines)
and `CONTRIBUTING.md` (433), sequentially, plus the existing survey
`docs/p3drovfx-research-2026-08-16.md` (751).

Their tree was read by seven parallel read-only investigations — the shape/morph
lineage and its submodule; the token and animation catalogue; the quick-toggle
edit model; the desktop drag and snap; the clock widget and popup; the weather
widget and popup; and a tree-wide sweep for animation idioms outside the
`Behavior on` norm — each instructed to open files rather than grep, and to quote.

**Our side was read by hand, not searched**, because that is the failure the
first survey recorded. Opened and read in full: `Appearance.qml`, `SpanTravel.qml`,
`SpanFade.qml`, `shape_morph.js`, `shapes/ShapeCanvas.qml`, `bar/ClockWidget.qml`,
`bar/ClockWidgetPopup.qml`, `bar/WeatherBar.qml`, `bar/WeatherPopup.qml`,
`bar/WeatherCard.qml`, `common/widgets/StyledPopup.qml`, `bar/BarPopupOverlay.qml`,
`common/widgets/BarWidgetSwitcher.qml`,
`common/widgets/widgetCanvas/AbstractWidget.qml` (**both** the live one and the
stale design-system copy, which is how §4.1 was caught),
`common/widgets/widgetCanvas/WidgetCanvas.qml`,
`background/widgets/AbstractBackgroundWidget.qml`,
`sidebarRight/quickToggles/AndroidQuickPanel.qml`,
`sidebarRight/quickToggles/androidStyle/AndroidQuickToggleButton.qml`,
`common/widgets/StyledListView.qml`, `common/widgets/StyledSlider.qml`,
`common/widgets/DockIconMotion.qml`, `bar/Bar.qml`'s window block, and the
relevant parts of `designsystem/widgets/DesktopWeatherWidget.qml` and
`designsystem/widgets/Carousel.qml`.

Three claims were settled by measurement rather than by reading:

- **`radius: <undeclared>` renders 0 and warns** — a `qml6` probe under
  `QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1` (AGENT.md's rule about a
  probe's output going to the journal), which printed
  `undeclared read -> undefined undefined`, `rect radius -> 0`, and
  `Unable to assign [undefined] to double`.
- **Which of the two `AbstractWidget.qml` files runs** — `git log` on each (the
  live one carries 8d079880d, 23c67d587, 37236c1b3; the design-system copy
  carries only the rename), plus a grep proving nothing imports the design-system
  path and no `qmldir` names it.
- **The §1.3 counts** — the same commands run over each tree's `modules/`
  directory, reproducible.

One claim in an earlier draft of this document was wrong and is corrected in
place rather than deleted: §4.7 first said their tree used positioner transitions
in one place. It uses them in at least six, and their `StyledListView` has one
more slot and one more enable flag than ours.

The sandboxed nested-Hyprland instance of their shell that was running on this
machine was not touched, and no `hyprctl` was run.
