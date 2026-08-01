# Dock Feedback Motion (M3 Expressive) — Design

**Goal:** Give the dock personality through feedback animations while staying
M3 Expressive compliant — every duration/curve from `Appearance.animation.*` /
`Appearance.animationCurves.*`, no ad-hoc literals.

**Decisions (user-confirmed):**
- All four feedback moments: hover lift, press/launch feedback, open/close
  transitions, active-state motion.
- Hover style: subtle M3E lift (single icon; no macOS proximity wave, no
  neighbor nudge).
- Launch-pending style: rhythmic bounce until the window maps (timeout
  fallback).
- Coverage: both pinned apps (`DragApps.qml` delegates) and running unpinned
  apps (`DockAppButton.qml`).

## Architecture

Approach A — shared motion component + launch tracker. One implementation,
consumed by both button flavors, so pinned/unpinned can never drift apart.

### New: `modules/common/widgets/DockIconMotion.qml`

Reusable `Item` wrapper placed around a dock icon's visual content. Pure
presentation — owns transforms only, never layout size (scale/translate via
`transform`, so the dock's row width never churns on hover).

Interface (all inputs declarative):

```qml
Item {
    property bool hovered: false     // consumer's hover state
    property bool pressed: false     // consumer's press state
    property bool launching: false   // from DockLaunchTracker
    property bool dragging: false    // true => all motion suppressed
    default property alias content   // the icon visuals
}
```

Behaviors, in priority order (dragging kills everything):

1. **Press squish** — `scale` to `0.92` while `pressed`; release springs back
   with `expressiveFastSpatial` overshoot. Press-in uses `elementMoveFast`
   (effects curve — fast, no bounce on the way down).
2. **Launch bounce** — while `launching`: looped `SequentialAnimation` on the
   vertical translate: hop up 8 px (`expressiveEffects` out), fall back
   (`expressiveEffects` in), brief grounded pause. Loop stops cleanly at
   ground level when `launching` clears (animation stops at loop boundary via
   `alwaysRunToEnd: true`).
3. **Hover lift** — `scale` to `1.15` and vertical translate `-3` px while
   `hovered` (and not pressed/launching), both through
   `expressiveFastSpatial` spring. Ripple from the underlying button remains.

### New: `services/DockLaunchTracker.qml` (singleton)

Tracks app launches between click and window map.

- `markLaunching(appId)` — called by both button flavors when a click/middle
  click executes a desktop entry.
- `isLaunching(appId)` → bool, reactive (internal `property var pending`
  map + change signal).
- Auto-clear on either:
  - `TaskbarApps` gaining a toplevel for that appId (connection watching the
    apps model), or
  - 10 s timeout (one `Timer` per pending entry, created imperatively).
- No persistence; process-local state only.

### Consumers

- **`DockAppButton.qml`** — wrap the icon `contentItem` internals in
  `DockIconMotion`; feed `hovered` from the existing hover `MouseArea` (plus
  the button's own hover for the no-toplevel case), `pressed` from the
  RippleButton, `launching: DockLaunchTracker.isLaunching(appToplevel.appId)`.
  Call `markLaunching` in the zero-toplevel `onClicked` branch and in
  `middleClickAction`.
- **`DragApps.qml`** pinned delegates — same wrap around the delegate's icon;
  `dragging` bound to the delegate/global drag state so motion never fights
  reorder. `markLaunching` on its launch path.
- **Open/close transitions** (`Dock.qml` + `DockAppButton.qml`): the
  running-apps `Repeater` delegates get an entrance (scale 0.6→1 + fade,
  `elementMoveEnter` / emphasizedDecel). Exit: the existing animated
  `implicitWidth` behavior on `activeAppsArea` already collapses the row;
  keep that as the exit motion (Repeater teardown can't run exit animations
  without a full ObjectModel rework — out of scope, YAGNI).
- **Active-state motion** (`DockAppButton.qml` count dots): `Behavior on
  implicitWidth` (`elementMoveSmall` spatial spring) and `Behavior on color`
  (`elementMoveFast`) on the dot rectangles, so focus changes spring instead
  of snapping. Dot count changes ride the entrance animation of the dot
  `Repeater` delegates. (Shape-morph "pill" behind the active icon:
  deliberately dropped — dots motion covers the state change; revisit only if
  it feels flat in use.)

## Error handling / guards

- `dragging == true` suppresses hover/press/launch motion (binding priority in
  DockIconMotion).
- Launch tracker timeout guarantees no infinite bounce for apps that never
  map a window (or map with a different appId — known limitation, timeout
  covers it).
- `alwaysRunToEnd` on the bounce loop prevents mid-air freeze when state
  clears.
- Monochrome-icon overlay (`Desaturate`/`ColorOverlay` in DockAppButton)
  must live inside the motion wrapper so it transforms with the icon.

## Testing

- New `tests/test_dock_motion.py` (contract style, like existing suites):
  - `DockIconMotion.qml` exists and references only `Appearance.animation.*`
    / `Appearance.animationCurves.*` (no raw duration integers except 0).
  - Both `DockAppButton.qml` and `DragApps.qml` instantiate `DockIconMotion`.
  - `DockLaunchTracker` has a timeout mechanism and is called from both
    launch paths.
  - Dot rectangles have Behaviors on width and color.
- Wire into `run_tests.sh`; full suite green.
- Live visual check on the desktop (hover, click-launch of a slow app,
  open/close windows, focus switches, drag-reorder unaffected).

## Out of scope

- macOS proximity magnification.
- Exit animation for removed running-app buttons (Repeater teardown).
- Active-app pill/shape morph.
- Bar's `DocktoPanel` and DockMedia internals (unchanged; DockMedia already
  has its own motion).
