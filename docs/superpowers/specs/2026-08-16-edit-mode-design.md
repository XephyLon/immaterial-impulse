# Edit Mode — design

**Status:** design, not implemented. §14 holds **one** open question.
**Scope:** `GlobalStates.qml`, `modules/imi/background/`, `modules/imi/desktopMenu/`,
`modules/common/widgets/widgetCanvas/`, `modules/common/widgets/` (`WidgetsSubmenu.qml`,
`LayoutSection.qml`, `DragApps.qml`), `modules/common/plugins/`, `modules/imi/bar/`,
`modules/imi/verticalBar/`, `modules/imi/dock/`, `modules/imi/lock/`,
`modules/common/panels/lock/`, `modules/imi/settings/pages/BarConfig.qml`, and `tests/`.

Paths are relative to `dots/.config/quickshell/imi/` unless written repo-relative, per AGENT.md's
layout note. Every file:line in this document was opened, on `gh/main` at
990d5b7dd ("docs(agent): the sound engine, and the four ways its predecessor was wrong").

---

## Problem

Four surfaces carry a layout the user is entitled to arrange, and each of them is arranged
somewhere else.

The desktop widgets are arranged **on the desktop**, by dragging them — and that editor is already
good: a hand-computed drag (`AbstractWidget.qml:95-135`), a 12px snap lattice (`:142-144`,
`:159-162`), snap-then-clamp ordering (`:196-214`), a marquee and a group drag
(`WidgetCanvas.qml:55-67`, `:135-206`), a resize grip that accumulates tension
(`PluginWidget.qml:700-799`), an alignment grid and animated centre-line highlights that appear
while you drag (`WidgetCanvas.qml:224-244`, `:246-284`), and flash lines on release
(`:303-331`). None of it is discoverable. Every affordance is hover-revealed or press-revealed,
the global lock is a switch two hovers deep in a context-menu submenu
(`modules/common/widgets/WidgetsSubmenu.qml:32-38`), and the one thing that reliably says "this
is editable" — the grid — only appears once you have already started dragging
(`WidgetCanvas.qml:211-217`).

The bar is arranged **in Settings**, as chips: `modules/common/widgets/LayoutSection.qml` renders
each widget id as a removable chip in a `Flow` and reorders by 2-D nearest-centre drag (`:51-85`).
It is a competent editor of a list of strings. It is not an editor of a bar: you cannot see what
you are arranging while you arrange it.

The dock is arranged **on the dock**, by dragging its icons
(`modules/common/widgets/DragApps.qml:319-378`) — with no settings equivalent, and no way to
discover that the drag exists.

The lock screen is not arranged. `LockSurface.qml` is three hand-anchored islands (`:105-234`,
`:236-461`, `:463-501`) and eleven booleans in `Config.options.lock` (`Config.qml:1203-1222`),
every one of which is a visibility switch on a fixed position.

So the request is not "add a layout editor". Three of the four already have one. The request is
for a **mode**: a moment when these surfaces are editable at once, with their affordances shown
rather than hidden, one way in and one way out, and nothing else happening by accident.

---

## 1. The model: a shrinking viewport

### 1.1 Entering shrinks the desktop; it does not overlay it

Entering Edit Mode **scales the desktop down and insets it, over the current wallpaper blurred.**
The reference points are GNOME's Overview and KDE Plasma's edit mode: the desktop stops being the
whole screen and becomes an object on the screen, with room around it for the editor's own chrome.

That shrink, plus the blur behind it, **is the mode signal**. There is no scrim, and the question
of whether to have one is closed. A dimming rectangle over a full-screen layer surface was always
the awkward part of this design — it dims the wallpaper the user is arranging widgets against, it
fights `appearance.transparency.enable`, and on a namespace with a shared `ignore_alpha` it either
asks the compositor to blur the whole screen or flattens the chrome's own body (§13). None of that
has to be answered now, because the mode announces itself by changing the shape of the desktop.

**The blur already exists in this tree and needs no new mechanism.** `Background.qml:915-945` is a
`Loader` whose `sourceComponent` is a `GaussianBlur` over whichever wallpaper layer is currently
live — the lock peel, the live Wallpaper Engine surface, or the static image/transition (`:932-936`)
— with a translucent `Rectangle` over it (`:939-943`), and a zoom animated by a 400ms
`expressiveDefaultSpatial` curve (`:919-927`). Today it is gated on
`Config.options.lock.blur.enable && (GlobalStates.screenLocked || scaleAnim.running)` (`:917`).
Edit Mode is a second gate on that same `Loader`. It is the same picture the lock screen already
draws, for the same reason, on the surface that already owns the wallpaper.

### 1.2 The inset is derived, not chosen

**Desktop width = screen width − (drawer width + a margin).** The drawer — the panel that holds
the catalogue of things you can add — therefore opens into space that already exists. The desktop
is inset to that size on entry, whether or not the drawer is open, and the vertical inset follows
from the same scale so the desktop keeps its aspect ratio.

There are deliberately no pixel values here. The drawer's width is a consequence of what it has to
show; the margin is a `Appearance.spacing.*` token; the scale is whatever those two leave. Any
number written into this document would be a second source of truth for a value the layout can
compute, which is the shape of every "two fields that must agree" defect AGENT.md records.

The scale is a **render-time transform, and that is what makes it cheap.** `Item.scale` (or a
`Scale` transform with `origin` at the top-left) does not touch `x`, `y`, `width` or `height`, so:

- `WidgetCanvas` stays `bgRoot.width` × `bgRoot.height` (`Background.qml:1121-1122`) and every
  clamp range — `[0, scaledScreenWidth - clampWidth]` (`AbstractBackgroundWidget.qml:110-111`) —
  is unchanged;
- every stored position in `plugin-state.json` still means the same point;
- the drag still lands exactly, because it is computed by mapping the pointer through the moving
  item into the canvas frame and the comment at `AbstractWidget.qml:109-111` already says why —
  *"the current transform, press scale included, cancels itself out"*. The 1.05 press scale at
  `AbstractBackgroundWidget.qml:30` is the same class of transform and the drag has been exact
  across it since d2ebb5aeb ("fix(widgetCanvas): compute the drag by hand - MouseArea.drag cannot
  track it").

So the viewport costs no arithmetic in the store, the clamp or the gesture. What it does cost is
in §2.4.

### 1.3 The drawer moves the desktop; it never resizes it

Opening the drawer **translates** the desktop. It does not shrink it further.

A viewport that changed size mid-edit would rescale every widget under the cursor: a drag in
flight would find its target a different size than when it was grabbed, `PluginWidget`'s span
animation would be retargeted mid-flight, and every `Behavior` carrying the desktop's own box
would be handed a moving target — which, per AGENT.md's rule and b710ef731 ("fix(plugins): stop the
position Behavior swallowing the parallax cancellation"), means it restarts every frame and never
ticks. Translation is a two-number change with none of that: the viewport's `x` moves, nothing
inside it re-lays out, and the widgets keep the size they had when the user grabbed them.

This is also why §1.2's inset is unconditional. If the desktop were full-width with the drawer
closed and inset with it open, opening the drawer would be a resize.

### 1.4 A tab bar below the viewport: Desktop and Lockscreen

Below the viewport sit two tabs: **Desktop** and **Lockscreen**.

The lock screen is a *tab*, not a mode and not a state. Switching to it changes what the viewport
draws — the lock wallpaper, the lock blur, the locked widget filter, the three islands — and
changes nothing about the mode: the same entry, the same exit ladder, the same chrome, one
`GlobalStates.editMode` boolean. Nothing about "am I editing?" partitions by tab.

This is the decision that shrinks §4.3 from a chapter to a section. Most of the merged spec's
analysis of *how to render a lock screen you are not locked into* was analysis of a fifth surface;
a tab is a filter on the viewport, and the half of the lock screen that is the desktop's own
widget layout (`AbstractBackgroundWidget.qml:18`, `PluginWidget.qml:611-613`) is already drawn by
the surface the viewport is.

### 1.5 The bar and the dock are not scaled and are not tabs

They stay exactly where they are, at full size, on their own layer surfaces, and editing them is
in-place direct manipulation on the real surface as §4.2 describes. On the Lockscreen tab they
simply disappear.

Both halves of "disappear" already exist and are how the real lock screen works today:

- the bar's `LazyLoader` is `active: GlobalStates.barOpen && !GlobalStates.screenLocked`
  (`Bar.qml:26-27`);
- the dock's `PanelWindow` is `visible: !GlobalStates.screenLocked` (`Dock.qml:37`).

The Lockscreen tab adds a term to each. Note what `visible: false` means on a layer-shell
`PanelWindow` — it destroys the surface rather than hiding it (AGENT.md, layer-shell section), so
flipping back to the Desktop tab rebuilds the dock's window on a fresh GL context. That is
acceptable here for the same reason it is acceptable on lock (the dock embeds no renderer), but it
is a thing to *look at* on a live load rather than assume.

**One consequence worth stating plainly: #229's item 5 is not needed here.** That item proposes
animating a bar's exclusive zone through a second, fully-masked space-reserver `PanelWindow`, so
the windows behind an auto-hiding bar glide instead of jumping. It is a real gap — `Bar.qml:63`
sets `exclusiveZone` as a bare conditional while the bar's own body slides on a
`Behavior on anchors.topMargin` — but it belongs to auto-hide, not to Edit Mode. Edit Mode never
moves the bar and never changes its exclusive zone: the bar is not scaled, not inset and not
translated, and the desktop shrinking inside a *different* surface reserves nothing. Citing #229's
item 5 here would attach a fix for one feature to the landing of another, which is exactly the
"stage 2 is a behaviour change reviewable on its own" discipline in §12 applied in reverse.

---

## 2. The architectural constraint

**This decides the implementation, so it goes before the design of anything drawn.**

### 2.1 Three surfaces, three windows

The background, the bar and the dock are separate wlr-layer-shell surfaces — separate windows, in
separate scene graphs, listed as three sibling `PanelLoader`s in
`panelFamilies/ImmaterialImpulseFamily.qml`:

| surface | window | layer | namespace |
| --- | --- | --- | --- |
| background (wallpaper + widget canvas) | `Background.qml:79` | `Bottom`, promoted to `Overlay` while locked (`:540`) | `quickshell:background` (`:541`) |
| bar | `Bar.qml:30` | `Top`, promoted to `Overlay` under fullscreen+special (`:67`) | `quickshell:bar` (`:64`) |
| dock | `Dock.qml:33` | per `DockGeometry` | `quickshell:dock` (`:75`) |

**Nothing can scale them from outside, and a layer surface cannot be transformed by a sibling.**
There is no ancestor item common to the three; each is a `PanelWindow` per screen with its own
`QQuickWindow`. GNOME and KDE can scale "the whole desktop" because their shell owns one scene
graph containing every element; ours does not, and no amount of QML gets one.

So the viewport must be **a full-screen layer that draws the shrunk desktop itself**.

### 2.2 The live tree, or proxies

Two ways to draw a shrunk desktop.

**(a) The live tree.** Draw the real `WidgetCanvas`, with the real `PluginWidget`s on it, under a
scale transform. Editing is genuinely WYSIWYG: what the user drags is the widget, at the widget's
own size relative to a desktop of the right proportions, with its own hover states, its own resize
grip, its own content.

**(b) Proxies.** Draw rectangles standing in for widgets, arrange those, and write the results
back.

**Recommended: (a).** Three arguments, all of which are rules this repo already enforces.

- **A proxy is a second renderer, and the second renderer rots.** This shell has one, and it is
  instructive: `modules/imi/overview/` draws a miniature of each workspace at
  `Config.options.overview.scale` with every window as an `OverviewWindow` — which is not a live
  view of the window but an **app icon in a rectangle** (`OverviewWindow.qml:50-60`), positioned by
  hand-derived `widthRatio`/`heightRatio` that re-derive the monitor's transform and scale
  (`:19-41`). That is what a proxy costs: a coordinate conversion per monitor property, and a
  picture rather than the thing. Apply it to widgets and every divergence between the picture and
  the desktop is invisible until it ships — the same shape as `PluginValidator.js`'s whitelist and
  `PluginNode.qml`'s renderer `switch` drifting apart.
- **The desktop editor already exists and is good.** Replacing direct manipulation of real widgets
  with dragging rectangles is a downgrade for the one surface that is finished.
- **The live tree costs nothing in the arithmetic that matters.** §1.2: `scale` leaves `x`, `y`,
  `width`, `height`, every clamp and every stored position untouched, and the hand-computed drag
  already cancels the transform. A proxy would need its own hit-testing, its own snap, its own
  clamp and its own commit — four copies of things that exist, which is §10.2's argument about the
  reorder gesture applied to the whole editor.

**What would have to be true for proxies to win.** Exactly one thing, and it is measurable rather
than arguable: that drawing the live tree at scale is either impossible or unaffordable. Two
specific ways that could turn out true, both listed in §11.4 as probes to run *before* stage 3:

1. **The frost.** Each desktop widget draws an in-shell frost — a `ShaderEffectSource` over the
   wallpaper, sampled at a rect computed by `ParallaxMath.sampleOrigin` from the canvas offset, the
   widget position and the wallpaper rect (`PluginWidget.qml:50-65`,
   `WallpaperBlurSurface.qml:98-117`). A scale on the canvas changes the relationship between
   those three frames. §2.4 argues this is already solved; if it is not, and the frost must stay
   live during the mode, that is a point for proxies.
2. **The compositor's alpha map.** `Background.qml:1186-1189` says, in its own words: *"Keep the
   loader untransformed. Hyprland derives live background blur from this surface's alpha map;
   wrapping plugin widgets in a Scale transform offsets that map from the live Wallpaper Engine
   layer beneath it."* That comment predates the in-shell frost (`WallpaperBlurSurface.qml:12-15`
   states the compositor handoff "no longer applies"), so it may be stale — but it is a written
   claim about the exact transform this design applies, and it must be **checked on a live load**,
   not reasoned away. If it holds and cannot be worked around, the live tree cannot be scaled on
   that surface and proxies become the fallback.

### 2.3 Which full-screen layer

Given (a), there is a second, narrower choice: which surface draws the viewport.

**Recommended: the background surface, because it already is one.** `Background.qml:79-550` is a
per-monitor `PanelWindow` with all four edges anchored, already holding the wallpaper, the
lock-blur `Loader`, and the `WidgetCanvas` with every `PluginWidget` on it. Making it the viewport
means scaling and insetting `parallaxViewport` (`:662-1117`) and `widgetCanvas` (`:1119-1175`)
together, with the blur `Loader` full-screen behind them. **Nothing is reparented, because the
canvas is already in the viewport.**

The alternative — a new full-screen `Overlay` surface with the real `WidgetCanvas` reparented into
it — is a shipped pattern here (`BarPopupOverlay.qml:138-146` sets `arriving.parent = contentHost`
across windows, 31493a21a ("feat(bar): teach StyledPopup and the overlay to hand the card over")),
so it is available. It costs one thing the in-place option does not: **a `ShaderEffectSource`
reaches items in its own scene graph only**, and `weSurfaceItem` — the live Wallpaper Engine
surface each widget's frost samples (`PluginWidget.qml:48`) — is an item in the *background*
window. Reparent the canvas into another surface and the live-wallpaper frost is not
mis-positioned, it is unreachable.

Take the new surface only for chrome that must not be occluded by the bar or the dock. The
background surface is on `Bottom`; the bar is on `Top`. If the tab bar, the drawer or the toolbar
land under either, they go on a second full-screen surface built on `BarPopupOverlay.qml`'s
pattern, with §10.3's four properties, and the viewport stays where it is. Whether they do land
under it is a layout fact about one screen, answerable with `hyprctl layers -j` on a live load
(§11.4), and it is the one thing about the chrome that no harness can see.

### 2.4 The frost stands down for the mode, and there is a precedent for exactly that

The live-wallpaper frost is not a problem to solve. `PluginWidget.qml:605-613` already reads:

```qml
readonly property bool lockCoversFrost: GlobalStates.screenLocked
    && Config.options.lock.blur.enable
```

with the comment: while the screen is locked *and* the lock blurs the wallpaper, the widget skips
its own blur surface, because the widget's translucent panel then shows the lock background
through it and the frost stays consistent with the lock screen.

Edit Mode blurs the wallpaper for exactly the same reason and produces exactly the same situation.
So the gate generalises from "locked with blur" to "a blurred backdrop covers the wallpaper", Edit
Mode is its second producer, and the whole scale-versus-sample-origin question disappears for the
duration of the mode: there is no per-widget frost to align.

The renaming is the work (`lockCoversFrost` → something that names the condition rather than one
of its causes), and it is a one-line change in the file that already owns the derivation.

---

## 3. The four models, measured

| | desktop widgets | bar | dock | lock islands |
| --- | --- | --- | --- | --- |
| geometry | free 2-D placement, 12px snap | ordered list, three buckets | ordered list, one strip | three anchored islands |
| size | span from a fixed set (`__gridSize`), or the widget's own modes | intrinsic | intrinsic | intrinsic |
| store | `plugin-state.json` (raw `FileView`) | `Config.options.bar.layouts.*` | `Config.options.dock.pinnedApps` | nothing |
| per monitor? | **yes** (`desktopPositions[screen][id]`) | no (a `bar.screenList` allow-list, `Bar.qml:17-25`) | no (every screen, `Dock.qml:30-31`) | n/a |
| direct manipulation today | yes | no | yes | no |
| catalogue of what can be added | `PluginManager.availablePlugins` | a hardcoded array in a settings page | `DesktopEntries` | fixed |
| write timing | on release, 100ms debounce | on drop, 50ms debounce | on release, 50ms debounce | n/a |
| in Edit Mode | inside the viewport, scaled | in place, full size | in place, full size | Lockscreen tab, inside the viewport |

Citations: `PluginState.qml:18-31` (schema), `:349-353` (the 100ms write timer);
`Config.qml:1027-1030` (the three bar arrays); `Config.qml:1149-1150` (`pinnedApps`);
`Config.qml:1203-1222` (the lock's eleven booleans).

Two things fall out that the viewport model does not change.

**(a) There is no shared geometry, so there is no shared canvas.** A 2-D free placement and a 1-D
ordered list do not have a common editor. The viewport is a shared *frame*, not a shared editor:
what is inside it is still the desktop's own editor, and the bar's and dock's editors are not
inside it at all.

**(b) There is a shared store discipline, and it is already "write through on release".** No
surface in this shell has a save step: `commitPosition()` writes on release
(`PluginWidget.qml:572-594`), `LayoutSection` writes on drop (`:71-85`), `DragApps.commitOrder`
writes on release (`:76-80`), the quick-toggle edit mode writes on every click. §7 argues Edit
Mode must not be the first thing to introduce a transaction.

**The overlay widgets are out of scope.** They are a fifth surface with a fifth store
(`Persistent.states.overlay.*`), already a `WidgetCanvas` with free drag, and they deliberately
decline the marquee because the overlay closes on a plain click. They are the obvious next
surface; they are not in this one.

---

## 4. What editing means, per surface

The governing rule, which §9 turns into a check: **Edit Mode changes where a thing is, how big it
is, what order it is in, and whether it is present on that surface. It changes nothing else.**

### 4.1 The desktop — mostly subtraction

Almost nothing new is drawn. What the mode does is stop hiding what is already there:

| today | in Edit Mode |
| --- | --- |
| the grid appears only mid-drag (`WidgetCanvas.qml:211-217`) | ~~on for the whole mode~~ — reversed after looking at it, see below |
| the resize grip fades in on hover (`PluginWidget.qml:709-726`) | every resizable widget shows its grip |
| the global lock is a submenu switch (`WidgetsSubmenu.qml:32-38`) | the mode suppresses it (below) |
| right-click on a widget toggles the global lock (`AbstractWidget.qml:85-89`) | right-click is a per-widget menu (Remove, Size, Pin) |
| adding a widget means opening Settings › Widgets | the drawer, fed by `PluginManager.availablePlugins` |

**The global lock is suppressed, not written.** `interactionLocked` is
`clickThrough || positionLocked || Config.options.background.widgetsLocked`
(`AbstractBackgroundWidget.qml:54-55`), and Edit Mode subtracts the third term only. The
per-widget `positionLocked` pin survives, preserving the invariant the file records for that OR
belt — *"'Lock widget positions' must never unlock something the user deliberately pinned, in
either direction"* (`:37-40`). Writing `widgetsLocked = false` on entry would destroy a stored
preference and leave the desktop unlocked after the mode ended.

**The grid stays the DRAG's, and the row above is withdrawn.** Written after the mode shipped and
was looked at: *"in Edit mode, the grid lines should not appear until I try to move a widget."*
The argument for forcing it on was discoverability — §2 calls the grid "the one thing that
reliably says this is editable" and complains that it only appears once you have already started
dragging — and that argument was made before stage 6 gave the mode a toolbar and a tab bar of its
own. Those say the mode is on now. A mode that opens on a screen of graph paper hides the desktop
the user came in to look at, which is the opposite of §4.1's own framing.

What the mode overrides is the config SWITCH (`background.showGrid`, whose meaning has always been
"draw the grid while I drag") rather than the gesture: editing, a drag always draws the lattice it
is landing on. The trigger is the distinction `AbstractWidget` already draws — `dragActive`, raised
past `drag.threshold` and never on the press — because every one of a widget's own controls presses
without travelling.
(fix(widgetCanvas): the lattice comes up with the drag, not with the mode.)

**The drawn grid becomes 12px.** `WidgetCanvas.qml:7` draws every 24px; `AbstractWidget.qml:23`
snaps every 12, and `docs/widget-grid.md`'s "Position snapping" section explains why the fine
lattice is deliberate. Drawing 24 while snapping 12 puts a widget between two lines at every second
stop, which reads as broken snapping — and it reads that way exactly when the grid is up, i.e.
during the drag doing the snapping. (This paragraph originally hung that on the grid being up for
the whole mode; the mode made it impossible to miss rather than made it true, so it survives the
row above being withdrawn.) Draw 12px lines at a lower opacity with every second one emphasised, so
the lattice is honest and the rhythm stays readable. This changes an existing default, so it lands
as its own commit.

**`WidgetsSubmenu` goes.** Its `widgetList` is empty by decision (`:14-19`) and its only live
control is the global lock, which the mode suppresses — a switch that turns off something the
editor turns back on. It is removed in stage 5, when the per-widget menu makes it redundant, as
its own commit so the removal has a reason attached.

### 4.2 The bar and the dock — in place, at full size

In Edit Mode the bar stops auto-hiding, its widgets stop responding to their own clicks, each
grows a remove badge, and dragging one moves it within its bucket or across into another. The
three buckets get visible boundaries — the one thing the chip editor genuinely does better than
the bar itself, because in the real bar an empty `middleLayout` is indistinguishable from an
invisible one.

Suspending auto-hide is a state change on a layer surface, and `visible: false` on one destroys
it. Express it the way `Bar.qml:57-58` already expresses `mustShow` — by adding a term — never by
touching `visible`.

The dock's drag already does the right thing (`DragApps.qml:319-378`), including choosing its axis
once from the edge (`alongAxis`, `:343-350`). Edit Mode adds a remove badge per icon and the
drawer. **The edge stays a settings row**, for both surfaces: dragging a layer surface between
edges cannot animate — position *is* `anchors` and `margins`, so it would reconfigure the surface
every frame — so the "drag" would be a press, a jump and a compositor slide, which is a worse
affordance than a button. The chrome may carry a shortcut *to* that row.

**One prerequisite is real and one is already done.**

- **Real: the widget catalogue must exist somewhere the bar can read it.** Today it is a hardcoded
  array of 21 entries inside a settings page (`BarConfig.qml:49-71`), concatenated with plugin bar
  widgets derived at `:41-47`. The bar itself has no catalogue: `BarContent.getWidgetUrl` goes
  through `bar_widget_source.js`'s `fileNameFor`, which answers with a file name and knows nothing
  about which widgets exist. A drawer would be a third list. Promote it to `BarWidgets.qml`, a
  singleton beside `PluginManager` exposing `available` and `nameFor(id)` — a move, not a redesign.
- **Already done: the `plugin:` prefix.** The merged version of this document listed
  `VerticalBarContent.getWidgetUrl` resolving `../bar/Plugin:docker_plugin.qml` as a bug to fix
  before the bar stage. It was fixed before this document was written: both bars now call
  `BarWidgetSource.fileNameFor(name)` (`BarContent.qml:61-64`, `VerticalBarContent.qml:66-69`) and
  `tests/test_bar_widget_parity.py` fails the suite on either bar deciding for itself.
  a47462fcc ("fix(verticalBar): render plugin bar widgets instead of an empty stub"),
  06d31aabc ("test(bar): pin the two bars to one widget-url resolution"). Nothing to do.

**One trap inherited.** `DockSeparator.qml` and `DockAppButton.qml` reach `dockRow.padding` and
`dockVisualBackground.margin` by QML dynamic scope. Edit-mode chrome that reparents anything in the
dock's tree breaks both with `undefined` → NaN geometry, a relayout that never converges, a pegged
core, and no error.

### 4.3 The Lockscreen tab

The lock screen is composed of two surfaces, and one of them is the viewport already:

- **The background surface**, promoted to `WlrLayer.Overlay` while locked (`Background.qml:540`),
  carrying the lock wallpaper (`:871-895`), the lock peel (`:900-913`), the lock blur (`:915-945`),
  the clock plugin, and every other desktop widget when `lock.showWidgets` is on
  (`AbstractBackgroundWidget.qml:18`).
- **`WlSessionLockSurface`**, `color: "transparent"`
  (`modules/common/panels/lock/LockScreen.qml:19`), carrying a `Loader` gated on
  `GlobalStates.screenLocked` (`:21`) whose content is `LockSurface.qml`: three `Toolbar` islands
  anchored to each other, main bottom-centre (`:105-234`), left and right hung off its edges
  (`:236-461`, `:463-501`).

So the tab needs: the viewport's wallpaper and blur switched to their locked inputs (which is a
gate change on things `Background.qml` already draws), the widget filter switched to the locked
one, and the three islands drawn.

**The islands cannot simply be rendered by locking.** Constructing a `LockContext` runs
`fprintd-list` at construction (`LockContext.qml:80-96`, `running: true` at `:82`) and declares two
`PamContext`s (`pam` at `:98`, `fingerPam` at `:122`); `LockSurface` calls `forceFieldFocus()` from
`Component.onCompleted` (`:61`), `onPressed` (`:39`), `onPositionChanged` (`:42`), `Keys.onPressed`
(`:76`) and `Keys.onReleased` (`:82`). A lock screen you can edit is a lock screen with its lock
switched off. Not acceptable at any price.

**Render the real islands, neutered by construction rather than by a flag:**

- `LockSurface` gains `property bool interactive: true`. When false, `forceFieldFocus()` returns
  immediately, the password field is `enabled: false` and `readOnly`, and the three power actions
  (`:484-501`, and `PasswordGuardedIconToolbarButton` at `:503-521`) do not connect. Something that
  can neither take a keystroke nor dispatch a session action cannot be an attack surface, and the
  property is a single grep target for a lint.
- A `LockPreviewContext` — a second component satisfying the same property surface, whose
  `tryUnlock`/`tryFingerUnlock` are empty and which constructs **no** `PamContext` and runs **no**
  `fprintd-list`. This is the piece that wants the most careful review, because "the preview
  context is the real one with a flag" is how a preview ends up authenticating.
- The `LockScreen` tree already takes its content as a `Component`
  (`LockScreen.qml:15`, `:17-28`), so the tree is not welded to `WlSessionLockSurface` — only its
  one instantiation site is.

**~~A widget has one position, and the lock screen shows it at that position.~~** *Overruled
2026-08-18* (maintainer: *"lockscreen widget layout is meant to be different from desktop layout if
the user decides to alter the widgets and their order in lockscreen"*, and the same day: *"a widget
state is not correctly saved when it's different between desktop and lockscreen (media widget being
3x2 instead of 1x2 for example)"*). The original paragraph is kept struck through because its two
objections were real and the replacement answers each:

- *A second position doubles the placement model.* → **Fork on first edit**, not two stores from
  day one. `lockPositions` sits beside `desktopPositions` with the same `[screen][pluginId]` shape,
  and a screen **absent** from it shows the desktop's layout — so every user is still in the
  one-position model until they move something on the Lockscreen tab. That first lock write copies
  the whole screen across (a snapshot, not a one-widget overlay), and from then on the two are
  independent. A "Widget layout follows the desktop / is separate" row in the drawer's Lock section
  says which state a screen is in and, while forked, offers **Use desktop layout** to re-link it.
- *Every preset would silently gain one.* → It should: a preset *is* the layout. `presets.sh`
  captures `lockPositions` beside `desktopPositions` and applies it under the same `has()` rule, so
  a preset from an older shell that lacks the key leaves a user's fork alone.
- **The span forks with the position.** The desktop's stays the per-plugin `__gridSize` option; a
  forked lock screen's lives *in* the widget's lock record as `gridSize`, copied by the fork
  snapshot. A lock record without one reads through to the desktop's.
- **Undo captures the surface at push time.** A closure that resolved it at pop time would write a
  lock position into the desktop store when popped from the other tab; every position and span
  writer names its surface into the closure. The re-link's undo restores whole records.

`modules/common/plugins/layout_surfaces.js` is the arithmetic; `PluginState.currentSurface`
resolves the default surface from the one lock-look derivation; `tst_layout_surfaces.qml`,
`test_layout_surfaces_contract.py` and `EditModeRuntimeTest.qml` (a real drag and a real grip pull
on the Lockscreen tab) hold it. `lock.centerClock` stays a render-time override, and what the tab
edits for *presence* is unchanged: `visibleWhenLocked` is still the single toggle.

What can be edited in the islands, and what cannot, is §14 — the one open question.

---

## 5. Widgets resize by span, not freely — and `Custom Image` is the sole exception

This is the correction with the most reach in this revision. Free-form resize is a Plasma import,
not the house pattern, and the tree says so in three places.

### 5.1 The host can only ever assign an offered span

`PluginWidget.qml:136-148` is the whole model:

- `gridSpec` is `manifest.grid`, or null;
- `offeredGridSizes` is `GridSizes.offeredSizes(gridSpec)` — a `sizes` list whose entries disagree
  with the default, or that holds an unusable entry, is rejected **whole** rather than repaired
  (9c4adcc5f ("feat(plugins): resolve a widget's grid span through a testable module"));
- `gridResizable` is `offeredGridSizes.length > 1`, so a widget offering one span shows no grip and
  gets no Size row;
- `storedGridSize` is stored choice → manifest default → null, and null is the content-sized path
  (494580b65 ("feat(plugins): resolve a placed widget's span from its stored choice"));
- `previewGridSize` is the span the grip is previewing, and `Escape` cancels by clearing it
  (`:729-732`).

The widget's pixel size is then `gridSpanWidth`/`gridSpanHeight`, i.e.
`Appearance.sizes.widgetGridSpanX(cols)` over a 132×108 cell with a 12px gap
(`Appearance.qml:687-695`). The grip does not pick the nearest span either: it accumulates pull and
gives one offered span per breakaway, with the remainder carried, rubber-banding at a wall
(`resize-tension.js`, ccde619bf ("feat(plugins): the grip accumulates tension instead of picking
the nearest span")).

There is no expression in the host for "any size the user drags to". Edit Mode's Size affordance is
therefore a **stepper over `offeredGridSizes`**, not a handle over pixels.

### 5.2 The precedent, in the widget that documents its own reasoning

`modules/common/plugins/bundled/calendar/Widget.qml` is the file to read before writing this
section, and it explains itself at `:64-76`:

> The corner handle resizes this widget and the opposite handle flips the wide size between a month
> and a week, **so the manifest declares no `grid`**: a span is a fixed pixel size the host assigns
> on every load, and it would overwrite whichever size the handles last chose.

So calendar declines `grid` **specifically to keep the host out of its size** — and then flips
between three discrete modes of its own (`normalizeSizeMode` at `:77-83`, `setSizeMode` at
`:90-93`), whose pixel sizes are themselves real component-grid spans (`:56-62`,
`widgetGridSpanX(1)`/`(2)`, `widgetGridSpanY(1)`/`(2)`) *"so the three modes land on the lattice"*.
Its corner handle does not resize freely: it compares the dragged width against the midpoint
between two spans and lands on one of them (`:539-550`). Its other handle is a plain toggle
between two modes (`:586`). `world-clock` is built the same way (`:65`, `:82-83`).
aaec02b3a ("feat(calendar): morph the calendar in one tree instead of rebuilding it"),
522fed107 ("feat(world-clock): morph the world clock in one tree instead of rebuilding it").

The lesson generalises past those two files: **declining `grid` is how a widget owns its size, and
every widget that has done so still chose discrete modes on the lattice.** Nothing about the
absence of `grid` implies free-form.

### 5.3 The one exception, and why it is one

`modules/common/plugins/bundled/custom-image/Widget.qml` resizes continuously.
`:33-43` states the reason:

> The manifest deliberately declares no `grid` … Sizing ourselves is also the only way to stay
> **square** and stay user-resizable: a grid span is a fixed count of 132×108 cells, which is
> neither.

Its grip writes a single scalar with a floor and no lattice —
`root.widgetSize = Math.max(80, startSize + delta)` (`:219-224`) — persisted on release
(`:225-227`). 862a3224a ("feat(widgets): port the custom image widget to a bundled plugin").

That is the whole exception, and it is exactly one widget in a bundled set of fourteen. Counted by
opening every manifest: five declare multiple spans or one (`nandoroid-weather`,
`nandoroid-media`, `nandoroid-currency`, `notes`, `user-card`, `image-converter`); `calendar` and
`world-clock` decline `grid` and run discrete modes; `clock`, `visualizer`,
`nandoroid-system-monitor`, `docker` and `discordVoice` are not user-resizable at all;
`custom-image` is free.

**What Edit Mode owes each.** A span widget gets a stepper over its offered spans. A widget with
its own modes keeps its own handles, shown rather than hover-revealed. `Custom Image` keeps its
free handle. Edit Mode adds no new resize mechanism, and specifically does not add a free-form
handle to widgets that have declined one — a resized widget whose span the host reassigns on the
next load is the failure calendar's comment is written to prevent.

---

## 6. Snap hysteresis

This belongs in this spec because dragging widgets is where it shows, and Edit Mode is the mode in
which every widget is being dragged.

### 6.1 What we have, stated correctly

The animation research (`docs/p3drovfx-animation-research-2026-08-16.md`, §4.1) corrects an earlier
claim that this shell has no snapping. Opened rather than searched, `AbstractWidget.qml` carries:

- a **12px lattice** (`:23`) with **per-axis offsets** (`:159-162`) so a subclass can move the
  lattice into the frame its coordinate means something in — and the comment there records why the
  seam hands in an offset rather than the lattice: `gridSize` is *shadowed* by `PluginWidget`'s span
  object, so a snap written in a subclass silently applies no lattice at all
  (8a534a7da ("fix(plugins): snap a widget's drag to the lattice it is stored on"));
- **snap-then-clamp ordering** (`:196-214`), spelled out because clamp-then-snap would round a
  group-drag leader back off its bound by up to half a cell;
- a **centre-line highlight** driven by `updateCenterHighlight()` (`:173-182`) against an unsnapped
  shadow position, drawn by `WidgetCanvas.qml:246-284` with three `Behavior`s on
  `elementMoveFast` — animated colour, width and opacity;
- a **grid overlay** while dragging (`WidgetCanvas.qml:224-244`);
- **flash lines** on release, fading `0.9 → 0` over 2000ms `OutCubic` and destroying themselves
  (`:303-331`), gated on `Config.options.background.showSnapLines` (`Config.qml:817`);
- a **marquee** and a **group drag** with shared clamp bounds (`WidgetCanvas.qml:135-206`).

What is genuinely missing is **widget-to-widget edge alignment** and the **two-threshold hold**.
That is the accurate version of the gap, and it is what this section is scoped to.

### 6.2 What to take (#229 item 10)

A **Schmitt trigger**: acquire a guide close, release it farther away — two thresholds, roughly
18px to acquire and 32px to release, with the 14px gap between them being what makes it feel like a
detent. The mechanism is not the two numbers, it is what they are measured against: **both tests
compare the unsnapped shadow position, never the rendered one.** With one threshold, snapping puts
the widget on the target while the pointer sits within `T` of it, so the next event re-snaps;
pushing just past `T` unsnaps and the widget jumps back to a position that may be within `T` again
from the other side. That is a per-event flip-flop, and it happens because the decision boundary and
the resulting position are the same number.

This tree already has the shadow position that makes it possible: `dragProxy`
(`AbstractWidget.qml:184-194`), *"deliberately no `x: root.x` binding: a live binding here re-yanks
the proxy to the snapped widget position after every drag step"*, synced imperatively at press and
at each drag end. Both halves of the trigger read `dragProxy`, exactly as `updateCenterHighlight()`
already does (`:176-177`).

The candidate set is four relations per other widget per axis — near-to-near, far-to-far,
near-to-far, far-to-near — each carrying **two numbers**: the `target` the widget travels to and the
`guide` the line is drawn at, because the line belongs to the *other* widget's edge. A relevance
filter on the perpendicular axis (a widget more than ~600px away across the axis being snapped
contributes no candidates) stops a widget left-aligning to something in the opposite corner.

**The two adjacency relations land one grid gap off the neighbour, not flush** (amended
2026-08-18, maintainer: *"There should be one gap of space between them. Gluing them together is a
problem."*). The gap is `Appearance.sizes.widgetGridGap` — the same 12px that already separates the
cells *inside* a multi-cell widget — scaled by `effectiveScale`, so two widgets side by side read as
one continuous grid rather than a slab. The two alignment relations take no gap: aligning an edge to
an edge is a line, not a distance. The guide is drawn at the neighbour's own edge for all four; the
gap is only where the widget lands. `edge_snap.js` takes the gap as a parameter so the module stays
free of `Appearance` and testable bare.

Three things to get right, from the same research:

- **Do not resurrect the stale duplicate.** A dead copy of this base class sits at
  `modules/common/plugins/designsystem/widgets/widgetCanvas/AbstractWidget.qml` and *does* have
  edge snap and live guides. Nothing imports it, its directory has no `qmldir`, its last commit is
  f43485e86 ("refactor: rename the shell from \"ii\" to \"imi\""), it still uses `drag.target` and a
  `dragProxy { x: root.x }` binding — the exact pair d2ebb5aeb removed — and it reads a config key
  that does not exist. Port the candidate arithmetic into the live file.
- **The arithmetic is the part a test can reach.** It goes in a `.pragma library` beside
  `ParallaxMath` and `gridSizes.js`, with a `tst_*.qml`; nothing about the rendered guide is
  reachable from `qmltestrunner`.
- **Animate our guides.** The research notes the reference implementation's guide lines are two
  plain `Rectangle`s with no `Behavior`, so they pop and teleport between guides. Ours already
  animate the centre lines (`WidgetCanvas.qml:246-284`); edge guides should join that family rather
  than start a second one.

---

## 7. State and persistence

### 7.1 What is mutated

| store | keys Edit Mode writes | mechanism |
| --- | --- | --- |
| `plugin-state.json` | `desktopPositions[screen][id]`, `pluginOptions[id].__gridSize` | `PluginState.setPosition` / `.setOption`, 100ms debounce (`:349-353`) |
| `config.json` | `bar.layouts.{left,middle,right}Layout`, `dock.pinnedApps`, `plugins.enabled`, `lock.show*` | `JsonAdapter` write-back, 50ms debounce |
| nothing | the mode, the tab, the drawer, the selection, the undo stack | `GlobalStates`, in memory |

**`GlobalStates.editMode`, not `Config.options.*.editMode`.** AGENT.md is explicit: ephemeral UI
state goes in `GlobalStates`, persisted settings in `Config`. A persisted edit mode is a shell that
comes back from a restart with the desktop shrunk and the bar inert. The active tab and the drawer's
open state are the same kind of thing and live beside it.

**Nothing goes in `Persistent`.** That holds session state which must survive a restart
(`night.temperatureActive`, `record.region`, the overlay widgets' geometry). Edit Mode is not that.

### 7.2 Live application, no save/cancel

Edit Mode applies every change immediately and has no Save and no Cancel. The argument is
arithmetic, not taste:

- **A transaction would need three shadow stores.** The mutations span `plugin-state.json` (a raw
  `FileView` with its own debounce), `config.json` (a `JsonAdapter` that writes back on *any*
  property write) and, potentially, preset files. `PluginState.snapshot()` / `replaceSnapshot()`
  exists and is exactly this for one of the three — which is what makes the shape of the missing
  two obvious.
- **`writeAdapter()` runs on essentially every launch and strips undeclared keys.** A staging area
  inside `config.json` would be destroyed by the first launch that did not know about it; outside
  it, it is a fourth store.
- **Every existing editor here writes through.** A save step would mean a widget dragged with the
  mode off commits instantly and the same drag with the mode on does not — two behaviours for one
  gesture, decided by a mode the user may have forgotten they are in.
- **Live application is the feedback.** The whole point of a viewport showing the real desktop is
  seeing the result.

### 7.3 Undo instead of cancel, deferred

What a Cancel button is for is "I did not mean that", and an undo stack serves it better: in
memory, session-scoped, bounded (say 50 entries), one entry per **committed** mutation (a drag's
release, a span commit, a reorder drop, an add, a remove — "committed" is a moment that already
exists at every call site), one stack across all surfaces because the user's notion of "the last
thing I did" does not partition by surface, and each entry a closure over the store write rather
than a diff (a diff needs a serialiser per store).

**It does not ship in the first landing.** It is the only piece whose absence is an inconvenience
rather than a gap, and the only one gated on an unknown: Ctrl+Z requires the chrome surface to hold
keyboard focus, which no harness can verify (§13).

### 7.4 A restart in the middle

Because the mode is `GlobalStates` and every mutation is already committed, a restart mid-edit does
the right thing with no code: the mode is gone, every committed change is on disk, and the undo
stack (which only ever offered to reverse committed changes) is gone with it. The only loss is a
gesture in flight, which was never committed.

An edit session is exactly when a hot-reload is most likely, since every `.qml` write reloads the
configuration. "The mode did not survive the reload" is correct behaviour — but a reload landing
mid-drag must not be the only path through which §8.3's cancel-not-commit rule is exercised, so the
harness drives it deliberately.

### 7.5 Presets

`scripts/presets.sh` captures `desktopPositions` and `pluginOptions` and merges on apply, honouring
`presetPersist` ids. Edit Mode changes what a user's layout *is*, so applying a preset afterwards
overwrites it — which is what a preset is for and is already true. Edit Mode adds nothing here and
must not: a "save this layout as a preset" button inside the mode is precisely the boundary
violation §9 forbids.

---

## 8. Entering and leaving

### 8.1 Entry

One new row in the desktop context menu, between **Widgets** (`DesktopMenu.qml:274-311`) and
**DropShelf** (`:313-345`), in the shape of the rows already there — no submenu and no chevron,
because unlike Wallpaper & style and Widgets this row has no quick-settings half and no Settings
page behind it. It is a verb.

```qml
RippleButton {
    implicitHeight: 40
    contentItem: RowLayout {
        MaterialSymbol { text: "edit" }
        StyledText { text: Translation.tr("Edit layout") }
    }
    onClicked: {
        GlobalStates.desktopMenuOpen = false
        GlobalStates.editMode = true
    }
}
```

The menu already knows which monitor and which point it was opened at —
`GlobalStates.desktopMenuScreen/X/Y`, written by `Background.qml:1257-1261` — which is enough to
put the toolbar on the screen the user was looking at. The mode itself is global: every monitor's
desktop shrinks, because the bar and dock layouts are global and a per-monitor edit mode would have
to explain why moving a bar chip on monitor 2 changed monitor 1.

**One entrance.** Not a keybind, not a Settings button, not a quick-toggle. All are cheap to add
later, and none of them is the brief.

### 8.2 Exit, as a ladder

`Escape` is overloaded on the desktop already: `WidgetCanvas.qml:44` clears a marquee selection and
`PluginWidget.qml:729-732` cancels a resize. Edit Mode must not take it from either, so Escape
resolves in order and the first match wins:

1. **A gesture is in flight** (a drag, a grip resize, a reorder) → cancel it, restoring the
   pre-gesture state. The mode stays on.
2. **A selection exists** → clear it (`WidgetCanvas.clearSelection`). The mode stays on.
3. **A non-default tab is showing** → return to the Desktop tab. The mode stays on.
4. **Otherwise** → leave the mode.

A pure function of three booleans and a string, and the natural home for the first unit test
(§11.1).

Also exits: the **Done** affordance on the toolbar (unconditionally — it also cancels an in-flight
gesture and clears the selection, because a user pressing Done means "stop"), and anything that
takes the screen away (`GlobalStates.screenLocked` going true, the session screen,
`GlobalStates.overviewOpen`).

Does **not** exit: a click on empty desktop — that is the marquee's press
(`WidgetCanvas.qml:55-61`) and the single most likely accidental click in the whole mode.
Click-away is a dismissal gesture for popups, not for modes; the desktop menu uses it
(`DesktopMenu.qml:150-154`) and Edit Mode must not, or every attempted marquee that starts and ends
on empty canvas would end the session. Opening Settings does not exit either: it is a
`FloatingWindow`, and closing it returns you where you were.

### 8.3 A half-placed widget

**A drag in flight when the mode ends.** The drag is unclamped until release by design
(`AbstractWidget.qml:196-214`) and only `commitPosition()` clamps and writes
(`PluginWidget.qml:572-594`). Ending the mode mid-drag must run the **cancel** path: restore the
pre-press position and the x/y bindings (`restoreXYBinding()`, `:562-570`). Committing instead
stores an unclamped overshoot, which is exactly the defect 705e9006d ("fix(plugins): stop a widget's
stored position disagreeing with where it is drawn") fixed — a real store held `visualizer` at
`x: -852` on a 5120px screen.

**A widget just added and not yet placed.** A newly enabled plugin lands at
`PluginState.defaultPosition()` on *every* monitor (`PluginWidget.qml:404-412`). There is no
"unplaced" state in the store and none should be invented: a widget with no position is a widget the
next shell start cannot draw. So an added widget is placed the moment it is added — at the pointer
if it came from a drop — and leaving the mode changes nothing about it. What Edit Mode owes it is
that dropping from the drawer places it where the user dropped it rather than behind whatever is
already at the default, which is worth doing in the same stage.

---

## 9. The boundary: what must not be reachable

**The rule:** Edit Mode may change *placement, order, span, and presence on a surface*. Everything
else is Settings.

Not tidiness: Settings is one click away *from* Edit Mode, and duplicating rows into the editor
means every one of them is a second call site for a config write. This repo has already paid for
exactly that — `ConfigSwitch`'s binding bug reached 159 call sites
(69c15279a ("fix(widgets): make a ConfigSwitch click an intent, not a write to `checked`")), and the
`activeStill` re-declaration re-armed six presets
(03b8b0298 ("fix(wallpaperEngine): derive the greeter's still path, do not store it")).

| not in Edit Mode | where it lives |
| --- | --- |
| a widget's own options (its manifest `options`) | Settings › Widgets |
| the host's "Widget behaviour" rows — blur, keep-translucent, follow-parallax, preset-persist | `PluginOptions.qml` |
| wallpaper, colour scheme, transparency, frost mode | Settings, and the desktop menu's Wallpaper & style |
| bar auto-hide, bar style, borderless, screen list | `BarConfig.qml` |
| dock auto-hide, icon size, monochrome icons, **edge** | `BarConfig.qml` |
| lock security, keyring, blur radius, fonts | `LockIdleConfig.qml` |
| installing or uninstalling a plugin | `PluginsPage.qml` |
| saving or applying a preset | the preset UI |
| anything about Hyprland | Settings › Hyprland |

**Two deliberate edge cases**, both of which look like violations and are not:

- **`positionLocked` and `clickThrough`** are "Widget behaviour" rows but they are *about*
  placement — a pin is a placement decision — so a per-widget Pin toggle in the mode's context menu
  is in scope. It writes the same `PluginState.setOption(id, "positionLocked", …)` the settings row
  does: one writer, two call sites, not two meanings.
- **`lock.showWidgets` / `showToolbars` / `showMedia`** are presence-on-a-surface, which the rule
  admits. They stay in `LockIdleConfig.qml` as well.

**The mechanism that holds it.** A rule written only in this document lasts until the second
contributor. `tests/lint_edit_mode_scope.py` reads every file under the edit-mode directory and
fails on a write to any `Config.options.*` path outside an allowlist of placement keys, and on any
`PluginState.setOption` whose key is not in `{__gridSize, positionLocked, clickThrough}`. The
allowlist is the spec; the lint is the receipt.

---

## 10. Interaction and motion

### 10.1 Nothing new is invented

Every affordance the mode draws is a control, and this codebase enforces with a lint that a
control's hover and press motion comes from one place:

- Buttons on the chrome (Done, tabs, per-widget remove) are `RippleButton`s, which drive
  `InteractionMotion` and apply its `scale`. Anything writing its own
  `scale: pressed ? 0.9 : (hovered ? 1.1 : 1)` inside one multiplies rather than replaces;
  `lint_interaction_motion_double.py` fails the suite on a scale-family property written from a raw
  hover/press flag inside a control that applies the model, and it is per **channel**, so the same
  rule holds separately for a radius.
- Feedback that is not a multiple of anything reads `hoverProgress` / `pressProgress`.
- Durations and curves come from `Appearance.animation.*` and the five tiers in
  `modules/common/interaction_motion.js`. `InteractionMotion.qml` writes the tier onto the animation
  *before* the target, in the same handler; a chrome element selecting a duration through a binding
  on the animation would carry the *previous* transition.

**The one place the lint cannot see, and it matters here.** `AbstractBackgroundWidget.qml:30` is
`scale: (draggable && containsPress) ? 1.05 : 1` — a raw press scale on a `MouseArea`, not on an
`InteractionMotion` control, so the lint is blind to it by construction. Edit Mode gives every
widget a visible handle, and a handle that also scales on press would compose with that 1.05 the way
discordVoice's glyphs composed with the model. **The lift while dragging belongs to
`WidgetElevation`** (`modules/common/plugins/designsystem/widgets/WidgetElevation.qml`), which owns
the numbers, is already driven by `hostDragging` through the duck-typed path, and which
`test_expressive_design_system.py` pins as the only file allowed to read `Appearance.elevation`.

**And the viewport's own scale composites with all of it.** `Item.scale` multiplies down the scene
graph exactly the way `opacity` does. The viewport transform sits above every widget, so a widget's
press scale is `viewportScale × 1.05` on screen — which is correct and wanted (the widget squishes
by the same *proportion* the user sees everything at), but it means nothing inside the viewport may
try to compensate for the viewport, and nothing may read a widget's on-screen size by multiplying
by hand.

### 10.2 The shared reorder, which is a prerequisite

The reorder gesture has been written four times and does not agree with itself:
`LayoutSection.qml:51-85` is 2-D euclidean nearest-centre over a `Flow`, committing with a
`splice`-out-`splice`-in; `DragApps.qml:343-378` projects onto one axis chosen by the dock's edge
and commits with an **adjacent swap** (`swapSlots`, `:65-74`); `DocktoPanel.qml:170-182` is a third
copy of the second; `AndroidQuickToggleButton.qml:216-220` is a fourth, and swaps too. A fifth
copy written for Edit Mode is exactly the failure AGENT.md's `CavaService` entry describes —
*"two names for one thing let one of them rot silently"*.

`modules/common/functions/layout_ops.js`, a `.pragma library`:

| function | meaning |
| --- | --- |
| `indexAt(centres, point, axis)` | nearest slot along one axis, or 2-D when `axis` is null |
| `move(list, from, to)` | splice-out/splice-in — **move semantics, not swap** |
| `insert(list, id, at)` / `remove(list, at)` | add and remove |
| `dropTarget(buckets, centres, point)` | which bucket and which index, for the bar's three arrays |

`move` rather than `swap` is a behaviour change for the dock and the quick toggles. A swap is wrong
for a drag crossing more than one neighbour: dragging an icon three places left displaces exactly
one other icon instead of shifting three. Worth doing, and worth doing in **its own commit before
Edit Mode**, so a behaviour change on the live dock is reviewable on its own.

The gesture becomes one component (`ReorderDragArea.qml`) exposing `dropIndex` and a drop indicator.
It does not own the commit; each surface commits to its own store.

### 10.3 Where the chrome lives

The viewport is the background surface (§2.3). Chrome that must sit above the bar or the dock goes
on **one always-mapped full-screen `WlrLayer.Overlay` surface per screen**, on
`BarPopupOverlay.qml`'s pattern (d29cd6e45 ("feat(bar): add the static overlay surface the popup
card will live on")). Its four load-bearing properties are not optional:

1. **Geometry is a constant of the screen.** All four edges anchored, no `margins`, no implicit
   size (`BarPopupOverlay.qml:44-51`). On a layer surface position *is* `margins`, so a toolbar
   animating into place would reconfigure the surface every frame.
2. **The mask tracks an item's x/y/width/height and nothing else** — `PendingRegion::setItem`
   connects exactly those four signals — so the chrome's motion is expressed as geometry, never as
   `scale`, `rotation` or `opacity`.
3. **Collapse the mask to 0x0 when the mode is off.** `build()` on a 0x0 item yields an empty region
   and `onPolished` then sets `Qt::WindowTransparentForInput`, which is the only thing making a
   permanently-mapped full-screen `Overlay` surface harmless.
4. **Mint a namespace and add it to `rules.lua`'s computed-threshold loop.** Note this corrects the
   merged version of this document, which said to reuse `quickshell:popup`.
   `BarPopupOverlay.qml:53-69` records why that was tried and abandoned: `quickshell:popup` carries
   `ignore_alpha = 1`, and once tray items moved onto the shared card their context menus —
   xdg-popups of *this* surface — inherited that 1 and stopped being blurred at all. The surface
   has its own namespace (`quickshell:barPopup`, `:70`) listed in the generated-threshold loop in
   `dots/.config/hypr/hyprland/rules.lua:230-238`, whose value `services/PopupBlurThreshold.qml`
   computes so it sits above the shadow and below the faintest body. **A namespace absent from that
   loop falls through the catch-all `ignore_alpha = 0.05`
   (`dots/.config/hypr/hyprland/rules.lua:143`), under which a full-screen surface's transparent
   pixels clear the threshold and the compositor is asked to blur the whole screen.** A new chrome
   surface repeats that exercise in full.

**Anything on the chrome that resizes morphs in one tree.** The toolbar changes width when its
contents change, and this repo's rule for that — enforced by `test_expressive_design_system.py` — is
that a size mode "may decide where an element sits, never whether it exists": a mode name may not
reach a `sourceComponent:` or a `visible:` binding, though `opacity` is allowed. The same file pins
that geometry reads the **settled** size rather than the animating box, that the span animations
have one spelling (`SpanTravel` / `SpanFade`), and that morphing containers share `shape_morph.js`.
A one-tree container also needs `clipContent`: a faded block, unlike a destroyed one, keeps painting
outside a shrinking card.

**The desktop's own chrome stays inside the viewport.** Grips, halos, guides and the grid are drawn
where they are drawn today, inside the widget canvas — moving them to a chrome surface would put
them in a different coordinate frame from the widgets they annotate *and* outside the viewport
transform, so they would be drawn at full size over a shrunk desktop.

---

## 11. Testing

The suite's shape decides where the value is. `qmltestrunner` runs the JS: a `tst_*.qml` imports a
module by relative path and the runner discovers it by prefix from `-input tests/`. That is the
**only** globbed discovery in the whole suite — the Python and shell tier is a hand-maintained
sequential list of 138 `if ! python3 …` blocks in `tests/run_tests.sh`. Python never executes
JavaScript; it reads source text. And CI has no weston, no `qs` and no compositor, so everything in
§11.3 is a local gate only.

(On the headline: the `qmltestrunner` Totals line on `gh/main` is **767 passing**. The Python tier
is roughly twice that and is invisible in it. A change that keeps 767 green has said nothing about
the other tier. Note also that weston harnesses die with `The Wayland connection broke` when several
run at once — that is contention, not failure.)

### 11.1 Pure logic, in `.js`, with `tst_*.qml` — where the value is

All `.pragma library`, all reachable from `qmltestrunner`. The rationale is the one `gridResize.js`
already states about itself: everything else about a resize needs a real host `qmltestrunner` cannot
construct, so the arithmetic is the part a test can reach at all.

- **`modules/common/functions/layout_ops.js`** → `tst_layout_ops.qml`. `move` across more than one
  neighbour (the case a swap gets wrong, asserted as a full expected list rather than "something
  changed"); `indexAt` on a single axis in a column, where the *other* axis's centres are all
  identical — the inert-comparison case `DragApps` shipped and `DockEdgeRuntimeTest` was built to
  catch; `dropTarget` returning a bucket **and** an index; an out-of-range index returning the list
  unchanged rather than a hole.
- **`modules/common/functions/edit_mode.js`** → `tst_edit_mode.qml`. The exit ladder as a pure
  function: `resolveEscape({gestureInFlight, selectionCount, tab})` → `"cancelGesture" |
  "clearSelection" | "desktopTab" | "exit"`, all four branches plus precedence.
- **`modules/common/functions/edge_snap.js`** (§6) → `tst_edge_snap.qml`. The candidate set (four
  relations per neighbour per axis, each carrying a `target` and a `guide`); the perpendicular
  relevance filter, including that the boundary value is excluded; and — the assertion the whole
  section exists for — that a pointer walking past a guide **acquires at the near threshold and
  releases only at the far one**, driven as a sequence of raw positions, so a single-threshold
  implementation fails it by flip-flopping.
- **The viewport's derivation** → the inset from screen width, drawer width and margin, and the
  invariant that the drawer's open state changes the desktop's `x` and **not** its width or scale.
  Two lines of arithmetic, and the one place a regression would be silent.

Each `tst_*.qml` needs nothing registered: it reaches the module by relative path. A new
**singleton** does — `BarWidgets.qml` needs a symlink into `tests/imports/qs/…` and a line in that
directory's local `qmldir` before any test can see it, and a **full `qs` restart** before the running
shell can.

### 11.2 Source contracts, in Python

`tests/test_edit_mode_contract.py`, in the shape of `test_dock_position_contract.py`:

- **One predicate.** No file computes "am I editing" from anything but `GlobalStates.editMode` — the
  direct analogue of `lint_bar_popup_overlay_static.py`'s rule for `barEdge` and the dock's
  one-derivation rule. Four copies of a mode check is how three of them go stale.
- **The viewport translates and does not resize.** The desktop container's `width`/`height`/`scale`
  do not read the drawer's open state; only its `x` does.
- **Nothing inside the viewport compensates for the viewport.** No file under the edit-mode
  directories divides or multiplies by the viewport scale to recover a screen coordinate.
- **The chrome surface is static** — no `margins`, no `implicitWidth`/`implicitHeight`, all four
  anchors — and **its mask collapses** to 0x0 when the mode is off.
- **The chrome surface's namespace is in `rules.lua`'s threshold loop.** A source contract across
  the QML and the Lua, because the failure (the compositor asked to blur the whole screen) is loud
  on screen and silent everywhere else.
- **No second motion.** No scale-family property in the chrome bound to a raw hover/press flag, and
  no `MultiEffect` shadow reading `Appearance.elevation` outside `WidgetElevation.qml`
  (`modules/common/plugins/designsystem/widgets/`).
- **The exit ladder is wired to the module**, not open-coded in a `Keys.onEscapePressed`.
- **Ending the mode mid-drag calls the cancel path**, i.e. `restoreXYBinding` and not
  `commitPosition`.
- **No swap left.** `DragApps` and the quick-toggle panel commit through `layout_ops.move`.
- **No free-form resize is introduced.** Nothing under the edit-mode directories writes a widget's
  `width`/`height`/size option from a pointer delta; a Size affordance indexes `offeredGridSizes`.
  §5's rule, mechanized, because the tempting way to build a resize handle is the one calendar
  declares no `grid` to avoid.
- **The lock preview cannot authenticate.** `LockSurface.qml` contains `interactive` and gates
  `forceFieldFocus`, the field's `enabled` and every session action on it; the preview host passes
  `interactive: false`; the preview context declares no `PamContext` and runs no `fprintd-list`.
  This is the one contract whose failure is a security bug rather than a layout bug, and it is worth
  a sweep that **asserts it still found the file** rather than passing when the grep matches nothing.

**Both files must be written so they can run and so they can fail.** `run_tests.sh` invokes each as
`python3 <file>`, so a module of bare `test_*` functions exits zero having asserted nothing — three
have shipped in that state. Subclass `unittest.TestCase` with `unittest.main()`, or end with the
`contract_runner` block. Prove each check fails by planting the violation, and **plant only in a
clean tree** — `git checkout -- <file>` reverts to HEAD and has destroyed uncommitted work three
times in two days. Add each as its own block in `tests/run_tests.sh`.

**Existing lints the new surfaces must satisfy**, listed because a new directory is exactly where an
exception gets carved: `lint_spacing.py`, `lint_material_icons.py` (the `edit` glyph must exist in
every installed copy of the font), `lint_clickable_cursor.py`, `lint_window_clear_color.py` (a chrome
surface's `color:` must be a **literal**; a bound one latches the surface opaque and costs it its
blur for the life of the process — deba3e3f6 ("fix(settings): keep the window's clear colour
constant so the frost survives")), `lint_qml_imports.sh`, `lint_duplicate_imports.py`,
`lint_qmldir_registration.py`, `lint_rich_text_optin.py`, `lint_disabled_opacity.py`.

### 11.3 Runtime harness — what it can and cannot say

`EditModeRuntimeTest.qml` at the theme root, driven by `tests/test_edit_mode_runtime.py` under
headless weston (`weston --backend=headless --renderer=pixman`, `LIBGL_ALWAYS_SOFTWARE=1`,
`QT_QUICK_BACKEND=software`, throwaway XDG dirs, `qs -p`, teardown by held PID), in the shape of
`WidgetResizeGripRuntimeTest.qml` and `DockEdgeRuntimeTest.qml`
(2c8ccae70 ("test(widgets): drive the resize grip with real mouse events")). `import QtTest` works
inside `qs -p`, so `TestCase.mouseClick`/`mouseDrag` deliver **real events** with no ydotool. It
builds a real widget canvas with real `PluginWidget`s from synthetic manifests, flips
`GlobalStates.editMode`, and drives:

- **A drag inside a scaled canvas lands where the pointer did.** The check the viewport exists for:
  the same gesture at scale 1 and at scale 0.8 must produce the same *screen* travel and the same
  stored position relative to the canvas. A synthetic drag is where a swallowed press-origin delta
  shows (d2ebb5aeb measured half a gesture lost), so this is the one assertion that has already
  caught this class of bug once.
- **The drawer's open state moves the desktop and does not resize it** — assert the container's
  width across the toggle, not only its x.
- A drag with the mode on and the global lock set **also** moves the widget (§4.1's suppression),
  while a per-widget `positionLocked` still refuses.
- A bar chip dragged **along** the bar reorders and dragged **across** it does not — the control
  that catches a comparison inert on one axis.
- Ending the mode mid-drag leaves the stored position at its pre-press value.

Three constraints, which belong in the harness's docstring rather than being rediscovered:

- **Weston implements no wlr-layer-shell**, so nothing about any *surface* — anchors, mask, keyboard
  focus, blur — is visible. The harness reaches content trees only.
- **A key event has no explicit target**: `TestCase` sends it to the focused item of its own window,
  so a driver parented outside any window cannot deliver one. The Escape ladder is tested through
  §11.1's pure function plus a direct call.
- **The harness must report that it ran.** Every harness prints `checks: N failures: M` with
  `checksRun` incremented inside its own `check()`, and the driver asserts the **literal** N held in
  a module-level `EXPECTED_CHECKS`. `failures: 0` is what a harness that ran nothing prints.
  `tests/lint_harness_check_counts.py` fails the suite on either half
  (0b3a900f4 ("test(lint): fail on a harness verdict that states no check count")). Build synthetic
  manifests through a `Repeater` rather than inline on the harness root — the model boundary is where
  `grid.sizes` was silently lost once already
  (109e6d897 ("fix(plugins): a manifest's grid.sizes survives the model boundary")).

One thing the harness must **not** do: reach the caller's compositor. `hyprctl` takes its target from
`HYPRLAND_INSTANCE_SIGNATURE` and from nothing else, so a bare `hyprctl` inside a harness talks to
the user's live session; `lint_harness_compositor_reach.py` fails the suite on one.

### 11.4 Not reachable, and must not be faked — the probes that gate stage 3

Four questions decide whether §2's recommendation survives, and none is reachable from any harness.
They are a **manual live load with a readback, performed before stage 3 is written**, and recorded
in the PR:

1. **Does the alpha-map claim at `Background.qml:1186-1189` still hold?** Scale the widget canvas
   on a live desktop with a Wallpaper Engine wallpaper running and look at whether the compositor's
   blur map follows. If it does not, §2.2's second condition is met and proxies come back on the
   table.
2. **Does the frost stand down cleanly?** With §2.4's gate extended, confirm no widget draws a
   misaligned frost during the mode, and that it comes back correctly on exit — noting that it comes
   back *serially*, one widget at a time, if anything rebuilds the blur surfaces
   (33139b688 ("fix(widgets): give every desktop widget's frost one shared wallpaper decode")).
3. **Where does the chrome land relative to the bar and the dock?** `hyprctl layers -j`, and the
   answer decides §2.3's second surface.
4. **Does a layer surface hold keyboard focus here?** The background surface takes keys only while
   `WlrLayershell.keyboardFocus` is `OnDemand`, which `GlobalStates.desktopWidgetKeyboardFocus` arms
   (`Background.qml:542-544`, `WidgetCanvas.qml:17-23`). Establish this with a live probe *before*
   designing any keyboard interaction — it is what §7.3's undo depends on.

Plus, on every live load: a confirmed `Configuration Loaded` and a `grep ERROR:` after the reload
(the QML suite stays fully green for a file that fails to compile), and a frame-by-frame capture
(`ffmpeg -fps_mode passthrough`) for anything under ~200ms.

Two traps in doing that: a widget disabled while its edit chrome is on screen destroys the content
while the chrome still points at it (the `BarContent.filterLayout` shape — the declaring object has
to vacate the slot from `Component.onDestruction`), and a `qs -p` probe is a fresh process, so it
will not reproduce the "new singleton needs a full restart" failure the user's long-running
`qs -c imi` will.

---

## 12. Landing plan

Ten stages. Each leaves the tree working, is separately reviewable on screen, and could be merged
and then abandoned without leaving the shell worse. Stages 1-2 are prerequisites carrying their own
user-visible value; **stage 3 is the first one a user would call "Edit Mode"**.

1. **`layout_ops.js` + `tst_layout_ops.qml`. No caller.** Pure arithmetic. *Ships alone as new
   tested code with no behaviour change.*
2. **The four existing reorder call sites adopt it, and swap becomes move.** `LayoutSection.qml`,
   `DragApps.qml`, `DocktoPanel.qml`, `AndroidQuickToggleButton.qml`. *Reviewable as "the dock's
   drag reorder stopped being a swap", which people can judge on its own.*
3. **The viewport, desktop only.** `GlobalStates.editMode`; the desktop-menu row; the shrink and
   inset on the background surface; the blur `Loader`'s second gate; the frost gate generalised
   (§2.4); the exit ladder (`edit_mode.js` + `tst_edit_mode.qml`); the desktop's affordances forced
   on (12px grid, grips, global-lock suppression); the mid-drag cancel. **Gated on §11.4's four
   probes.** *Shippable alone: right-click → Edit layout shrinks the desktop and gives you the
   editor you already had, made visible.*
4. **The chrome: toolbar, Done, and the tab bar with only the Desktop tab in it.** On the second
   surface if probe 3 says so, on the background surface if not. *The stage where the surface
   contract lands (`test_edit_mode_contract.py`'s first half).*
5. **The drawer, and add-at-pointer.** The drawer's width becomes the inset's input; opening it
   translates the desktop; a widget dropped from it lands at the pointer.
   `PluginManager.availablePlugins` feeds it. *`lint_edit_mode_scope.py` lands here with the
   allowlist it will police; `WidgetsSubmenu` is removed in its own commit.*
6. **Per-widget context menu and the Size stepper.** Right-click on a widget opens Remove / Pin /
   Size instead of toggling the global lock; Size indexes `offeredGridSizes`. *§5's rule, and its
   contract.*
7. **`BarWidgets` catalogue promoted out of `BarConfig.qml:49-71`.** *Ships as a move; `BarConfig`
   reads the singleton and looks identical.*
8. **The bar and the dock, in place.** Auto-hide suspended by adding a term to `mustShow`, widgets
   inert, remove badges, `ReorderDragArea` across the three buckets, visible bucket boundaries, add
   from `BarWidgets` and `DesktopEntries`. *Test: the runtime harness's along/across drag pair.* Two
   orientations, two content trees: a fix applied to one is invisible in the other.
9. **`LockSurface.interactive`, the preview context, and the Lockscreen tab.** The refactor and the
   preview context first, as their own commit with no editing in it — that is the stage that most
   wants a careful review, so it should not be carrying a feature. Then the tab: the locked
   wallpaper, blur and widget filter in the viewport, the islands rendered, the bar and dock gone,
   and island *visibility* editable.
10. **Edge snap and hysteresis (§6), then undo (§7.3).** Edge snap is arithmetic plus a `tst_*`; undo
    is last because it is the only piece gated on §11.4's probe 4.

---

## 13. Risks worth naming before building

- **The alpha-map comment.** `Background.qml:1186-1189` explicitly says not to wrap plugin widgets
  in a `Scale` transform. It may be stale — it predates the in-shell frost — but it is the single
  written objection to the whole design, and §11.4's probe 1 exists for it. Do not reason it away.
- **A full-screen `Overlay` surface that forgets to collapse its mask eats every click on the
  desktop.** The mode being *off* is the dangerous state, because that is the one nobody looks at.
- **A namespace missing from `rules.lua`'s threshold loop asks the compositor to blur the whole
  screen** (`dots/.config/hypr/hyprland/rules.lua:143`, and the loop at `:230-238`). The failure
  directions are opposite — too low and the whole screen frosts, too high and the chrome's own body
  goes flat — and neither logs anything.
- **The dock's dynamic-scope lookups** resolve `dockRow` and `dockVisualBackground` by name through
  the dock's tree. Chrome that reparents anything there yields `undefined` → NaN geometry → a
  relayout that never converges and a pegged core, with no error.
- **Suspending the bar's auto-hide is a state change on a layer surface**, and `visible: false` on
  one destroys it rather than hiding it. Add a term to `mustShow` (`Bar.qml:57-58`).
- **The dock is already hidden by `visible: false` while locked** (`Dock.qml:37`), so the Lockscreen
  tab inherits a surface teardown and rebuild on every tab flip. Fine in principle; look at it.
- **Keyboard focus on a layer surface is not a given, and Ctrl+Z depends on it** — and **no harness
  can verify it**, because weston gives no wlr-layer-shell.
- **A green suite says nothing about whether any of this loads.** `qmltestrunner` never builds these
  widgets; a `FINAL` property override on anything deriving from `RippleButton`, or a missing
  `import qs.modules.common`, passes every test and takes down every panel that reaches it.
- **`__gridSize` is per plugin, not per monitor** (`PluginState.qml:18-31` — `pluginOptions` is keyed
  by id alone, while `desktopPositions` is keyed by screen then id). Resizing a widget on one monitor
  resizes it on all of them. Shipped behaviour, not something Edit Mode introduces, but Edit Mode is
  where a user will first notice it.
- **`background.screenList` is declared (`Config.qml:945`) and written by the "Show widgets on"
  selector, and nothing reads it.** Desktop widgets render on every screen regardless. A mode that
  shrinks every monitor's desktop at once will make that gap conspicuous.

---

## 14. The open question

**Can the user reorder what is *inside* the lock islands, or only toggle which widgets appear?**

**Visibility alone needs no new storage.** `lock.showToolbars`, `lock.showMedia` and
`lock.showWidgets` already exist (`Config.qml:1206-1208`), and per-item visibility inside an island
can be expressed the same way.

**Reordering needs three ordered lists in `Config.options.lock` and a data-driven rewrite of
`LockSurface.qml:236-501`.** Those line numbers still hold on `gh/main`: `:236` is the `// Left
toolbar` comment above `leftIsland`, and `:501` is the closing brace of `rightIsland`. Between them
are hand-placed children — an `IconAndTextPair` for the username, a `Loader` for the media block, a
keyboard-layout pair, a battery pair, and three toolbar buttons — each declared in place, several
with their own `visible:` conditions and one with a `MaterialSymbol` nested two levels down. The
main island (`:105-234`) is a third such list, and it also holds the password field, so a
data-driven rewrite there is not the same job as the other two.

Turning that into three ordered lists means: an id per item, a delegate per item type, a resolver
mapping an id to a component, and the rule `gridSizes.resolveSize` already applies to a stored
choice — **an unknown id resolves to its default position rather than disappearing**, because a
list written by one version and read by another is exactly where a silent removal happens.

**Recommendation: visibility for the first landing, contents as a follow-up spec.** Three reasons.
The islands' *positions* are literals in the anchors and are not editable either way (§4.3), so
reordering their contents delivers less than it looks like it will. The rewrite touches the file
whose defining property is that it is a security surface, in the same stage that introduces the
preview context — and §12 stage 9 deliberately splits the preview refactor from the feature for
exactly that reason. And this is the question whose answer decides whether stage 9 is small or
large, so answering it "small" is what keeps the mode shippable before the lock work is finished.

If the answer is "reorder", it is its own spec and its own stage 11, not an expansion of stage 9.
