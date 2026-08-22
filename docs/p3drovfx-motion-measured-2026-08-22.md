# `P3DROVFX/ii-p3drovfx` — the motion language, measured off screen

> Date: 2026-08-22. Measurement and cross-reference; nothing was ported.
> Third in the series, after [`p3drovfx-research-2026-08-16.md`](p3drovfx-research-2026-08-16.md)
> (by feature) and [`p3drovfx-animation-research-2026-08-16.md`](p3drovfx-animation-research-2026-08-16.md)
> (by technique, read from their source).
>
> Those two read code. This one reads **pixels**: two 60fps screen recordings of
> their shell running, measured frame by frame, and only then matched back to
> the source that produces them. It exists because the claim under test —
> "their motion animates each element individually while keeping the layout
> cohesive" — is a claim about what a person sees, and the previous surveys
> could not settle it by grepping.
>
> Their tree read at `3d4a62a` with its `shapes` submodule initialised.

---

## 1. Method, and why it is stated

Two recordings, both 60fps: a bar strip (854x128, 18.75s) and the right
sidebar's AI pane (528x1182, 11.2s).

Every frame was extracted and three things were computed per frame:

- **mean absolute difference** against the previous frame, to find where motion
  happens at all rather than scrubbing by eye;
- **mean luminance of a horizontal band**, to measure a fade — the panels are
  flat dark surfaces, so a band's brightness IS its opacity;
- **horizontal displacement by cross-correlation** of a band's luminance
  profile against the settled frame, to measure a translate.

The third is the one that matters, and it is why this is measured rather than
described. Watching the AI pane leave, three rows appear to shear apart — the
chips row looks like it leads and the input row lags. Cross-correlated against
the settled frame they are **identical to the pixel** at every frame of the
exit (0, -2, -3, -6, -5, -16, -27, -37, -55, -86...). The shear is the panel's
own edge clipping rows of different widths. An eyeballed reading of that clip
would have gone into this document as a finding.

`docs/superpowers/` records the same lesson twice already (a live-machine
measurement without a control measures something else; two screenshots of a
live desktop are not an A/B test). This is the version of it for video.

---

## 2. What the pixels say

### 2.1 The AI pane's entrance is a staggered cascade with zero translation

Normalised per band against its own settled value, on the open at frame 508:

| band | 50% | 90% |
|---|---|---|
| container (rows 470-500, 690-740) | 100ms | 133ms |
| chips row (rows 926-961) | 233ms | 367ms |
| input row (rows 1030-1050) | 267ms | 367ms |
| model selector (rows 970-1010) | 400ms | 533ms |

Two facts, both load-bearing:

- **Horizontal displacement is 0 for every band at every frame of the
  entrance.** Nothing slides in. Each element is already at its final position
  from the first frame it is visible, and only its opacity (plus a scale and a
  small vertical offset — §3) changes.
- **The container finishes before the contents start.** It is at 90% by 133ms;
  the first child does not reach 50% until 233ms.

That is the whole of the claim, and it is exactly right: the elements are
animated individually, and the layout they animate into never moves.

### 2.2 The exit is one rigid transform, and it is four times faster

The same three rows, cross-correlated through the close: identical displacement
to the pixel throughout. The container translates and the children ride it.

Measured close durations across three cycles: 117ms, 117ms, 150ms. Measured
open, container-start to last-child-settled: 533ms.

**The ratio is roughly 4:1.** M3's own asymmetry is 400ms decelerating in,
200ms accelerating out — 2:1. Theirs is more extreme than the spec in the same
direction.

### 2.3 The bar does the same thing at a smaller scale

The bar strip's event at 15.1s is a fade-out of ~200ms followed by a fade-in in
which two regions (x≈464 and x≈770) arrive **~70ms apart**, both at unchanged
positions. Same grammar, one step of stagger instead of four.

---

## 3. What produces it

`modules/ii/bar/popups/clock/ClockWidgetPopup.qml:203-285`, which is the
clearest written instance of the idiom:

```qml
// Delays computed dynamically based on visibility order to prevent stagger skipping
const delays = [40, 100, 160, 220, 280];
readonly property bool startAnim: root.opened && root.popupOpenProgress > 0.6
```

and each member's reset:

```qml
clockHero.opacity = 0.0;
clockHero.scale = 0.85;
clockHeroTransform.y = 25;
```

Four decisions in that, three of which we do not have:

1. **A 60ms step**, indexed by visible rank so a hidden member leaves no hole.
2. **A container-progress gate.** Contents do not begin until the popup is 60%
   open. This is what makes §2.1's shape — container, *then* fill — and it is
   the piece that reads as deliberate rather than mushy.
3. **A three-property entrance**: opacity 0→1, scale 0.85→1, y +25→0. Not a
   fade.
4. **No reset on close**, stated in their own comment:

   > Do not reset on close start: the cards must stay visible so they shrink
   > with the surface, like the other popups. The reset happens once the close
   > animation reaches progress 0.

   Which is §2.2: the exit is the container's, not the children's.

---

## 4. Cross-reference

### 4.1 Against M3 Expressive

| | M3E | Theirs | Ours |
|---|---|---|---|
| Entrance curve/duration | emphasized decelerate, ~400ms | ~400ms per member | `elementMoveEnter` — 400ms, `emphasizedDecel` (`Appearance.qml:554`) |
| Exit curve/duration | emphasized accelerate, ~200ms | 117-150ms | `elementMoveExit` — 200ms, `emphasizedAccel` (`Appearance.qml:569`) |
| Stagger | sequential entry for groups | 60ms step, clamp at 5 | 40ms step, clamp at 5 (`motion_policy.js:96,102`) |
| Rank by visible position | — | yes | yes (`motion_policy.staggerRanks`) |
| Gate contents on container progress | not specified | yes, at 0.6 | **not found** |

We are not behind M3E on the vocabulary. The catalogue is identical in both
trees — the first survey established that in its §1.1, down to the `2 / 15`
fraction in `emphasized` — and our tiers are the canonical 400/200 pair where
theirs runs the exit faster than the spec.

The one item in that table we do not have at all is the **container-progress
gate**, and it is not an M3 rule; it is their invention. M3 says a group enters
in sequence and says nothing about what the group's own container is doing
while it happens. Theirs waits. Ours has no opinion, which in practice means
children animate while their container is still growing.

### 4.2 Against our tree — the actual gap is adoption

`docs/M3_GUIDELINES.md:131-139` already codifies stagger as a rule, and
`modules/common/motion_policy.js` already implements it correctly, including
both of the fixes the second survey ranked at #8 (rank by visible position, and
a clamp so a long list does not cascade for seconds).

Call sites that use it:

| | files |
|---|---|
| Ours | 3 — `ExpandablePanel.qml`, `Carousel.qml`, `docker/DockerPopup.qml` |
| Theirs | 20 |

That is the finding. This is not a missing capability, a missing token, or a
worse curve. **We built the policy and wired it into three places.** Every
surface that arrives as a group — the sidebars, the settings pages, the
launcher's results, the session screen, the popups — arrives all at once,
because nothing asked it not to.

---

## 5. What to take, in order

1. **Wire the stagger that already exists into the surfaces that arrive as
   groups.** No new mechanism; `staggerRanks` + `staggerDelay` + `staggerStep`
   at each call site. This is the whole of §4.2 and it is most of the felt
   difference.
2. **A container-progress gate**, as a named property rather than seven copies
   of `> 0.6`. The one technique here that is theirs rather than M3's, and the
   one that makes a staggered group read as composed instead of loose.
3. **A three-property entrance tier** — opacity, scale from 0.85, and a small
   rise — so a member's arrival is not only a fade. We have `SpanFade` and
   `SpanTravel`; what is missing is the scale term and a single spelling of the
   three together.
4. **Reconsider the exit ratio.** Ours is the spec's 2:1. Theirs is 4:1 and
   feels sharper for it. This is a taste call, not a correctness one, and it
   should be made once and centrally rather than per surface.

Explicitly **not** taken: their reset-and-replay idiom as a general pattern
(`resetContentEntrance()` / `startContentEntrance()` with a generation counter
and `Qt.callLater`). The second survey already declined it in its §3.14 and
nothing measured here changes that — it is imperative state doing what a
declarative `Behavior` and a delay do, and the generation counter exists to
undo the race the imperative version creates.
