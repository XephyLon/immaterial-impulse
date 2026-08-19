# Expressive morphing, and a motion model for interaction — design

**Status:** implemented (v0.24.0; `b88c5a018` landed the shared `WidgetCard`/`MediaCard`/`WeatherCard`). Two items remain narrower than designed: the calendar rebuild uses `calendar_geometry.js` but not `WidgetCard`, and the interaction-model retrofit reaches `RippleButton`, `MediaTransportButton` and `DockIconMotion` only.
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

### Decided (12 Aug): the 2x1 outline waves too, and the button waves with it

The alternative was flattening `amplitudeMultiplier` to 0 at 2x1 so the wave resolved into a plain
border. Rejected: the wave is present at every span, so nothing about it enters or exits.

The stronger half of the decision is that **the button and the seeker animate as one thing.**
`LayoutCompact.qml:97` already describes the arrangement this needs — the button body and the seek
ring are *two concentric draws of one cookie outline*, the body inside the ring so the stroke reads
as the button's border rather than a line laid across its edge. The wave therefore belongs to that
shared outline, and both draws sample it at the same phase. The button breathes with the track
instead of sitting still inside something that moves.

That makes the seeker a property of the button's own geometry, not an overlay on it, and it is the
clearest statement in the whole design of what "one renderer, three baselines" buys.

### The arc-length trap, and the constraint that avoids it

`outlineLength` is measured **once**, and the comment says why: *"the shape never changes, so a
moving progress costs a dash pattern rather than a re-measure."* A wavy outline breaks that premise —
if the shape moves, its length moves, and `dashForProgress` divides by a total that is now a lie. A
progress of 50% would drift against the actual halfway point of the path, visibly, as the wave
travels.

Re-measuring every frame is the obvious escape and the wrong one: `measureCubics` samples every
cubic, and it would run per frame per widget.

The cheap escape is a constraint on the wave rather than a change to the measuring. A travelling
wave is a *phase* shift, and phase-shifting a periodic modulation around a closed loop leaves its
arc length unchanged **provided a whole number of wavelengths fits around the loop**. Fit an integer
number and the length is invariant, the measure-once optimisation survives untouched, and the dash
maths stays exact. Fit a fractional number and the modulation has a seam that beats against the
travel, which is both a length error and a visible artefact.

So: **the wave's frequency around a closed baseline is an integer, and it is a derived value rather
than a tunable one.** The straight 3x2 baseline has no such constraint — it has ends, not a seam —
which is worth noting because `WavyLine`'s `frequency: 6` is a free parameter there and must not be
copied across as if it were.

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

**From implementation (12 Aug):** the blocker was not where this section expected. `ShapeCanvas`
already strokes an outline (`borderWidth`/`borderColor`), so a shape loses nothing there. What a
shape could not do was *be a card at all*: every normalised polygon was scaled by
`min(width, height)` and centred, so a 320x112 card would have drawn a 112x112 shape floating in its
middle. The foundation was an opt-in `stretch` placement — identical to the square one on square
items, which is what makes it safe under every existing caller — with the path built in pixel space,
because scaling the context scales the pen and only a uniform scale cancels that out; stretched axes
differ, so a border would thicken on the short axis by the aspect ratio.

**And the count was wrong: seven copies, not four.** The lint that reserves the tint pair to the
card found three more on its first run — the media 3x2, the media 2x1, and the system monitor's
helper feeding three cards. calendar's drift also went further than recorded: it does not use the
conditional at all. A survey done by reading finds the copies already known about; the mechanized
rule found the rest immediately.

### Why this lands before the media work

It is the cheapest step in the whole plan and the least likely to break anything: mechanical,
adoptable one widget at a time, and each adoption leaves the tree working. Media then gets built on
the card rather than the card being reverse-engineered out of media afterwards. It also front-loads
the decision that the rest depends on — that a surface's shape is a *parameter* — at the level where
it is easiest to prove.

## 3d. Card motion

**Settled with the user (12 Aug).**

### One clock for the widget's box, many for what is inside it

The card does **not** animate its own width and height. `PluginWidget` already owns that
(`Behavior on width`/`height`, `enabled: gridResizeAnimated`), and a card that animated its size too
would be a second clock describing the same movement.

That is not hypothetical. It already ships:

| | duration | curve | honours `gridResizeAnimated` |
| --- | --- | --- | --- |
| `PluginWidget` `Behavior on width`/`height` | `gridResizeDuration` | expressive spatial | yes |
| `DesktopWeatherWidget:43` `Behavior on implicitWidth` | **250 ms, hardcoded** | `[0.2, 0, 0, 1]` fallback | **no `enabled:` at all** |

Both fire on one span change, so the box and the content disagree for the whole transition, and the
second animates even with the feature switched off. Absorbing this is part of what the card is for.

**Cards that reflow *within* a widget are free to differ.** The system monitor's three cards may
rearrange rather than merely scale (3-across to stacked), and that motion is their own — own
duration, own curve, deliberately not slaved to the box. The rule is narrower than "one clock for
everything": one clock per *movement*, and a card rearranging inside a resizing widget is a
different movement from the widget's box travelling.

### The shape morphs continuously

A card's shape interpolates through the span change rather than swapping at a threshold. It follows
that the shape morph and the size animation must be driven by the same progress — the §3 caution
about the ring detaching from the cookie, one level up. A card whose outline arrives before its
box does reads as two objects.

### Frost is dropped for the duration of the motion, and restored after

The frost does not track a resizing card. `WallpaperBlurSurface` binds its `sourceRect` to
`root.width`/`height`, so every frame of a resize is a fresh sample and a resized texture, times
however many frosted cards are on screen.

This is cheap to restore precisely because of #147: the surface asks for the plain wallpaper file
with no `sourceSize` and no `sourceClipRect`, so every surface shares one `QQuickPixmap` cache key,
and *"a surface created after that decode is Ready in the frame it is built"*. Re-creating a frost
surface costs no decode.

The card keeps its tint throughout, so there is nothing to substitute and nothing to flash: the card
already draws `color: useBlurBackground ? applyAlpha(colOnPrimary, backgroundOpacity)
: colOnPrimary` beneath the frost (`DesktopWeatherWidget:84`). Dropping the blur leaves the tinted
card moving, and restoring it puts the frost back over the same tint.

### Resizing is elastic: a heavy card with elastic edges

**Settled and tuned on screen (12 Aug).**

Today the grip does not resize the card, it *picks* a span: `previewGridResize` maps the drag
straight to `GridSizes.nearestSize` and sets it, so the pointer moves continuously while the card
occupies one of four sizes. #171 animates the jump, which is a smoother teleport rather than a card
that follows the hand.

The model instead: **pulling takes force.** The card holds its size while tension builds, the edges
being pulled distort first, and only past a breakaway threshold does the material give and the card
spring to the next span. Leftover pull carries into the next span, so one drag walks through several
sizes without re-grabbing.

Three things make it read as material rather than as a rectangle with bent sides:

- **The corners are not rigid.** Fixed radii were what felt wrong. Under load the corner being pulled
  *tightens* (material drawn toward a point) and the two corners it pulls away from *open up*; the
  far corner stays at rest.
- **The bulge sits near the hand**, not at the edge's midpoint - so the distortion looks drawn toward
  the pointer.
- **The dragged corner leads** and the edges follow it.

### The tuned constants

Found by pulling on them rather than by argument, with a freeze-under-load control so a held
distortion could be judged against each knob:

| | value | meaning |
| --- | --- | --- |
| breakaway | **60 px** | pull before the card gives |
| edge bow | **14 px** | distortion at full tension |
| give curve | **1.15** | >1: resists, then gives |
| corner follow | **1.00** | the dragged corner leads |
| bulge peak | **0.85** | near the corner being pulled |
| corner tension | **0.50** | pulled corner tightens, others open |

### Those numbers are not portable, and the reason is measured

The knobs above are per-frame coefficients from a `requestAnimationFrame` loop tuned on a **240 Hz**
display. Ported literally they are wrong: the same spring at 60 Hz settles in **733 ms** instead of
183 ms. Matching the per-frame recurrence against a damped spring converts them once:

```
v(n+1) = damp * (v(n) + stiff * (target - x))          per frame, dt0 = 1/240
omega  = sqrt(damp * stiff) / dt0        zeta = (1 - damp) / (2 * omega * dt0)
```

giving the values that **do** port:

| | |
| --- | --- |
| spring frequency | **omega 56.79 rad/s (9.04 Hz)** |
| damping ratio | **zeta 1.268** - overdamped, settles without overshoot |
| bow time constant | **tau 6.0 ms** |

Verified: the time-based form reproduces the tuned motion at 240 Hz to the decimal (168.42, 188.30,
195.40 px at 50/100/200 ms).

**And a trap inside the fix.** Integrating this spring at the display's own interval is unstable:
explicit Euler needs `2*zeta*omega*dt < 2`, and at 1/60 that term is **2.4** - the simulation
diverges to 1e10 rather than settling. Substepping at a fixed 1/240 is stable at 60, 144 and 240 Hz,
with 144 and 240 matching exactly and 60 differing only by the coarser sampling grid (7.5 px at
50 ms, converged by 200 ms). QML's `SpringAnimation` sidesteps this by integrating internally, but
its `spring`/`damping` are its own units rather than omega/zeta, so that conversion happens once and
should be pinned by a runtime test sampling mid-transition - the check #171 established.

### Moving is a different movement, and wants a different spring

Dragging a card to reposition it and dragging its grip to resize it are two movements, so per the
rule above they get two springs - and they are not close:

| | omega | zeta | |
| --- | --- | --- | --- |
| resize | 56.79 rad/s (9.04 Hz) | **1.268** | overdamped: settles, never overshoots |
| move | 95.52 rad/s (15.20 Hz) | **0.352** | underdamped: lags the pointer, overshoots, springs back |

The move also carries what the resize does not:

- **Volume-preserving squash along the direction of travel**, so the card reads as a material rather
  than as a scaled image. Stretch factor `1 + min(0.16, speed * 0.010/240)` with speed in px/s.
- **A press lift** - shadow and a few percent of scale - on grab, easing back on release.
- **Rubber-banding at the field edges** (0.34 of the travel kept past a limit), rather than a stop.
- Direction is only computed above **96 px/s**; below that the card is treated as still, or the
  stretch axis jitters from near-zero velocity.

### Two porting lessons, both learned the hard way here

**Every constant carries units, and only some of them are springs.** Moving this tuning between two
loops, the spring constants were converted and the rest were not. The squash constant was written
for velocity in px per *frame* and reused against px per *second* - a factor of 240, so it sat pinned
at its cap and the card sheared instead of stretching. The velocity thresholds were out by the same
factor. The spring conversion is the interesting arithmetic and therefore the one that gets
attention; the plain multipliers beside it are what actually broke.

**Position must be composited, not laid out.** Driving the card's `left`/`top` per frame forced
layout and paint on every frame behind a blur, and read as stutter rather than as elasticity; the
same motion through a transform is smooth. The QML counterpart is the same distinction - a property
that triggers relayout versus one the scene graph can carry - and this repo has already met the
render-versus-store half of it in the parallax work.

### What is drawn and what is committed stay separate

The stretched size is never a span. On release the card commits the nearest **offered** span and
springs into it. This is the same split as `followParallax`: the drawn value is derived, the stored
value is authoritative.

### The standing trap

Nothing may clamp, measure or persist against the animating value. `PluginWidget.settledWidth`
exists for exactly this, and cards inherit the discipline: a card that measures itself mid-animation
reads a number that was never real. See AGENT.md's note on the same failure in the resize path.

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
   `WallpaperBlurSurface` and a stroked outline (bundled, per §3c). Weather, currency and media adopt
   it; `calendar` follows later. Removes `DesktopWeatherWidget`'s competing size Behavior. Nothing
   morphs yet - this step only removes the duplication and makes the shape expressible.
2. Elastic resize on the card: breakaway, edge bow, live corner radii, and the spring - with the
   constants expressed as time rather than per frame (§3d), and a runtime test that samples
   mid-transition.
3. `media_geometry.js` + tests. No caller.
4. Media collapses to one tree, **no animation** - every span still renders correctly, statically.
   This is the risky structural step and is worth reviewing alone.
5. Behaviors on the shared elements' geometry. Resize now morphs position and size.
6. Shape morphing for the transport controls, on the resize's clock.
7. Progress: the wave gains a path baseline, then the 2x2 inner ring and the 2x1 wavy outline
   drawn as one shape with the play button. No renderer cross-fade - §3 removed the need for one.
8. The interaction-state model in `Appearance`; `RippleButton` adopts it.
9. Media controls adopt it.
10. Extract whatever is genuinely generic into the widget framework - *after* steps 3-9 have shown
   what that is.

Steps 3-4 are the ones that could go wrong quietly. Step 10 is deliberately last: the framework is
derived from a working case, per the settled input — with the card as the one exception, for the
reason given in §3c.
