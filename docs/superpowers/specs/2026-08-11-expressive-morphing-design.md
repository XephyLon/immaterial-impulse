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

## 3. Progress is the hard one, and needs a decision

Progress exists as a wavy bar at 3x2 and as the cookie's stroked outline at 2x1. Those are the same
information in radically different geometry, and morphing one into the other is not a rect tween.

**2x2 currently has no progress at all.** A shared element must exist at every span or have a defined
exit, so this needs answering before implementation:

- give 2x2 a progress ring on its cookie outline — consistent with 2x1 and makes the three sizes one
  family; or
- treat progress as present at 3x2 and 2x1 only, and give it an explicit exit at 2x2.

The first is more coherent and is the recommendation. It is called out because it is a *visible
design change to a size the user has already reviewed*, not an implementation detail.

Implementation note: the 2x1 ring is already an arc-length dash along a rounded-polygon path
(`shapes/path-length.js`). The 3x2 wavy bar is a different renderer entirely. The honest first
version is a cross-fade between the two renderers while their *bounding geometry* morphs — a true
path morph between a wave and a ring is a research problem, not a sprint.

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

That has a cost worth naming: converting a `Rectangle` to a shape-canvas draw is more expensive per
frame than a rectangle with a corner radius, and the 1x1 case also **clips against the card**, so the
morph has to carry the clip as well as the outline. Clipping is a property of the parent, not the
shape, so a shared element that leaves the card's bounds at one span needs the clip animated or
switched at a defined moment.

The order this implies: media proves the architecture, weather proves the *shape* half — its three
containers are a harder morph than media's pill-to-cookie, and the 1x1 clip is a case media does not
have at all.

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

1. `media_geometry.js` + tests. No caller.
2. Media collapses to one tree, **no animation** — every span still renders correctly, statically.
   This is the risky structural step and is worth reviewing alone.
3. Behaviors on the shared elements' geometry. Resize now morphs position and size.
4. Shape morphing for the transport controls, on the resize's clock.
5. Progress: the 2x2 decision from §3, then the renderer cross-fade.
6. The interaction-state model in `Appearance`; `RippleButton` adopts it.
7. Media controls adopt it.
8. Extract whatever is genuinely generic into the widget framework — *after* steps 1-7 have shown
   what that is.

Steps 1-2 are the ones that could go wrong quietly. Step 8 is deliberately last: the framework is
derived from a working case, per the settled input.
