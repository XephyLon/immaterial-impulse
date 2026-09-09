# Proposal: an overlay enter/leave motion tier

> Draft / tracking proposal. Not scheduled. Re-derived from the unmerged
> branch `feat/overlay-transitions` (2026-08-02, five commits, now 2,300+
> commits behind main); the branch is prior art, not a base. Paths are
> relative to `dots/.config/quickshell/imi/` unless written repo-relative.

## Goal

The full-screen overlays — cheatsheet, session menu, drop shelf, desktop
menu, screenshot toast — get one shared enter/leave motion (a scrim fade plus
a card scale-and-rise, and the reverse on leave) instead of appearing and
vanishing in one frame.

## Current state

- The bar popups, sidebars and the launcher have real motion: they use the
  `Appearance.animation` tiers and, for the bar, `BarPopupOverlay.qml`'s
  card motion with `mask: Region { item: card }`.
- The overlays do not. `modules/imi/cheatsheet/`, `modules/imi/sessionScreen/`,
  the drop shelf, the desktop menu and the screenshot result window each set
  `visible` on a layer surface and draw the next frame in place. There is no
  overlay tier in `Appearance.qml` and no shared component they could use.
- The 2026-08-02 branch built exactly that: a motion tier, two driver
  widgets (an `OverlayScrim` and an `OverlayCard`), moved the five surfaces
  onto them, and covered the tier statically and at runtime. It predates the
  panel-family registry, the M3 motion multiplier (`appearance.motion`),
  reduce-motion, and the ext-background-effect blur regions, so its code does
  not apply, but its design and its two recorded traps do.

## Why

- These are the largest surfaces in the shell and the only ones that still
  pop. The contrast with the bar and sidebars is the most visible motion
  inconsistency left after 1.0.
- One shared tier means one place to honour `appearance.motion.multiplier`
  and `reduceMotion`, instead of five.
- The leave half matters for correctness, not only looks: a surface hidden
  in one frame drops its blur region and its exclusive zone at once, which is
  the flash the bar popups already solved.

## Approach

**1. The tier.** In `modules/common/Appearance.qml`, beside the existing
tiers: `animation.overlayEnter` (about 250 ms, emphasized-decelerate) and
`animation.overlayLeave` (about 180 ms, emphasized-accelerate), both scaled
by the motion multiplier and collapsed to 0 under reduce-motion.

**2. Two widgets** in `modules/common/widgets/`:

- `OverlayScrim` — full-surface `Rectangle` that fades its opacity on the
  tier; owns nothing else.
- `OverlayCard` — the content container: opacity 0→1, scale 0.96→1, y offset
  +12→0 on enter; the reverse on leave. Exposes `open` and a `closed()`
  signal fired when the leave animation ends, so the host hides the surface
  **after** the motion, not before.

**3. The two traps the branch recorded**, kept as tests:

- **Hide after leave.** A host that sets `visible = false` when `open` flips
  never shows the leave motion. The card's `closed()` is the only place the
  surface may hide; a static lint greps each overlay host for `visible:`
  bound to the open state and fails it.
- **Input during leave.** A leaving overlay must not eat clicks: the host
  drops its keyboard focus and input region when `open` flips, and only the
  visuals wait. Otherwise the 180 ms of leave motion is 180 ms of dead
  desktop.

**4. Migration**, one surface per PR in this order: screenshot toast (smallest),
desktop menu, session menu, drop shelf, cheatsheet (largest, has its own
inner tabs). Each PR is a live-load check plus the runtime test from the
branch, rewritten against the current harness.

**5. Blur regions.** The overlays that blur through `WindowBlurRegion`
publish their region from the card's settled geometry, so the region
appears when the card has landed and goes when leave begins; the blur then
never outlives the card.

## Risks

- **Layer-shell timing.** A layer surface mapped and animated in the same
  frame can show one unanimated frame on some compositors; the card starts
  at opacity 0 and animates from the first frame after map, which the
  runtime test asserts by sampling opacity at t=0.
- **Cheatsheet size.** It is the heaviest overlay; scaling a large item every
  frame is a layer texture the size of the screen. The card sets
  `layer.enabled` only during the motion, as `PluginWidget.qml` does for
  widgets.
- **Reduce motion.** Zero durations must still fire `closed()`; the test
  covers the multiplier at 0.

## Open questions

- Should the session menu's confirm buttons appear staggered (the M3 "list
  entrance") or with the card? Proposal: with the card; stagger is a
  follow-up.
- Does the drop shelf, which can stay open while the user works, want the
  same leave motion as a dismissed dialog? Proposal: yes, shorter.

## Out of scope

- Shared-element transitions between overlays.
- The lock screen's enter/leave, which has its own peel.
