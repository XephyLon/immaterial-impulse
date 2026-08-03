# Changelog

All notable changes to Immaterial Impulse are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/), and the project follows
[Semantic Versioning](https://semver.org/) (currently pre-1.0: `0.x` may make
breaking changes on a minor bump).

The version is stored in `VERSION` (a symlink to the shell's
`dots/.config/quickshell/imi/VERSION`, so it deploys with the config and the
About page can read it). The companion `qs-wallpaperengine` is versioned in its
own repo; the installer pins which revision it builds.

## [Unreleased]

### Fixed
- **The login screen shows the current wallpaper again (second attempt).** The
  SDDM fork was retargeted for the installer only, and its `setup.sh` clones
  the theme content from its own `THEME_REPO` rather than copying the checkout
  it runs from — that still pointed at upstream, so every install laid
  upstream's theme back down over the fork's. The installed theme therefore
  still read `~/.config/illogical-impulse/config.json`, a directory the 0.13.1
  purge removed, and had no Wallpaper Engine handling at all, so the greeter
  fell back to a stock background. The fork now installs itself, and the
  installer pin is a full commit SHA checked by a test.
  Wallpaper Engine is also resolved *before* the static wallpaper now, rather
  than only when `background.wallpaperPath` is empty: selecting a WE wallpaper
  does not clear that key, so any install that used a static wallpaper first
  kept showing the old picture on the login screen. The order now matches
  `Background.qml`'s `weActive` — a WE project wins unless it is a "web" one,
  which the shell cannot render either.
- **Switching keyboard layout works again (#69, second attempt).** The previous
  fix cleared the stale `input.kbOptions = grp:win_space_toggle` from
  `config.json` and changed nothing on any real machine, for two independent
  reasons. It was guarded by a persisted "already migrated" marker, and a
  marker records that the check ran, not that the value was ever there — an
  install whose config-directory migration declined burned it against the
  installer's default and then received the user's real config afterwards,
  permanently out of reach. And `config.json` is not what Hyprland reads: the
  option reaches the compositor through the generated
  `hypr/hyprland/shellOverrides/main.lua`, which is only rewritten when the
  Hyprland settings page is opened, so the clear never arrived there. The clear
  is now unconditional — `grp:win_space_toggle` is not a value the shell can
  hold legitimately, since the settings control offers only "none" and
  Alt+Shift — and it purges the generated lua too, through a new `--reset-if`
  mode that removes the managed line only while it still holds the stale value.
  Both halves are covered by a runtime test against real files; the old fix had
  no test at all, which is why it shipped broken. Symptoms: Super+Space fired
  the xkb toggle *and* the compositor bind, two switches that cancelled, so the
  OSD announced a layout change that had not happened, while Super+Alt+Space
  switched the layout on top of toggling the window float.

## [0.13.1] — 2026-08-03

### Fixed
- **The login theme follows the desktop again, and installs unattended.** The
  SDDM theme now comes from our fork (`XephyLon/imi-sddm-theme`). Upstream
  resolved the shell's config at `~/.config/illogical-impulse/config.json`, a
  path that stopped existing when the shell was renamed, so its "sync ii
  settings" mode had been syncing a copy frozen at the rename. It also had no
  non-interactive mode, so an unattended install EOF'd on its first prompt and
  exited having installed nothing; and it ignored Wallpaper Engine entirely, so
  the greeter fell back to a stock background exactly when the desktop was at
  its least default — it now plays a WE video wallpaper directly, or uses the
  still the shell renders for scene/web ones.
- **Wallpaper changes reach the login screen again.** The theme registers its
  trigger as a `post_hook` inside `~/.config/matugen/config.toml`, and the
  installer deploys that file with `rsync --delete` from a copy that has no
  such line — so every update deleted the hook and the greeter quietly froze.
  The installer restores it after deploying, deriving the right variant from
  what the theme actually installed.

- **The pre-rename config directory is archived and removed instead of being
  left behind.** Migrating `~/.config/illogical-impulse` into
  `~/.config/immaterial-impulse` used to keep the old directory in place as a
  backup. That is not harmless: anything resolving a config by absolute path
  finds the stale one and silently succeeds against it — `ii-sddm-theme`'s
  installer reads `~/.config/illogical-impulse/config.json` directly, so the
  login theme was syncing settings frozen at migration time and never saw
  another change. The directory is now archived to
  `~/.local/share/immaterial-impulse/backups/illogical-impulse-<timestamp>.tar.gz`
  and removed, and installs that already migrated under the old behaviour get
  their leftover cleaned up on the next launch. The archive has to write and
  read back before anything is deleted, so a full disk keeps the directory
  rather than losing it.


## [0.13.0] — 2026-08-03

### Added
- **Settings now survive the move from upstream.** Arriving from
  `end-4/dots-hyprland` or `pctrade/end4-pC` already moved your config
  *directory*; it never converted anything inside it. The shell reads
  `config.json` through a JSON adapter that silently ignores any key it does not
  recognise, so a setting this fork renamed was replaced by a default with no
  error and nothing to point at. Two things were being lost and are now carried
  across on first launch:
  - **`panelFamily`.** A config naming `ii` or `waffle` (end-4's second panel
    family, which was never ported here) matched no panel family at all - the
    desktop came up **completely blank**: no bar, no dock, and no error in the
    log. Both now resolve to `imi`.
  - **`bar.floatStyleShadow` -> `bar.shadow`.** Not a straight copy. Upstream
    only ever drew that shadow under the Float corner style, while ours draws it
    under every style that paints a background, so what migrates is the shadow
    you actually had on screen rather than the flag on disk.

  Everything else in the schema turned out to be intact - this fork's key set is
  a superset of upstream's, with no type changes and nothing moved to a different
  parent. The keys that were *removed* rather than renamed (`waffles.*`, and
  end-4's `notifications.monitor.*`, which nothing ever read) are recorded as
  removals rather than given an invented destination. The full audited
  old-key -> new-key table, and an explicit list of what is **not** covered
  (`~/.config/hypr/`, `~/.config/matugen/`), is in `docs/UPSTREAM_MIGRATION.md`.

  It runs once, keyed on a marker of its own rather than on the old directory
  still existing - that directory is already gone for anyone whose directory
  migration ran earlier, and those are exactly the people who still need this.

### Changed
- **Notes are a list of notes again, not one scratchpad — and both notes
  surfaces now share it.** The notes desktop widget and the overlay notes
  editor (`Super`-summoned overlay) used to share a single plaintext file, so
  there was only ever one note. They now share a JSON array of separate notes,
  stored in the same file as before
  (`~/.local/state/quickshell/user/notes.txt`). **What happens to your existing
  text:**
  - Whatever is in your scratchpad today becomes your first note, word for
    word. Nothing is deleted, and a file that cannot be parsed is kept as a
    note rather than reset.
  - If you used the old built-in notes widget (removed earlier in this cycle),
    the notes it kept in `~/.local/state/quickshell/user/desktopnotes.txt` are
    **imported back** and will reappear alongside your scratchpad. That import
    runs exactly once; notes you delete afterwards stay deleted.
  - `desktopnotes.txt` is read and then left alone forever — it is never
    modified or removed, so it remains your own copy of those notes.
  - `notes.txt` now contains JSON rather than raw text. If you edit or sync it
    by hand, expect an array of `{ id, content, attachments, createdAt }`.
    Replacing it with plain text is safe: it is read back as a single note.
  The desktop widget gets a list of notes, an add button, a per-note delete
  button and a flip to a full-size editor. Swipe-to-delete and the old
  per-note colour cycling from the removed built-in were **not** restored. The
  overlay editor keeps its editor and its copyable-bullet buttons, and gains a
  strip of note chips plus add and delete buttons, so it can reach every note
  instead of only the first. Adding, editing or deleting a note in one surface
  shows up in the other immediately.
- A fresh install now ships the clock and the visualizer on its desktop, not
  the calendar. Both of the two sit at an edge - the clock centred, the
  visualizer full-bleed along the bottom - so neither claims a tile the user
  has not chosen to give it. Existing installs are untouched: the curated
  defaults are seeded only when `~/.config/immaterial-impulse/config.json` does
  not already exist.

### Fixed
- **The night light indicator now tells the truth, and your setting survives a
  restart.** The toggle and the bar indicator could say night light was on with
  a perfectly neutral screen, or off with a warm one. The shell was asking
  `hyprsunset` what it was doing, and `hyprsunset` cannot answer: its only
  requests are `temperature`, `identity` and `gamma`, and the `temperature`
  query reports the last temperature the daemon was *told* — turning night light
  off with `identity` never changes that number. The shell then compared it
  against a hardcoded `6500`, which was never `hyprsunset`'s neutral to begin
  with (it is the cool end of the Intensity slider; the daemon's own default is
  6000 and its neutral is the identity matrix, not a temperature). The answer
  was therefore wrong on essentially every restart. The shell now remembers
  whether you had night light on and re-applies it on startup instead of
  guessing — so the setting survives a reboot, and turning it off actually stays
  off. Automatic scheduling is unchanged: startup restores what you last had and
  never consults the clock, so it still does not switch itself on just because
  you logged in after sunset.
- **Opening a Settings page no longer eats the setting you had.** Every numeric
  setting is edited through a spin box or slider that declares its own range —
  the OSD timeout's box, for instance, stops at 3000 ms. Nothing in the config
  format does: `osd.timeout` is a plain number and the shell honours whatever is
  in it. Those controls used to report the value being *loaded* as if it were a
  value you had just typed, so a config holding `4321` was quietly cut down to
  `3000` and written back to disk **the moment the page was drawn** — no prompt,
  no warning, and nothing you did. Anything you set by hand, restored from a
  backup, or imported from a preset outside a control's range was lost on the
  first look at the page that shows it, and the same round trip rounded off
  fractional values (a 90-second wallpaper interval became 60, a 0.185 overview
  scale became 0.18). Sliders were worse: their smoothing animation wrote every
  intermediate frame of it.

  Controls now write only when you actually move them, and a stored value
  outside a control's range is shown as it is rather than silently pinned to the
  nearest end — so you can see the real number and, if you want, walk it back
  into range. Values already inside a control's range behave exactly as before.
- **The "−" button on every number field was almost unclickable.** Only its
  leftmost few pixels did anything; the rest of it sat underneath the editable
  number, which swallowed the clicks. The whole button works now. Number fields
  are a little wider as a result.
- **Click through only made half of a widget click-through.** A desktop widget
  switched to **Click through** stopped taking the drag and stopped swallowing
  the desktop's right-click menu — but every control the widget drew for itself
  kept working, and a click that landed on one never reached the desktop behind
  it. The widget host is a `MouseArea`, and disabling a `MouseArea` disables
  only that one area, not the items inside it; the mechanism read as if it
  disabled the whole widget and never did. Everything a desktop widget draws now
  sits inside a wrapper that goes inert with it, so **Click through** means what
  the switch says: the widget is transparent to the pointer, controls included.
  Nothing visibly changes and no widget changes size. Only the Visualizer ships
  click-through on, and it has nothing to click, so nobody was hitting this yet —
  it is fixed before anything else opts in. Pinning a widget with **Lock
  position** still leaves its controls working, which is the difference between
  the two switches.
- **Coming from upstream no longer silently loses your entire settings
  directory.** Moving `~/.config/illogical-impulse` to
  `~/.config/immaterial-impulse` is done at first launch by a script that
  refused to migrate into a directory that already contained a `config.json`.
  That guard cannot tell your config from a file you have never seen, and two
  things routinely put one there before it ran:
  - **The installer put it there itself.** It seeds the curated
    `defaults/config.json` into `~/.config/immaterial-impulse` whenever it finds
    no config there — which is always true for someone arriving from upstream,
    because theirs is still under the old name. The migration then found that
    seeded file in the way and skipped the whole directory. No race needed; this
    happened to everyone who used the installer.
  - **The shell could get there first.** The migration was launched and then not
    waited for, so it ran alongside the shell's own config load. When the shell
    won, it wrote a default `config.json` into the destination and the migration
    skipped the directory for the same reason.

  Either way you kept none of your settings, none of your custom actions,
  presets or AI prompts, and there was nothing in the log to say why. Your old
  directory was never deleted, so nothing was ever destroyed — but you had no
  way to know that was where your settings still were.

  Now: the shell waits for the migration to finish before it reads or writes the
  config directory at all, and the migration decides by comparing the file in
  the way against the config this shell ships. An untouched shipped default is
  replaced by your real config; anything you have actually changed here is
  **never overwritten** — instead the shell declines, changes nothing, and logs
  which directory your settings are still in so you can merge them by hand. If
  the migration itself gets stuck, the shell still comes up, but read-only, so a
  half-finished move can't cost you the file. A successful merge keeps the old
  directory as a backup; delete or rename it once you no longer want it.
- The design-system compile check swept a hardcoded list of bundled packages
  that had rotted: it still named `nandoroid-clock` and `nandoroid-at-a-glance`,
  directories that have never existed at that path, so every run reported two
  meaningless failures. Both roots are discovered with `find` now, so the check
  covers every bundled package's entry point (118 files, up from a fixed list)
  and cannot drift again; a sweep that matches nothing fails instead of passing
  silently. It is also wired into `tests/run_tests.sh` for the first time -
  nothing ran it before, which is why the dead names survived since the ii->imi
  rename. It skips where there is no Wayland display, so CI is unaffected.

### Added
- **Per-widget lock and click-through for desktop widgets.** Every desktop
  widget gains two switches of its own next to `Blur background` in
  Settings → Widgets. **Lock position** pins that one widget while the rest
  stay draggable; it combines with the existing global `Lock widget positions`
  rather than replacing it, so the global switch can only ever lock further and
  never unpins something you pinned deliberately. **Click through** takes the
  widget out of pointer input entirely, so clicks land on whatever is behind it
  — including the desktop's own right-click menu. They stay two separate
  switches because "pinned but still clickable" is a real thing to want; the
  reverse is not, so click-through implies the lock. A plugin can ship either
  one on by default from its manifest (`desktopWidget.locked`,
  `desktopWidget.clickThrough`), and you can still switch it back off.
- **The Visualizer now ships click-through on.** It spans the full width of a
  monitor and has nothing on it to click, so it was covering a whole strip of
  desktop, swallowing the right-click menu there, and could be dragged half
  off-screen with no bounds. Switch its click-through off if you want to
  reposition it.
- **`shape` and `color` manifest option types.** `shape` takes the same
  `choices` array as `choice` but renders each entry as the Material shape it
  names rather than as a text chip — a 31-entry row of shape *names* is
  unreadable, and `ConfigSelectionArray`'s chip flow only wraps when the row
  has no label, so such a row could not be labelled either. `color` renders a
  row of palette swatches from `Appearance.colors` role names; the empty
  string is a legal choice and draws an "automatic" slot, so a widget with a
  sensible colour of its own gets its override *and* the way back to that
  default in one row, rather than a second switch sitting beside the row
  saying the same thing.
- **A `grid`-exempt escape hatch for full-bleed widgets.** The component grid
  caps at 12 columns (1716px — barely a third of a 5120px display), so a
  screen-wide widget cannot express itself through `grid` at all. It omits
  `grid`, takes the host's content sizing, and binds its own `implicitWidth` to
  the monitor the host tells it it is on. `docs/widget-grid.md` documents the
  rule and the two other legitimate exemptions (user-resizable, and square).
- **Host opt-ins for widgets that draw straight onto the wallpaper.** A package
  component may now declare `visibleWhenLocked` (stay up while the screen is
  locked, regardless of `lock.showWidgets`), `forceCenter` (centre on the
  monitor without disturbing the persisted position), and `needsColText` (run
  the least-busy-region pass so `hostColText` tracks the wallpaper underneath).
  The bundled Clock uses all three. Every one is optional; a widget that
  declares none behaves exactly as it did before.

### Changed
- **The two desktop-widget systems are now one.** Every desktop widget used to
  be either a hardcoded `FadeLoader` in `modules/imi/background/Background.qml`
  gated on `background.widgets.<key>.enable`, or a bundled plugin gated on
  `plugins.enabled`. All eleven built-ins are gone: seven were ported to
  bundled plugins (Visualizer, Custom Image, Image Converter, User Card, World
  Clock, Calendar, Clock) and four were deleted as duplicates of a plugin that
  already shipped (resources → System Monitor, media → Media Player, weather →
  Weather, notes → Notes). Every desktop widget now goes through one code path
  (`PluginManager` → `PluginWidget` → `PluginNode`) and is enabled from
  Settings → Widgets — which means one frost/blur implementation, one position
  persistence system, and one place to look. Porting the clock also retired the
  older declarative `clock_plugin`, so there is exactly one clock in the list.
- **Nothing you had switched on switches off.** A one-shot migration translates
  `background.widgets.*.enable` into `plugins.enabled`. The clock gets a second
  one: it is the only widget that shipped *on*, and its four styles look
  nothing like one another, so it carries its own settings and its desktop
  position across as well rather than silently repainting and moving itself.
  Both migrations are marked so they never run twice, and the clock's marker is
  written only once the values have actually landed.
- **The world clock's timezones moved in with the rest of its settings.** They
  were the last thing in the old desktop-widget config block that the shell
  still wrote to while running; they now live in `plugin-state.json` alongside
  the widget's other options. A third one-shot migration carries an existing
  list across — including on installs that had already run the two earlier
  ones, which is all of them — and a list you have since changed through the
  widget's own picker always wins over the one being migrated. The four zones
  you picked survive the upgrade; there is nothing to redo.

### Fixed
- **A locked widget could still be resized.** The Calendar, World Clock and
  Custom Image each draw a corner grip that resizes them, and each one checked
  only the global `Lock widget positions` switch. Lock one of those widgets on
  its own and the lock held for dragging but not for the grip — the widget was
  pinned and still fully resizable, which is not what "locked" means anywhere
  else. All three grips now follow the same resolved lock the drag does, so a
  widget locked for any reason (its own switch, the global one, or
  click-through) has a dead grip. That also closes a hole in **Click through**:
  the widget itself stopped taking clicks, but a grip drawn *inside* it did
  not, so a click-through widget could still be resized by its own handle.
- **Laptops lost their battery reading when the resources widget was deduped.**
  The built-in `ResourcesWidget` showed CPU, RAM and — wherever a battery
  existed — the battery, falling back to disk only on a desktop. The bundled
  `nandoroid-system-monitor` it was deduped into is always Disk, so every
  laptop the migration moved onto the plugin quietly lost the reading. The
  third card follows the battery again, gated on `Battery.available` rather
  than the raw display device, so a transient UPower device swap cannot make
  the whole card flip to Disk and back. The plugin also gains a **Battery
  instead of disk** switch (on by default): the built-in never let a laptop
  user keep disk, and that guess is wrong for anyone who put the widget there
  to watch it. A machine with no battery renders exactly what it did before,
  to the pixel.
- **The world clock card overflowed its own bottom margin, and always had.**
  Its content came to 6px more than the card at both the old height and the
  new one, so the bottom row of city chips sat 2px off the card edge while the
  top sat on a full margin. The chips now take the column's leftover height
  instead of a fixed 50px, so the card cannot be overshot by a font that
  renders a little tall, and they divide the card width instead of being a
  fixed 120px block centred inside it — they line up with the header and the
  time above them now, down both edges. The local time drops 42px to 36px,
  which is where the room for a real `space150` card inset comes from; it is
  still 2.4× the largest text under it. The timezone-picker side gets that
  same inset and a heading, instead of a back arrow alone against an empty row.
- **The wide world clock drew each city's name through its own clock hands.**
  `AndroidClock` placed the label just under the centre dot while the minute
  hand reaches 0.82 of the dial radius, so the two always overlapped. A
  labelled clock now reserves a band for the label and centres the dial in
  what is left; an unlabelled one (the clock preview in Settings) is laid out
  exactly as before. The label also picks up the shell's own font instead of
  asking the canvas for `sans-serif`.
- **The calendar's padding was whatever made it fit.** Putting the widget on
  the real grid cell left every gap inside it set to whatever absorbed the 24px
  it lost, so the month title, the weekday letters and the day grid all sat the
  same 4px apart with nothing saying which belonged to which. All three sizes
  now share one card inset and one three-step rhythm — `space150` around the
  card, `space100` between the title block and the calendar block, `space50`
  between the weekday letters and the grid they label. The day columns spread
  across the full card width instead of sitting as a fixed 196px block centred
  in a 252px surface, so the weekday letters line up over the days they name
  and the day block is inset evenly on all four sides; the week strip is
  centred in its card rather than piled against the top with all the slack
  under it.
- **Every "2×2" world clock and calendar was 24px too tall.** Both assumed a
  132×**120** grid cell; the cell is 132×**108**. A widget off the lattice
  cannot line up with its neighbours no matter where it is dropped — its bottom
  edge lands past every other tile's, on every row. Both are now sized through
  `Appearance.sizes.widgetGridSpanX/Y`, which also makes them follow
  `effectiveScale` instead of being wrong on every scaled setup.
- **Every unselected shape in a shape picker rendered invisible.**
  `ConfigSelectionShapeArray`'s default `shapeColor` was `colPrimaryContainer`,
  near-identical to the chip background it was drawn on.
- **The desktop media widget would have thrown on its first reset.**
  `Background.qml`'s media `onLoaded` referenced a `mediaTimer` that was
  declared nowhere in the tree.
- **The cookie clock's Gemini auto-styling would have silently stopped.**
  `scripts/colors/switchwall.sh` read `.background.widgets.clock.cookie.aiStyling`
  out of `config.json`. The clock's settings live in `plugin-state.json` now, so
  that read would have returned `"null"` forever and the wallpaper category
  would never have been generated.
## [0.12.0] — 2026-08-02

### Added
- (#75) Kitty terminal colors now follow the wallpaper through a matugen
  template, so its palette re-themes together with the shell and other apps on
  a wallpaper change (alongside the existing terminal palette pass).

### Fixed
- Super+Alt+Space (window float toggle) no longer also switches the keyboard
  layout. The shipped default config still carried `input.kbOptions =
  grp:win_space_toggle` even after the layout switch was moved to a compositor
  bind — xkb `grp:` toggles match modifiers loosely, so Super+Space fired with
  Alt held too. Fresh installs now seed `kbOptions = ""`, and a one-time
  migration clears a stale `grp:win_space_toggle` from existing configs on the
  next shell start, so both are fixed. Super+Space then runs only the
  exact-matching `switchxkblayout all next` bind, which cycles the real
  `us, eg` layout list and reverses cleanly.
- (#70) The wallpaper no longer disappears after a transition on OpenGL
  2.1-class GPUs. The Doom melt transition used a `const int[256]` table and a
  bitwise `&`, which the GLSL ES 1.00 profile the RHI compiles to on those
  backends rejects, so its shader failed to build and left the desktop blank.
  The shader now compiles there (procedural noise, `mod` instead of `&`), and a
  transition-shader compile error falls back to the plain wallpaper instead of
  blank output.
- (#71) A bar hover popup opened next to a closing one (e.g. weather after
  clock) is no longer painted over by the one still finishing its close
  animation. Adjacent popups are separate layer-shell surfaces, so stacking
  order — not activeness — decided which drew on top; a lingering popup now
  collapses the moment a neighbour opens.
- (#72) The SDDM login theme (ii-sddm-theme) no longer silently fails to
  install from the default TUI. Its upstream installer is interactive, but the
  default fzf TUI ran the install pipeline with stdin from `/dev/null`, so the
  installer hit EOF on its first prompt and aborted with no output. It now runs
  as an interactive post-install step on the real terminal, and the wrapper
  reconnects to `/dev/tty` (or skips with a message) instead of aborting.

## [0.11.0] — 2026-08-02

### Changed
- The **Plugins** settings page is now **Widgets**, with a search field and
  capability filter chips (Desktop, Bar, Overlay, Panel). Type names, file
  names and the `plugins.*` config keys are unchanged, so existing installs
  are unaffected.
- `FilterChip` moved from a page-local component inside the gated-off plugin
  store to `modules/common/widgets/`, so both filter surfaces share one
  implementation. The capability vocabulary moved to
  `PluginManager.surfaceCapabilities` for the same reason.
- Widget cards are restacked: the name shares its line with a byline, the
  description gets the second, and **surface tags** run along the third, drawn
  from the same vocabulary as the filter chips so a card explains why a filter
  matched it. The byline is trimmed to creator and version — manifest authors
  routinely append the repo or a contributors note. Row actions sit before the
  switch, and the third-party badge is error-coloured: not because such a
  widget is broken, but because it runs with the shell's own access and came
  from outside it.
- `ConfigSwitch` gains `titleContent`, `detailContent` and `trailingContent`
  slots. Its label is one text item and its switch is the last thing it draws,
  so a caller previously could not put anything beside either. The third-party
  pill and the surface tags share a new `Badge` widget rather than
  open-coding the same pill twice.
- Widget settings (frost, blurred opacity, install-from-URL) moved into their
  own section. They describe how widgets behave, not which ones the list is
  showing, and they had been standing between the "Available Widgets" header
  and the list it names.

### Fixed
- **A band of dead space sat under every enabled widget.** An expanded panel
  computed its height as content plus a 20px inset unconditionally, so one
  that opened onto nothing still claimed the inset — visible under widgets
  exposing no options, and under every enabled widget until its options
  finished loading.
- Row actions were pushed past the card's right edge. A wrapping description
  reports its full unwrapped width as its implicit width, and the row honoured
  that as a minimum, so the card could not shrink to fit its own buttons.
- **A widget's options disappeared when a filter was selected.**
  `ExpandablePanel` only ever received a height from `animateTo()`, which runs
  solely from `onExpandedChanged` — so a panel *created* already expanded never
  emitted the signal, never got a height, and rendered its content clipped to
  nothing. Selecting a filter rebuilds the list's delegates, so every enabled
  widget came back open-but-empty until its switch was toggled off and on.
  Affects any call site that creates a panel in the expanded state.
- Plugins declaring `overlay-widget` (Discord Voice) were missing from the
  capability vocabulary entirely and matched no filter.
- Widgets whose manifest predates the `capabilities` key (the bundled clock)
  matched no filter chip and vanished from every filtered view.
- Settings labels rendered through `ConfigSwitch`, and icon names rendered
  through `MaterialSymbol`, inherited Qt's `Text.AutoText`, so an installed
  plugin manifest could inject rich text into the settings UI through its
  name, description or option icons. Both now render as plain text.
- An empty widget list claimed the filters were responsible even when none
  was set — reachable on first paint, since the manifest scan is async.
- Searching settings for "widgets" could not reach the Widgets page: the name
  collided with a section of Wallpaper & Desktop, which is matched first. An
  exact page-name match now wins over any section match.

## [0.10.0] — 2026-08-01

### Added
- `ExpandablePanel` gains a **clickable header**: the whole row becomes a
  ripple surface, so a panel whose header holds only a small chevron no
  longer feels dead next to one filled by a switch. It reports the click
  rather than toggling itself, so a call site that binds `expanded` to its
  own state keeps that binding.
- `RippleButton` gains **per-corner radii** and an **`appear`** reveal
  factor, so the fourteen shared buttons derived from it can sit in a
  panel header or cascade in without either capability being re-derived at
  each call site.
- A developer gallery for judging the panel's optional traits side by side
  against the defaults (`qs -p ExpandablePanelGallery.qml`, not shipped).

### Changed
- The settings page's plugin cards are now built on `ExpandablePanel` too,
  so they and the Docker popup's container cards share one implementation
  rather than resembling each other. Both toggle from anywhere on the
  header, with a ripple across the row.
- Staggered content rises into place as it appears, and animates out
  instead of snapping.

### Fixed
- Expanding a panel jolted instead of gliding. The vertical insets were
  applied in a single frame while only the content height eased, so the
  card jumped ~21px and then animated the rest.
- Every expansion after the first ran the *collapse* curve — accelerating
  instead of decelerating — because one animation chose its duration and
  easing from a ternary that had not re-evaluated by the time it started.
- Collapsed content was excluded from layout while hidden, so re-opening
  animated toward a stale height and corrected mid-flight.
- Disabled buttons inside an expanded panel rendered as if enabled. The
  staggered reveal wrote `opacity` directly, destroying the binding that
  expresses the disabled state.
- A panel header's hover and ripple kept rounded bottom corners while
  open, leaving notches against the content below.

## [0.9.2] — 2026-08-01

### Fixed
- **"Update Dots" now updates the components you actually have.** Every
  optional component defaulted to unchecked in the installer's checklist,
  and that installer is also the updater — so someone who installed
  Wallpaper Engine and later clicked Update Dots got the menu with it
  unticked, the step exited immediately, and the component was never
  updated. Wallpaper Engine, the SDDM theme and the Plymouth splash are
  now pre-selected when they are already installed.

  This is what kept the 0.9.0 and 0.9.1 crash fixes from reaching anyone
  who updated through the button rather than a terminal. An unchecked box
  in an updater is a silent skip, not a neutral default.

## [0.9.1] — 2026-08-01

### Fixed
- **Re-running the installer now actually repairs the Wallpaper Engine
  wrapper.** 0.9.0 fixed the library-path leak that crashed apps launched
  from the shell, but no existing install could receive the fix: the
  installer skips its work when the build stamp matches and the wrapper
  file exists, and it exited before rewriting the wrapper. Updating,
  re-running the installer and restarting all looked like no-ops while the
  old wrapper stayed on disk. The stamp guards the expensive fetch and
  build, never the wrapper, which is now always rewritten.

  If you followed 0.9.0's "re-run the installer" note and Firefox kept
  crashing, this is why. Re-run it once more on this version.

## [0.9.0] — 2026-08-01

> **Wallpaper Engine users: re-run the installer.** This release fixes a bug
> where apps launched from the shell inherited the wrapper's library path and
> could crash on startup. The fix lives in the wrapper at
> `/usr/local/bin/quickshell`, so it only takes effect once the Wallpaper
> Engine install step runs again.

### Added
- **`ExpandablePanel`** — a shared, plugin-facing component for rows that
  expand, implementing every Expandable Content rule in the M3 guidelines:
  asymmetric enter/exit motion, opacity paired with the height, clipping,
  content that stays alive until its exit reaches zero, a leading-edge
  indent, and collapsed content that takes no keyboard focus. The outline,
  hairline rule, shape morph, tonal lift and staggered reveal are all
  optional properties, so plugin authors get correct behaviour by default
  and can dress it to match their widget.

### Changed
- Docker container and Compose cards are built on `ExpandablePanel`. They
  gain the correct collapse curve, a paired fade, input gating and a
  staggered reveal of their action buttons.
- **A fresh install now enables no plugins.** Seven were on by default,
  several of which paint on the desktop immediately, and their off switch
  lives under Plugins rather than Widgets — so people were finding widgets
  they could not work out how to remove. Existing installs are untouched.

### Fixed
- **Apps launched from the shell could crash on startup** on Wallpaper
  Engine installs. The wrapper exported `LD_LIBRARY_PATH` with the
  linux-wallpaperengine lib directories on it; that is inherited by every
  process the shell spawns, and those directories ship CEF's own
  `libEGL.so` and `libGLESv2.so`. Firefox resolved those instead of the
  system libraries and died during GPU init. The export was never needed —
  the binary already carries a `RUNPATH` — and is gone.

## [0.8.0] — 2026-08-01

Mostly a correctness release. Two of the fixes below were reported by
users and neither was ours originally — the quick-toggle scrambling came
in with the upstream absorb, and the Qt 6.8 requirement was a property
assignment nobody noticed was version-gated.

### Changed
- The **Docker plugin popup** is built from the shell's own M3 Expressive
  components instead of widgets it defined for itself: `SecondaryTabBar`
  over a `SwipeView` for the Containers/Compose switch, `StyledRectangle`
  cards, `FlowButtonGroup` + `RippleButtonWithIcon` action rows,
  `StyledFlickable` scrolling, `IconToolbarButton` header actions,
  `MaterialLoadingIndicator` for refresh, and `PagePlaceholder` empty
  states. Card expansion animates through a `Revealer` rather than
  toggling visibility, so neighbouring cards no longer jump.

### Fixed
- **Android quick toggles no longer scramble.** Editing the layout left
  every tile after the edit point showing the previous tile's icon and
  firing its action, while the delete and resize badges acted on the tile
  you could see — so you toggled one thing and deleted another. Changing
  the column count or importing a preset triggered it too, and it
  persisted after closing the sidebar. The Classic panel was unaffected.
- The Quick settings page no longer disappears on Qt older than 6.8.
  `StyledImage` assigned a 6.8-only property declaratively, which made it
  fail to compile and took down every page that used it — which among the
  settings pages was Quick alone.
- A settings page whose QML fails to build now says so instead of showing
  an empty pane beside a fully populated navigation rail.
- An unreadable `config.json` — wrong permissions, a bad mount — no longer
  leaves every settings page permanently blank. Only a missing file was
  handled before; any other read error left the config never marked ready.
- Quick page: the "Group style" and "Screen round corner" cards each read
  their height from the *other* card's column. Both sit in the same grid
  row, whose height is the larger of the two, so nothing rendered wrongly
  — but the bindings said something untrue about which card owns which
  height.
- Quick page: the scheme-preview command lost its virtualenv fallback to
  QML's template substitution (`${...}` is QML syntax too), which broke
  the whole binding and left the palette swatches without a command.
- The Docker popup is the 480px wide it always declared. The width sat on
  a `ColumnLayout`, which overwrites its own `implicitWidth` from its
  children, so the popup had been silently content-sized.

## [0.7.0] — 2026-08-01

Immaterial Impulse is an independent project now, not a fork that tracks
its ancestors. Nothing is pulled from `pctrade/end4-pC` or
`end-4/dots-hyprland` any more, and the code and naming that existed to
keep those merges tractable is gone.

### Changed
- **The shell is `imi`, not `ii`.** It installs to
  `~/.config/quickshell/imi` and runs as `qs -c imi`; the QML module
  namespace is `qs.modules.imi.*` and the panel family identifier is
  `"imi"`. `ii` was illogical-impulse's abbreviation. Existing installs
  are handled: a `panelFamily` of `"ii"` in an already-written config
  still resolves (without that, the shell would start with no panels at
  all), and the installer clears a leftover `~/.config/quickshell/ii`
  once the new directory is in place.
- The Python virtualenv variable is `IMMATERIAL_IMPULSE_VIRTUAL_ENV`.
  Every consumer falls back to `ILLOGICAL_IMPULSE_VIRTUAL_ENV` and
  `env.lua` exports both, so a Hyprland session started before the update
  keeps generating colors and thumbnails until the next login.
- The welcome screen's Usage, Configuration and GitHub buttons open this
  project's own docs instead of end-4's wiki, which describes a shell
  this one has diverged from. The sponsor button now says whose page it
  opens, and the repository's GitHub Sponsor button no longer routes to
  end-4.
- README and AGENT.md describe the fork relationship in the past tense.
  Attribution to end-4 and pctrade stays in `LICENSE`, `licenses/` and
  the credits — the project is GPL-3.0 and the ancestry is real.

### Removed
- The compositor abstraction. `WM` absorbed `HyprlandBackend` (its API is
  unchanged, so no call site moved), `CompositorGlobalShortcut` gave way
  to `GlobalShortcut` directly, and the 25 `WM.compositor === "hyprland"`
  branches are gone.
- With them, an entire unreachable sidebar entrance implementation: both
  sidebars defined `animatedEntrance` as permanently false and carried a
  slide-in animation, a delayed-close timer, a full-window mask and a
  click-outside-to-dismiss area behind it. Open/close behavior is
  unchanged — that path never ran.

### Fixed
- The repo-root `VERSION` symlink, which the directory rename left
  dangling.

## [0.6.1] — 2026-07-31

### Fixed
- Quick page: the scheme grid ran a little taller than the wallpaper
  preview. The right column is now height-locked to the preview
  (56px light/dark row + three 66px chip rows + gaps = 280), and the
  palette circles were re-proportioned (34px slot, tighter label gap) so
  the shorter chips keep even outer padding.

## [0.6.0] — 2026-07-31

### Added
- Snagit-style **annotation bar** on region screenshots: releasing a
  rectangular Copy selection now pauses on an Annotate phase with a
  toolbar under the region - draw (freehand), arrow, box and ellipse
  tools, six colors, three stroke widths, undo and clear - then Copy
  (Enter) or Cancel (Esc). Annotated snips are composited at native
  resolution via grabToImage and go through the observable copy pipeline
  (clipboard + screenshot popup); an untouched selection falls back to
  the original lossless magick crop. Right-click edit, circle mode, OCR/
  Lens/QR and recordings keep their instant flows.

### Added
- Per-plugin **"Keep settings across presets"** toggle (pin switch at the
  top of every plugin's options): a flagged plugin's options, desktop
  positions and enabled state survive preset application; the flag itself
  is never captured into presets. Covered by an end-to-end presets.sh
  behavior test.

### Fixed
- Bar/overlay-only plugins (Discord Voice, Docker) no longer show a dead
  "Blur background" toggle - host blur is a desktop-widget mechanism, so
  the injected row now appears only for plugins with a `desktopWidget`
  entry point.

### Changed
- Drop Shelf and Screenshot Result are core shell modules again, not
  bundled plugins: always loaded by the panel family, options in the shell
  config (`dropShelf.*` with the blur knobs, `screenshotResult.*`) and in
  Settings (Drop shelf under Sidebars & Panels; Screenshot popup was
  already under Capture). Plugin-state options migrate is manual-free: the
  live install's preferences were carried over. `PluginPanelHost` stays
  for third-party panel plugins.

## [0.5.1] — 2026-07-31

### Fixed
- Super+Alt+Space (float toggle) also switched the keyboard layout when the
  Settings' layout-switch shortcut was set to Super+Space: xkb `grp:`
  toggles fire even with extra modifiers held. The Super+Space layout
  switch is now a real compositor bind in keybinds.lua (exact modifier
  matching, no-op with a single layout), and the Settings selector no
  longer offers the colliding xkb value - it is relabeled "Extra layout
  switch (xkb)" with only None/Alt+Shift left.

## [0.5.0] — 2026-07-31

### Changed
- Settings reorganized domain-first (per `docs/settings-ux-research.md`,
  Option A). The "Interface" junk-drawer page is gone; every section moved
  to a concrete home, none were altered:
  - **Appearance**: Icon pack, Fonts, Terminal (incl. background image),
    Color generation
  - **Wallpaper & Desktop** (was Desktop): + Wallpaper selector
  - **Bar & Dock** (was Bar): + Dock; − Notifications
  - **Sidebars & Panels** (new): both sidebars + quick toggles/sliders/
    corner-open (from General), Overview, Overlay/Crosshair/Floating
    image, On-screen display (from Interface)
  - **Notifications** (new): promoted out of Bar
  - **Lock & Idle** (new): Lock screen, Screensaver, Keep awake (from
    Interface), Work safety (from General)
  - **Capture** (new): Screen recorder + Instant replay, Save paths (from
    Services), Screenshot popup, Region selector (from Interface)
  - **Services** keeps only the outward-facing ones: AI, Networking,
    Music recognition, Search, Updates, Weather
  - **General** keeps the true globals: Time, Battery, Audio, Sounds,
    Language. Quick is unchanged.
  The nav search metadata is now generated from the pages' actual section
  titles, and the navigation test's page map covers all 13 pages.

## [0.4.0] — 2026-07-31

### Fixed
- Privacy pill named Electron apps "Chromium" (Vesktop's mic use showed as
  Chromium): when a stream's `application.name` is a known-generic
  Electron/WebRTC alias, the capitalized `application.process.binary`
  (e.g. "Vesktop") is shown instead - specific names like "OBS Studio"
  still win. Applied to both the JSON and legacy-text pactl parsers and
  the byte-synced test double.

### Removed
- All Niri compositor support from the upstream merge - this fork targets
  Hyprland exclusively. Deleted: NiriBackend/NiriXkb/NiriConfig services,
  the Niri settings page, NiriBackdrop, the niri monitor-config model, and
  every `WM.compositor === "niri"` branch (session actions, lock, night
  light's wlsunset path, workspace model, wallpaper selector, sidebar
  reload, settings gates, record.sh). Upstream's `WM` and
  `CompositorGlobalShortcut` remain as thin Hyprland-only facades so the
  30+ consumer files stay merge-compatible with upstream. The "Niri Like"
  overview *style* (a layout option on Hyprland) is unrelated and kept.
  SystemTheming (orphaned by the Niri page removal) and FastBlurred
  (unreferenced) removed too.

### Added
- Upstream merge (`pctrade/end4-pC`, decrypted from commits `ns`/`cf`/`nl`/
  `lw`x2 + PR #27):
  - **Niri compositor support**: a `WM` abstraction service (compositor
    detection, workspaces, windows, shortcuts) with `HyprlandBackend`/
    `NiriBackend`, `CompositorGlobalShortcut` wrapper, `NiriXkb`, a Niri
    settings page (config editing via `niri msg`), `NiriBackdrop`, and
    niri-gated behaviors (lock wallpaper/overview disabled, wlsunset night
    light, workspace model branching, logout via `niri msg action quit`).
    The Hyprland/Niri settings pages are now pushed compositor-gated into
    the (still section-annotated) pages list.
  - Bar M3 clock pill: robust against locales/formats with seconds
    (splits on am/pm markers instead of fixed part positions) - PR #27 by
    Reazndev.
  - Night light rework adopted: on startup the service syncs with what is
    actually running instead of force-enabling inside the night window;
    our cold-start launch-flags fix is re-grafted on top.
  - Background clock quote now only shows for pixel/cookie clock styles.
  - Discarded: upstream's full clipboard wipe (would destroy our pinned
    entries - our pins-aware wipe stays), upstream's lock workspace-move
    niri gating (our lock pushes content visually and never touches
    compositor workspaces), upstream's removal of the VPN/Tailscale quick
    toggles. Upstream literals tokenized onto the spacing scale per merge
    policy; record.sh's monitor detection gained the niri branch inside
    our gpu-screen-recorder implementation.

## [0.3.1] — 2026-07-31

### Fixed
- Session screen: "Reboot into..." was unreachable by keyboard (no
  downward path led to it) and sat orphaned on its own row. The grid is
  now a symmetric 3x3 - session actions on top, power actions
  (Shutdown / Reboot / Reboot into...) on the bottom row - with a full
  arrow-key navigation map. The boot-entry pills themselves are now
  keyboard-navigable too, and the picker was restyled twice over: entries
  now stack under the grid clamped to its width (the pill row overflowed
  sideways), Down walks the list / Up returns to "Reboot into...", the
  focused entry fills primary (the current OS stays tonal), Enter reboots
  into it, and the opener button shows a toggled state while open.

## [0.3.0] — 2026-07-31

### Added
- **Selective EFI reboot** in the session screen: a "Reboot into..." action
  (shown only when the firmware exposes more than one permanent boot entry)
  expands a picker of EFI boot entries - transient USB/CD/network entries
  filtered out, current entry marked - and picking one sets `BootNext` via
  `pkexec efibootmgr -n` (polkit prompt) before rebooting straight into
  that OS. Firmware-level, so it works with GRUB, systemd-boot and Windows
  Boot Manager alike; parser covered by node-executed contract tests.
- **Plymouth boot splash** (opt-in installer component, Arch/mkinitcpio):
  a minimal Material-style theme (`sdata/plymouth-theme/immaterial-impulse`)
  with the suite wordmark, a rotating arc spinner, and a text-free LUKS
  password prompt (lock glyph + bullets - no fragile label-plugin dependency
  inside the initramfs). `setup` gains a PLYMOUTH component /
  `INSTALL_PLYMOUTH=1`: installs plymouth, copies the theme, adds the
  mkinitcpio hook (with backup and self-restore), and rebuilds the
  initramfs; the kernel-cmdline `quiet splash` change is printed, never
  auto-applied.

### Changed
- Scheme picker chips preview the colors they would apply, Android-12
  style: a new `scheme_preview.py` quantizes the current wallpaper once
  and derives primary/secondary/tertiary swatches for every Material
  scheme variant (~0.2 s in the color venv); each chip renders them as a
  segmented palette circle (top half primary, quarters secondary/
  tertiary) with the full scheme name below and a ring + check badge on
  the selected one. Refreshed on wallpaper and dark/light changes; falls
  back to the scheme icon when the venv is unavailable.
- Quick settings' Wallpaper & Colors section restyled: scheme chips are
  uniform tonal cards with centered icon+label (no more diagonal
  icon/label scatter), selection animates color and relaxes into a pill,
  the Light/Dark pair matches the same container family with horizontal
  content, and the cramped 2px gaps grew into the spacing scale.
- Screen recorder rebuilt on **gpu-screen-recorder** (GPU encode - NVENC/VAAPI,
  ShadowPlay-style), replacing wf-recorder's CPU x264 path:
  - Same interfaces as before (bar record button, region-selector record
    actions, `Super+Shift+R` / `Ctrl+Alt+R` binds, `record.sh --region/
    --fullscreen/--sound/--path`), now driven by config: quality preset,
    codec (auto/H.264/HEVC/AV1), FPS, framerate mode, cursor, desktop audio
    and optional mic merge - all in Settings → Services → Screen recorder.
  - **Instant replay** (`ScreenRecord` service): a persistent ring-buffer
    daemon keeps the last N seconds (default 120, RAM or disk); save a clip
    with `Alt+F10`, the bar button that appears while replay is armed, or
    `qs -c imi ipc call record replaySave`; toggle with `Shift+Alt+F10`, the
    settings switch, or IPC. Enablement is persisted config, so replay
    survives restarts; a failing daemon disables itself instead of
    respawn-looping.
  - Recording pause/resume (`Ctrl+Alt+R` family unchanged; pause via
    `quickshell:screenRecordPause` global or `record pause` IPC, SIGUSR2).
  - One-shot recordings and the replay daemon are separate gsr processes;
    the record toggle and pause are pidfile-scoped so they can never kill
    the replay buffer. Saved-file notifications come from gsr's `-sc` hook
    with the real path (replay clips included).
  - Suite dependency lists switched from `wf-recorder` to
    `gpu-screen-recorder` (arch/fedora/gentoo/nix).
  - The bar's privacy pill now also shows shell-owned captures: a
    `screen_record` icon while a recording runs (with pause state in the
    hover popup) and a `replay` icon while the instant-replay buffer is
    armed. An **Instant replay** quick toggle joins both right-sidebar
    styles (Android grid: drag it in from the unused set; classic panel:
    always present) - toggle to arm, long-press to save a clip.

## [0.2.0] — 2026-07-31

### Fixed
- Selected icon pack reset by "Update Dots": the dots sync ships a
  `kdeglobals` with `[Icons] Theme=breeze-dark`, overwriting the theme the
  user picked in Settings → Interface → Icon pack (the selection itself
  survives in the shell config; it just never got re-applied). The installer
  now re-applies `appearance.iconTheme` via `apply-icon-theme.sh` after
  every file sync, best-effort.
- About page PC-spec cards stuck on "Loading..." until visiting another
  section: the specs refresh fired on a hardcoded page index (7) that went
  stale when the Plugins page shifted About to 8. The trigger now targets
  the last page by position, and a test pins SettingsContent against
  hardcoded `currentPage` indexes.
- Broken icons (raw "VIDEO_TE□LATE"-style ligature text) in the desktop menu's
  Live Wallpaper entry, the live-wallpaper folder setting and the sidebar
  settings' Media Player card: the SDDM theme ships an older Material Symbols
  Rounded copy that fontconfig can pick over the system font, and it predates
  the `video_template`/`music_note_2` names. Renamed to `animated_images` /
  `music_note`, and a new lint (`tests/lint_material_icons.py`) validates
  every literal icon name against the GSUB ligatures of EVERY installed copy
  of the font so stale-font breakage can't sneak back in.

### Added
- About page "What's new" card: renders the changelog of the installed suite
  checkout (`~/.local/share/immaterial-impulse/src/CHANGELOG.md`, the copy
  get.sh refreshes on Update Dots) as collapsible Markdown, bounded to the
  newest two sections, with a Full-changelog link to GitHub. Hidden when the
  checkout or file is absent.
- Drop Shelf is now a bundled **plugin** (`drop_shelf`, enabled by default)
  with Dropover-style summoning (see `docs/dropshelf-shake-research.md`):
  - **Mid-drag summon**: `Super+U` (Hyprland `quickshell:dropShelfSummon`
    global shortcut) or `qs -c imi ipc call dropShelf toggle` opens the shelf
    under the cursor — works while dragging files, so the in-flight drag can
    be dropped straight onto it.
  - **Drag-to-bar reveal**: dragging files onto the bar pops the shelf out
    below it (the Wayland-native trigger — a `DropArea` learns of a drag the
    moment it crosses a shell surface); dropping on the bar itself also
    stashes the files.
  - **Shake to summon** (opt-off by default): a helper polls the Hyprland
    request socket (raw socket, ~0.03 ms/query at 60 Hz) and recognizes
    ≥3 fast horizontal direction reversals with extrema-based leg tracking
    (`scripts/dropshelf/shake_detector.py`, pure-logic detector covered by
    `tests/test_dropshelf_summon.py`). Paused while locked or a fullscreen
    app is focused. Wayland offers no global "drag in progress" signal, but
    every pointer drag holds the primary button — the gesture is armed only
    while BTN_LEFT is down (global state read via the `EVIOCGKEY` evdev
    ioctl; needs `input`-group membership, degrades to always-armed
    without it), so shaking a free cursor does nothing.
  - A summoned shelf **auto-dismisses** (default 5 s, configurable) unless
    hovered, dropped on, or holding items.
  - **Blur-able background**: the shelf tint's opacity is configurable and
    the compositor blurs behind every `quickshell:*` layer, so lowering it
    frosts the shelf; both knobs live in the plugin's settings along with
    bar-reveal, shake, sensitivity and auto-dismiss options.
  - The desktop-menu "DropShelf" entry and the bar reveal hide when the
    plugin is disabled; the shelf window is created lazily on open.
- Discord voice: one-shot companion installer
  (`scripts/discordVoice/install_companion.sh`) — auto-detects Vesktop and
  Equibop (`--client` to pick), clones and builds the matching mod (Vencord /
  Equicord, same plugin API) with the End4DiscordVoice user plugin, and
  points the client's custom-mod location at the build (backing up
  `state.json` first). The Discord Voice popup gains a one-click **Install
  voice companion** button that runs the installer and streams its progress
  whenever the bridge reports the companion is missing; the bridge error
  also names the script. Official Discord still needs nothing; Legcord
  remains unsupported (bundled Vencord, no custom-location picker).
- Upstream merge (`pctrade/end4-pC`):
  - Desktop Notes widget: a flip-card notes list on the background (add, edit,
    swipe to delete; persisted in the shell state dir), toggle in
    Settings → Background widgets.
  - Live wallpaper preview (opt-in via `background.enableWallpaperPreview`):
    single-click or arrow-key navigation previews the wallpaper on the real
    background, double-click applies; preset apply clears any pending preview.
  - Dock-to-panel bar widget: drag-to-reorder pinned apps with animated slot
    translation.
  - Dock: the pinned-apps section and its separators hide when nothing is
    pinned; drag-ghost polish.
  - Screenshot while recording snips via plain grim+slurp instead of the
    region-selector UI (which doubles as the recording control), and the record
    keybind now stops a running recording. (Hardened over upstream: the save
    directory is passed as an argv element instead of interpolated shell text.)
  - Bar settings: the divider space-width spinbox is only enabled for the
    "space" divider style.
- Upstream feature sweep (first batch, from the `end-4/dots-hyprland` tracker):
  - GPU usage/temperature now works on AMD/Intel too (hwmon/sysfs fallback);
    the NVIDIA path is unchanged.
  - Bluetooth connect/disconnect button shows a "Connecting…"/"Disconnecting…"
    pending state while the operation is in flight.
  - Bluetooth device battery (upstream PR #3538): the quick-toggle tile status
    and tooltips now show the connected device's battery percentage (when the
    device reports one), matching the device-list dialog.
  - Calendar: configurable first day of week (Monday/Saturday/Sunday).
  - Bar: option to show only the current monitor's workspaces
    (`bar.workspaces.showAllMonitors`).
  - Weather: provider choice (OpenWeatherMap or keyless wttr.in) and a
    user-settable OWM API key (falls back to the built-in key when empty).
  - Caps Lock / Num Lock on-screen display (toggle: `osd.lockKeys`).
  - Clipboard pinning: pin entries so they stay on top and survive "wipe all".
  - Clipboard clear buttons (upstream PR #3546): the launcher's clipboard view
    gains a header with "Clear results" (deletes only the entries matching the
    current filter) and "Clear all" buttons, plus an empty-state hint; both
    respect pinned entries, and deletions go to `cliphist delete` over stdin.
  - File/folder search in the launcher (`~`-prefixed query, fd/find backed).
  - Lock screen: previous/play-pause/next controls on the media widget.
  - OLED screensaver (Settings → Interface): idle overlay with a full-black or
    a slowly-drifting dim clock mode; off by default.
  - NetworkManager VPN toggles in the right sidebar plus a bar status icon.
  - Automatic dark/light theme switching by time — sunrise/sunset or fixed
    times (Settings → Wallpaper & Colors); off by default.
  - ICS calendar: load events from local `.ics` files and remote ICS URLs and
    mark days that have events in the sidebar calendar.
  - Bar "Timer" pill (add via Settings → Bar): a dynamic-island pill showing a
    running pomodoro/stopwatch, opening the sidebar on click.
  - Privacy indicator (in the default right bar): an alert pill that appears
    only while an app is using the microphone, camera, or sharing/recording the
    screen, listing the source in a hover popup. Each signal's icon and the pill
    ease in and out.
  - Notes plugin (bundled desktop widget): a persistent, autosaving notepad
    that shares the notes scratchpad with the overlay notes editor.
  - Hyprland submap indicator (upstream PR #2225, in the default right bar): a
    pill with a keyboard icon and the submap name that appears while a keybind
    submap (e.g. resize) is active and eases out when it resets; icon-only in
    the vertical bar. Tracked by the new `HyprlandSubmap` service.
  - Dock: right-click context menu on app icons (upstream PR #3045) —
    desktop-entry actions (e.g. "New Window"), open new instance, move all of
    an app's windows to a workspace, pin/unpin, and close window(s). Window
    previews are suppressed and the dock stays revealed while the menu is open.
    (Drag-to-reorder of pinned apps, the PR's other half, already exists here.)
  - Tailscale (upstream PR #3501, reworked for the sidebar): a quick toggle
    next to the VPN toggles (both classic and Android styles) that brings
    Tailscale up/down, plus an exit-node dialog (right-click / tile menu)
    listing peers that advertise themselves as exit nodes — online first, with
    a "None (direct)" row — applied via `tailscale set --exit-node=…` with a
    one-shot `pkexec` fallback for non-operator users. Backed by the new
    `Tailscale` service polling `tailscale status --json`; hidden entirely
    when the CLI isn't installed.
  - OpenRGB accent sync (upstream PR #3415, reworked as a plain CLI call): an
    opt-in toggle (Settings → Quick) that applies the Material You accent
    color to RGB hardware whenever the palette changes, debounced, via
    `openrgb --mode static`; silently inert when the binary is missing.
    Individual devices can be excluded from the sync with per-device switches
    under the toggle (`appearance.openrgb.excludedDevices`, keyed by device
    name so paired hardware like RAM sticks toggles as one).
    An optional ambient mode (`appearance.openrgb.colorSource: "monitor"`)
    instead follows the focused monitor's dominant on-screen color — by
    default only while a fullscreen app runs (games, video), snapping back to
    the accent on exit. Sampling is a low-rate grim capture reduced by
    Quickshell's ColorQuantizer, with a deadband and optional smoothing so
    near-static scenes produce no device writes; needs `grim`, silently inert
    without it. The shell manages an `openrgb --server` for the streaming
    writes (serverless CLI calls re-detect hardware every time, resetting
    devices to white), and excluded devices are kept out of OpenRGB's own
    detector list so the server never claims them — a claimed device loses
    its firmware lighting even without a single color write. GPU lighting is
    excluded from ambient writes by default (`monitorExcludedTypes`): GPU RGB
    rides the graphics i2c bus, and streaming to it mid-game stalls
    rendering; the ambient loop also scans devices once per activation
    instead of before every write. The bar's privacy indicator filters the
    sampler's once-a-second capture pulses (`bar.privacyIndicator.
    ignoreAmbientCapture`, default on) — real screen shares still show, since
    they hold their state past the pulse window.
- Component grid for desktop plugins: formalizes the nandoroid design-system
  grid (a 132×108 cell with a 12px gap) as `Appearance.sizes.widgetGridSpanX/Y`
  with an opt-in manifest `grid: { cols, rows }` that sizes a widget to whole
  cells so it tiles flush with the built-in widgets; the Notes widget is now a
  true 2×2 tile (276×228). Documented in `docs/widget-grid.md`.
  - Settings → Plugins now badges third-party (externally installed) plugins.
  - Presets: an Overwrite action on each preset card saves the current setup
    over that preset (two-tap confirm).
- Media plugin: the Next/Previous cog buttons now spin like cassette reels
  while media is playing (both clockwise, icons stay upright), easing back to
  rest on pause.
- Curated default configuration: fresh installs now seed `config.json` from the
  maintainer's tuned setup (sanitized of machine-specific state) instead of the
  bare upstream fallback defaults; existing configs are never touched.
- Icon pack selector (Settings → Interface): preview-grid cards rendering each
  theme's real icons, system-wide apply (GTK 3/4 `settings.ini`, `kdeglobals`,
  gsettings) with validation, and an automatic shell relaunch to adopt the pack.
- Verified-prebuilt Wallpaper Engine install path: on x86_64 the installer
  downloads a checksum-verified release tarball (seconds) and falls back to the
  source build on any mismatch; companion release CI lives in qs-wallpaperengine.
- Quiet-mode install is now cancellable (Ctrl-C cleanly stops the whole build).
- Frost mode toggle (tint vs true blur) for plugin backdrops in Settings → Plugins.
- README: palette showcase screenshots (Green / Study / Red).
- README translations: Simplified Chinese (`README.zh-CN.md`) and Japanese
  (`README.ja.md`), with a language switcher linking all three.
- Dock feedback motion (M3 Expressive): hover lift, press squish, a launch
  bounce that runs until the app's window appears, an appear pop for new
  icons, and springing active-window dots — consistent across pinned and
  running apps, all on Appearance motion tokens.

- Test coverage sweep: 16 new suites covering the installer's destructive
  paths (rsync --delete sandboxing, legacy package removal, cancel traps),
  the color pipeline (lock/desktop palette parity, scheme detection,
  generator goldens), the keybind cheatsheet parser, momentum scrolling,
  and always-on services (Battery, Bluetooth, Updates, Brightness,
  SystemInfo, ConflictKiller, Polkit, Ydotool) - plus three previously
  orphaned suites now actually running in CI.
- Screenshot result popup (bundled plugin): every screenshot - region snip or
  Print keybind - pops a preview with save / annotate / discard actions;
  auto-dismisses, hover pins it. The plugin platform's `panel` entry point is
  now actually instantiated (PluginPanelHost), so plugins can ship
  free-floating surfaces.
- Centered Wallpaper now shows live Wallpaper Engine content inside its shape
  (centre-cropped from the same surface the blur/lock shaders sample, so no
  second renderer), falling back to the static/thumbnail image when no live WE
  surface is drawing.
- Experimental updater (`./setup exp-update`) now reports how many updates are
  available before pulling and prints the new CHANGELOG entries under a
  "What's New" heading after a successful update.
- Plugins settings: each plugin and its options are now one unified rounded
  card (header, hairline divider, then its option toggles as part of the same
  surface) with clear gaps between plugins, and the plugin name is larger and
  heavier so it reads as the card's heading.
- Plugin store (Settings → Plugins → Browse plugins): browse, search, and
  filter a curated catalog of community plugins and install or update them in
  one click through the existing hardened installer. Entries come from a new
  registry repo (`XephyLon/imi-plugin-registry`) whose CI cross-checks each
  entry's metadata against the plugin's actual manifest, so the permissions
  shown in the install confirmation dialog are verified, not self-reported.
  Update badges (semver against the installed version) appear on the Plugins
  page and on installed plugins' cards, with an "Update all" queue in the
  store. The installer gains `--upgrade` (stage, verify, then atomic swap with
  rollback) and writes a `.store.json` provenance sidecar after every install.
  The store UI ships gated off behind `plugins.storeEnabled` (config-file-only,
  default false) until the public registry goes live. Documented in
  `docs/PLUGIN_STORE.md`.

### Fixed
- Bar and dock media widgets broke on Arabic (RTL) track metadata: the text
  auto-aligned to the right edge away from the artwork, and Arabic's taller
  line box overflowed the fixed-height card, clipping the lines top and
  bottom. Text is now left-anchored with fixed, vertically-centered line
  slots so every script lays out like Latin.
- "Keep system awake" sometimes still let the session lock and hibernate: the
  idle inhibitor was bound to a 0×0 surface that maps unreliably, so Hyprland's
  ext-idle-notify (read by hypridle) intermittently ignored it. It now uses a
  reliably-mapped 1×1 transparent background-layer surface.
- Upstream bug sweep (audited `end-4/dots-hyprland`'s tracker against our fork,
  fixed the ones still present):
  - Sidebars/panels no longer "blink" open then instantly shut — a transient
    focus-grab clear from a ToplevelHandle activation is now debounced.
  - Launcher/app search no longer pegs a core: the app list is deduped in O(n)
    instead of O(n²) on every desktop-entry change.
  - Hyprland data refresh is debounced, so spawning apps (e.g. kitty) or fast
    workspace switches no longer stutter the UI by spawning `hyprctl` per event.
  - The battery widget no longer flaps in/out and no longer fires false
    low-battery notifications (or auto-suspend) when UPower transiently swaps its
    display device.
  - A fully-bracketed song title (e.g. `[BLEED BLOOD]`) shows the real title
    instead of "No media".
  - The cheatsheet no longer double-lists a keybind defined in both the default
    and custom Lua configs; custom now overrides default.
  - An offline random-wallpaper fetch can no longer corrupt config by persisting
    a truncated/missing wallpaper path.
  - Base installs (without Wallpaper Engine) now also launch the shell with the
    threaded render loop, so a GPU-saturating process can't freeze it.
  - Notification popups wait a short grace period before hiding on unfocus, so a
    brief cursor flicker no longer dismisses them.
  - With bar auto-hide on, the media box and tray-overflow popup are no longer
    orphaned above a hidden bar (new `bar.autoHide.dismissPopups` option).
  - The screen-corner "absolute corner" hover no longer opens the sidebar when
    "Hover to trigger" is turned off (it is a sub-option of it).
- Experimental updater failed to detect/report updates that existed: its change
  detection keyed off the reflog's `HEAD@{1}`, which a preceding stash or
  detached-HEAD checkout silently repointed. It now captures a stable pre-pull
  baseline SHA and counts incoming commits straight from refs (`git fetch` +
  `git rev-list --count`).
- Terminal background settings note that the pattern applies to the Kitty
  terminal only.
- Lock-screen palette could differ from the desktop's for the same image: lock
  color generation passed `--smart` (silently swapping the configured scheme to
  neutral on low-chroma images) and hardcoded tonal-spot for `auto` instead of
  running the same image-based detection as the desktop.
- Wallpaper Engine wallpapers were permanently mute: the embedded renderer
  hardcoded `--silent` and the selector's volume button toggled a flag nothing
  read. The button now drives the new `audioEnabled` surface property (toggling
  reloads the wallpaper - audio is a load-time decision inside WE).
- Multi-second shell freezes on wallpaper/preset switches, root-caused to three
  compounding issues: Qt's basic render loop on NVIDIA/Wayland blocking the GUI
  thread on embedded-WE video GL (fixed via `QSG_RENDER_LOOP=threaded` in the WE
  wrapper); kde-material-you re-applying the unchanged icon theme every switch
  (dropped `iconslight`/`iconsdark`); and Quickshell rescanning every `.desktop`
  file on any parent-directory churn, stalling the UI in multi-second QML GC
  pauses (patched in qs-wallpaperengine's bundled Quickshell). Cycling all four
  presets went from 11 UI stalls (up to ~4.8 s) to none.
- MPRIS artwork, favicon, weather, wallpaper-download and AI-request fetches no
  longer splice external values into `bash -c` strings (command-injection
  hardening; values now passed as arguments).
- Cookie clock (and other draggable desktop widgets) follow preset position
  changes again instead of ignoring them or snapping back while dragging.

## [0.1.0] — 2026-07-23

First versioned release of the unified suite (the `Immaterial Impulse` fork of
illogical-impulse), collecting the work done to date:

### Added
- Unified repo: the Quickshell shell, full Hyprland config, and a `whiptail`
  installer in one tree, superseding a prior illogical-impulse install (with
  first-run config-dir + keyring migration).
- Optional installer components: Wallpaper Engine (custom Quickshell build) and
  the `ii-sddm-theme` SDDM login theme.
- Plugin platform (declarative + package plugins), Material You theming extended
  to cava/tmux, and the Caelestia animation preset.
- Wallpaper Engine wallpaper picker with type-filter chips.
- Automatic Hyprland animation-preset loading; restored keybind cheatsheet
  (`Super`+`/`).
- This changelog and versioning.

[Unreleased]: https://github.com/XephyLon/immaterial-impulse/compare/v0.10.0...HEAD
[0.10.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.9.2...v0.10.0
[0.9.2]: https://github.com/XephyLon/immaterial-impulse/compare/v0.9.1...v0.9.2
[0.9.1]: https://github.com/XephyLon/immaterial-impulse/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.6.1...v0.7.0
[0.6.1]: https://github.com/XephyLon/immaterial-impulse/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/XephyLon/immaterial-impulse/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/XephyLon/immaterial-impulse/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/XephyLon/immaterial-impulse/releases/tag/v0.1.0
