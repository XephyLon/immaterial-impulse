# Morphing hover overlay for bar popups — design

**Status:** design, not implemented
**Issue:** [#140](https://github.com/XephyLon/immaterial-impulse/issues/140)
**Scope:** `modules/common/widgets/StyledPopup.qml` and its ten users; one new panel
(`modules/imi/bar/BarPopupOverlay.qml`)

Paths below are relative to the theme root `dots/.config/quickshell/imi/` unless written
repo-relative. Quickshell C++ citations are against the checkout at
`/home/xephy/dev/qs-wallpaperengine/build/quickshell` (`e649d24`).

## Problem

Each bar widget opens its own layer-shell popup. Hovering from clock to weather destroys one
surface's visibility state and reveals another with no relationship between them. Ten surfaces,
ten shadows, ten compositor map animations.

The target: one card that travels and resizes along the bar while its content cross-fades, and
that shrinks toward its owning widget before fading on exit.

## Settled input (issue #140, do not relitigate)

- **Participants:** all ten `StyledPopup` users.
- **Morph:** travel and resize together, content cross-fading during the move.
- **Exit:** shrink toward the owning widget, then fade.
- **Architecture:** one **static** full-screen layer surface per screen, morphing a `Rectangle`
  inside it, `mask: Region { item: card }`. The surface's own geometry never animates —
  `StyledPopup.qml:112-120` records why (binding the margins reintroduced a create-map-destroy
  loop; on a layer surface, position *is* `margins`).

`DesktopMenu.qml` is the cited precedent for the *window* shape (full-screen `PanelWindow` +
animating card, `DesktopMenu.qml:119-181`). One correction worth carrying into implementation: it
does **not** use a mask — it deliberately swallows the whole screen with a dismiss `MouseArea`
(`DesktopMenu.qml:150-154`) because it is modal. For the masked-window-over-a-card half of the
shape the in-tree precedents are `NotificationPopup.qml:42-44` (a mask over a
`ListView.contentItem` whose delegates animate) and `Dock.qml:57`.

---

## 1. Content ownership — the load-bearing decision

### What the code actually does today

`StyledPopup` is a `LazyLoader` whose `component` is the `PanelWindow`
(`StyledPopup.qml:10, 75`). Content arrives through `default property Item contentItem`
(`StyledPopup.qml:13`) and is **reparented into the popup window** once the card exists:

```qml
// StyledPopup.qml:191-197
Component.onCompleted: {
    if (popupWindow.innerContent) {
        popupWindow.innerContent.parent = popupBackground
        popupWindow.innerContent.anchors.centerIn = popupBackground
    }
}
```

So cross-window reparenting of popup content is not a new idea to be evaluated — **it is the
mechanism already in production**, on every one of the ten popups.

### Three facts established by probe, not by reasoning

Run offscreen with `qml6`, no compositor, no shell touched:

**(a) Content is already eager. `active: everShown` (`StyledPopup.qml:29`) makes the *window*
lazy; it does nothing for the content.** An inline object assigned to a `default property Item`
on a non-visual holder is constructed with its holder. Probed: the holder's `contentItem` is a
live `QQuickRectangle` with a correct `implicitWidth` at the enclosing component's
`Component.onCompleted`, with `parent = null` and `Window.window = null`.

Consequence: today, at shell start, all ten popup content trees (the clock's whole calendar,
NetworkSpeed's five `StyledPopupValueRow`s, Weather's forecast column) already exist, unparented,
with live bindings. **"Keep all ten alive" is the status quo, not a new cost.** Nobody has to
argue for it.

**(b) An unparented content tree does not polish, so its implicit size is stale.** Probed: a
`ColumnLayout` whose child's `implicitWidth` binding changed from 100 to 300 still reported 100
after a full event-loop turn while unparented, and reported 300 on the first frame after being
parented into a windowed item. `QQuickLayout` and `QQuickPositioner` both size on the polish
pass, and polish only runs for items in a `QQuickWindow`.

This is not a corner case — it is nine of the ten. `WeatherPopup.qml:11`,
`BatteryPopup.qml:21`, `NetworkSpeedPopup.qml:122`, `DockerPopup.qml:39` and
`DiscordVoicePopup.qml:24` root a `ColumnLayout`; `SysTray.qml:117` a `GridLayout`;
`ResourcesPopup.qml:14` a `Row` positioner (also polish-driven); and
`PrivacyIndicatorPopup.qml:56` is a plain `Item` whose `implicitHeight` is
`column.implicitHeight` — a `ColumnLayout`, so it inherits the staleness through the binding.
Only `ClockWidgetPopup.qml:14` is immune: its `implicitHeight` is
`pendingLabel.y + pendingLabel.height`, pure anchors, which resolve immediately.

**Consequence for the morph: you cannot measure the incoming popup before you parent it.** The
target geometry is not knowable one frame ahead.

**(c) Destroying the declaring widget destroys the content even while it is on display.** Probed:
after reparenting content into a card and then `destroy()`ing its holder, the JS handle went null
and `card.children.length` went to 0. `QQuickItem::setParentItem` changes the *visual* parent; the
`QObject` parent stays the declaring `StyledPopup`.

This is reachable in normal use: bar widgets are built by `Loader { source: getWidgetUrl(...) }`
over a `Repeater` on the layout arrays (`BarContent.qml:65-76, 193-209`), and
`BarContent.filterLayout` (`BarContent.qml:46-59`) drops `sysTray` when the tray empties and drops
`plugin:*` when a plugin is disabled. Disabling the Docker plugin while its card is on screen
deletes the content out from under the card.

### Decision

**Reparent one at a time. Do not stack all ten in the card.**

- Content stays declared exactly where it is, in `ClockWidgetPopup.qml` &c., unparented and
  windowless, as it already is.
- On takeover, the overlay parents the **incoming** content into the card's content host at
  `opacity: 0`.
- The **outgoing** content stays parented for the duration of the cross-fade, then is set back to
  `parent = null`.
- **At most two content trees are ever in a window.** Never ten.

The alternative — parking all ten inside the card and animating opacity — puts ten layout trees
into a live window permanently: ten polish passes per frame, ten scene-graph subtrees, and ten
sets of relayout bindings in the one place this codebase has repeatedly turned relayout into a
CPU-pegging freeze (AGENT.md → "Any `.qml` that references `Appearance` … NaN geometry …
relayout never converges"; `BarContent.getWidgetUrl`'s comment about "multi-gigabyte relayout
loops" at `BarContent.qml:67-70`). Reject it.

The "keep per-widget `Loader`s and cross-fade two at a time" option is the same thing as
reparenting, with an extra `Loader` per popup that buys nothing: the content objects already exist
whether or not a `Loader` fronts them (fact **a**), so the `Loader` would only add a destroy/rebuild
cycle on every hover — which is precisely the churn a shared surface exists to remove.

### What the lazy-build guarantee becomes

It was never a build guarantee; it was a *window* guarantee. Restate it honestly:

> **No popup content is in a window until it is shown, and no more than two are in a window at
> once.**

That is strictly stronger than what ships today for the ten-popup case (today, once `everShown`
flips, each popup keeps its own mapped-but-hidden window and its content parented into it,
forever — ten windows and ten windowed content trees after a user has hovered everything once).
Sharpening this is a real win, not just a wash.

If genuinely lazy *construction* is wanted later, it is a separate change to the ten call sites
(wrap each content in a `Loader` with `active: root.everShown`) and is orthogonal to this design.
Do not bundle it: it would change what `implicitWidth` reads as on first show, and this feature
already has enough first-show timing in it.

### API shape

`StyledPopup` keeps its filename, its default property, and all ten call sites unchanged. It stops
being a `LazyLoader` with a `PanelWindow` and becomes a **declaration + hover state machine** that
publishes itself into `GlobalStates.activeBarPopup`. The overlay reads it.

Kept verbatim: `hoverTarget`, `contentItem`, `contentPadding`, `popupBackgroundMargin`,
`pinnedOpen`, `targetHovered`, `popupHovered`, `hoverHeld`, `popupVisible`, `updateHoverHold()`,
`hoverCloseTimer`.

Three call sites reach past the public API and must be edited with the switch:

| Site | Today | Becomes |
|---|---|---|
| `SysTray.qml:115` | `active: root.trayOverflowOpen && …` (overrides `LazyLoader.active`) | `pinnedOpen` alone carries it; drop `active:` |
| `DockerPlugin.qml:139` | `popupLoader.item?.item` (the `PanelWindow`) | `popupLoader.item?.surfaceWindow`, a read-only alias the overlay writes back onto the popup it owns |
| `DiscordVoicePlugin.qml:70` | same | same |

No new singleton. `GlobalStates.activeBarPopup` (`GlobalStates.qml:49-53`) already exists and
already means "the popup that most recently claimed the slot" — this design only changes what
watching it does. Avoiding a new `pragma Singleton` matters here: a new singleton only registers
on a full `qs` restart, never on hot reload, which would make every increment of the landing plan
below un-hot-reloadable.

---

## 2. Geometry

### The surface

`modules/imi/bar/BarPopupOverlay.qml`, a `Scope` with a `Variants` over the same screen model as
`Bar.qml:17-24`, one `PanelWindow` per screen, added to `ImmaterialImpulseFamily.qml` alongside
the existing bar entries (`panelFamilies/ImmaterialImpulseFamily.qml:32, 51`) with no
`extraCondition` — it serves both bars, because `VerticalBarContent.getWidgetUrl` loads the same
`../bar/*.qml` widget files (`VerticalBarContent.qml:63-67`).

The window declares, and never changes:

```qml
anchors { top: true; bottom: true; left: true; right: true }
color: "transparent"
exclusionMode: ExclusionMode.Ignore
exclusiveZone: 0
WlrLayershell.namespace: "quickshell:popup"
WlrLayershell.layer: WlrLayer.Overlay
```

No `margins` block, no `implicitWidth`, no `implicitHeight`. Anchoring all four edges makes the
window's content-item coordinate space equal to screen coordinates, which removes the whole class
of "which edge is the bar on" arithmetic from the *surface* and leaves it only in the card's
target computation.

Keep the `quickshell:popup` namespace rather than minting a new one. AGENT.md → Layer-shell
gotchas, "`quickshell:popup` is already handled", documents what that namespace's
`ignore_alpha = 1` (`rules.lua:157`) actually does: it blurs the opaque body and skips the
translucent shadow, which is the split the region mechanism exists to produce, and it is already
correct for the card. A new namespace would fall through to the catch-all `ignore_alpha = 0.05`
(`rules.lua:143`), under which a permanently-mapped full-screen surface's *transparent* pixels
clear the threshold and the compositor is asked to blur the entire screen. Reusing the namespace is
a one-word decision that avoids a rules.lua change and a very bad default. See §5 for what must
**not** be added to it.

### Target derivation

Reuse `updatePosition()`'s mapping unchanged (`StyledPopup.qml:94-110`) for the **along-bar** axis
and replace the across-bar axis with a constant, because the overlay is now screen-anchored rather
than bar-edge-anchored:

```
m   = Appearance.sizes.elevationMargin          // Appearance.qml:571 → spacing.space125 → 10
t   = popup.hoverTarget
tw  = popup.barThickness                        // StyledPopup.qml:73

along (horizontal bar):
  cardX = clamp(t.QsWindow.mapFromItem(t, (t.width  - cardW)/2, 0).x, m, screen.width  - cardW - m - 10)
across, edge "top":     cardY = tw + m
across, edge "bottom":  cardY = screen.height - tw - m - cardH

along (vertical bar):
  cardY = clamp(t.QsWindow.mapFromItem(t, 0, (t.height - cardH)/2).y, m, screen.height - cardH - m - 15)
across, edge "left":    cardX = tw + m
across, edge "right":   cardX = screen.width - tw - m - cardW
```

`t.QsWindow.mapFromItem(...).x` is already screen-x: the horizontal bar window spans the full
width from x=0 (`Bar.qml:142-147`), and the vertical bar spans the full height from y=0. The `10`
and `15` right/bottom slacks are carried over verbatim from `StyledPopup.qml:101, 108` — they are
arbitrary but shipped, and changing them is not this feature's business.

`barEdge`/`barThickness` stay on `StyledPopup` (`StyledPopup.qml:68-73`); the overlay reads them
off the current popup rather than recomputing.

### Animatable targets

The card's `x`, `y`, `width`, `height` are **assigned imperatively** from `retarget()` and smoothed
by `Behavior`s. They are never bound. This mirrors the discipline `updatePosition()` already
enforces, for the same reason: nothing that the card's geometry feeds may also feed back into
computing it.

```qml
Behavior on x      { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
Behavior on y      { ... same ... }
Behavior on width  { ... same ... }
Behavior on height { ... same ... }
```

`elementMove` (`Appearance.qml:323-335`, expressive default spatial) is the right token for a
travel-and-resize: it is the spatial curve, and it is what `DesktopMenu`'s card already uses for
its enter (`DesktopMenu.qml:175-177` uses `elementMoveEnter`; the morph is a move, not an enter).

### The measure-then-morph sequence

Fact (b) says the incoming size is unknown until the content is parented and polished. So:

1. Takeover requested for popup `B` (current is `A`).
2. Parent `B.contentItem` into `contentHost`, `anchors.centerIn: contentHost`, `opacity: 0`.
   Set `B.popupHovered` wiring live; clear `A.popupHovered`.
3. `retargetTimer.restart()` — a zero-interval `Timer`, exactly the device at
   `StyledPopup.qml:116-120`, for exactly the same reason (do the imperative write after the
   frame has settled).
4. On fire: read `B.contentItem.implicitWidth/implicitHeight`, add `2 * B.contentPadding`, clamp
   per the table above, assign `card.x/y/width/height`. The `Behavior`s animate.
5. Cross-fade: `A.contentItem.opacity → 0` on `elementMoveExit` (`Appearance.qml:366-378`,
   emphasized-accel), `B.contentItem.opacity → 0 → 1` on `elementMoveEnter`
   (`Appearance.qml:351-363`, emphasized-decel). Run the exit at the start of the move and the
   enter over its back half — the M3 reading of "cross-fading during the move".
6. When `A`'s fade completes, `A.contentItem.parent = null`. Guard on `A` still being the outgoing
   item (a third takeover may have started).

The one-frame deferral in step 3 costs ~16 ms of latency, invisible against the 180 ms hover
grace, and buys a correct first target instead of a two-stage snap from a stale implicit size.

### What drives size when outgoing and incoming differ

**Nothing but the incoming content.** The card's `width`/`height` are explicit; the outgoing
content is never consulted after the takeover. The outgoing tree simply fades while the card
resizes out from under it.

Concretely, the card holds:

```qml
Item {
    id: contentHost
    anchors { fill: card; margins: <current popup>.contentPadding }
    clip: true
}
```

`clip: true` is load-bearing: when the card shrinks, the outgoing content is larger than the host
and would otherwise paint outside the card's rounded body. Clipping is rectangular, but the
content is inset by `contentPadding` on all sides so it never reaches the corner radii.

Live resize of the *shown* content (the clock ticking a row in, NetworkSpeed's rows changing)
retargets through the same path — a `Connections` on the current content's
`implicitWidthChanged`/`implicitHeightChanged` calling `retargetTimer.restart()`, which is the
direct analogue of `StyledPopup.qml:133-137`.

### Multi-monitor

Each overlay accepts a claim only if
`GlobalStates.activeBarPopup.hoverTarget.QsWindow.window.screen === modelData`. Otherwise it plays
its exit. Today's single global slot already closes a popup on monitor A when a widget on monitor
B is hovered; this preserves that and makes it explicit.

---

## 3. Handoff

`GlobalStates.activeBarPopup` changes meaning from "the popup that just claimed the slot, so
everyone else should close" to "**the popup the card is showing, or morphing to**". The claim
itself (`StyledPopup.qml:46-51`) and the grace timer (`StyledPopup.qml:41-44`) are unchanged.

The overlay derives:

```qml
readonly property var requested: {
    const p = GlobalStates.activeBarPopup
    if (!p || !p.popupVisible) return null
    if (p.hoverTarget?.QsWindow?.window?.screen !== modelData) return null
    return p
}
onRequestedChanged: requested ? takeOver(requested) : beginExit()
```

`StyledPopup.qml:57-66` — the "a different popup took over, drop my grace period" `Connections` —
**stays exactly as written.** Its comment about not overlapping the incoming popup is now
redundant (there is only one card) but its effect is still what we want: the outgoing popup's
`popupVisible` goes false immediately, so the morph starts on the same frame the pointer lands on
the new widget instead of 180 ms later.

### Pointer moves to a non-participating widget

Workspaces, the active-window title, the util buttons — none of them claim the slot. `A`'s
`targetHovered` goes false, `updateHoverHold()` restarts the 180 ms timer
(`StyledPopup.qml:32-39`), and if nothing reclaims within it, `popupVisible` goes false and the
card exits.

**Do not add "any bar hover closes the card immediately".** The 180 ms is what makes travelling
across a gap between two participating widgets forgiving, and shortening it to zero for
non-participants would make a two-pixel overshoot between clock and weather kill the morph.

### Pointer leaves the bar entirely

Identical path — there is no separate case. `hoverCloseTimer` fires, `popupVisible` goes false,
the overlay plays the exit.

**Exit choreography.** Shrink toward the owning widget, then fade:

1. Compute the shrink anchor: the centre of `popup.hoverTarget` mapped into overlay coordinates,
   projected onto the card's leading edge (bar-adjacent side).
2. Animate `width`/`height` toward a small floor (not zero — see §5) and `x`/`y` toward the anchor
   on `elementMoveExit`.
3. When the shrink completes, animate `card.opacity → 0` on `elementMoveFast`
   (`Appearance.qml:381-397`).
4. When opacity reaches 0, set `width = 0; height = 0`, unparent the content, clear
   `GlobalStates.activeBarPopup` if it still points at the exiting popup.

Step 4's geometry collapse is not cosmetic. See §5.

If a new claim arrives mid-exit, cancel at whatever geometry the card currently has and morph from
there. A morph interrupted by a re-hover of the widget it is leaving must look like the card
snapping back, not like a close followed by an open.

### `pinnedOpen`

`pinnedOpen` popups (`SysTray.qml:114`, `DockerPlugin.qml:123`, `DiscordVoicePlugin.qml:70`) are
click-toggled, not hover-driven, and two of them arm a `HyprlandFocusGrab` over
`[barWindow, popupWindow]` (`DockerPlugin.qml:133-155`, `DiscordVoicePlugin.qml:75-95`).

**DECIDED — pinned holds the card. A hover claim is refused while a popup is pinned.** Do not
reopen this.

While `current.pinnedOpen` is true, `StyledPopup.onTargetHoveredChanged` does not write
`GlobalStates.activeBarPopup` if the existing occupant is pinned and is not itself. Clicking the
tray overflow while the clock card is up morphs the card across to the tray and locks it there;
clicking again releases it and the card exits (or immediately re-claims for whatever is under the
pointer).

The guard lives in `StyledPopup.onTargetHoveredChanged` (`StyledPopup.qml:46-51`), not in the
overlay's `takeOver`. That placement is part of the decision: the slot is the shared resource, so
refusing to *claim* it is one condition on one write, whereas refusing to *honour* a claim would
leave `GlobalStates.activeBarPopup` pointing at a popup the card is not showing — a second, silent
notion of "current" for every later reader to get wrong.

**Rationale, and the accepted cost.** A pinned popup is the result of a deliberate click, often
with a focus grab held over it; a hover is an accident of where the pointer passed. Letting the
accident evict the deliberate act would take the tray overflow or the Docker panel out from under
a pointer merely travelling across the bar. The cost, accepted by the user: **while a popup is
pinned, hovering another bar widget produces nothing at all — no card movement, no feedback.** The
bar looks unresponsive to hover until the pinned popup is dismissed. That is the intended
behaviour, not a bug to fix later; the alternative (hover steals the card and force-unpins) was
considered and rejected.

`surfaceWindow` on the pinned popup resolves to the overlay's `PanelWindow`, so the focus grab
still has two windows to hold. **Whether a grab over a full-screen-but-input-masked surface still
clears on an outside click cannot be determined statically** — the click falls outside the input
region, so it should reach a different surface and clear the grab, but Hyprland's grab bookkeeping
is per-surface, not per-region. This is the one genuinely open question left in the design —
experiment in §7, item 4.

### Clicking inside the card mid-morph

The mask follows the animating card per frame (§5), so the click target is wherever the card
visually is. But the *content* under the pointer may be the outgoing tree at 40% opacity, whose
buttons are still live.

**Rule: the outgoing content is `enabled: false` from the instant a takeover starts.** It fades as
a picture, not as a control. `enabled: false` on a plain `Item` cascades to its children — but
`ClockWidgetPopup`'s content root is an `Item` while `SysTray`'s is a `GridLayout` and
`Resources`' is a `Row`, all plain items, so the cascade holds. Note AGENT.md's warning that
`enabled` does **not** cascade through a `MouseArea` (which redeclares it); none of the ten
content roots is a `MouseArea`, but a future one must not be.

The incoming content is `enabled: true` from the moment it is parented, so a fast pointer that
lands on the new card before the morph settles interacts with the new content — which is what the
pointer was aimed at.

---

## 4. Bar orientation

`barEdge` already resolves all four cases (`StyledPopup.qml:68-73`): horizontal → `top`/`bottom`
from `Config.options.bar.bottom`; vertical → `left`/`right` from the same key.

Because the overlay is anchored to all four screen edges, orientation changes **nothing about the
surface** — no reconfigure, no remap, no `margins` to recompute. It changes only:

| `barEdge` | fixed axis | animated axis | shrink direction on exit |
|---|---|---|---|
| `top` | `y = barThickness + m` | `x`, `width`, `height` | up, toward the widget |
| `bottom` | `y = screen.height - barThickness - m - h` | `x`, `width`, `height` | down |
| `left` | `x = barThickness + m` | `y`, `width`, `height` | left |
| `right` | `x = screen.width - barThickness - m - w` | `y`, `width`, `height` | right |

Two consequences worth writing down:

- On `bottom` and `right` the fixed axis is a function of `height`/`width`, which are themselves
  animating. Assign both from the same `retarget()` call so they stay consistent; do **not** bind
  `y` to `height`. A binding there is a live feedback path between two animating properties and is
  the shape of bug that AGENT.md's `Loader`/`implicitWidth` note and the `MouseArea.drag` note are
  both about.
- Flipping `Config.options.bar.vertical` swaps which panel family entry is loaded
  (`ImmaterialImpulseFamily.qml:32, 51`) and rebuilds every widget, so every `StyledPopup` is
  rebuilt and the slot is empty. The overlay must handle `GlobalStates.activeBarPopup` pointing at
  a destroyed object — the same null-guard fact (c) demands anyway. A `barEdgeChanged` handler
  should force the card to idle rather than trying to morph across an orientation change; there is
  no sensible interpolation between "10px below the top edge" and "10px right of the left edge".

---

## 5. Shadow and mask

### The mask follows an animating item. This is settled by source, not by hope.

`PendingRegion::setItem` connects the tracked item's `xChanged`, `yChanged`, `widthChanged` and
`heightChanged` to its own `itemChanged` (`src/core/region.cpp:39-46`), and the constructor wires
`itemChanged → changed()` (`src/core/region.cpp:16`). `ProxyWindowBase::setMask` connects
`PendingRegion::changed → onMaskChanged` (`src/window/proxywindow.cpp:472`), which sets
`pendingPolish.inputMask` and schedules a polish (`src/window/proxywindow.cpp:523-524`). The
region is rebuilt and `window->setMask()` called once in `onPolished`
(`src/window/proxywindow.cpp:660-667`).

So: **an animating card updates its mask once per frame, coalesced, automatically. No republishing
is needed.**

`WindowBlurRegion`'s publish-now-and-settle pair (`WindowBlurRegion.qml:86-111`) is **not** a
counterexample and must not be copied here. That republishes an `ext-background-effect` region — a
*protocol* commit to the compositor that can be dropped if it lands mid-configure, which is why it
re-sends after map/resize, and why AGENT.md's "a blur region is published on the *timer* for panels
built by a `LazyLoader`" point exists at all. The input mask is a `wl_surface` input-region
attribute, applied by Qt on polish, on a surface that in this design never reconfigures and is
never unmapped. Different mechanism, different failure mode, no timer — and the permanently-mapped
surface means the "no layer surface yet at `Component.onCompleted`" case that motivated that
AGENT.md point cannot arise here either.

### Three caveats that constrain the animation

**(i) Transforms are not tracked.** `build()` uses `mapToScene`
(`src/core/region.cpp:157-158`), so a scaled card would produce a *correct* region — but nothing
connects `scaleChanged` or `rotationChanged` to `changed()`. **Express the morph and the exit as
`x`/`y`/`width`/`height`, never as `scale`.** If a scale pop is ever wanted, `changed()` is
declared exactly for this and is documented as manually emittable
(`src/core/region.hpp:161-165`) — `maskRegion.changed()` from a 16 ms `Timer` for the animation's
duration.

**(ii) Opacity is not tracked either.** A card faded to `opacity: 0` still has full width and
height, so its mask is still a live click-eating rectangle. This is the concrete mechanism behind
the "input masking swallows clicks" risk. Hence §3's exit step 4: **collapse `width`/`height` to
0 after the fade**, and only then. `PendingRegion::build()` on a 0×0 item yields an empty region,
`onPolished` then sets `Qt::WindowTransparentForInput`
(`src/window/proxywindow.cpp:666`), and the entire full-screen surface becomes input-invisible.
That flag is the safety net for the idle state and it is worth stating as the invariant:

> **Invariant: when no popup is current, the card is 0×0 and the overlay window carries
> `Qt::WindowTransparentForInput`.**

**(iii) Shrink to a floor, not to zero, during the exit.** Collapsing geometry mid-fade would drop
the mask before the card is invisible, which is harmless for input but makes the shrink and the
fade fight over the same frames. Shrink to something like `2 * m`, fade, then zero.

### Shadow

One `StyledRectangularShadow { target: card }`, replacing ten. It follows automatically:
`anchors.fill: target` (`StyledRectangularShadow.qml:7`) and `radius: target.radius`
(`:8`) track the animating card with no extra work.

The one concern is `cached: true` (`StyledRectangularShadow.qml:13`). A cached
`RectangularShadow` renders to an offscreen texture; a card whose width and height change every
frame invalidates that cache every frame, so the caching is pure overhead exactly when the card is
busiest. **Recommendation: bind `cached: !overlay.morphing`** — cached while parked, uncached
while animating. Whether this is measurable or premature cannot be determined without running it
(§7).

The card must keep `elevationMargin` clearance from the screen edges so the shadow is never
clipped by the surface; the clamps in §2 already provide exactly that, which is what the `m` terms
are for.

### Blur

Nothing to add, and two things not to add. AGENT.md → Layer-shell gotchas,
"`quickshell:popup` is already handled, and adding `blur = false` to it breaks it", covers this
namespace exactly: the card's opaque `colLayer1Base` body (`StyledPopup.qml:182`) is blurred
through the namespace's `ignore_alpha = 1` while the translucent shadow is skipped, which is the
split the region mechanism exists to produce. Consolidating ten surfaces into one changes none of
that — the alpha profile of the pixels is identical.

So: do **not** publish a `WindowBlurRegion` from the overlay, and do **not** add `blur = false` for
`quickshell:popup`. AGENT.md gives the failure mode for the second (the region becomes the only
source of blur, nothing reaches it at alpha 1, the surfaces go flat) and
`tests/lint_blur_region_pairing.py` catches the half-landed version of the first. Note also that
`quickshell:popup` is deliberately *outside* the generated-threshold loop in `rules.lua:219-222`
that `services/PopupBlurThreshold.qml` feeds — that threshold is for namespaces whose own `blur` is
off, and this one's is on. Leave it out.

### Untestable

AGENT.md → Layer-shell gotchas, "This whole area is invisible to the test suite", states the
binding constraint: Quickshell's plugin does not load in `qmltestrunner`, so `Region` cannot even be
*constructed* there. No test can observe whether this design's mask is empty, correct, or ignored —
not a gap in coverage, an impossibility. Every claim in this section about how it looks and where
clicks land has to be looked at on screen.

That point also carries the technique this feature needs: prefer a frame-by-frame capture
(`ffmpeg -fps_mode passthrough`) over an impression for anything under ~200 ms. The cross-fade and
the exit shrink both sit in that window, so "it looked fine" is not evidence about either. §7 lists
what to look at.

---

## 6. Migration and risk

### Does `StyledPopup` stay for non-participants?

There are none. All ten users participate, and `StyledPopup` is not used anywhere else
(`PopupToolTip.qml`, `StyledPopupMenu.qml`, `SysTrayMenu.qml` are separate types with their own
windows and are out of scope). So `StyledPopup` stays as the *type* — same file, same default
property, same hover state machine — and loses only its `PanelWindow`.

### Incremental landing

Do not switch ten popups in one commit. The mechanism that makes this incremental is a per-popup
opt-in on `StyledPopup` — **not a `Config` option**, which would be a user-visible setting for a
migration state and would drag in the two-sided settings-page requirement for nothing:

```qml
// StyledPopup.qml
property bool morph: false
active: everShown && !morph      // legacy window path, unchanged, while morph is false
```

Both paths then coexist by construction, and `GlobalStates.activeBarPopup` already coordinates
across them: a legacy popup still closes when the slot changes (`StyledPopup.qml:57-66`), and the
overlay releases the card when the slot holds a non-morphing popup.

The series:

1. **`BarPopupOverlay.qml` + family entry.** Full-screen masked surface, card at 0×0, no
   participants. Verify on screen that an always-mapped full-screen `Overlay` surface with an
   empty mask is invisible and swallows nothing — desktop clicks, a fullscreen game, the desktop
   right-click menu.
2. **`StyledPopup` gains `morph`, `surfaceWindow`, and the overlay handshake**, with `morph`
   false everywhere. Zero behavior change; the diff is inert. This is the commit to review
   carefully.
3. **Clock and Weather opt in.** Two adjacent widgets: the smallest change that can demonstrate a
   morph. Tune the curves here.
4. **Battery, Resources, NetworkSpeed, PrivacyIndicator opt in.** The rest of the hover set.
5. **The pinned three opt in** (SysTray overflow, Docker, DiscordVoice), with the `surfaceWindow`
   and focus-grab edits. Highest risk, most isolated, last.
6. **Delete the legacy path**: remove `morph`, `active`, `everShown`, and the `PanelWindow`
   `component` from `StyledPopup.qml`. Now it is a plain state-machine object.
7. **`AGENT.md` update** — the Layer-shell gotchas section gains the "mask tracks x/y/w/h but not
   transform or opacity" point, and the Design language section's shared-widget list needs
   `StyledPopup`'s description corrected. Per CONTRIBUTING's citation rule, cite the commit from
   step 1 or 2.

Each of 3-5 is independently revertable by flipping one boolean.

### What could regress

**The create-map-destroy loop (named danger).** Avoided structurally: the overlay window declares
no `margins`, no `implicitWidth`, no `implicitHeight`, and is anchored to all four edges, so its
geometry is a constant of the screen. This is a property a static check can hold — CONTRIBUTING's
"twice means mechanize" applies, and this codebase has now paid for surface-geometry bindings
twice (`StyledPopup.qml:112-115`'s comment, and this design existing at all). Add
`tests/lint_bar_popup_overlay_static.py`: fail if `BarPopupOverlay.qml`'s `PanelWindow` block
declares any of `margins`, `implicitWidth`, `implicitHeight`, or if any of `anchors.top/bottom/
left/right` is anything other than `true`. Prove it fails by planting one — in a clean tree
(CONTRIBUTING's plant-only-when-committed rule).

**Input masking swallowing clicks.** The highest-severity failure available here: a full-screen
`Overlay` surface with a wrong mask makes the whole desktop unclickable. Mitigated by the §5
invariant (0×0 when idle → `WindowTransparentForInput`) and by step 1 of the landing plan
verifying the idle state before any popup can reach the card. Watch specifically for the mask
being left large after an exit that was interrupted by a takeover that was itself cancelled.

**Content destroyed while displayed** (fact **c**). Every read of `GlobalStates.activeBarPopup`
and of the current content must be null-guarded, and the overlay needs a
`Component.onDestruction`-driven release on the popup side. Symptom if missed: an empty card
stuck at its last size with a live mask.

**Lazy content becoming eager.** It is already eager (fact **a**), so this cannot regress in the
direction feared. The direction it *can* regress is the reverse: more than two content trees
parented into the card at once, quietly, if a fast pointer starts a third takeover before the
second cross-fade finishes. Guard: `takeOver()` must unparent any tree that is neither the
incoming nor the immediately-outgoing one, synchronously.

**Shadow/blur band.** Nothing here changes blur. But if a future change gives the card a
translucent body, `ignore_alpha = 1` on this namespace puts it *below* the threshold, so it shows
unblurred transparency rather than frost — the `colLayer0`/`colLayer1` trap AGENT.md documents,
reached from the other side. Keep `colLayer1Base`. Note that raising the threshold to accommodate
such a body is not available either: AGENT.md → "`ignore_alpha` is one value per namespace, shared
between a panel and its popups" records that doing exactly that took the blur off the bar, the
dock and both sidebars at once.

**The compositor's map animation disappears.** Today each popup surface maps and unmaps, so
Hyprland plays a layer animation on every show. With a permanently-mapped surface that animation
happens once, ever. The card's own enter/exit is now the *only* motion. If the result reads flat,
the fix is in the card's animation, not in remapping the surface.

---

## 7. Verification — what only the screen can answer

Everything below needs a live shell; none of it is reachable from `tests/run_tests.sh`, and per
AGENT.md `Region` cannot even be constructed under `qmltestrunner`. For items 2, 3 and 5 —
everything that happens inside the ~200 ms of a morph — capture frames
(`ffmpeg -fps_mode passthrough`) and step through them rather than trusting an impression, as
AGENT.md's blur section requires for exactly this duration.

1. **Idle overlay is inert.** With the card at 0×0: click the desktop, drag a window, open the
   desktop right-click menu, run a fullscreen game. Nothing may be swallowed. Cross-check
   `hyprctl layers` shows the surface on `overlay` for the right namespace.
2. **Mask tracks the animation.** Start a clock→weather morph and click a control in the incoming
   content ~100 ms in, while the card is still moving. It must hit. (Predicted yes, from
   `region.cpp:39-46` + the per-polish rebuild; this is the experiment that would prove it.)
3. **Exit leaves nothing behind.** After a full exit, click exactly where the card was. The click
   must reach whatever is beneath. Repeat with an exit interrupted at 50% by a re-hover, and with
   an exit interrupted by a claim on the *other* monitor.
4. **Focus grab still clears.** Open the Docker popup (pinned, grabbed), click a window elsewhere.
   It must close *and* the click must reach the window. This is the single most uncertain claim in
   the design — a grab over a full-screen-but-masked surface has no in-tree precedent.
5. **Shadow caching.** Compare `cached: true` and `cached: false` during a long morph
   (clock→sysTray, the widest travel available) for dropped frames and for shadow artefacting at
   the trailing edge.
6. **All four orientations.** Flip `bar.vertical` and `bar.bottom` through all four combinations
   and morph in each. Confirm no surface reconfigure churn — watch the log for repeated
   layer-surface configure lines, which is what the create-map-destroy loop looked like.
7. **Widget disappears under the card.** With the Docker card up, disable the Docker plugin from
   the settings page. The card must exit cleanly, not strand.
8. **Two monitors.** Hover clock on monitor A, then clock on monitor B. Both cards must not be up
   at once, and B's card must appear on B.

Per CONTRIBUTING, this is a case where "the code you're touching depends on live compositor state
and genuinely can't be unit tested" — say so in the PR rather than skipping silently. The one
mechanizable piece is the static lint in §6, and it should land with step 1.

---

## Open question

One remains, and it needs the shell running rather than a decision:

**Does `HyprlandFocusGrab` still clear on an outside click when the grabbed surface is full-screen
but input-masked?** Docker and DiscordVoice grab `[barWindow, popupWindow]`
(`DockerPlugin.qml:133-155`, `DiscordVoicePlugin.qml:75-95`); under this design `popupWindow`
becomes the always-mapped full-screen overlay. A click outside the card falls outside the input
region, so it should reach a different surface and clear the grab — but Hyprland's grab bookkeeping
is per-surface, not per-region, and there is no in-tree precedent for a grab over a masked
full-screen surface. If it does not clear, the pinned plugin popups cannot use the shared surface
and need their own (which is why they are step 5 of the landing plan, isolated and last).

Experiment: §7 item 4 — open the Docker popup, click a window elsewhere, confirm it both closes and
that the click reaches the window.

**Previously open, now decided:** whether a pinned popup holds the card against hover claims. It
does; a hover claim is refused while pinned, and the accepted cost is that the bar gives no hover
feedback at all until the pinned popup is dismissed. See §3 → `pinnedOpen`.

---

## Reference

- `modules/common/widgets/StyledPopup.qml` — current implementation; `:13` default property,
  `:29` lazy gate, `:41-66` handoff, `:68-73` orientation, `:94-137` position, `:139-141` mask,
  `:191-197` the reparent that already exists.
- `modules/imi/desktopMenu/DesktopMenu.qml:119-181` — full-screen `PanelWindow` + animating card
  (dismiss `MouseArea`, not a mask).
- `modules/imi/notificationPopup/NotificationPopup.qml:42-44` — mask over an item whose contents
  animate.
- `modules/common/widgets/WindowBlurRegion.qml:86-111` — publish-now plus settle timer, and why the
  mask needs neither.
- `services/PopupBlurThreshold.qml` and `rules.lua:203-222` — the generated popup blur threshold,
  and why `quickshell:popup` is deliberately not in it.
- AGENT.md → Layer-shell gotchas, the four blur points added by bc4a9b180 ("fix(blur): stop the
  compositor frosting drop shadows") — regions are inert on popups, `ignore_alpha` is shared per
  namespace, `quickshell:popup` is already correct and `blur = false` breaks it, and none of this
  is visible to the test suite.
- `modules/common/widgets/StyledRectangularShadow.qml:7-13` — `anchors.fill: target`,
  `cached: true`.
- `modules/imi/bar/Bar.qml:17-24, 142-147` — per-screen `Variants`, full-width edge anchoring.
- `modules/imi/bar/BarContent.qml:46-76` — how bar widgets are built and dropped.
- `dots/.config/hypr/hyprland/rules.lua:143, 156-157` — `quickshell:*` alpha threshold and the
  `quickshell:popup` override.
- quickshell `src/core/region.cpp:17, 39-46, 150-165` and `src/core/region.hpp:161-165` — what a
  `Region` tracks and what it does not.
- quickshell `src/window/proxywindow.cpp:472, 513-514, 523-524, 660-667` — mask rebuild on polish,
  `WindowTransparentForInput`.
