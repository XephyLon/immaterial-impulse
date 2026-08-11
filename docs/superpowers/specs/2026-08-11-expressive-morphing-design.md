# Expressive morphing, and a motion model for interaction — design

**Status:** design, not implemented
**Scope:** the bundled `nandoroid-media` widget first; `modules/common/plugins/` and
`modules/common/widgets/` once the reusable parts are extracted

Paths are relative to `dots/.config/quickshell/imi/` unless written repo-relative.

## Problem

Resizing a widget currently *replaces* its contents. `nandoroid-media/Widget.qml` holds a `Loader`
whose `source` is a per-span URL, so changing span destroys `LayoutLarge` and constructs
`LayoutCookie`. The play button at 3x2 and the play button at 2x2 are different objects that have
never coexisted.

The animated resize added in #171 makes the *box* travel and cross-fades the content at the midpoint.
That is the best a destroy-and-rebuild can do, and it is exactly the effect being rejected: the
controls disappear and different ones appear. A user watching a resize should see the play button
*move and change shape*, not vanish.

> "These elements should not disappear, they should morph into their location and style on the other
> size. It's more of a cohesion thing."

Second, unrelated to size: interaction feedback is per-component and ad hoc. `RippleButton` animates
a ripple and swaps its radius on press; other controls do less, or something different. Every state
change — hover in, hover out, press, release — should read as motion, and the same motion everywhere.

## Settled input

- **One reflowing tree.** Each widget is a single tree whose elements are *repositioned and restyled*
  per span. Nothing is created or destroyed by a resize.
- **Media first, framework second.** Build it on the media widget; extract the reusable parts once
  they have proven themselves on a real case rather than an imagined one.
- **Shared set:** transport controls, artwork, and progress/seek. Title and artist are *not* shared —
  they exist only at 3x2, so they enter and exit.
- **Shared interaction-state model, retrofitted gradually.** One vocabulary, adopted by
  `RippleButton` and the media controls first.

---

## 1. One tree, spans as bindings

`LayoutLarge.qml`, `LayoutCookie.qml` and `LayoutCompact.qml` collapse into one tree. Each shared
element's geometry and style become functions of the span:

```qml
MediaButton {
    id: playButton
    role: MediaButton.Play
    x: MediaGeometry.playRect(root.span).x
    y: MediaGeometry.playRect(root.span).y
    // …width, height, shape
    Behavior on x { NumberAnimation { /* expressive spatial */ } }
}
```

**The cost, stated plainly:** three readable files become one denser one, and per-size layout work
stops being separable. That is the price of the elements surviving, and it is not recoverable by
being clever — a `Loader` is a destroy. It is worth it only if the geometry lives in a testable
module rather than inline, so the file holds *structure* and the module holds *numbers*.

So: `media_geometry.js` returns, for a span, the rect and shape of every shared element. Pure,
therefore testable, and it is the only place a size's layout is decided.

### What still cross-fades

Unshared content — title, artist, the lyrics affordance — has nothing to morph into. It fades and
scales on the span change, which is what #171 already does for whole layouts; the mechanism stays,
its scope narrows to the elements that genuinely appear and disappear.

## 2. Shape morphing is already available

`shapes/morph.js` implements Material 3's shape morph: it matches features between two rounded
polygons and interpolates their cubics at a progress value. `ShapeCanvas` already drives it, with a
350 ms transition on every polygon change.

So a control that is a pill at 3x2 and a cookie at 2x1 does not need a new mechanism — it needs its
start and end polygons handed to a `Morph` and a progress driven by the same curve as the geometry.

Two cautions:

- `ShapeCanvas` starts its own 350 ms transition on *every* polygon change. During a resize the shape
  and the position must move on **one** clock, or the button arrives before it finishes becoming
  round. The morph progress should be driven by the resize, not by a second timer.
- Per-frame geometry regeneration was measured at 0.59 ms per shape and four animating cookies held
  62 fps (#161). Several morphing controls at once is a different load; measure before assuming.

## 3. Progress: decided — an inner wavy ring at 2x2

**Decision (2026-08-12):** 2x2 gains a seek ring *inside* the cookie, carrying the **same travelling
wave** as the 3x2 straight bar.

Both halves matter, and the second one changes the engineering.

### Inside, not on the outline

The earlier recommendation was a ring on the cookie's own outline. Inside is better: at 2x2 the
cookie outline *is* the widget's edge, so stroking it as progress reads as a border, and it would
contend with the container's own shape morph during a resize. An inset ring is independent geometry
that can morph freely without fighting the shape it sits in.

### The wave makes it one renderer, not two

This spec previously said a true path morph between the 3x2 wave and a ring was "a research problem,
not a sprint", and proposed cross-fading two renderers. **That is wrong once the ring is wavy.**

`WavyLine.qml` is a displacement normal to a baseline, parameterised by distance along it:

```qml
waveY = centerY + amplitude * Math.sin(frequency * 2 * Math.PI * x / root.fullLength + phase);
```

Nothing there requires the baseline to be straight. Substitute a path for the segment and the same
expression holds — and `path-length.js` already measures arc length along cubics
(`measureCubics`), which is precisely the parameter it wants. So:

| Span | Baseline | Renderer |
| --- | --- | --- |
| 3x2 | a straight segment | wave along a baseline |
| 2x2 | an inset closed ring | wave along a baseline |
| 2x1 | the play button's cookie outline | wave along a baseline |

One renderer, three baselines. The morph is then a morph of the *baseline* — geometry the shape
system already handles — rather than a cross-fade between two ways of drawing.

### It is mostly assembled already

- `WavyLine.qml` — the wave, animated by a `FrameAnimation` calling `requestPaint` (the wave is a
  `Canvas`, which repaints on resize and nothing else, so the driver is not optional).
- `SineCookie.qml` — a sine-modulated *closed* cookie, proving the wrapped case. It fills rather than
  strokes, and the clock is its only caller, so stroking it is the delta.
- `path-length.js` — arc length and `dashInPenWidths`, already driving the 2x1 ring's progress.

The wavy ring is the intersection of those three, not new invention.

### One question this raises, for the user

The 2x1 ring is a **plain** stroke today, and per `LayoutCompact.qml:97` it deliberately doubles as
the play button's border. If 3x2 and 2x2 are wavy and 2x1 is not, the wave enters and exits across a
resize — the exact discontinuity this whole design rejects.

Two ways out:

- Make the 2x1 outline wavy too. Consistent, but it changes how that button looks, and the button is
  already reviewed and shipped.
- **Animate `amplitudeMultiplier` to 0 at 2x1** so the wave flattens into the border. A flat wave *is*
  the current plain stroke, so this is continuous, needs no special case, and the property already
  exists and is already animatable. **Recommended.**

## 3b. Weather is the second case, and it sharpens the requirement

The media widget is not special. `DesktopWeatherWidget.qml` does the same thing with inline
components rather than files:

```qml
Loader {
    sourceComponent: sizeMode === "1x1" ? mode1x1Layout
                   : sizeMode === "2x1" ? mode2x1Layout : mode3x1Layout
}
```

One file, three `Component`s, one `Loader` — still a destroy. (An earlier note in this project said
weather "switches layout within one file" as though that made it closer to the target. It does not;
the swap is the same.)

Its weather-icon container is the clearest example of what the user means by cohesion, and it is
already *designed* as a morph across the three sizes:

| Span | The glyph's container |
| --- | --- |
| 3x1 | `MaterialShape { shape: Ghostish }` — an asymmetric wavy shape |
| 2x1 | `Rectangle { radius: 30 }` — a tall squircle |
| 1x1 | `Rectangle { radius: 16 }`, clipped by the card so it peeks from the corner |

**These are three different component types, not one component in three states.** A `Rectangle`
cannot morph into a `MaterialShape`: different renderers, no shared geometry. So persistence is not
enough on its own —

> A shared element must be **one component whose shape is a parameter**, not several components that
> happen to resemble each other.

Which is what `shapes/morph.js` already assumes: it interpolates between two *rounded polygons*. A
squircle and Ghostish are both expressible that way; a `Rectangle` with a `radius` is not, until it
is re-expressed as one.

### The morph already ships, and it is one property

This is not a mechanism to be built. Turn on **Wallpaper & Desktop → Centered wallpaper** and change
the shape: it morphs. The whole of it is

```qml
MaterialShape { shape: bgRoot.centeredWallpaperShape }   // Background.qml:950
```

because `ShapeCanvas` morphs on *any* polygon change, unprompted:

```qml
root.morph = new Morph.Morph(root.prevRoundedPolygon ?? root.roundedPolygon, root.roundedPolygon);
morphBehavior.enabled = false; root.progress = 0;
morphBehavior.enabled = true;  root.progress = 1;
```

So "one component whose shape is a parameter" is not a new pattern to invent — it is the pattern
already on screen, and the morph comes free the moment the component stays alive. That collapses the
weather work from *construction* to **conversion**: re-express the 2x1 squircle and the 1x1 clipped
corner as `MaterialShape`s, bind `shape` to the span, keep the item alive. Nothing else is required
for the outline to morph.

What is left is genuinely weather-specific and not free: the **clip**. The 1x1 glyph is cut by the
card, and clipping is the parent's property, not the shape's — no polygon interpolation expresses it.
That is the one part of the weather case with no existing answer, and media has no equivalent.

### One caution, from the same snippet

That reset is a *restart*, not a retarget: it disables the `Behavior`, slams `progress` to 0, and
re-enables. A shape change arriving mid-morph therefore snaps back to the start instead of
continuing from where it is. For the wallpaper shape picker that is invisible — nobody changes shape
twice in 350 ms. During a resize it is reachable: drag a grip through two spans quickly and the
outline jumps. §4 requires every transition to be interruptible; the shape morph does not currently
meet that bar, and making it retarget is a change to `ShapeCanvas` shared with the wallpaper.

The order this implies: media proves the architecture, weather proves the *shape* half — and since
the shape half turns out to be mostly conversion, weather is the cheaper of the two to land once the
one-tree structure exists.

## 3c. The shared card, and why it comes first

**Settled with the user (12 Aug):** widgets draw their surfaces from a shared component library.
Three constraints came with that, and each one shapes the component:

- **The card does not own frost.** `nandoroid-system-monitor` has *three* frosted cards and no outer
  container, so a widget has zero, one or many. Frost stays a widget-level declaration
  (`blurRegions`) that points at whichever cards exist.
- **Desktop widgets and bar popups are different.** This library is desktop widgets only. A bar popup
  is not a card with different numbers in it.
- **`calendar` gets rebuilt to match** once the architecture is settled on media and weather. Its
  divergence is a defect to correct, not a parameter to preserve.

So the abstraction is a **card**, not a "widget container" — a widget composes some number of them.

### The evidence it should be shared, which is not the same as speculation

The spec's step 8 defers extraction until a real case has proven what is generic. That rule does not
apply here, and it is worth saying why rather than quietly breaking it. It guards against inventing
an abstraction for something that exists *once*. The card already exists four times:

| file | container |
| --- | --- |
| `DesktopWeatherWidget.qml:83` | `Rectangle`, `radius: 30 * Appearance.effectiveScale` |
| `DesktopCurrencyWidget.qml:92` | identical |
| `nandoroid-media/LayoutCookie.qml:91` | identical |
| `calendar/Widget.qml:212` | `Appearance.rounding?.verylarge ?? 30`, and a different colour |

Three copies and one that has **already drifted**. Deduplicating a demonstrated repetition is
evidence-driven; that is a different act from inventing an interface for an imagined one.

### Frost is a rounded rectangle, and a morphing card is not

This is the constraint that decides the component, and it is not obvious from the outside. A blur
region is not data handed to the compositor — `WallpaperBlurSurface` builds an `OpacityMask` whose
`maskSource` is a `Rectangle`:

```qml
readonly property Rectangle _mask: Rectangle { radius: root.cornerRadius }
layer.effect: OpacityMask { maskSource: root._mask }
```

and `PluginWidget:381` feeds it region records of `{x, y, width, height, radius}`. **A frosted card
can therefore only ever be a rounded rectangle.** Morph one into a cookie and the frost stays a
rounded rect behind it — the blur stops following the outline, visibly, at exactly the moment the
shape becomes interesting.

The fix belongs in the blur surface rather than in the cards: `OpacityMask` does not care what the
mask *is*, only that it has alpha. So

- a card exposes its own mask item, and a `MaterialShape` serves as one unchanged;
- a region record gains an optional `mask`, and `WallpaperBlurSurface` prefers it, falling back to
  the radius `Rectangle` when absent.

That keeps every existing caller working — including the three system-monitor cards, which have no
reason to stop being rounded rectangles — while making a morphing frosted card expressible at all.

### Why this lands before the media work

It is the cheapest step in the whole plan and the least likely to break anything: mechanical,
adoptable one widget at a time, and each adoption leaves the tree working. Media then gets built on
the card rather than the card being reverse-engineered out of media afterwards. It also front-loads
the decision that the rest depends on — that a surface's shape is a *parameter* — at the level where
it is easiest to prove.

## 4. A motion model for interaction

One vocabulary, in `Appearance`, for the states every interactive element passes through:

| Transition | Reads as |
| --- | --- |
| rest → hover | a lift: subtle scale and container tint |
| hover → rest | the same, reversed, slightly slower |
| hover → pressed | a settle: scale down, corner radius tightens |
| pressed → released | a return that overshoots slightly, on a spring |
| any → disabled | opacity only, no motion |

The rules that make it feel like one system rather than five animations:

- **Every transition is interruptible.** A press during the hover-in must retarget from wherever it
  is, not restart. `Behavior` does this; a `SequentialAnimation` triggered on a signal does not.
- **Press is acknowledged immediately.** The press-down curve is short (the shell's `elementMoveFast`
  tier); the release may be slower.
- **Release animates even when the pointer has left.** A press that ends outside the control still
  returns, or the control is left visibly stuck.

`RippleButton` already owns `hovered`, `down` and a ripple; it becomes the first adopter rather than
being replaced. The media controls are the second. Everything else follows later — the point of
"gradually" is that a 158-site sweep is a separate, mechanical piece of work, and mixing it with a
new motion model would make both unreviewable.

## 5. What this replaces

#171's midpoint content swap is superseded **for shared elements**. Its box animation, its clamp
handling and its stored-position repair all stay — those are about the widget's own rect and are
orthogonal. This narrows the fade to unshared content; it does not undo the work.

## 6. Risks worth naming before building

- **A `Behavior` whose target moves every frame never ticks.** This has already shipped twice in this
  repo (the parallax opt-out; nearly again in #171). Span-driven targets are discrete, so the
  geometry is safe — but a morph progress driven by a continuously-changing source is exactly the
  shape that fails, silently, looking like no animation at all.
- **One tree means every element is always alive.** The 2x1 currently constructs no artwork and no
  visualiser; in a reflowing tree they exist at zero opacity unless explicitly unloaded. That is a
  cost in bindings and in cava claims — a `VisualizerCookie` holding a `CavaRef` at 2x1 would run
  cava for a size that shows no visualiser.
- **Interruptibility is the thing that will be got wrong.** Resizing mid-hover, pressing mid-resize,
  releasing after the span changed under the pointer — each is a state the model must survive, and
  none of them are reachable from a unit test.

## 7. Testing

Reachable, and therefore where the value is:

- `media_geometry.js` — every shared element's rect and shape per span, pure, driven from a QML
  `TestCase`. This is the majority of the correctness.
- The interaction-state model's timing/curve selection, if expressed as data rather than inline
  animations.
- The runtime harness (`qs -p` + headless weston) can assert a property is **strictly between** its
  endpoints mid-transition — the check that distinguishes a live animation from a snap, and the one
  that catches a dead `Behavior`. #171 established this pattern; reuse it.

Not reachable, and must not be faked: how any of it *looks*. `qmltestrunner` cannot construct
Quickshell types and the software scene graph draws no `Canvas` or `ShaderEffect`. Offscreen
rendering to a PNG is legitimate for geometry questions and has already caught a real bug (the
seek-ring dash pattern).

## 8. Landing plan

Each step leaves the tree working and is separately reviewable on screen.

1. The shared card: one component, shape as a parameter, plus the optional-mask change to
   `WallpaperBlurSurface`. Weather, currency and media adopt it; `calendar` follows later. Nothing
   morphs yet - this step only removes the duplication and makes the shape expressible.
2. `media_geometry.js` + tests. No caller.
3. Media collapses to one tree, **no animation** — every span still renders correctly, statically.
   This is the risky structural step and is worth reviewing alone.
4. Behaviors on the shared elements' geometry. Resize now morphs position and size.
5. Shape morphing for the transport controls, on the resize's clock.
6. Progress: the wave gains a path baseline, then the 2x2 inner ring and the 2x1 amplitude
   fade. No renderer cross-fade - §3 removed the need for one.
7. The interaction-state model in `Appearance`; `RippleButton` adopts it.
8. Media controls adopt it.
9. Extract whatever is genuinely generic into the widget framework — *after* steps 2-8 have shown
   what that is.

Steps 2-3 are the ones that could go wrong quietly. Step 9 is deliberately last: the framework is
derived from a working case, per the settled input — with the card as the one exception, for the
reason given in §3c.
