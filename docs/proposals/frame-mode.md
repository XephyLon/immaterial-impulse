# Proposal: frame mode

> Draft / tracking proposal. Not scheduled.

## Goal

An optional **frame mode** that draws the shell's surfaces as one continuous
connected surface rather than a set of floating islands: the bar, screen edges,
and screen corners form a frame, and modals (launcher, notifications, popouts)
visually dock into that frame instead of hovering over the wallpaper.

Reference point: the Caelestia shell's connected-surface look.

## Current state

The shell is built as independent surfaces. `panelFamilies/ImmaterialImpulseFamily.qml`
registers each one as its own `PanelLoader`:

```
Bar, Background, Cheatsheet, Dock, Lock, MediaControls, NotificationPopup,
OnScreenDisplay, OnScreenKeyboard, Overlay, Overview, Polkit, RegionSelector,
ScreenCorners, Screensaver, ...
```

Each anchors and rounds itself independently, and `modules/imi/screenCorners/ScreenCorners.qml`
already draws screen-edge corners as a separate surface — so the ingredients for
a frame exist, but nothing coordinates them.

That single registry is the natural anchor for this work: frame mode is
fundamentally about making those surfaces aware of each other's geometry.

## Why

- It is a distinct visual identity, not just a theme. The current look is
  conventional floating panels; a connected frame is what makes shells like
  Caelestia recognizable at a glance.
- The pieces are already there — `ScreenCorners`, bar anchoring, per-surface
  rounding — but uncoordinated, so the shell pays the cost of edge-drawing
  without the payoff of a coherent frame.
- Corner treatment is currently the most visible inconsistency between surfaces,
  and the same problem the shared `ExpandablePanel` work solved at widget scale
  (a header's rounded corners must square off where content joins it).

## Approach

- A single geometry authority — the frame owns which edges are occupied, how
  thick each is, and where the inner rounded corners fall. Surfaces query it
  rather than each computing rounding independently.
- Extend the per-corner radius pattern already established on `RippleButton`
  (`cornerTopLeft`/`cornerTopRight`/`cornerBottomLeft`/`cornerBottomRight`) to
  shell surfaces, so a surface can square exactly the edges where it meets the
  frame and stay rounded elsewhere. This is the same fix, one scale up.
- Modals attach to a frame edge: the launcher grows out of the bar rather than
  appearing centered over the wallpaper; notifications slide from the frame edge
  they are anchored to.
- Gate the whole thing behind a config option, defaulting **off**. Frame mode is
  a look, not a correctness fix, and the existing floating look must remain
  available.

## Risks

- This touches nearly every surface in `ImmaterialImpulseFamily.qml`. It should
  be built incrementally — frame geometry first, then one surface at a time —
  not as a single cutover.
- Multi-monitor and mixed-DPI setups make frame geometry substantially harder
  than it looks; per-screen frames are almost certainly required rather than one
  global frame.
- Vertical bar mode (`Config.options.bar.vertical`, which already gates the
  `Bar` loader) changes which edge the frame is thick on, so it must be part of
  the geometry model from the start rather than retrofitted.

## Out of scope

- Redesigning the individual surfaces' contents.
- Removing or replacing the existing floating look.
- Animating transitions between frame mode and floating mode.
