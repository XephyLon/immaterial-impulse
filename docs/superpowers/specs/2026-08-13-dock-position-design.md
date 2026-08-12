# The dock's edge, the way the bar already does it — design

**Status:** design, not implemented. §9 holds seven questions that must be answered before an
implementation plan; four of them change the shape of the work rather than a detail of it.
**Scope:** `modules/imi/dock/`, `modules/common/widgets/Dock*.qml` + `DragApps.qml`,
`modules/common/Config.qml`, `modules/imi/settings/pages/BarConfig.qml`, `defaults/config.json`,
and one line of repo-relative `dots/.config/hypr/hyprland/rules.lua`.

Paths are relative to `dots/.config/quickshell/imi/` unless written repo-relative.

## Problem

The bar can sit on any of the four screen edges and the dock cannot sit anywhere but the bottom.
The edge is asserted once, as a literal, with no config key behind it:

```qml
anchors { bottom: true; left: true; right: true }   // Dock.qml:48
```

`Config.options.dock` (`Config.qml:1123-1137`) has eleven keys and none of them is a position. The
settings UI has a Dock section (`BarConfig.qml:658-720`) sitting four hundred lines below the bar's
own four-way position selector (`BarConfig.qml:219-233`), and offers nothing equivalent.

That one literal is cheap to change. Its consequences are not, and the honest part of this document
is the list of things that quietly encode "the dock is at the bottom" without saying so.

## How the bar actually does it

Read rather than assumed, because three of the four facts below are surprising.

**The setting is two booleans, and one of them is overloaded.** `bar.bottom` (`Config.qml:991`,
commented `// Instead of top`) and `bar.vertical` (`Config.qml:1004`). When `vertical` is true,
`bottom` stops meaning bottom and starts meaning *right* — `VerticalBar.qml:108-113` anchors
`left: !Config.options.bar.bottom` / `right: Config.options.bar.bottom`. The settings row hides this
behind a bitfield (`BarConfig.qml:222-232`: `1 = bottom, 2 = vertical`, so `3 = right`), and that
same bitfield is open-coded a second time in `QuickConfig.qml:558-561` and a third in
`welcome.qml:208-211`.

**Four edges are two modules, not one rotated one.** `ImmaterialImpulseFamily.qml:32` loads `Bar`
only when `!bar.vertical`; `:54` loads `VerticalBar` only when `bar.vertical`. They are separate
files with separate content trees (`BarContent.qml` / `VerticalBarContent.qml`). Within one
orientation the flip *is* handled in place, by `AnchorChanges`/`PropertyChanges` states keyed on
`bar.bottom` (`Bar.qml:303-321` for the content, `:262-279` and `:332-349` for the corner
decorators). So: **mirror in place, rebuild across orientations.** That is the bar's answer, and it
is the strongest single piece of evidence in the repo about what a horizontal-to-vertical change
actually costs.

**Everything downstream re-derives a named edge from the pair.** The pair is stored; a string is
what gets consumed:

```qml
readonly property string barEdge: {
    if (!barVertical) return Config.options.bar.bottom ? "bottom" : "top"
    return Config.options.bar.bottom ? "right" : "left"
}                                                       // StyledPopup.qml:120-123
```

The identical block appears at `MediaControls.qml:35-38` and `BarPopupOverlay.qml:385-390`, and
`lint_bar_popup_overlay_static.py:82-94` exists to force the third one to derive from config rather
than from whichever popup is on screen — the fix for #140, where a per-popup watcher fired on a
binding's first evaluation and read as an orientation flip (`867dd811a`). Consumers then pair it
with a thickness token: `barThickness` = `verticalBarWidth` or `barHeight`
(`StyledPopup.qml:124`, `MediaControls.qml:41`, from `Appearance.qml:499-501` and `:604-606`).

**The compositor is told "slide" and infers the direction.** `rules.lua:144` and `:229` give
`quickshell:bar` and `quickshell:verticalBar` a bare `animation = "slide"`. Hyprland picks the
direction from the surface's anchors, so the bar's open/close animation follows its edge with no
shell involvement at all. `quickshell:dock` is the one that hardcodes it: `animation = "slide bottom"`
(`rules.lua:147`).

**And the exclusive zone is measured, not declared.** From the running shell (`hyprctl layers -j` /
`hyprctl monitors -j`, 5120x1440, defaults):

| namespace | y | h | reserved |
| --- | --- | --- | --- |
| `quickshell:bar` | 5 | 63 | top 45 |
| `quickshell:dock` | 1365 | 75 | bottom 65 |

Both sit on layer level 2 (`Top`). The dock's 75 is `dock.height` 60 + `elevationMargin` 10 +
`hyprlandGapsOut` 5 (`Dock.qml:53-55`), and its 65 is that minus the elevation margin
(`Dock.qml:43-46`). The bar's 45 is its 40px zone (`Bar.qml:63`) plus its 5px detach margin. Note
`Bar.qml:62` sets `exclusionMode: ExclusionMode.Ignore` *and* reserves 45px anyway — whatever that
property does here, it is not "do not reserve". §3 does not build on it.

---

## 1. Which edges the dock gets, and what breaks at each

All four. But "all four" is two different pieces of work, and conflating them is how this ships
half-done.

### The opposite-edge flip is a mirror, and the existing tree survives it

Bottom to top changes six things, all of them local and all of them already expressible as states
in the style of `Bar.qml:303-321`:

| file:line | today | at the top edge |
| --- | --- | --- |
| `Dock.qml:48` | `anchors { bottom: true; left; right }` | `top` instead of `bottom` |
| `Dock.qml:76-93` | reveal pushes the mouse area's `topMargin` down by `implicitHeight + 1` to hide | pushes the `bottomMargin` up |
| `Dock.qml:121-122` | `topMargin: elevationMargin` (shadow), `bottomMargin: hyprlandGapsOut` (edge gap) | the pair swaps sides |
| `DockIconMotion.qml:33,52,104-106` | hover lift and launch bounce are `-y` only | `+y` |
| `DockAppButton.qml:141-146` | running-window dots anchor `top: iconImageLoader.bottom` | dots above the icon |
| `DockContextMenu.qml:70-71`, `DragApps.qml:360-361` | popups open with `gravity: Edges.Top` | `Edges.Bottom` |

The `RowLayout` (`Dock.qml:130`), the icon sizing (`DockAppButton.qml:28`,
`DockButton.qml:9`: `implicitWidth: implicitHeight - topInset - bottomInset`), `DockMedia`'s 240px
card (`DockMedia.qml:18`) and the drag reorder all survive unchanged. This half is a mirror.

### The vertical dock is a different layout, not a rotated one

Five things do not rotate, and saying otherwise would be the lie this document exists to avoid.

1. **Icon sizing inverts.** `DockAppButton.qml:28` and `DockButton.qml:9` derive width from height
   minus the *vertical* insets. In a column the governing axis is width, and the insets that must be
   subtracted are the horizontal ones. Both expressions have to be written in terms of "along" and
   "across" rather than width and height.
2. **The margin asymmetry is replicated in three widgets by dynamic scoping.**
   `DockSeparator.qml:7-8` reads `dockRow.padding`; `DockAppButton.qml:37-41` reads
   `dockVisualBackground.margin` *and* `dockRow.padding`. Neither is passed in — they resolve by QML
   dynamic scope through the dock's own tree. Any restructure that renames or relocates `dockRow` or
   `dockVisualBackground` silently breaks both, with no error, because a failed dynamic lookup
   yields `undefined` and NaN geometry (see AGENT.md's Design-language note on the CPU spin that
   follows). This is the single most dangerous mechanical fact in the file.
3. **The drag reorder is X-only.** `DragApps.qml:88` places slot *i* at
   `x: index * (btnSize + btnSpacing)`; the reorder math at `:287-306` compares
   `dragHandler.centroid.scenePosition.x` against each child's mapped centre `x`; the preview
   popup's placement (`popupCenterXForButton`, `DragApps.qml:45-48`) maps only the x component.
4. **Running-window dots hang below the icon** (`DockAppButton.qml:141-146`), which in a column
   points into the neighbouring icon rather than out of the dock.
5. **The media tile does not fit.** `DockMedia.qml:18` is a 240px-wide card with art, a two-line
   title/artist column and a transport row (`:145-236`), sized to `parent.height` (`:87`). A dock
   whose thickness is `dock.height`'s 60px has a 60px-wide column to put it in. There is no rotation
   of a 240x60 card that is 60x240 and still readable. This is a product decision, not a layout
   one — §9 Q1.

### The shell already ships a vertical dock strip, and it is not in the dock

`modules/imi/bar/DocktoPanel.qml` renders the dock's pinned and running apps *inside the bar* — same
`Config.options.dock.pinnedApps` (`:22`, `:136`, `:180`), same `dock.monochromeIcons` (`:339`,
`:444`) — and it has had a full vertical mode since it landed:

- `:20` `property bool vertical: Config.options.bar.vertical`
- `:213` `flow: root.vertical ? Flow.TopToBottom : Flow.LeftToRight`
- `:267-268` drag translation switches axis; `:290`, `:302` reorder compares `scenePosition.y`
- `:355-363`, `:460-468` running dots move from below the icon to the right of it
- `:388-395` the separator swaps its long axis

So four of the five problems above already have a worked answer in this tree, written by this
project, against the same data. The vertical dock is not a design from zero — it is `DocktoPanel`'s
layout hosted on a dock surface. The fifth (the media tile) is the one `DocktoPanel` never had to
solve, because it never carried one.

## 2. Where the setting lives

**One key: `Config.options.dock.edge`, a string, one of `"top" | "bottom" | "left" | "right"`,
default `"bottom"`.** Added to the `dock` `JsonObject` at `Config.qml:1123-1137` and to
`defaults/config.json:486-503`.

Not the bar's `bottom` + `vertical` pair, for reasons that are about this repo rather than about
taste:

- **The bar cannot have the string and the dock can.** `bar.bottom` is present in every
  `config.json` the shell has ever written and in every preset file under
  `~/.config/immaterial-impulse/presets/`, which `writeAdapter()` never rewrites (AGENT.md, "Presets
  are the exception"). Renaming it is lossy in a way a migration cannot fully repair. `dock.edge`
  is new: no stored values, no presets naming it, no migration.
- **The string is what every consumer already wants.** Three files derive exactly this vocabulary
  from the bar's pair (`StyledPopup.qml:120-123`, `MediaControls.qml:35-38`,
  `BarPopupOverlay.qml:385-390`) and a lint exists to stop a fourth derivation drifting. Storing
  what is consumed removes the derivation instead of adding a fourth copy of it.
- **A missing key falls back to the QML default**, so a user whose `config.json` predates this
  change gets `"bottom"` and sees no change. That is the correct no-op; it is *not* the "changing a
  default is invisible" trap in AGENT.md, because the key is new rather than re-defaulted.

**Global, not per-monitor** — matching the bar, whose `bottom`/`vertical` are global and whose only
per-monitor key is `bar.screenList` (`Config.qml:1033`). The dock has no `screenList` at all: it
runs `Variants { model: Quickshell.screens }` unfiltered (`Dock.qml:20`). That gap is real and is
*not* in scope here (§9 Q4).

**`dock.height` and `dock.hoverRegionHeight` keep their names and gain a second meaning:** the
dock's thickness, and the reveal sliver's thickness, on whichever axis the edge implies. They are
misnamed for a vertical dock. Renaming them is the preset problem above for no user-visible gain,
so the names stay and this paragraph is the record of what they mean. The settings UI can relabel
them without touching the keys.

**Settings UI:** one `ConfigSelectionArray` row at the top of the existing Dock section
(`BarConfig.qml:663`, inside the first `GroupedList`), modelled on the bar's
(`BarConfig.qml:219-233`) but writing the string directly:

```qml
ConfigSelectionArray {
    text: Translation.tr("Dock position")
    icon: "swap_vert"
    currentValue: Config.options.dock.edge
    onSelected: newValue => { Config.options.dock.edge = newValue; }
    options: [
        { displayName: Translation.tr("Top"),    icon: "arrow_upward",   value: "top" },
        { displayName: Translation.tr("Left"),   icon: "arrow_back",     value: "left" },
        { displayName: Translation.tr("Bottom"), icon: "arrow_downward", value: "bottom" },
        { displayName: Translation.tr("Right"),  icon: "arrow_forward",  value: "right" }
    ]
}
```

One row, in one file. The bar's selector exists in three (`BarConfig.qml:222`,
`QuickConfig.qml:558`, `welcome.qml:208`), each open-coding the bitfield; that is a wart to not
reproduce (§9 Q6).

## 3. Anchoring, exclusive zone, margins

### One derivation, in a testable module

`modules/imi/dock/dock_geometry.js` — a `.pragma library`, in the style of `media_geometry.js`,
`cookie_layout.js` and `resize-tension.js`, all of which exist for the same reason: the numbers are
the part a test can reach. It takes the edge string and the size tokens and returns:

| returns | horizontal edges | vertical edges |
| --- | --- | --- |
| `anchors` | `{top: edge==="top", bottom: edge==="bottom", left: true, right: true}` | `{left: edge==="left", right: edge==="right", top: true, bottom: true}` |
| `thickness` | `dock.height + elevationMargin + hyprlandGapsOut` (the current `Dock.qml:53-55`) | identical arithmetic, applied to width |
| `exclusiveZone` | `thickness - elevationMargin` (the current `Dock.qml:43-46`, measured at 65) | identical |
| `inwardInset` / `outwardInset` | `elevationMargin` / `hyprlandGapsOut` | same pair, on the horizontal axis |
| `hiddenOffset` | `+ (thickness + 1)` on the inward margin | same, on the inward margin |

`inwardInset` / `outwardInset` are the whole of §1's margin asymmetry, named once. `Dock.qml:121-122`,
`DockSeparator.qml:7-8`, `DockButton.qml:8` and `DockAppButton.qml:37-41` all currently spell the
same pair out by hand as `topMargin`/`bottomMargin`; after this they read it. That is what makes the
mirror a state change rather than four coordinated edits that can drift.

The exclusive-zone arithmetic does not change. The measured baseline (`bottom 65` at defaults) is
recorded above precisely so a regression is a number rather than an impression.

### The reveal push changes axis, not shape

`Dock.qml:76-93` animates `dockMouseArea.anchors.topMargin` between three values — 0 (revealed),
`implicitHeight - hoverRegionHeight` (hover sliver), and `implicitHeight + 1` (hidden). All three
become the *inward* margin, and the `Behavior` (`:91-93`) is untouched. `mask: Region { item:
dockMouseArea }` (`:57`) follows the item on its own — `PendingRegion::setItem` connects x, y, width
and height (AGENT.md, layer-shell section), and this motion is all four.

### The bar and the dock on the same edge

**This is already reachable today and nothing arbitrates it.** A bottom bar (`bar.bottom = true`)
and a bottom dock both anchor the bottom edge, both sit on layer `Top` (measured, §"How the bar
actually does it"), and neither reads the other. `Bar.qml:62` claims `ExclusionMode.Ignore` while
demonstrably reserving 45px, so the property's name is not a reliable guide to what the compositor
will do with two exclusive surfaces on one edge. **Measure it — `hyprctl layers -j` plus the
`reserved` array from `hyprctl monitors -j`, with a bottom bar and a pinned dock — before writing a
line of arbitration.** Reasoning about it from the property names is exactly the mistake AGENT.md's
`hyprsunset` entry documents.

Two policies, and they answer different questions:

**Stacking is fine and needs no code.** If the compositor lays the two out cumulatively, a bottom
bar plus a pinned dock is a legitimate arrangement that many people would choose deliberately. The
dock should not refuse it, and the settings UI should not grey the bar's edge out of the dock's
selector. Forbidding a working arrangement to avoid writing a guard is the wrong trade.

**The unusable arrangement is not "same edge" — it is "same edge, both auto-hiding".** Both
surfaces hide by leaving a reveal sliver at the screen edge: the bar's is
`bar.autoHide.hoverRegionWidth`, 2px by default (`Config.qml:979`), published inside the surface at
`Bar.qml:235-252`; the dock's is `dock.hoverRegionHeight`, also 2px (`Config.qml:1131`), at
`Dock.qml:84`. Two 2px strips fighting over row 0 of one screen edge is not a layout that can be
tuned into working — and `Bar.qml:68-79`'s comment is the record of how expensive that class of bug
already was once. When a hidden dock covers a hidden bar's strip, the bar becomes unrevealable and
the user has no way to discover why.

The precedent for resolving a same-edge collision is in this repo and is not a prohibition: when the
bar and the screen corners are forced onto one layer, `Bar.qml:86-105` carves the corners' hit rects
out of the bar's own mask with a subtractive `Region`, so the loser stays reachable. The equivalent
here is that the **dock gives**: when `dock.edge` equals the bar's edge and either is auto-hiding,
the dock offsets its reveal sliver inboard by the bar's reserved thickness so both strips exist and
neither is on top of the other. The dock is the one that gives because it is opt-in
(`dock.enable` defaults to `false` in the schema, `Config.qml:1124`) and the bar is the shell's
primary chrome and is always present.

Whether that offset is the right answer or whether the combination should simply be refused in the
UI is §9 Q3. What is settled is that the guard belongs on the *reveal strips*, not on the edge.

## 4. What else has to follow the dock

Short, and the reason it is short is worth stating: **almost nothing in this shell tracks the dock,
because the compositor's reserved area does the tracking for it.** A pinned dock reserves 65px
(measured) and every layer surface with a non-negative exclusive zone is laid out outside it without
naming the dock at all. An unpinned dock reserves nothing and overlaps whatever is under it —
already true today, and a move only changes *what* it overlaps.

**Must change:**

| file:line | why |
| --- | --- |
| repo-relative `dots/.config/hypr/hyprland/rules.lua:147` | `animation = "slide bottom"` is the only hardcoded direction. Replace with the bare `animation = "slide"` the two bars already use (`:144`, `:229`) and let Hyprland infer it from the anchor. No generated `shellOverrides` file is needed — that machinery (`services/PopupBlurThreshold.qml`, `rules.lua:208-210`) exists for values a layerrule cannot compute, and this is not one. |
| `DockContextMenu.qml:70-71` | `gravity: Edges.Top` / `edges: Edges.Top` — the menu always opens upward. Derive from the edge. `:93-96` bottom-aligns the card inside its popup surface and follows. |
| `DragApps.qml:357-362` | the window-preview popup's `gravity`/`edges`; `:373` and `:401-403` bottom-align the card; `:45-48` centres it on the button's x only. |
| `DockIconMotion.qml:33,52,104-106` | lift, bounce and the `Translate` are `-y` only. Needs an axis and a sign, both derived from the edge, not four call sites each deciding. |
| `DockAppButton.qml:141-146` | running dots below the icon; `DocktoPanel.qml:355-363` is the worked vertical answer. |

**Deliberately unchanged, with the reason:**

- `NotificationPopup.qml:33,37,66,117-141` — `exclusiveZone: 0`, bottom-anchorable, no dock term.
  It works today only because a *pinned* dock's reserved area pushes it, and it overlaps an unpinned
  one. A side dock inherits exactly that behaviour, unchanged. Fixing it is a separate, pre-existing
  problem.
- `OnScreenDisplay.qml:189-190,215-217` — follows `bar.bottom` and offsets by `barHeight`. It tracks
  the *bar*; it has never tracked the dock and this change does not make it need to.
- `Overview.qml:26,56` with `OverviewWidget.qml:32-36` — reads Hyprland's `monitorData.reserved`,
  so it picks the dock up by reserved area rather than by name, on any edge, for free.
- `Background.qml:540-547` and the desktop-widget host — no dock term anywhere. Widgets clamp to
  `[0, screenSize - widgetSize]`, so a side dock can cover a widget parked at that edge, exactly as
  a bottom dock already can.
- `RegionSelection.qml:102` — excludes the dock from screenshot region snapping by namespace
  (`":dock"`), which survives any move.
- `rules.lua:181` (`blur = false`) and `:219-227` (the popup `ignore_alpha` loop) — namespace-keyed
  and edge-agnostic. The `WindowBlurRegion` at `Dock.qml:66-70` tracks `dockVisualBackground`, which
  moves with the layout, so the blur region follows without an edit.

## 5. Motion: a re-map, not a journey

**The dock does not travel across the screen when its edge changes, and this is a constraint rather
than a preference.**

The M3E initiative's rule is that elements should travel rather than disappear. It is scoped to
elements *inside* a surface — the expressive-morphing spec's whole subject is a widget's own tree
reflowing between spans. A layer surface is a different object: **on a layer surface, position *is*
`anchors` and `margins`**, so animating the dock from the bottom edge to the left edge means
reconfiguring the surface on every frame for the duration. AGENT.md states the consequence directly,
in the `BarPopupOverlay` note: a card animating along the bar "would reconfigure the surface every
frame — the create-map-destroy loop `StyledPopup`'s imperative positioning already existed to
avoid". That is the same mechanism, over a longer distance, and it is the reason `BarPopupOverlay`
is a full-screen surface with a moving item inside it.

The full-screen-surface trick does not rescue this one either. A dock hosted on a screen-sized
surface would need a mask tracking the moving body (which `PendingRegion` does support) but would
also have to publish an *exclusive zone*, and a zone is a property of the surface's anchored edge —
there is no such thing as a partial zone on a surface that is mid-flight between two edges. So the
travel and the reserved area are mutually exclusive, and the reserved area is the feature.

**What happens instead, and it is not settle-on-restart:** the change is live and animated. The
surface exits toward the edge it is leaving and enters from the edge it is arriving at, which is
precisely what a bare `animation = "slide"` gives once `rules.lua:147`'s hardcoded direction is
removed (§4). No shell-side animation code is required for the surface itself. Same-orientation
flips (bottom↔top, left↔right) additionally keep their content tree alive, so icon state, hover
state and `DockLaunchTracker` bookkeeping survive the flip; the internal mirror rides
`Appearance.animation.elementMove` through the `Behavior`s the tree already carries.

**Orientation changes cost more, and the cost depends on §9 Q2.** If the vertical dock is a second
module gated in the panel family (the bar's shape, `ImmaterialImpulseFamily.qml:32/54`), a
horizontal↔vertical change destroys one content tree and builds another: the compositor's slide
carries the surface, but the contents genuinely do disappear and reappear. If it is one tree with a
`vertical` flag (`DocktoPanel`'s shape), nothing is destroyed and the icons reflow — closer to the
initiative's spirit, at the cost of one denser file. That is the strongest argument for the
one-tree route, and it is why the question is in §9 rather than decided here.

## 6. Testing

**Reachable, and therefore where the value is.**

- `tests/tst_dock_geometry.qml` — a `TestCase` in the shape of `tst_bar_geometry.qml`: save
  `Config.options.dock.edge` in `initTestCase`, restore in `cleanupTestCase`, and drive
  `dock_geometry.js` across all four edges. Assert anchors, thickness, exclusive zone, and that
  `inwardInset`/`outwardInset` genuinely swap sides between `"bottom"` and `"top"` rather than
  merely differing. Include the unknown-edge case returning the default rather than a guess, the
  rule `tst_media_geometry.qml` established. Assert the measured baseline explicitly: at defaults,
  `exclusiveZone("bottom") === 65`.
- `tests/test_dock_position_contract.py` — a source contract in the shape of `test_dock_motion.py`:
  no literal `anchors { bottom: true` left in `Dock.qml`; `DockContextMenu` and `DragApps` derive
  their popup `gravity` rather than naming `Edges.Top`; `DockIconMotion` exposes an axis input and
  no bare `Translate { y:` remains; every one of `Dock.qml`, `DockSeparator.qml`, `DockButton.qml`,
  `DockAppButton.qml` reads its insets from `dock_geometry.js` rather than spelling
  `elevationMargin`/`hyprlandGapsOut` out. Prove it fails by planting each violation — in a clean
  tree, per CONTRIBUTING's plant-and-revert warning.
- `tests/lint_dock_edge_derivation.py` — one derivation only, the direct analogue of
  `lint_bar_popup_overlay_static.py:82-94`'s rule for `barEdge`. Fails on a second file computing
  the dock's edge from anything but `Config.options.dock.edge`.
- `tests/tst_config.qml` — extend the existing dock block for the new key's default.
- Every one of the above must be added to `tests/run_tests.sh` as its own block. Discovery is
  automatic only for `tst_*.qml`; the Python layer is a hand-maintained sequential list, and three
  modules have already shipped inert for exactly this reason.

**Reachable only partly.** A runtime harness (`DockEdgeRuntimeTest.qml` at the repo root, driven by
`tests/test_dock_edge_runtime.py` in the shape of `test_widget_resize_motion_runtime.py`) can build
the dock's *content* tree on all four edges and assert it lays out. It cannot say anything about the
surface: weston gives no wlr-layer-shell (AGENT.md, `2c8ccae70`), so anchors, exclusive zone and the
compositor's slide are all invisible to it. Say so in the harness's docstring rather than letting a
green run imply more than it checked.

**Not reachable, and must not be faked.** How any of it looks; the compositor's inferred slide
direction; and the bar/dock same-edge arbitration in §3. Those are a live look plus a readback:
`hyprctl layers -j` for surface geometry and `hyprctl monitors -j` for `reserved`, against the
baseline table recorded above. Note that the QML suite stays fully green for a `Dock.qml` that fails
to compile — confirm `Configuration Loaded` and grep `ERROR:` after the live load, not just `WARN`.

## 7. Landing plan

Each step leaves the tree working and is separately reviewable on screen.

1. **`dock_geometry.js` plus `tst_dock_geometry.qml`. No caller.** Pure arithmetic for four edges,
   including the measured `exclusiveZone("bottom") === 65`. *Test: the new `tst_*.qml`, registered
   automatically.*
2. **`Dock.qml` reads its current geometry from the module, still hardcoded to `"bottom"`.**
   Nothing changes on screen; the four hand-spelled inset pairs in `Dock.qml`, `DockSeparator.qml`,
   `DockButton.qml` and `DockAppButton.qml` become reads. This is the step where the dynamic-scope
   coupling (§1) can bite silently, so verify live and watch for NaN geometry. *Test:
   `test_dock_position_contract.py`, first half.*
3. **`Config.options.dock.edge` + `defaults/config.json` + the settings row.** Wired to nothing
   yet. *Test: `tst_config.qml` default; `test_dock_position_contract.py` asserts the row exists in
   the Dock section and writes the string directly.*
4. **The opposite-edge mirror: `"top"` works.** Anchors, reveal push, inset swap, dot anchor,
   motion sign, popup gravity — expressed as states in the style of `Bar.qml:303-321`. *Test:
   contract test for the derived gravity and the absent literal anchors; live look at both edges.*
5. **`rules.lua:147` becomes a bare `animation = "slide"`.** One line; verify the slide follows the
   edge for both `"bottom"` and `"top"` before any vertical work exists to confuse the result.
6. **`lint_dock_edge_derivation.py`.** Lands before the vertical work, so the second layout cannot
   introduce a second derivation. *Test: it is the test; prove it fails on a planted second
   derivation.*
7. **The vertical layout: icon strip only.** Column flow, cross-axis icon sizing, dots beside the
   icon, y-axis drag reorder — ported from `DocktoPanel.qml:213,267-268,290,302,355-363,388-395`
   rather than reinvented. Media tile hidden at vertical edges for this step regardless of Q1's
   answer, so the step is reviewable alone. *Test: extend `tst_dock_geometry.qml` to the vertical
   anchors and thickness; the runtime harness builds the column.*
8. **The media tile's vertical answer**, whatever Q1 settles on. Separate commit; it is the only
   genuinely new design in the series.
9. **The bar/dock same-edge guard**, per Q3, after §3's measurement. Separate commit because it is
   the only one whose correctness is established by `hyprctl` readback rather than by a test.

Steps 2 and 7 are the ones that can go quietly wrong: step 2 because a broken dynamic lookup
produces `undefined` rather than an error, step 7 because a vertical layout that lays out and looks
plausible can still have the drag reorder inert.

## 8. Risks worth naming before building

- **The dynamic-scope coupling in `DockSeparator.qml:7-8` and `DockAppButton.qml:37-41`** resolves
  `dockRow` and `dockVisualBackground` by name through the dock's tree. A restructure that renames
  or reparents either produces `undefined` → NaN geometry, which in this codebase is a relayout that
  never converges and a pegged core, not a visible error.
- **`DocktoPanel.qml` shares `Config.options.dock.pinnedApps` and `dock.monochromeIcons`.** Any
  change to those keys' meaning, or to `DragApps`' reorder contract, lands in a bar widget too.
  `DocktoPanel`'s own placement follows the *bar* and must keep doing so — it must not start reading
  `dock.edge`.
- **Two reveal slivers on one edge** (§3) is the failure mode most likely to reach a user, because
  it needs no unusual configuration: a bottom bar with auto-hide plus the shipped dock defaults
  (`defaults/config.json:486-503` has `enable: true`, `pinnedOnStartup: true`).
- **A green suite says nothing about whether the dock loads.** `qmltestrunner` never builds these
  widgets; a `FINAL` override or a missing `import qs.modules.common` passes every test and takes
  down every panel that reaches it.
- **The `elevationMargin`/`hyprlandGapsOut` asymmetry is load-bearing for the blur region.**
  `Dock.qml:66-70` publishes a region over `dockVisualBackground`, whose margins are that pair. A
  region over an unpainted rect frosts bare wallpaper, and `lint_blur_region_pairing.py` pins the
  region to the layer rule but cannot see whether it is over the right rect.

## 9. Open questions for the user

These are not rhetorical. Four of them change what gets built.

1. **Does the vertical dock carry the media tile at all?** `DockMedia.qml` is a 240x60 card and
   there is no rotation of it that works in a 60px column. Three options, none of them derivable
   from the code: (a) hide it at vertical edges, the way the vertical bar simply omits widgets that
   do not fit — cheapest, and step 7 does this regardless; (b) an art-only square tile that expands
   to transport controls on hover — a genuinely new component; (c) a stacked column of art, a
   marquee title and a transport row, which needs the dock's thickness to grow well past 60px at
   vertical edges. **Recommendation: (a) for the first landing, and treat (b) as its own spec.**
2. **One tree with a `vertical` flag, or two modules?** The bar chose two
   (`ImmaterialImpulseFamily.qml:32/54`); `DocktoPanel.qml` does the same job in one. One tree
   preserves icon and launch state across an orientation change and is closer to the M3E direction
   (§5); two files are more readable and match the bar exactly. **Recommendation: one tree**, on
   `DocktoPanel`'s evidence — but "just like the bar" could reasonably be read as mandating two.
3. **Same edge as an auto-hiding bar: offset, or refuse?** §3 argues the dock should give and offset
   its reveal sliver inboard of the bar's. The alternative is refusing the combination in the
   settings UI. Offsetting keeps a valid arrangement working; refusing is simpler and cannot be got
   subtly wrong. **No recommendation** — this is a product call about whether the shell may decline
   a configuration.
4. **Should the dock gain a `screenList` while this work is open?** It currently appears on every
   monitor (`Dock.qml:20`) where the bar is filterable (`Config.qml:1033`). Related, adjacent,
   and not required by the position work. Default answer: **no, separate change.**
5. **Is a new `dock.edge` string acceptable, or is literal parity with `bar.bottom` + `bar.vertical`
   wanted?** §2 argues for the string on migration grounds that genuinely do not apply to a new key.
   Literal parity would mean reproducing an overloaded boolean and a bitfield for consistency's
   sake. **Recommendation: the string.**
6. **Should the dock's position row also appear in `QuickConfig.qml` and `welcome.qml`?** The bar's
   is in all three, each open-coding the bitfield. **Recommendation: no** — one row, in the Dock
   section — but if the intent is that the two positions feel like one setting, they should probably
   sit together in all three places.
7. **`dock.height` / `dock.hoverRegionHeight` keep their names and mean "thickness" on both axes.**
   §2 declines to rename them because of the preset problem. If a rename is wanted anyway, it needs
   its own migration covering the preset files, and it should be its own commit.
