# Edit Mode — design

**Status:** design, not implemented. §11 holds nine questions; four of them change the shape of the
work rather than a detail of it.
**Scope:** `GlobalStates.qml`, `modules/imi/desktopMenu/`, `modules/imi/background/`,
`modules/common/widgets/widgetCanvas/`, `modules/common/plugins/`, `modules/imi/bar/`,
`modules/imi/verticalBar/`, `modules/imi/dock/`, `modules/imi/lock/`,
`modules/common/panels/lock/`, `modules/common/widgets/`, `modules/imi/settings/pages/BarConfig.qml`,
and `tests/`.

Paths are relative to `dots/.config/quickshell/imi/` unless written repo-relative, per AGENT.md's
layout note.

---

## Problem

Four surfaces carry a layout the user is entitled to arrange, and each of them is arranged somewhere
else.

The desktop widgets are arranged **on the desktop**, by dragging them — and that editor is already
good: a hand-computed drag (`AbstractWidget.qml:95-135`), a 12px snap lattice (`:142-144`), a
marquee and a group drag (`WidgetCanvas.qml:33-206`), a resize grip that accumulates tension
(`PluginWidget.qml:709-799`), an alignment grid and snap lines that appear while you drag
(`WidgetCanvas.qml:224-284`, `:303-331`). None of it is discoverable. Every affordance is
hover-revealed or press-revealed, the global lock is a switch buried two hovers deep in a context
menu submenu (`WidgetsSubmenu.qml:32-38`), and the one thing that reliably tells a user the desktop
is editable — the grid — only appears once they have already started dragging.

The bar is arranged **in Settings**, as chips: `LayoutSection.qml` renders each widget id as a
removable chip in a `Flow` and reorders by 2-D nearest-centre drag (`:51-85`), with a `+` dropdown
to add (`:152-218`). It is a competent editor of a list of strings. It is not an editor of a bar:
you cannot see what you are arranging while you arrange it.

The dock is arranged **on the dock**, by dragging its icons (`DragApps.qml:319-378`) — with no
settings equivalent at all, and no way to discover that the drag exists.

The lock screen is not arranged. `LockSurface.qml` is three hand-anchored islands
(`:105-111`, `:237-245`, `:464-472`) and eleven booleans in `Config.options.lock`
(`Config.qml:1203-1222`), every one of which is a visibility switch on a fixed position.

So the request is not "add a layout editor". Three of the four already have one. The request is for
a **mode**: a moment when every one of these surfaces is editable at once, in place, with its
affordances shown rather than hidden, with one way in and one way out, and with nothing else
happening by accident.

Two facts set the size of the work, and both are good news.

**First, this shell has already built an edit mode, and it works.** The Android quick-toggle panel
has `editMode` (`AndroidQuickPanel.qml:13`), toggled from a button beside Settings and Session
(`SidebarRightContent.qml:242-250`), and in that mode the panel grows a tray of unused toggles
below a divider (`AndroidQuickPanel.qml:186-232`), a delete badge and a drag-resize badge on every
tile (`AndroidQuickToggleButton.qml:266-307`, `:309-366`), a drag-to-reorder with a live drop
indicator (`:154-252`, `AndroidQuickPanel.qml:158-183`), and one inline `ConfigSpinBox` for the
column count (`:234-247`). It writes straight through to
`Config.options.sidebar.quickToggles.android.toggles` with no save step, and its whole interaction
vocabulary is stated in one tooltip: "LMB to enable/disable / RMB to toggle size / Scroll to swap
position" (`SidebarRightContent.qml:248`). Every structural decision this document has to make has a
worked precedent inside that one file.

**Second, the lock screen is already half desktop.** `LockSurface.qml` has no clock. The lock
screen's clock is the `clock` desktop-widget plugin, drawn by the ordinary background layer surface,
which raises itself from `Bottom` to `Overlay` while locked (`Background.qml:540`) under a
`WlSessionLockSurface` whose colour is `"transparent"` (`LockScreen.qml:20`). Other desktop widgets
join it when `lock.showWidgets` is on (`AbstractBackgroundWidget.qml:18`,
`PluginWidget.qml:29-33`). So "the lock screen's layout" is not a fifth model — it is the desktop
widget layout under a different visibility filter, plus three toolbars nobody can move.

---

## 1. The four models, and what they have in common

### 1.1 Measured

| | desktop widgets | bar | dock | lock |
| --- | --- | --- | --- | --- |
| geometry | free 2-D placement, 12px snap | ordered list, three buckets | ordered list, one strip | three anchored islands |
| size | span from a fixed set (`__gridSize`) | intrinsic | intrinsic | intrinsic |
| store | `plugin-state.json` (raw `FileView`) | `Config.options.bar.layouts.*` | `Config.options.dock.pinnedApps` | nothing |
| per monitor? | **yes** (`desktopPositions[screen][id]`) | no (one `screenList` allow-list) | no (every screen, `Dock.qml:30-31`) | n/a |
| direct manipulation today | yes | no | yes | no |
| catalogue of what can be added | `PluginManager.availablePlugins` | a hardcoded array in a settings page | `DesktopEntries` | fixed |
| write timing | on release, 100ms debounce | on drop, 50ms debounce | on release, 50ms debounce | n/a |

Citations for the row that matters most: `PluginState.qml:18-31` (schema), `:63-75` (`setPosition`),
`:349-353` (the 100ms write timer); `Config.qml:1027-1030` (the three bar arrays);
`Config.qml:1149-1150` (`pinnedApps`); `Config.qml:1203-1222` (the lock's eleven booleans).

Three things fall out of that table.

**(a) There is no shared geometry, so there can be no shared canvas.** A 2-D free placement and a
1-D ordered list do not have a common editor. Anything that claims to be one is really two editors
with a shared border.

**(b) There is a shared *store discipline*, and it is already "write through on release".** No
surface in this shell has a save step. `commitPosition()` writes on release
(`PluginWidget.qml:575-594`); `LayoutSection` writes on drop (`:71-85`); `DragApps.commitOrder`
writes on release (`:76-80`); the quick-toggle edit mode writes on every click
(`AndroidQuickToggleButton.qml:258-263`, `:300-305`). §4 argues that Edit Mode must not be the first
thing to introduce a transaction.

**(c) The reorder gesture has been written three times already and does not agree with itself.**
`LayoutSection.qml:51-69` is 2-D euclidean nearest-centre over a `Flow`, committing with a
`splice`-out-`splice`-in. `DragApps.qml:341-377` projects onto one axis chosen by the dock's edge
and commits with an **adjacent swap** (`swapSlots`, `:65-74`). `DocktoPanel.qml:290,302` is a third
copy of the second. The quick-toggle panel's is a fourth
(`AndroidQuickToggleButton.qml:183-223`), and it swaps rather than moves too. A fifth copy written
for Edit Mode is exactly the failure AGENT.md's `CavaService` entry describes — "two names for one
thing let one of them rot silently" — so §7 makes the shared reorder module a *prerequisite*, not
a nice-to-have.

### 1.2 One surface, four modes, or something else — the central choice

**Option A — one editing surface.** A single screen-map editor: a window (or a full-screen overlay)
showing a miniature of the monitor with the bar, dock, widgets and lock islands as draggable
proxies. This is what "one editing surface from the start" reads like on first hearing, and it is
the wrong answer here for three separate reasons, each of which is a rule this repo already
enforces.

- **A miniature is a second renderer, and the second renderer rots.** The bar and dock are layer
  surfaces whose position *is* `anchors` and `margins` and whose thickness comes from
  `DockGeometry.thickness()` and `Appearance.sizes.bar*`; the desktop widgets' frost is a
  `ShaderEffectSource` `sourceRect` over a shared wallpaper decode, aligned by
  `ParallaxMath.sampleOrigin` (`PluginWidget.qml:62-64`). None of that survives being redrawn at
  1:8 in a proxy. What the user would arrange is a picture of the shell, and every divergence
  between the picture and the shell is invisible until it ships. This is the same shape as the
  `PluginValidator.js` whitelist and the `PluginNode.qml` renderer `switch` drifting apart.
- **The desktop editor already exists and is good.** Replacing direct manipulation of real widgets
  with dragging rectangles in a miniature is a downgrade for the one surface that is already
  finished.
- **It becomes a second Settings.** A window with everything in it grows rows. The boundary in §6
  is much easier to hold when the editor is physically on the thing being edited: there is nowhere
  to put an unrelated toggle.

**Option B — four modes sharing an entry point.** The desktop menu's Edit row opens a picker: edit
the desktop, the bar, the dock or the lock screen. Rejected because the picker is a question the
user cannot answer before seeing the answer, and because four modes means four exits, four undo
stacks, four "am I editing?" predicates, and — by §1.1(c)'s precedent — four reorder gestures.

**Option C — one mode, one arbiter, four in-place editors. Recommended.**

There is exactly one boolean, `GlobalStates.editMode`. Every surface observes it and shows its own
affordances in its own geometry, in place, on the real thing. What is genuinely shared is not a
canvas but four things that must be shared or they will drift:

1. **The mode itself** — one predicate, one entry, one exit ladder, one set of things that force it
   off (§5).
2. **The chrome surface** — one always-mapped full-screen layer surface per screen carrying the
   scrim, the toolbar, drop indicators and drag proxies, on `BarPopupOverlay.qml`'s pattern (§7.3).
   This is the honest meaning of "one editing surface": one surface, four geometries drawn on it.
3. **The reorder gesture and its arithmetic** — one `.js` module, one gesture component (§7.2).
4. **The mutation log** — one undo stack across all four stores, because a user who moved a widget
   and then a bar chip expects one Ctrl+Z to mean the last thing they did (§4.3).

The rest is per surface, because the geometry is per surface. Option C is what the quick-toggle
panel already does at the scale of one panel, and it is the only option under which the lock screen
(§3) is a variation rather than a special case.

---

## 2. What "editing" means, per surface

The governing rule, which §6 turns into a check: **Edit Mode changes where a thing is, how big it
is, what order it is in, and whether it is present on that surface. It changes nothing else.**

### 2.1 The desktop — mostly subtraction

Almost nothing new is needed. What Edit Mode does is stop hiding what is already there:

| today | in Edit Mode |
| --- | --- |
| the alignment grid appears only mid-drag (`WidgetCanvas.qml:211-217`) | it is on for the whole mode |
| the resize grip fades in on hover (`PluginWidget.qml:709-799`) | every resizable widget shows its grip |
| the global lock is a submenu switch (`WidgetsSubmenu.qml:32-38`) | the mode suppresses it (see below) |
| right-click on a widget toggles the global lock (`AbstractWidget.qml:85-89`) | right-click is a per-widget menu (Remove, Size, Pin) |
| adding a widget means opening Settings › Widgets | an add affordance on the chrome, from `PluginManager.availablePlugins` |

**The global lock is suppressed, not written.** `interactionLocked` is
`clickThrough || positionLocked || Config.options.background.widgetsLocked`
(`AbstractBackgroundWidget.qml:54-55`), and Edit Mode subtracts the third term only. The per-widget
`positionLocked` pin survives, which preserves the invariant AGENT.md records for that OR belt —
"'Lock widget positions' must never *unlock* something the user deliberately pinned, in either
direction" (`AbstractBackgroundWidget.qml:37-40`). Writing `widgetsLocked = false` on entry instead
would silently destroy a stored preference and leave the desktop unlocked after the mode ended; a
mode that changes a setting as a side effect of being entered is exactly the class of bug the
`ConfigSpinBox` write-back trap is about.

Note the discrepancy Edit Mode makes visible: the drawn grid is 24px
(`WidgetCanvas.qml:7`, `:224-244`) while the snap lattice is 12px (`AbstractWidget.qml:24`, and
`docs/widget-grid.md:294-310`). While the grid was only up for the duration of a drag this read as
decoration; with the grid up for the whole mode a widget landing between two lines reads as broken
snapping. §11 Q3.

### 2.2 The bar — direct manipulation, and the catalogue it needs first

In Edit Mode the bar stops auto-hiding, its widgets stop responding to their own clicks, each grows
a remove badge, and dragging one moves it within its bucket or across into another. The three
buckets get visible boundaries — which is the one thing the chip editor genuinely does better than
the bar itself, because in the real bar `middleLayout` being empty is indistinguishable from
`middleLayout` being invisible.

Two prerequisites, both real:

**The widget catalogue must exist somewhere the bar can read it.** Today it is a hardcoded array of
21 entries inside a settings page (`BarConfig.qml:49-71`), concatenated with plugin bar widgets
derived at `:41-47`. The bar itself has no catalogue at all: `BarContent.getWidgetUrl(name)`
capitalises the id and resolves a filename (`:65-76`). An add affordance in Edit Mode would be a
third list. It gets promoted to `BarWidgets.qml` (a singleton beside `PluginManager`, exposing
`available` and `nameFor(id)`) exactly as `FilterChip` and `surfaceCapabilities` were promoted out
of `PluginStorePage` by the widgets-page spec — a move, not a redesign.

**`VerticalBarContent.getWidgetUrl` does not handle the `plugin:` prefix.**
`VerticalBarContent.qml:62-66` resolves `"../bar/" + Capitalise(name) + ".qml"` with no branch for
`plugin:`, so a plugin bar widget in a vertical bar resolves to
`../bar/Plugin:docker_plugin.qml`. This is latent today (you have to add a plugin widget while the
bar is vertical) and Edit Mode makes it one drag away. It is a bug to fix in its own commit before
the bar stage lands, not something for Edit Mode to route around.

### 2.3 The dock — the smallest one

The dock's drag already does the right thing (`DragApps.qml:319-378`) including choosing its axis
once from the edge (`alongAxis`, `:341-343`). Edit Mode adds a remove badge per icon, an add
affordance, and — the only new geometry — visibility for the *edge*, since `dock.edge` is the one
piece of dock layout that is not an ordering (`Config.qml:1136-1146`, settings row at
`BarConfig.qml:688-724`). Whether the edge is draggable in Edit Mode or stays a settings row is
§11 Q4; the argued default is that it stays a row, because moving a layer surface between edges is
a re-map rather than a journey (the dock-position spec, §5) and a drag whose target cannot follow
the pointer is a worse affordance than a button.

One trap inherited: `DockSeparator.qml:7-8` and `DockAppButton.qml:37-41` reach `dockRow.padding`
and `dockVisualBackground.margin` by QML dynamic scope. Edit-mode chrome that reparents anything in
the dock's tree breaks both with `undefined` → NaN geometry and no error.

### 2.4 The lock screen — §3

---

## 3. Editing a lock screen without being locked

### 3.1 What the lock screen actually is

Composed of two surfaces, not one:

- **The background layer surface**, promoted to `WlrLayer.Overlay` while locked
  (`Background.qml:540`), carrying the lock wallpaper (`:252`, `:265`), the lock blur
  (`:511`, `:917-940`), the clock plugin (which sets its own `wantsVisibleWhenLocked` and takes
  `lock.centerClock`, `bundled/clock/Widget.qml:37-40`), and every other desktop widget when
  `lock.showWidgets` is on.
- **`WlSessionLockSurface`**, `color: "transparent"` (`LockScreen.qml:20`), carrying a `Loader`
  gated on `GlobalStates.screenLocked` (`:21`) whose content is `LockSurface.qml`: three `Toolbar`
  islands anchored to each other, main bottom-centre (`:107-111`), left and right hung off its edges
  (`:240-245`, `:467-472`).

So **half the lock screen's layout is the desktop's layout**, already stored per monitor in
`plugin-state.json`, already editable. The genuinely un-editable half is three islands and their
contents.

### 3.2 Why you cannot just lock

The obvious approach — enter Edit Mode, lock the screen, disable authentication — fails on
`LockContext`: constructing one arms PAM and `fprintd-list` (`LockContext.qml:92`), and
`LockSurface` calls `forceFieldFocus()` from `Component.onCompleted`, `onPressed`,
`onPositionChanged`, `Keys.onPressed` and `Keys.onReleased` (`:38-43`, `:60-61`, `:76`, `:82`). A
lock screen you can edit is a lock screen with its lock switched off, which is a security surface
whose defining property has been made conditional. Not acceptable at any price.

### 3.3 The three ways to render it unlocked, and the recommendation

**(a) Instantiate `LockSurface` in a normal window.** Attractive because `LockScreen.qml` already
takes the content as a `Component` (`:15`, `:20-28`) — the tree is not welded to
`WlSessionLockSurface`, only its one instantiation site is. Three blockers, all fixable:
`required property LockContext context` (`LockSurface.qml:18`) means a preview must construct a
context, and constructing one starts PAM; the focus-grabbing above; and the media/tray children
(`:258-422`, `:453-460`) are live, which is correct for a preview and wrong for a *layout* preview
of a media player that is not playing.

**(b) Render the real thing on the real surfaces, in a "locked preview" state.** Set the same
inputs the lock sets — the background surface takes its lock wallpaper, blur and widget filter — and
draw the three islands from a **preview host** that instantiates `LockSurface` with a context that
cannot authenticate. This is (a) plus the observation that the background half needs no proxy at all
because it is the surface that already draws it.

**(c) A static mock of the islands.** A second renderer. Rejected on §1.2's first argument.

**Recommended: (b), with the auth surface neutered by construction rather than by a flag.**
Concretely:

- `LockSurface` gains `property bool interactive: true`. When false: `forceFieldFocus()` returns
  immediately, the password field is `enabled: false` and `readOnly`, and the three power actions
  (`:484-500`, and `PasswordGuardedIconToolbarButton` at `:503-521`) do not connect. A preview that
  can neither take a keystroke nor dispatch a session action cannot be an attack surface, and the
  property is a single grep target for a lint.
- A `LockPreviewContext` — a `LockContext` subtype (or, better, a second `Component` satisfying the
  same property surface) whose `tryUnlock` and `tryFingerUnlock` are empty and which never
  constructs the PAM object. This is the piece that must be reviewed most carefully, because "the
  preview context is the real one with a flag" is how a preview ends up authenticating.
- The preview is hosted on the edit chrome surface (§7.3), not on a new window, so it inherits the
  mode's exit ladder for free.

**What can be edited there:** the order and presence of the items inside each island, and the
islands' visibility (`lock.showToolbars`, `lock.showMedia`, which exist today as booleans at
`Config.qml:1207-1208`). What *cannot*, without new storage: the islands' positions, since there is
no key for them — `LockSurface`'s anchors are literals.

### 3.4 The constraint that must be stated, not discovered

**A widget has one position, and the lock screen shows it at that position.** `desktopPositions` is
keyed `[screenName][pluginId]` and holds `{x, y, placementStrategy}` (`PluginState.qml:18-31`,
`:45-55`) — there is no locked variant. So arranging widgets "for the lock screen" arranges them
for the desktop too. `lock.centerClock` is the one existing exception and it is a per-widget
override applied at render (`bundled/clock/Widget.qml:37-40`), not a second stored position.

Two options, and this is a decision rather than a detail (§11 Q1):

- **Accept it.** The lock context of Edit Mode edits *which* widgets appear while locked
  (`lock.showWidgets` today is one global switch; a per-widget `__lockVisible` under the reserved
  `__` prefix would make it per widget) and the islands. Positions stay shared. Cheap, honest,
  and the shipped behaviour is already this.
- **Add a second position.** `desktopPositions[screen][id].lock = {x, y}`, falling back to the
  desktop position when absent. This is a `plugin-state.json` schema change — `schemaVersion` is 2
  (`PluginState.qml:13`) and `loadText` re-validates every top-level key (`:298-341`), so it is
  tractable — but it doubles the placement model, and `scripts/presets.sh` captures
  `desktopPositions` wholesale (`:50-72`) so every preset gains the second position silently.

**Recommendation: accept it for the first landing.** A second position is a store change wearing a
layout feature's clothes, and AGENT.md's rule about two fields that must agree eventually
disagreeing applies directly.

---

## 4. State and persistence

### 4.1 What is mutated

| store | keys Edit Mode writes | mechanism |
| --- | --- | --- |
| `plugin-state.json` | `desktopPositions[screen][id]`, `pluginOptions[id].__gridSize` | `PluginState.setPosition` / `.setOption`, 100ms debounce (`:349-353`) |
| `config.json` | `bar.layouts.{left,middle,right}Layout`, `dock.pinnedApps`, `plugins.enabled`, `lock.show*` | `JsonAdapter` write-back, 50ms debounce (`Config.readWriteDelay`) |
| nothing | the mode itself, the selection, the undo stack | `GlobalStates`, in memory |

**`GlobalStates.editMode`, not `Config.options.*.editMode`.** AGENT.md is explicit: ephemeral UI
state goes in `GlobalStates` and persisted settings go in `Config`, and this is the former. A
persisted edit mode is a shell that comes back from a restart with the scrim up and the bar inert.

**Nothing goes in `Persistent`.** `Persistent.states` holds session state that must survive a
restart (`night.temperatureActive`, `record.region`, the overlay widgets' geometry at
`Persistent.qml:100-168`). Edit Mode is not that.

### 4.2 Live application, no save/cancel

Edit Mode applies every change immediately and has no Save button and no Cancel button. The
argument is not taste, it is arithmetic:

- **A transaction would need three shadow stores.** The mutations span `plugin-state.json` (a raw
  `FileView` with its own debounce), `config.json` (a `JsonAdapter` that writes back on *any*
  property write) and, potentially, preset files. There is no transaction primitive here, and
  building one means a snapshot-and-restore across two write paths with different timings.
  `PluginState.snapshot()` / `replaceSnapshot()` (`:294-305`) exists and is exactly this for one of
  the three — which is what makes the shape of the missing two obvious.
- **`writeAdapter()` runs on essentially every launch and strips undeclared keys.** A staging area
  living anywhere in `config.json` would be destroyed by the first launch that did not know about
  it, and a staging area outside it is a fourth store.
- **Every existing editor in this shell writes through.** Introducing a save step in Edit Mode
  would mean a widget dragged on the desktop with the mode *off* commits instantly and the same
  drag with the mode *on* does not. Two behaviours for one gesture, decided by a mode the user may
  have forgotten they are in.
- **Live application is the feedback.** The point of editing in place is seeing the result; a
  preview that is not applied is a miniature by another name.

### 4.3 Undo instead of cancel

What a Cancel button is actually for is "I did not mean that". That is served better, and much more
cheaply, by an undo stack:

- **In memory, session-scoped, bounded** (say 50 entries), living on the mode.
- **One entry per committed mutation** — a drag's release, a span commit, a reorder drop, an add,
  a remove. Not per frame: the drag is already unclamped until release
  (`AbstractWidget.qml:196-214`, `PluginWidget.commitPosition`), so "committed" is a moment that
  already exists at every call site.
- **One stack across all four surfaces**, because the user's notion of "the last thing I did" does
  not partition by surface.
- **An entry is a closure over the store write, not a diff of the store.** `{ undo: fn, redo: fn }`
  captured at the call site. A diff would need a serialiser per store.
- **Ctrl+Z / Ctrl+Shift+Z, only while the mode is on**, which means the chrome surface must hold
  keyboard focus — see §7.3 and the risk in §10.

Whether undo ships in the first landing is §11 Q5; the recommendation is **no** — it is stage 10,
last, because it is the only piece whose absence is an inconvenience rather than a gap, and the only
one gated on an unknown (§10's keyboard-focus question).

### 4.4 A restart in the middle

Because the mode is `GlobalStates` and every mutation is already committed, a shell restart
mid-edit does exactly the right thing with no code: the mode is gone, every committed change is on
disk, and the undo stack (which only ever offered to reverse committed changes) is gone with it.
The only loss is a gesture in flight, which was never committed.

There is one thing to be careful of rather than to build: an edit session is exactly when a
hot-reload is most likely, since every `.qml` write reloads the whole configuration. "The mode did
not survive the reload" is correct behaviour, not a bug report — but a reload that lands mid-drag
must not be the only path through which the cancel-not-commit rule in §5.3 is exercised, so the
harness drives it deliberately.

### 4.5 Presets

`scripts/presets.sh` captures `desktopPositions` and `pluginOptions` into `._pluginState`
(`:50-72`) and merges on apply, honouring `presetPersist` ids (`:91-124`). Edit Mode changes what a
user's layout *is*, so applying a preset after editing overwrites it — which is what a preset is
for, and is already true. Edit Mode adds nothing here and must not: a "save this layout as a preset"
button inside Edit Mode is precisely the boundary violation §6 forbids.

---

## 5. Entering and leaving

### 5.1 Entry

One new row in the desktop context menu (`DesktopMenu.qml:225-366`), between **Widgets** and
**DropShelf**, in the shape of the rows already there:

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

No submenu and no chevron: unlike Wallpaper & style and Widgets, this row has no quick-settings
half and no Settings page behind it. It is a verb.

The menu already knows which monitor and which point it was opened at
(`GlobalStates.desktopMenuScreen/X/Y`, written by `Background.qml:1257-1261`), which is enough to
place the mode's toolbar on the screen the user was actually looking at. The mode itself is global —
all monitors show their chrome — because the bar and dock layouts are global and a per-monitor edit
mode would have to explain why moving a bar chip on monitor 2 changed monitor 1.

**Not proposed:** a keybind, a Settings button, or an entry in the quick-toggle panel. One entrance
until there is evidence a second is wanted (§11 Q6).

### 5.2 Exit, as a ladder

`Escape` is overloaded on the desktop already: `WidgetCanvas.qml:44` clears a marquee selection, and
`PluginWidget.qml:729-732` cancels a resize. Edit Mode must not take Escape away from either. So
Escape resolves in order, and the first match wins:

1. **A gesture is in flight** (a drag, a grip resize, a reorder) → cancel that gesture, restoring
   the pre-gesture state. The mode stays on.
2. **A selection exists** → clear it (`WidgetCanvas.clearSelection`). The mode stays on.
3. **Otherwise** → leave the mode.

This ladder is a pure function of three booleans and is the natural home for the first unit test
(§8.1).

Also exits:

- **The Done affordance** on the chrome toolbar. Unconditional: it also cancels an in-flight
  gesture and clears the selection, because a user pressing Done means "stop".
- **Anything that takes the screen away**: `GlobalStates.screenLocked` going true, the session
  screen opening, `GlobalStates.overviewOpen`. A mode whose chrome is a full-screen `Overlay`
  surface must not be alive underneath a lock screen.

Does **not** exit:

- **A click on empty desktop.** That is the marquee's press (`WidgetCanvas.qml:55-61`), and it is
  also the single most likely accidental click in the whole mode. Click-away is a dismissal
  gesture for popups, not for modes; the desktop menu uses it (`DesktopMenu.qml:150-154`) and Edit
  Mode must not, or every attempted marquee that starts and ends on empty canvas would end the
  session.
- **Opening Settings.** Settings is a `FloatingWindow`; leaving Edit Mode on behind it is harmless
  and closing it returns you to where you were.

### 5.3 A half-placed widget

There are two distinguishable states and they end differently.

**A drag in flight when the mode ends.** The drag is unclamped until release by design
(`AbstractWidget.qml:196-214`) and only `commitPosition()` clamps and writes. Ending the mode
mid-drag must run the **cancel** path, not the commit path: restore the pre-press position and the
x/y bindings (`restoreXYBinding()`, `PluginWidget.qml:562-567`). Committing instead would store an
unclamped overshoot, which is exactly the defect 705e9006d fixed — a real store held `visualizer`
at `x: -852` on a 5120px screen.

**A widget just added and not yet placed.** A newly enabled plugin lands at
`PluginState.defaultPosition()` — `{x: 100, y: 100}` — on *every* monitor
(`PluginState.qml:33-39`, `PluginWidget.qml:424-425`). There is no "unplaced" state in the store
and none should be invented: a widget with no position is a widget the next shell start cannot
draw. So an added widget is placed the moment it is added, at the pointer if the add came from a
drop, and leaving the mode changes nothing about it. The only thing Edit Mode owes it is that
adding from the chrome places it where the user dropped it rather than at `(100, 100)` behind
whatever is already there — which, given three widgets added in a row currently stack exactly on
top of each other, is worth doing in the same stage.

---

## 6. The boundary: what must not be reachable

**The rule:** Edit Mode may change *placement, order, span, and presence on a surface*. Everything
else is Settings.

The rule is not a matter of tidiness. Settings is reachable *from* Edit Mode in one click (the
desktop menu is still one right-click away, and a per-widget menu can carry an "Open settings…"
row that leaves the mode). Duplicating rows into the editor means every one of them is a second
call site for a config write, and this repo has already paid for exactly that: `ConfigSwitch`'s
binding bug reached 159 call sites, and the `activeStill` re-declaration re-armed six presets.

**Explicitly not reachable:**

| not in Edit Mode | where it lives |
| --- | --- |
| a widget's own options (its manifest `options`) | Settings › Widgets → `PluginOptions.qml:95-98` |
| the host's "Widget behaviour" rows — blur, keep-translucent, follow-parallax, preset-persist | `PluginOptions.qml:36-73`, `:103-129` |
| wallpaper, colour scheme, transparency, frost mode | Settings, and the desktop menu's Wallpaper & style |
| bar auto-hide, bar style, borderless, screen list | `BarConfig.qml` |
| dock auto-hide, icon size, monochrome icons | `BarConfig.qml:676-775` |
| lock security, keyring, blur radius, fonts | `LockIdleConfig.qml` |
| installing or uninstalling a plugin | `PluginsPage.qml:161-197`, `:418-449` |
| saving or applying a preset | the preset UI |
| anything about Hyprland | Settings › Hyprland |

**Two deliberate edge cases**, both of which look like violations and are not:

- **`positionLocked` and `clickThrough`** are also "Widget behaviour" rows
  (`PluginOptions.qml:36-73`) but they are *about* placement — a pin is a placement decision — so a
  per-widget Pin toggle in Edit Mode's context menu is in scope. It writes the same
  `PluginState.setOption(id, "positionLocked", ...)` the settings row does, so there is one writer
  and two call sites, not two meanings.
- **`lock.showWidgets` / `lock.showToolbars` / `lock.showMedia`** are presence-on-a-surface, which
  the rule admits. They stay in `LockIdleConfig.qml` as well.

**The mechanism that holds it.** A rule written only in this document is a rule that lasts until
the second contributor. `tests/lint_edit_mode_scope.py` reads every file under the edit-mode
chrome directory and fails on a write to any `Config.options.*` path outside an allowlist of
placement keys, and on any `PluginState.setOption` whose key is not in
`{__gridSize, positionLocked, clickThrough}`. The allowlist is the spec; the lint is the receipt.

---

## 7. Interaction and motion

### 7.1 Nothing new is invented

Every affordance Edit Mode draws is a control, and this codebase now enforces with a lint that a
control's hover and press motion comes from one place:

- Buttons on the chrome (Done, Add, per-widget remove) are `RippleButton`s, which drive
  `InteractionMotion` and apply its `scale`. Anything writing its own
  `scale: pressed ? 0.9 : (hovered ? 1.1 : 1)` inside one multiplies rather than replaces —
  `lint_interaction_motion_double.py` fails the suite on a scale-family property written from a raw
  hover/press flag inside a control that applies the model.
- Feedback that is not a multiple of anything reads `hoverProgress` / `pressProgress`, per the same
  lint's docstring.
- Durations and curves come from `Appearance.animation.*` and the five tiers in
  `modules/common/interaction_motion.js` (`stateOf`, `targetsFor`, and the transition table), with
  the numbers in `Appearance.qml:341-379` — `hoverScale 1.02`, `pressScale 0.97`,
  `pressRadiusScale 0.85`, `disabledOpacity 0.4`. `InteractionMotion.qml` writes the tier onto the
  animation *before* the target, in the same handler, and a chrome element that selects a duration
  through a binding on the animation would carry the *previous* transition.

The lint resolves which types apply the model rather than naming them, so this is not advice:
the moment any edit-mode component declares an `InteractionMotion` and applies its `scale`, every
descendant of it is subject to the rule automatically.

**The one place the lint cannot see, and it matters here.**
`AbstractBackgroundWidget.qml:30` is `scale: (draggable && containsPress) ? 1.05 : 1` — a raw press
scale on a `MouseArea`, not on an `InteractionMotion` control, so
`lint_interaction_motion_double.py` is blind to it by construction (its `DRIVES_MOTION` /
`APPLIES_MOTION_SCALE` pair requires both halves). Edit Mode gives every widget a visible handle,
and a handle that also scales on press would compose with that 1.05 exactly the way discordVoice's
glyphs composed with the model. **The lift while dragging belongs to `WidgetElevation`** — which
already owns the numbers, the hover/drag lift and the layer, is already driven by `hostDragging`
through the duck-typed path, and which `test_expressive_design_system.py` pins as the only file
allowed to read `Appearance.elevation`.

### 7.2 The shared reorder, which is a prerequisite

`modules/common/functions/layout_ops.js`, a `.pragma library`, owning the arithmetic the four
existing copies each spell differently:

| function | meaning |
| --- | --- |
| `indexAt(centres, point, axis)` | nearest slot along one axis, or 2-D when `axis` is null |
| `move(list, from, to)` | splice-out/splice-in — **the move semantics, not the swap** |
| `insert(list, id, at)` / `remove(list, at)` | add and remove |
| `dropTarget(buckets, centres, point)` | which bucket and which index, for the bar's three arrays |

`move` rather than `swap` is a behaviour change for the dock and the quick toggles, both of which
swap today (`DragApps.qml:65-74`, `AndroidQuickToggleButton.qml:216-220`). A swap is wrong for a
drag that crosses more than one neighbour: dragging an icon three places left in a swap
implementation displaces exactly one other icon rather than shifting three. This is worth doing and
it is worth doing in **its own commit, before Edit Mode**, so that a behaviour change on the live
dock is reviewable on its own and not as a side effect of a new feature.

The gesture itself becomes one component (`ReorderDragArea.qml`) exposing `dropIndex` and a drop
indicator, in the shape of `LayoutSection.qml:87-149` and `AndroidQuickPanel.qml:158-183`. It does
not own the commit; each surface commits to its own store.

### 7.3 Where the chrome lives

**One always-mapped full-screen `WlrLayer.Overlay` surface per screen**, on
`BarPopupOverlay.qml`'s pattern, carrying the toolbar, drop indicators, drag proxies, the lock
preview and — if §11 Q7 lands one — the scrim. The four properties that make that pattern safe apply
unchanged and are not optional:

1. **Geometry is a constant of the screen.** All four edges anchored, no `margins`, no
   implicit size. On a layer surface position *is* `margins`, and a toolbar animating into place
   would reconfigure the surface every frame.
2. **The mask tracks an item's x/y/width/height and nothing else** — `PendingRegion::setItem`
   connects exactly those four signals — so the chrome's motion is expressed as geometry, never as
   `scale`, `rotation` or `opacity`.
3. **Collapse the mask to 0x0 when the mode is off**, which is what makes a permanently-mapped
   full-screen `Overlay` surface harmless: `build()` on a 0x0 item yields an empty region and
   `onPolished` then sets `Qt::WindowTransparentForInput`.
4. **Reuse a namespace whose `ignore_alpha` suits the body being painted.** A new namespace falls
   through the catch-all `0.05`, under which a full-screen surface's transparent pixels clear the
   threshold and the compositor is asked to blur the whole screen. The scrim is the awkward part
   here — it is a large, deliberately translucent rectangle — and §11 Q7 asks whether there is a
   scrim at all.

**Anything on the chrome that resizes morphs in one tree.** The toolbar changes width when its
contents change — a per-widget menu appearing, an add tray opening — and this repo's rule for that,
enforced by `test_expressive_design_system.py`, is that a size mode "may decide where an element
sits, never whether it exists": a mode name may not reach a `sourceComponent:` or a `visible:`
binding, though `opacity` is explicitly allowed. The same file pins that geometry reads the
**settled** size rather than the animating box (a rect measured off `implicitWidth`, which carries a
`Behavior`, becomes a per-frame target and never converges), that the span animations have one
spelling (`SpanTravel` / `SpanFade` — there were twenty-three copies of that `NumberAnimation`
before), and that morphing containers share `shape_morph.js`. A per-state `Loader` swap on the
toolbar is exactly the snap those extractions exist to eliminate. A one-tree container also needs
`clipContent`: a faded block, unlike a destroyed one, keeps painting outside a shrinking card.

**The desktop's own chrome stays on the desktop.** Grips, halos and the grid are drawn where they
are drawn today, on the background surface, inside the widget canvas — moving them to the chrome
surface would put them in a different coordinate frame from the widgets they annotate, and the
parallax cancellation (`ParallaxMath.drawnFromPlacement`) is exactly that frame difference.

---

## 8. Testing

The suite's shape decides where the value is. `qmltestrunner` runs the JS: a `tst_*.qml` imports a
module by relative path (`import "../modules/common/interaction_motion.js" as Motion`) and the
runner discovers it by prefix from `-input tests/`. That is the **only** globbed discovery in the
whole suite — the ~130 Python and shell checks are a hand-maintained sequential list of
`if ! python3 "$SCRIPT_DIR/<file>"` blocks. Python never executes JavaScript; it reads source text.
And CI has no weston, no `qs` and no compositor, so **everything in §8.3 is a local gate only**.

(A note on the headline: "757 passing" is the `qmltestrunner` Totals line alone. The Python tier is
roughly twice that and is invisible in it. A change that keeps 757 green has said nothing about the
other tier.)

### 8.1 Pure logic, in `.js`, with `tst_*.qml` — where the value is

Three modules, all `.pragma library`, all reachable from `qmltestrunner`. The rationale is the one
`gridResize.js:5-9` already states about itself: everything else about a resize needs a real host
that `qmltestrunner` cannot construct, so **the arithmetic is the part a test can reach at all**.

- **`modules/common/functions/layout_ops.js`** → `tests/tst_layout_ops.qml`. `move` across more
  than one neighbour (the case a swap gets wrong, asserted as a full expected list rather than as
  "something changed"); `indexAt` on a single axis in a column, where the *other* axis's centres
  are all identical — the inert-comparison case `DragApps` shipped and `DockEdgeRuntimeTest` was
  built to catch; `dropTarget` returning a bucket **and** an index; an out-of-range index returning
  the list unchanged rather than a hole.
- **`modules/common/functions/edit_mode.js`** → `tests/tst_edit_mode.qml`. The exit ladder as a
  pure function: `resolveEscape({gestureInFlight, selectionCount})` → `"cancelGesture" |
  "clearSelection" | "exit"`, all three branches plus precedence (a gesture *and* a selection
  resolves to the gesture).
- **`modules/imi/lock/lock_islands.js`** (if §11 Q2 lands the island-content editor) → item order
  and presence per island, with an unknown item id resolving to the default position rather than
  disappearing — `gridSizes.resolveSize`'s rule applied to a different list.

Each `tst_*.qml` needs nothing registered: it reaches the module by relative path. A new
**singleton** does — `BarWidgets.qml` (stage 3) needs a symlink into `tests/imports/qs/...` and a
line in that directory's local `qmldir` before any test can see it, and a **full `qs` restart**
before the running shell can.

### 8.2 Source contracts, in Python

`tests/test_edit_mode_contract.py`, in the shape of `test_dock_position_contract.py`:

- **One predicate.** No file computes "am I editing" from anything but `GlobalStates.editMode` —
  the direct analogue of `lint_bar_popup_overlay_static.py:82-94`'s rule for `barEdge`, and of the
  dock's one-derivation rule. Four copies of a mode check is how three of them go stale.
- **The chrome surface is static.** No `margins`, no `implicitWidth`/`implicitHeight`, all four
  anchors — the same assertions `lint_bar_popup_overlay_static.py` already makes, pointed at the
  new file.
- **The mask collapses.** The chrome's mask item is 0x0 when the mode is off.
- **No second motion.** No scale-family property in the chrome bound to a raw hover/press flag, and
  no `MultiEffect` shadow reading `Appearance.elevation` outside `WidgetElevation.qml` (which
  `test_expressive_design_system.py` already enforces globally — the point of restating it here is
  that a new directory is exactly where an exception gets carved).
- **The exit ladder is wired to the module**, not open-coded in a `Keys.onEscapePressed`.
- **Ending the mode mid-drag calls the cancel path**, i.e. `restoreXYBinding` and not
  `commitPosition`.
- **No swap left.** `DragApps` and the quick-toggle panel commit through `layout_ops.move`; nothing
  under the edit-mode surfaces still spells an adjacent-swap.
- **The lock preview cannot authenticate.** `LockSurface.qml` contains `interactive` and gates
  `forceFieldFocus`, the field's `enabled` and every session action on it; the preview host passes
  `interactive: false`; the preview context declares no PAM object. This is the one contract in the
  list whose failure is a security bug rather than a layout bug, and it is worth a sweep that
  **asserts it still found the file** rather than passing when the grep matches nothing — the
  `test_expressive_design_system.py` habit (`:198-206`, `:228-229`, `:268-269`) of pinning that a
  sweep is not blind.

**Both files must be written so they can run and so they can fail.** `run_tests.sh` invokes each as
`python3 <file>`, so a module of bare `test_*` functions exits zero having asserted nothing — three
have shipped in that state. Subclass `unittest.TestCase` with `unittest.main()`, or end with the
`contract_runner` block. Prove each check fails by planting the violation: "a pattern with baked-in
indentation passes vacuously after any reformat". Plant only in a clean tree —
`git checkout -- <file>` reverts to HEAD and has destroyed uncommitted work three times in two days.
And add each as **its own block** in `tests/run_tests.sh`.

**Existing lints the new surfaces must satisfy**, listed because a new directory is exactly where an
exception gets carved: `lint_spacing.py` (no raw literals in the M3 token range),
`lint_material_icons.py` (the `edit` glyph must exist in every installed copy of the font),
`lint_clickable_cursor.py` (a `MouseArea` in the bar with a primary-click handler must set
`cursorShape` — stage 6 adds several), `lint_window_clear_color.py` (the chrome surface's `color:`
must be a **literal**; a bound one latches the surface opaque and costs it its blur for the life of
the process), `lint_qml_imports.sh` (a bareword `Appearance` needs `import qs.modules.common`;
without it the binding is `undefined` → NaN geometry → a pegged core), `lint_duplicate_imports.py`,
`lint_qmldir_registration.py`, `lint_rich_text_optin.py`, and `lint_disabled_opacity.py` (the Done
button dims once, not twice).

### 8.3 Runtime harness — what it can and cannot say

`EditModeRuntimeTest.qml` at the theme root, driven by `tests/test_edit_mode_runtime.py` under
headless weston (`weston --backend=headless --renderer=pixman`, `LIBGL_ALWAYS_SOFTWARE=1`,
`QT_QUICK_BACKEND=software`, throwaway XDG dirs, `qs -p`, teardown by held PID), in the shape of
`WidgetResizeGripRuntimeTest.qml` and `DockEdgeRuntimeTest.qml`. `import QtTest` works inside
`qs -p`, so `TestCase.mouseClick`/`mouseDrag` deliver **real events** with no ydotool. It builds a
real widget canvas with real `PluginWidget`s from synthetic manifests and a real bar content tree,
flips `GlobalStates.editMode`, and drives them:

- A drag with the mode on moves the widget and writes the store; the same drag with the mode on and
  the global lock set *also* moves it (the suppression in §2.1), while a per-widget `positionLocked`
  still refuses.
- A bar chip dragged **along** the bar reorders and dragged **across** it does not — the control
  that catches a comparison which is inert on one axis, and the reason `DockEdgeRuntimeTest` runs
  the horizontal edge first.
- Ending the mode mid-drag leaves the stored position at its pre-press value.

Three constraints, all of which belong in the harness's docstring rather than being discovered:

- **Weston implements no wlr-layer-shell**, so nothing about the chrome *surface* — its anchors, its
  mask, whether it takes keyboard focus, whether the scrim blurs — is visible. The harness reaches
  content trees only.
- **A key event has no explicit target**: `TestCase` sends it to the focused item of its own window,
  so a driver parented outside any window cannot deliver one. The Escape ladder is therefore tested
  through §8.1's pure function plus a direct call, not by delivering a key to the real surface.
- **The harness must report that it ran.** Every existing harness prints `failures: 0` on an empty
  step list and every driver asserts exactly that one line, which is how a probe once filed a full
  green trail for a transition it never ran. The integration-testing spec's first defence is the
  harness printing `checks: N failures: M` with the driver asserting the **literal** N — not a count
  derived from the source, which would move with a loop that stopped iterating. This harness carries
  that from its first commit, and a synthetic manifest built through a `Repeater` rather than
  declared inline on the harness root, because the model boundary is where `grid.sizes` was silently
  lost once already.

One thing the harness must **not** do: reach the caller's compositor. `hyprctl` takes its target
from `HYPRLAND_INSTANCE_SIGNATURE` and from nothing else, so a bare `hyprctl` inside a harness talks
to the user's live session — `lint_harness_compositor_reach.py` fails the suite on one.

### 8.4 Not reachable, and must not be faked

How any of it looks; whether the chrome surface really holds keyboard focus (so whether Ctrl+Z ever
arrives); whether the scrim frosts or flattens; whether the lock preview matches the real lock
screen. Weston implements no wlr-layer-shell, `qmltestrunner` cannot construct a `Region`, and CI
has no compositor at all — so these are a **manual** live load plus a readback, performed by a human
and recorded in the PR: `hyprctl layers -j` for the chrome surface's presence and level, a confirmed
`Configuration Loaded` and a `grep ERROR:` after the reload (the QML suite stays fully green for a
file that fails to compile), and a frame-by-frame capture (`ffmpeg -fps_mode passthrough`) for
anything under ~200ms.

Two traps in doing that: a widget disabled while its edit chrome is on screen destroys the content
while the chrome still points at it (the `BarContent.filterLayout` shape — the declaring object has
to vacate the slot from `Component.onDestruction`), and a `qs -p` probe of the harness is a fresh
process, so it will not reproduce the "new singleton needs a full restart" failure the user's
long-running `qs -c imi` will.

---

## 9. Landing plan

Ten stages. Each leaves the tree working, is separately reviewable on screen, and could be merged
and then abandoned without leaving the shell worse. Stages 1-3 are prerequisites that carry their
own user-visible value; **stage 4 is the first one a user would call "Edit Mode"**.

1. **`layout_ops.js` + `tst_layout_ops.qml`. No caller.** Pure arithmetic: `move`, `insert`,
   `remove`, `indexAt`, `dropTarget`. *Ships alone as new tested code with no behaviour change.*
2. **The four existing reorder call sites adopt it, and swap becomes move.**
   `LayoutSection.qml:71-85` (already a move, so this is a substitution),
   `DragApps.qml:65-80` and `DocktoPanel.qml:290,302` (behaviour change: a multi-slot drag now
   shifts rather than swapping), `AndroidQuickToggleButton.qml:205-223`. *Reviewable as "the dock's
   drag reorder stopped being a swap", which is a fix people can judge on its own.*
3. **`BarWidgets` catalogue promoted out of `BarConfig.qml:49-71`**, plus the `plugin:` fix in
   `VerticalBarContent.getWidgetUrl` (`:62-66`). *Ships as a bug fix plus a move; `BarConfig` reads
   the singleton and looks identical.*
4. **The mode itself, desktop only.** `GlobalStates.editMode`; the desktop-menu row; the chrome
   surface with a Done button and nothing else on it; the exit ladder (`edit_mode.js` +
   `tst_edit_mode.qml`); the desktop's affordances forced on (grid, grips, global-lock
   suppression); the mid-drag cancel. *Shippable alone: right-click → Edit layout gives you the
   desktop editor you already had, made visible.* Test: `tst_edit_mode.qml`, plus
   `test_edit_mode_contract.py`'s first half (one predicate, static surface, collapsing mask,
   cancel-not-commit).
5. **Per-widget context menu and add-at-pointer.** Right-click on a widget in the mode opens
   Remove / Pin / Size instead of toggling the global lock; the chrome grows an add affordance
   fed by `PluginManager.availablePlugins`; a widget added by drop lands at the pointer.
   *Test: `lint_edit_mode_scope.py` lands here, with the allowlist it will police.*
6. **The bar, in place.** Auto-hide suspended, widgets inert, remove badges, `ReorderDragArea`
   across the three buckets, visible bucket boundaries, add from `BarWidgets`. *Test: the runtime
   harness's along/across drag pair.*
7. **The dock, in place.** Remove badges and add; the drag is already correct after stage 2.
8. **`LockSurface.interactive` and the preview context.** A pure refactor plus one new component,
   with no editing yet: the preview renders, cannot take a keystroke, cannot dispatch a session
   action. *Ships alone and is the stage that most wants a careful review, so it should not be
   carrying a feature.*
9. **The lock context of Edit Mode.** Island item order and presence, the locked visibility filter,
   the background surface in its locked appearance.
10. **Undo.** The mutation log, Ctrl+Z/Ctrl+Shift+Z, and the keyboard-focus question in §10 answered
    with a live readback before any of it is written.

Stages 2 and 6 are the ones that can go quietly wrong: stage 2 because a reorder that lays out
perfectly can have its comparison inert on one axis (nothing errors, the icons simply refuse to move
past each other), stage 6 because the bar's two orientations are two modules with two content trees
and a fix applied to one is invisible in the other.

---

## 10. Risks worth naming before building

- **Keyboard focus on a layer surface is not a given, and Ctrl+Z depends on it.** The background
  surface only takes keys while `WlrLayershell.keyboardFocus` is `OnDemand`, which
  `GlobalStates.desktopWidgetKeyboardFocus` arms (`Background.qml:542-544`,
  `WidgetCanvas.qml:17-23`). The chrome surface needs the same arrangement, and **no harness can
  verify it** — weston gives no wlr-layer-shell. Establish it with a live probe before designing
  any keyboard interaction, not after.
- **A full-screen `Overlay` surface that forgets to collapse its mask eats every click on the
  desktop.** The mode being off is the dangerous state, because that is the one nobody looks at.
  This is why §8.2 pins the collapse as a contract rather than trusting it.
- **If §11 Q7 lands a scrim, it is a large translucent rectangle on a namespace with a shared
  `ignore_alpha` threshold.** Too low and the compositor is asked to blur the whole screen; too high
  and the chrome's own body goes flat — and a namespace's threshold is one value shared with its
  popups, so raising it for the scrim takes the blur off whatever else uses that namespace. The
  failure directions are opposite and neither logs anything.
- **The dock's dynamic-scope lookups** (`DockSeparator.qml:7-8`, `DockAppButton.qml:37-41`) resolve
  `dockRow` and `dockVisualBackground` by name through the dock's tree. Edit-mode chrome that
  reparents anything there yields `undefined` → NaN geometry → a relayout that never converges and
  a pegged core, with no error.
- **Suspending the bar's auto-hide is a state change on a layer surface**, and `visible: false` on
  a layer-shell `PanelWindow` destroys it rather than hiding it. The suspension must be expressed
  the way `Bar.qml` already expresses `mustShow` (`:57-58`), by adding a term, not by touching
  `visible`.
- **A green suite says nothing about whether any of this loads.** `qmltestrunner` never builds
  these widgets; a `FINAL` property override on anything deriving from `RippleButton`, or a missing
  `import qs.modules.common`, passes every test and takes down every panel that reaches it.
- **`__gridSize` is per plugin, not per monitor** (`PluginState.qml:18-31` — `pluginOptions` is
  keyed by id alone, while `desktopPositions` is keyed by screen then id). Resizing a widget in Edit
  Mode on one monitor resizes it on all of them. This is shipped behaviour, not something Edit Mode
  introduces, but Edit Mode is where a user will first notice it.
- **`background.screenList` is declared (`Config.qml:945`) and written by the "Show widgets on"
  selector, and nothing reads it.** Desktop widgets render on every screen regardless. An Edit Mode
  that shows chrome per monitor will make that gap conspicuous.

---

## 11. Questions

Each is a decision the user might reasonably make differently, with the argued default.

**1. Do widgets get a second, lock-screen position?** §3.4. Accepting one shared position is
cheap, honest and matches shipped behaviour; a second position doubles the placement model and
lands silently in every preset. **Recommendation: one position for the first landing.**

**2. Are the lock islands' *contents* editable, or only their visibility?** Reordering the items
inside `leftIsland` / `rightIsland` needs new storage (three ordered lists in
`Config.options.lock`) and a data-driven rewrite of `LockSurface.qml:236-501`, which is currently
hand-placed children. Visibility alone needs nothing new. **Recommendation: visibility for stage 9,
contents as a follow-up spec** — but this is the question whose answer decides whether stage 9 is
small or large.

**3. Does the drawn grid become 12px to match the snap?** The canvas draws every 24px
(`WidgetCanvas.qml:7`) and snaps every 12 (`AbstractWidget.qml:24`). With the grid up for the whole
mode, a widget landing between lines reads as broken snapping. **Recommendation: draw 12px lines at
a lower opacity with every second one emphasised**, so the lattice is honest and the rhythm is
still readable. This changes an existing default, so it is a separate commit.

**4. Is the dock's (and bar's) edge draggable in Edit Mode?** Dragging a layer surface between
edges cannot animate — position is `anchors` and `margins`, so it would reconfigure the surface
every frame — so the "drag" would be a press, a jump, and a compositor slide.
**Recommendation: no. Edge stays a settings row**, and Edit Mode's chrome may carry a shortcut *to*
that row.

**5. Does undo ship in the first landing?** **Recommendation: no** — stage 10. It is the only piece
whose absence is an inconvenience rather than a gap, and it is the piece that depends on the
keyboard-focus unknown in §10.

**6. One entrance or several?** The desktop menu row is the brief. A keybind and a quick-toggle
button are both cheap to add later. **Recommendation: one, until asked.**

**7. Is there a scrim at all?** A dimming overlay says "you are in a mode" unambiguously and is the
convention. It also dims the wallpaper the user is arranging widgets against, fights the
transparency toggle, and raises the `ignore_alpha` problem in §10. The alternative is no scrim, a
persistent toolbar, and the affordances themselves as the signal — which is what the quick-toggle
edit mode does (`AndroidQuickPanel.qml`: no scrim, just badges and a tray).
**Recommendation: no scrim; the toolbar and the grid are the signal.**

**8. Does Edit Mode reach the overlay widgets?** The overlay is a fifth surface with a fifth store
(`Persistent.states.overlay.*`, `Persistent.qml:100-168`), and it is already a `WidgetCanvas` with
free drag — but it deliberately does not opt into the marquee (`OverlayContent.qml:42`), because
the overlay closes on a plain click. Out of the brief's scope. **Recommendation: out of scope, and
say so in the doc rather than leaving it ambiguous** — it is the obvious next surface.

**9. What happens to `WidgetsSubmenu.qml`?** Its `widgetList` is empty by decision
(`:14-19`: "what to do with the rest of it is Task 6's call") and its only live control is the
global lock, which Edit Mode suppresses. Once Edit Mode exists the submenu is a switch that turns
off something the editor turns back on. **Recommendation: leave it in stage 4, and remove the
Widgets submenu in stage 5** when the per-widget menu makes it redundant — as its own commit, so
the removal has a reason attached to it.
