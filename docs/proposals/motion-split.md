# Proposal: the split motion

> Measured 2026-09-17 off the reference below. The first adopter is the dock's
> attached <-> floating switch in frame mode (§6); the shape is meant to carry
> to every later "one surface becomes two" in the shell (§7). Nothing in this
> file is a guess: every number is a frame count, and the frames are listed so
> the measurement can be re-run.

## 1. The reference

https://www.reddit.com/r/unixporn/comments/1wey17r/niri_hope_this_surprises_you_a_little/
- a niri desktop with a dynamic-island bar (the pill at the top centre). The
video is `v.redd.it/jsk4jqmqv7ph1`, 1280x720 at 30 fps, 6m03s. Reddit refuses
the page to yt-dlp without an account; the DASH manifest
(`/DASHPlaylist.mpd`) is served anonymously with a browser User-Agent and
`Referer: https://www.reddit.com/`, and `yt-dlp -f 'bv*'` on it fetches
`CMAF_720.mp4` (20 MiB). The clip is not committed.

The moment of interest is the **screen-recording island** at 0:30-0:35. The
clock pill starts a recording: it becomes a recorder pill and its stop button
- a round, same-colour body - **splits off to the right** through a gooey
neck (frames 906-935). Three seconds later the button is clicked and it
**merges back** into the pill through the same neck, in reverse (frames
1009-1032). Every other island event in the clip (the media card, the menu,
the notification) is a one-body morph; this is the only two-body one.

Contact sheets, 2x, every frame, ms from the trigger in the margin:
`docs/assets/motion/split-detach.jpg`, `docs/assets/motion/split-merge.jpg`.
The composition's extent against time is `docs/assets/motion/split-extent.png`.

### How it was measured

`ffmpeg -vf "select='between(n,890,945)+between(n,1000,1035)',crop=320:64:480:0"`
gives the island region at native resolution. The pill is 244/255 bright on a
221/255 wallpaper, so a threshold at 236 on the mean of RGB is the island's
outline; per column, the outline's vertical extent is the body's thickness,
runs of occupied columns are bodies, and a run's interior columns thinner
than 75% of its thickest are its neck. Text and glyphs inside a body are
darker than the threshold and do not reach the outline, so they do not count.
Frame numbers below are the clip's own (0-based); ms are relative to the
trigger frame, at 33.3 ms per frame.

### The source, read after the measurement

The shell in the clip is Clavis (https://github.com/StatIndet/quickshell,
GPL-3), and its recording pill is the island; the source was read on
2026-09-17 at 5183553 after the frames had been measured. It confirms the
measurement at a scale of exactly 0.5 (a 2560-wide screen recorded at 1280)
and it says how the motion is built, which the frames could not:

- **The neck is a distance field, not a drawn path.**
  `assets/shaders/keystone/frag/pill_morph.frag`: two rounded-box signed
  distance functions (the main body and a "satellite") joined by a
  polynomial smooth-minimum with a `blendRadius`, and the coverage is a
  0.8 px smoothstep of the joined distance. The neck, its concave flanks and
  the corners rounding are all the ONE blend radius; nothing is drawn twice
  and nothing is antialiased against anything else.
- **One scalar, linear in time, with the shape keyed in VALUE.**
  `pillMorphProgress` runs 0 -> 1 over 1000 ms on a split and 820 ms on a
  merge (`KeystoneSurface.qml` `pillEntryDuration`, `pillFusionDuration`),
  `Easing.Linear`. Every dimension is a piecewise smoothstep over it
  (`HorizontalPillRecordingVisual.qml` `morphValue`, `satelliteMorphValue`),
  five keyframes - idle, peak, neck, split, settled - at 0, 0.58, 0.76, 0.80
  and 1.0, the satellite holding idle until 0.32:

  | | idle | peak (0.58) | neck (0.76) | split (0.80) | settled (1.0) |
  |---|---|---|---|---|---|
  | main width | 220 | 250 | 220 | 210 | 200 |
  | main height | 42 | 52 | 46 | 44 | 42 |
  | satellite offset from the main's far edge | -h/2 (inside) | 40 | 38 | 38 | 38 |
  | blend radius | 0 | 50 | 28 | 18 | 0 |

  At 0.5: main 110 x 21 against the measured 108 x 20 clock pill; joined
  extent 250 + 40 + 26 = 316 -> 158 against the measured 156; height 52 ->
  26 against 25; settled 200 + 38 + 21 = 259 -> 129.5 against 128. The split's
  1000 ms is the measured 30 frames; the merge's 820 is the measured 24.
- **A merge started mid-split is proportional**: `max(220, 820 * progress)`
  ms (`KeystoneSurface.qml:773`), so a reversal near either end is short and
  never under the effects tier's length.
- **Blur is published for the two bodies only** (`blurBackgroundItems`), the
  neck unblurred.
- **The attached island has concave edge fillets** where it meets the screen
  edge (`AttachedEdgeCurve.qml`: a Canvas bezier 8 along, 14 deep), hidden
  the moment it detaches.
- **Size changes elsewhere use an overshooting bezier** (`KeystoneMotion.qml`:
  500 ms to grow, 360 to shrink, control points past 1.0), not this scalar.

What the source changes in this proposal: §4's two-segment bezier stays as
ImI's tier (it fits the frames, and one Easing.BezierSpline is what the
motion catalogue is made of), and §6's neck is built the way the source
builds it - a distance-field blend in one shader - instead of a path, for
the reasons recorded there. The reversal rule is taken as read.

## 2. The shape grammar

Two bodies: the **island** (the pill) and the **child** (the stop button).
What the frames show, and what every implementation has to keep:

- **The child never moves.** Its centre sits 54 px right of the composition's
  centre from the frame it first appears (912) to the frame it is absorbed
  (1016); its outline is `x 204-223` at rest in both sequences. What moves is
  the island's *outline*: it reaches out past the child's resting place, then
  withdraws and leaves the child behind (split); it reaches out, swallows the
  child, then contracts to one body (merge). (In the source the satellite is
  parameterised from the main body's far edge - `mainWidth + offset`, the
  main swelling 220 -> 250 -> 200 under it - and the composition is centred;
  the frames are what that composes to on screen, and the frames stand.)
- **There is a JOINED state, and it is bigger than either rest state in both
  axes.** Split and merge both pass through exactly the same outline: `x
  82-237`, 156 px wide, 25 px tall, against a 108x20 clock pill, a 98x20
  recorder pill, a 20x20 child and a 128x20 composition at rest. The joined
  outline's right edge is the child's right edge plus 14 px (0.7 child
  widths). The island swells to hold the child and then relaxes; the extent is
  not a spring overshoot - the merge passes through it in the *shrinking*
  direction, which no overshoot does - it is a target of its own.
- **The composition is centred throughout.** The centre of the joined outline
  (159.5) is the centre of the clock pill (159.5) is the centre of
  island-plus-gap-plus-child at rest (159.5). Where the child is fixed, the
  island's left edge moves in the opposite direction to its right edge.
- **A neck bridges the seam for ~165 ms each way.** Split: the outline's
  waist at the child's near side thins from 18 to 8 px (of 25) over five
  frames, then breaks with a 6 px gap. Merge: contact at a 7 px waist, filling
  to 17 px over five frames. The neck exists while the outlines are within
  about 8 px of each other - **40% of the pill's thickness** - and its
  thinnest point is about a third of the pill's thickness. It sits at the
  child's near edge: the child stays round, the island's outline is what
  deforms.
- **Every corner is round throughout.** Both bodies are stadiums (radius =
  thickness / 2) in every frame; the reference has no square seam. A tab that
  squares its corners at the seam (the dock) is this shell's own rule, and §6
  says when the corners round.
- **Bodies never fade.** Neither the island nor the child changes opacity at
  any frame. The child is absorbed by the island's outline closing over it,
  not by a fade. What does fade is *content* - the glyphs inside - and it
  fades **outside** the spatial motion, never during it: on the split the
  clock crossfades to the recorder glyphs (0-165 ms) *before* the outline
  moves; on the merge the button's red dot fades (0-130 ms) *before* the
  outline moves and the recorder glyphs fade (530-700 ms) *after* it lands.
  Effects and space are sequenced, not overlapped.
- **The gap at rest is half the child.** 10 px between outlines, a 20 px
  child, a 20 px pill.

## 3. Timeline

### Split (trigger = frame 906, the clock's glyphs start to fade)

| ms | frame | extent | what |
|---|---|---|---|
| 0-165 | 906-911 | 108 -> 112 | content crossfade; outline still (+4 px) |
| 165-400 | 911-918 | 112 -> 122 | the island swells slowly, thickness 20 -> 23 |
| 400-560 | 918-923 | 122 -> 156 | fast swell to the joined outline, thickness 25 |
| 560-700 | 923-927 | 156 -> 144 | the neck: waist 18 -> 8 px at the child's near side |
| 726 | 928 | 111 + 6 + 23 | pinch-off; two bodies |
| 726-960 | 928-935 | 140 -> 128 | settle: island 111 -> 98, child 23 -> 20, gap 6 -> 10, thickness 22 -> 20 |
| 990 | 936 | 128 | at rest |

Trigger to rest 1000 ms; the outline moves for 800 ms of it (165-960); the
seam opens at 560-726, i.e. halfway through the outline's motion.

### Merge (trigger = frame 1009, the click; the button's dot starts to fade)

| ms | frame | extent | what |
|---|---|---|---|
| 0-130 | 1009-1013 | 128 -> 132 | the child's glyph fades; outline near still |
| 130-200 | 1013-1015 | 132 -> 140 | both bodies reach: island 103 -> 112, child 20 -> 24, gap 9 -> 4 |
| 231 | 1016 | 144 | contact; one outline with a 7 px waist |
| 231-330 | 1016-1019 | 144 -> 156 | the fused outline swells to the joined outline; waist fills 7 -> 17 |
| 330-760 | 1019-1032 | 156 -> 111 | contraction to one body; 128 by 462 ms, 111 by 760 |
| 530-700 | 1025-1030 | 111 | the recorder glyphs fade out |
| 760 | 1032 | 111 | at rest (the empty pill then morphs into a notification card - a different gesture) |

Trigger to rest 760 ms; the outline moves for ~730 ms (33-760); the seam
closes at 231-330, 30-43% of the way. The merge's front half is 70 ms shorter
than the split's; nothing else differs.

## 4. Curves

Each direction is two stages of about 400 ms with the seam between them,
and the two stages have different shapes. Normalising each stage's extent to
0..1 and fitting against `Appearance.animationCurves` (rms of the fit, lower
is better; a free cubic-bezier fit for reference):

| stage | ms | best catalogue curve | rms | next | free fit | rms |
|---|---|---|---|---|---|---|
| split, swell 112 -> 156 | 400 | `standardAccel` [0.3, 0, 1, 1] | 0.094 | `emphasizedAccel` 0.130 | [1.00, 0.33, 0.26, 0.12] | 0.017 |
| split, release 156 -> 128 | 400 | `linear` | 0.112 | `standard` 0.185 | [0.33, -0.02, 0.00, 0.52] | 0.027 |
| merge, swallow 128 -> 156 | 330 | `standardAccel` | 0.063 | `linear` 0.131 | [0.84, 0.18, 0.97, 1.57] | 0.026 |
| merge, absorb 156 -> 111 | 430 | `standard` [0.2, 0, 0, 1] | 0.052 | `expressiveEffects` 0.065 | [0.22, -0.02, 0.07, 0.98] | 0.015 |

The reach towards the joined state **accelerates** (a `standardAccel` shape:
slow for the first half, then most of the distance in the last third), and
the withdrawal from it **decelerates** (`standard`: a short ease-in, most of
the distance early, a long tail). The samples, for the record - split swell
`0 .05 .05 .09 .11 .18 .18 .23 .52 .68 .77 .89 1`, split release
`0 .04 .07 .36 .43 .57 .64 .79 .82 .86 .93 .93 1`, merge swallow
`0 .04 .07 .14 .14 .36 .43 .57 .79 1 1`, merge absorb
`0 .04 .27 .44 .62 .76 .84 .87 .91 .93 .96 .98 .98 1`.

The source (§1) has no bezier at all: its scalar is linear in time and the
SHAPE is keyed in value - the satellite leaves at 0.32, the swell peaks at
0.58, the neck thins to 0.76, pinches by 0.80 and the bodies settle to 1.0.
Read against the two-stage fit below, that puts the parting of the outlines
(this proposal's seam, 0.5 of the value) inside the source's 0.32-0.58
release, and the pinch (0.9 of the value, 0.7 of the time) inside its
0.80-1.0 settle, where the blend radius runs 18 -> 0. The fit stands; the
keyframes are the ground truth to retune against.

No single catalogue curve describes a whole direction: treating either
direction as ONE scalar with the seam at 0.5, the best catalogue curve is
`linear` (rms 0.075 split, 0.107 merge) and `emphasized` - the accelerate-then-
decelerate curve the catalogue already has - scores 0.293, because its
inflection is at 17% of the duration where the measured seam is at 50%.

**The curve that fits is the two stages joined, with the seam at the
midpoint**: `standardAccel` scaled into the first half of the unit box and
`standard` into the second, as one `Easing.BezierSpline` of two segments:

```
split: [0.15, 0, 0.5, 0.5, 0.5, 0.5,   0.6, 0.5, 0.5, 1, 1, 1]
        \_ standardAccel, 0..0.5 _/    \_ standard, 0.5..1 _/
```

Against the measured sequences it scores rms 0.075 (split) and 0.054 (merge,
seam re-pinned to 0.5), better than anything in the catalogue for either.
Its samples at tenths: `0 .04 .13 .24 .37 .50 .75 .90 .96 .99 1`. What that
buys beyond the fit: **one scalar drives a whole direction, and the scalar's
value 0.5 IS the seam** - the frame the outlines touch or part - so
everything that has to happen at the seam (the neck breaking, a corner
rounding, a colour flipping) is keyed on a number every adopter already has,
instead of on a second timer that must agree with the tier's duration.

## 5. Mapping onto the tiers

Nothing in `Appearance.animation` is this shape: the spatial tiers
(`elementMove`, `elementMoveSmall`) leave the unit box - an overshoot, which
the reference does not have - and reach 0.5 by 15% of their duration; the
directional pair (`elementMoveEnter`/`Exit`) is one stage each and the wrong
one for a gesture the user reverses. So this proposes a tier, taken whole,
on the guideline's own rule that new motion needing a new curve adds a tier
and a paragraph, never a literal:

- **`Appearance.animation.split`** - 800 ms base (the measured 800 ms of
  outline motion; the merge's 730 is within one tier of it, and one tier
  serving both directions is the popup card's precedent), curve
  `animationCurves.split` above, `Easing.BezierSpline`, a `numberAnimation`
  factory like every other tier, and through `motion.scale()` so the speed
  slider and the reduce-motion floor reach it.
- **`Appearance.animation.splitSeam`** - `0.5`, unitless: where on the
  scalar the outlines touch. Published beside the tier the way
  `contentGate` is, because it is a property of the curve (the join of its
  two segments) and an adopter that hard-codes 0.5 is an adopter that
  silently disagrees the day the curve is retuned.
- **`Appearance.animation.splitNeckReach`** - `0.8`, unitless: how far into
  the settle half of the scalar the neck bridges before it pinches off, as a
  fraction of the scalar's VALUE. Set in the time domain, which is what the
  eye sees: the reference's neck lasts 165 ms of an 800 ms motion, from the
  seam at 0.5 of the time to the pinch at 0.7, and on the curve above - whose
  settle half is front-loaded - 0.7 of the time is 0.9 of the value, i.e.
  0.8 of the settle half. (The first cut read it as a distance, 40% of the
  body's thickness; on a 5 px lift that meant the neck broke only at rest,
  and a value-domain 0.5 pinched in 50 ms. Both were measured off the
  sandbox and rejected.) Past the pinch the bodies settle apart.
- Shape rides the scalar: a corner rounds from the seam to rest, because the
  rounding is the seam's own shape opening.
- Effects at the seam - a colour, a border, a glyph - take
  `elementMoveFast` (200 ms, `expressiveEffects`), **sequenced** with the
  spatial tier, never overlapped with it: the reference's content changes
  land strictly before the outline moves (split) or after it lands (merge),
  and a look that changes while the outline is still travelling reads as two
  gestures. A switch with no travel is a look change alone, on the effects
  tier, corners included.

Guideline paragraph, for `docs/M3_GUIDELINES.md` §2 once the tier lands:

> ### Split (one body becomes two, or two become one)
>
> (The paragraph as landed in `docs/M3_GUIDELINES.md` §2 "Split"; the wording
> there is the rule.)

## 6. The first adopter: the dock's attached <-> floating switch

Today (`appearance.frame.dock`, #396) the switch is a JUMP: the layer-shell
margin reconfigures the surface by the band's thickness in one step, and the
colour, border and corner radii flip in one frame.

### The mapping, and the one inversion

- The **band is the island** and the **pill is the child**. The band is a
  compositor-fixed line at the screen edge, so it cannot be the body whose
  outline reaches out; the pill is the free body. This inverts the reference
  (there the child stands still and the island's outline travels), and the
  inversion is forced by what a band is, not chosen. What survives the
  inversion is everything §2 says about the *seam*: one body travels, the
  other holds; nothing fades; the neck bridges the last 40%; the joined state
  is where the outlines are one.
- **Attached IS the joined state** (the tab fused with the band, outward
  corners squared, the band's colour, no border); **floating is the apart
  state** (a gap between pill and band, four round corners, `colLayer0`, a
  border). The gap is the compositor's outer gap (`gapsOut`, 5 px by
  default), whatever the band's thickness: "on the band" and "a gap above
  it" are `gapsOut` apart by #396's own definition. So attach -> float is
  the reference's RELEASE half read as a lift: the pill rises off the band
  by the gap, the neck stretches and breaks, the outward corners round as
  the gap opens. Float -> attach is the SWALLOW: the pill sinks, the neck
  forms as the outlines come within reach, the corners square as it fuses.
- **The swell is the fused outline stretching.** The reference's island
  grows before it releases. The band, a 5 px line, cannot grow and the pill
  has no room to thicken inside its surface, so the swell is reinterpreted:
  up to the seam the pill lifts with a full-width neck under it, and what
  the eye sees is ONE outline - the tab - getting taller. The two-stage
  curve's accelerating first half is that stretch; the seam is where it
  starts to part.
- **The neck is a distance field.** It is the identity of the motion:
  without it a lift is a pill moving 5 px, which is what a settings toggle
  already does when a margin changes. It is built the way the source builds
  it (§1): the pill's rounded box and the band's half-plane as signed
  distance fields, joined by a polynomial smooth-minimum whose radius is
  the neck, covered once by one `ShaderEffect` (`shaders/split.frag`) over
  the box `blendBox` lays out - the pill, the lift down to the band, the
  blend's spill along it. The first cut was a `Shape` on one SVG path under
  the pill, reaching a pixel into it: drawn edge to edge, the pill and the
  path each antialiased their half of a boundary sitting on a fractional
  pixel while the lift animated, and two half-coverages of one colour over
  the light band composited to a hairline across the whole width for the
  whole fused half of every lift. A field has no second edge to meet.

### The hard constraint, and the recommended shape

The surface's layer-shell margin cannot animate: every write is a
compositor reconfigure. Three shapes were weighed:

- **(a) Keep the surface at the attached position; animate the pill inside
  it.** The surface's outward margin stays at `band - gap` (the attached
  offset) in both states, and the pill's outward inset animates between
  `gap` (attached) and `2 * gap` (floating) on the split scalar - the pill
  lifts into its own inward elevation margin (10 px at the defaults, against
  a 5 px lift). Where a configured gap outgrows that margin, the strip grows
  by exactly the shortfall (`splitRoom`; nothing at the defaults). The
  surface never moves for the switch; it reconfigures once, when frame mode
  or the pin changes. **Recommended, and built.**
- **(b) Animate inside the old surface, then reconfigure at the end where the
  pixels already match.** The same lift, plus a hand-off at the end that has
  to land on the same pixel and a second surface position to keep in sync
  with the first. Nothing (a) does not do, for one more thing to get wrong.
- **(c) Two surfaces** (a reserver like the bar's, and a travelling one) -
  the machinery `BarExclusiveZoneReserver` exists for, and more than a 5 px
  lift needs.

Under (a) the **exclusive zone** is the one thing that still steps: attached
reserves `height + band` from the edge, floating `height + gap + band`, and
the difference is the gap that keeps windows off the floating pill. The zone
reserves the UNION of where the pill is and where it is going
(`splitZoneExtra`): it steps at the START of a lift (the windows move away,
the pill lifts into the space) and at the END of a landing (the pill lands,
then the windows follow it in) - a boolean that flips, never a per-frame
write, and never while the pill is up: written at the start of a landing,
which the first cut did, it put the windows against the still-floating pill
for the length of the motion. The compositor re-tiles, and tiled windows
travel on Hyprland's own window animation, so each step is a window slide
and not a jump (measured in the sandbox: the reservation 65 -> 70 at +0.4 s
of a lift, still 70 at +0.6 s of a landing, 65 at +1.1 s; a kitty of 841 px
becomes 836 and back). The surface does not move, so the
unpinned dock's hover sliver - which must stay AT the edge - is untouched:
an unpinned dock never reserves and never lifts (the existing gate), and at
the default band its look-only switch takes the effects half alone.

### What rides the scalar

- **Position**: the pill's outward inset, `gap + gap * s` (attach -> float)
  and the reverse, on the pill's OWN margins (`liftedMargins`), so the blur
  region - which tracks its item's own geometry - rides the lift. The inward
  margin gives up exactly what the outward one gains. The icons ride the
  pill through a centre offset on the strip (`liftOffset`).
- **Corners**: `cornerRadiiAt(edge, radius, s, seam, reach)`. The two
  outward radii are `radius * clamp((s - seam) / ((1 - seam) * reach), 0, 1)`
  - square while the outlines are one, rounding over the NECK's span as the
  flank exposes them, round by the pinch - on both directions of the one
  scalar. Rounding to rest instead left a square corner hovering over a lit
  gap once the flank had passed it (a reviewer's frame scan). The inward
  pair stays at `radius` throughout. With no lift the seam is 0, the reach
  1, and the rounding rides the look's own effects-tier scalar.
- **The neck**: the blend's radius is nothing at rest and four lifts at
  the seam (`neckBlend` - a smooth-minimum bridges a gap of g once its
  radius passes 2g, and the gap at the seam is half the lift), held through
  the settle. It acts over the waist (`neckWaist`: the pill's full width up
  to the seam - the fused outline stretching as the pill lifts its first
  2.5 px, the reference's swell, which a 5 px band cannot show any other way
  - narrowing to nothing at the pinch, `splitNeckReach` of the way through
  the settle half), tapering along the band from the waist's centre; the
  bodies settle apart after it. Three things the field needed that the
  source's does not, because a flat pill edge faces a flat band where the
  source has a circle, each measured on the sandbox frames: the taper,
  because a flat edge over a flat band is one distance everywhere and a
  uniform blend lets go all at once instead of pinching; a coverage ramp of
  one screen pixel of the field's own gradient (`fwidth`), because between
  two facing edges the fields' gradients cancel and a ramp in field units
  smeared into a soft grey flank; and the pill's field reaching into the
  band by a pixel less the lift (`fieldPill`), because a blend that is
  nothing at rest cannot bridge the sub-pixel gap of the first frames and
  the ramp showed it as a hairline along the seam. While the field paints
  the pill's `Rectangle` does not (an `opacity` flip, no Behavior): the same
  silhouette in the same colour at both hand-overs - square corners and no
  blend at 0, round corners and no waist past the pinch - and a translucent
  fill drawn twice is darker. The blur region stays the pill's: the two
  bodies, the neck unblurred, as the source publishes it.
- **A direction from part way is proportional**: the tier times the
  distance left, never under the effects tier (`splitDuration`, the
  source's rule), from a start the Behavior latches when its target changes
  - bound to the moving scalar, the duration re-evaluated every frame of
  its own run and shortened it as it went (measured: a reversal at 250 ms
  took 680). Measured after: a reversal from 40% of the way lands in 266 ms,
  one from 6% in the 133 ms floor, the whole lift in 800.
- **Colour and border**: `elementMoveFast`, sequenced. On a lift they run
  after the scalar lands at 1 (`attachedLook` holds the tab's look while the
  scalar is below 1; the pill takes `colLayer0` and its border once it is
  free - the reference's content-after-landing). On a landing they run
  before the scalar leaves 0: `attached` flips at once, and the scalar's
  Behavior is a `SequentialAnimation` whose `PauseAnimation` is the effects
  tier's length when the target is 0 (read off the Behavior's own
  `targetValue`) - the reference's dot-before-outline. Measured in the
  sandbox: a 133 ms look change, then the descent. The border is a COLOUR
  that fades - from the tab's own colour (a transparent ring would be a
  seam, since a Rectangle's fill stops at its border) to `colLayer0Border` -
  never a width: a width animated from 0 draws nothing until it reaches 1,
  which a frame scan showed as a one-frame pop wearing the tier's name.
- **The scalar follows the configured choice, not `attached`**: `attached`
  folds in the fullscreen term, and a scalar driven by it replayed a landing
  on every fullscreen exit. `splitTarget` reads the frame option and the pin
  alone - so pinning a floating dock is a lift off the band, not a jump to a
  lifted pill; fullscreen reaches the lift through `reserves` (travel 0
  while hidden) and the look through `attached`, and neither replays
  anything. Unpinning a floating dock still snaps the lift to zero in one
  frame, under the unpin's own reveal and zone changes; stated, not fixed.
- **The pause is only for a pending look change**: a landing from rest
  waits the effects tier for the tab's colour to land; a lift reversed
  mid-flight has the tab's look already and waits for nothing - a pause
  there parked the pill in the air.
- **A lift that did not begin as the tab rises as a pill.** `liftFromTab` is
  decided at the scalar's target's rising edge from what was on screen the
  turn before (`attachedBefore`, last turn's `attached`, refreshed one turn
  late with `Qt.callLater`): pinning a floating dock, or switching the frame
  on under one, raises the target with the pill already on screen, and the
  pill rises without a neck and keeps its corners and border. Two earlier
  spellings were wrong and are recorded so they are not tried again: reading
  the look at the edge (its own terms move on that edge, in an order nothing
  orders, and the old latch fed itself back), and reading "what changed
  since the last edge" (a change between edges - unpin, flip the option
  while unpinned, pin - escapes it).
- **Two limits, stated.** A pill-lift reversed into a landing before it
  lands (pin a floating dock, choose Attached mid-lift) takes the tab's look
  during the descent rather than before it: `attached` flips at once and the
  scalar is below 1, so nothing pauses - the one path where effects and
  space overlap, by construction. And the motion is pinned as source text
  and measured in the sandbox, not sampled in flight by the suite: the dock
  is a `PanelWindow`, which headless weston cannot build (no layer shell),
  and a nested-Hyprland probe is run by hand here, not by `run_tests.sh`.
- **No lift, no spatial tier.** An unpinned dock at the default band, or the
  frame switching off, has nothing to split off: the Behavior is disabled
  (`enabled: splitTravel > 0`), the scalar snaps, and the look - colour,
  border and corners - changes on the effects tier through a scalar of its
  own (`lookApart`).
- **The blur region** rides the pill: a `Region` re-evaluates on its item's
  own geometry, and here it is the pill's own inset that moves, not an
  ancestor's offset (the hide is that case and keeps its `atRest` gate). Its
  per-corner radii are bindings on the pill's, so the frost's corners round
  with the pill's.

### Verification (per the review rule)

Sandbox recordings at 60 fps (`wf-recorder` on the nested output), both
directions, read frame by frame the way the reference was: the pill's
extent one row above the band goes 322 -> 0 px across a ~700 ms lift and
0 -> 322 across a ~600 ms landing that starts 133 ms after the look has
changed; pinned and unpinned; the default band and 14 px; the dock on the
left edge; the settings row. `tst_dock_geometry.qml` pins the lift, the
room, the lifted margins, the icon offset, the corners at a scalar and the
neck's boxes; `test_frame_mode_contract.py` pins the tier, the one scalar
and its one Behavior, the pause, the zone step from the configured state,
the look's sequencing and the neck; `lint_motion_tier_partial.py` holds the
tier whole. Reviewer >= 8.5 on all three axes before the one full suite.

## 7. Where the split goes next

Every later "one surface becomes two" in the shell is the same grammar with
the same tier, and these are the ones already in sight:

- **The launcher growing out of the bar** (frame mode's modal docking, the
  proposal's next slice): the bar plate is the island, the launcher card is
  the child. It does not fade in centred over the wallpaper; the plate's
  outline reaches down (the swell), the card is released with the neck at
  its top edge, and its top corners round as it clears the band. Closing is
  the swallow. Same scalar, seam at 0.5, effects (the card's own border and
  layer colour) after it is free.
- **Notifications docking into the frame**: the band on the notification's
  edge is the island; a card arriving is released from the band (it does not
  slide in from off-screen), a card dismissed is swallowed by it. Where the
  band is the default 5 px the neck spans the whole travel, as it does for
  the dock.
- **The modes flash** (`ModeFlashPopup`): the bar's mode pill is the island,
  the banner is the child. Today it is a popup with an entrance; as a split
  it is the pill's outline swelling and releasing the banner below it, which
  says where the banner came from without a second element.
- **The bar's centre pill in frame mode** already squares all four corners
  because it is fused with the band (`BarContent`); a bar that auto-hides in
  frame mode is a split too - the plate lifting off the band - and takes this
  tier when auto-hide is modelled (frame-mode stage 2).

The rule for the next slice is the rule for this one: measure it against
the reference's grammar (§2) before writing it, and if the measurement says
the tier's shape is wrong for it, retune the tier and its paragraph rather
than writing a literal beside them.
