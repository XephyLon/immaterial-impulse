# Duplicated components — the repo-wide census

Status: inventory only, nothing swept. Compiled 2026-08-28 from two
read-only surveys of `main` @ `8df7e3e93`. Supersedes nothing; the Phone
tab's own consolidation plan is
[`phone-tab-component-consolidation.md`](phone-tab-component-consolidation.md).

## The scale

- **282 QML files / 56,437 lines** under `modules/imi/`, plus 181 shared
  widgets and a 70-file vendored mirror under
  `modules/common/plugins/designsystem/widgets/`.
- **~105–110 of the 282 files (38%)** carry at least one hand-rolled
  instance of a shape the shell already ships.
- **~4,500–5,500 lines** of duplicated presentational QML in `modules/imi/`,
  plus **7,034 lines** of unreachable code in the designsystem mirror.
- **12 shape families.** Two of them have a *split canonical supply* that
  must be resolved before any call site is touched.

## Start here: six fixes that landed on one copy and not its sibling

Each verified against `git log -S` and the commit's own `--stat`. These are
live defects, not tidiness, and they are the argument for the whole sweep.

1. **The weather glyph.** `fix(weather): resolve icons against the provider
   that reported the code` touched `Icons.qml`, `WeatherPopup.qml` and the
   test; `WeatherHourlyChart.qml` was fixed later; **`bar/WeatherBar.qml`
   never was** — it still calls `Icons.getWeatherIcon(Weather.data.wCode)`
   at four sites. On OpenWeatherMap the bar draws a clear sky while the
   popup directly beneath it draws the thunderstorm.
2. **The Material-pill blacklist forked.** `bar/BarContent.qml` lists
   `timerPill`, `privacyIndicator`, `submapIndicator`;
   `verticalBar/VerticalBarContent.qml` lists `media` instead. Two commits
   touched only the horizontal one, so on a Material **vertical** bar four
   widgets that draw their own pill get a second one painted behind them,
   and `media` gets the reverse.
3. **`DialogListItem` never got the content-padding fix.** The commit that
   introduced `WindowDialog.contentPadding` to stop the padding drifting
   left `horizontalPadding: Appearance.rounding.large` (23) in place, while
   the dialogs moved to `space400` (32). Four dialogs — Wi-Fi, Bluetooth,
   Tailscale, Phone — have a **9px step down their left edge**, caused by
   the fix meant to prevent exactly that.
4. **`MarqueeText` reached three rows of four.** Wi-Fi, Bluetooth and the
   volume mixer scroll their long names; `TailscaleExitNodeItem.qml:43`
   still elides, matches the commit's stated rule word for word (a tailnet
   names several hosts off one prefix), and has no declining entry in
   `test_marquee_text_contract.py`'s reviewed register. It is also absent
   from `DesignSystemCompile.qml`.
5. **The `Toolbar` conversion skipped a sibling.** `OptionsToolbar` and
   `RecordingRegionPanel` were converted; `regionSelector/AnnotationToolbar.qml`
   has never been touched on its own merits — and `RegionSelection.qml`
   mounts *both* on the same canvas in one session, at 56px with a shadow
   and 48px without.
6. **The cross-coupled card heights.** `c0c4ee6e3` rewrote `+ 24` as
   `space150 * 2` in three lines of `QuickConfig.qml`; nine other cards
   (five in `SidebarsPanelsConfig.qml`, plus a seventh spelling at `+ 28`)
   still carry the literal. Equal today; silently split the moment the inset
   is retuned.

Two more of the same kind, from the mirror census: the `opsz` font-engine
quantization and the notification blur-region fix each landed on the
mainline copy only.

## Standalone fixes worth making regardless of any sweep

- **`WaveVisualizer` violates the cava contract on the live path.**
  `modules/common/widgets/WaveVisualizer.qml:11` hardcodes
  `maxVisualizerValue: 1000`; the *dead* designsystem copy reads
  `CavaService.maxValue` correctly. `test_cava_contract.py` misses it
  because its gate skips any file not naming `CavaService.values`.
- **`enum Shape` is hand-maintained in two copies and already differs** —
  38 entries in the designsystem, 37 in mainline. QML enum members are
  ints; the shared prefix agreeing is luck. An insertion anywhere but the
  tail renumbers one copy silently, and shapes resolve through stored and
  manifest values.
- **`bar/UtilButton.qml` is an `Item` + `MouseArea`**, and `UtilButtons.qml`
  declares every button twice — once as that, once as `CircleUtilButton`
  (a real `RippleButton`). On `cornerStyle === 3` **eight actions are
  keyboard-dead**; on any other style they are not.
- **`bar/CircleUtilButton.qml` is byte-identical** to the shared widget and
  shadows it by same-directory resolution.
- **`AttachedFileIndicator` exists twice** and `sidebarLeft/AiChat.qml`
  imports both modules — which one draws depends on import order. The
  shared copy has a `highlight` property the local one lacks, and is the
  one that does *not* draw.
- **`ScrollToBottomButton.qml:44` writes `font.pixelSize` on a
  `MaterialSymbol`**, destroying `MaterialSymbol.qml:22`'s
  `pixelSize: iconSize` binding: the glyph draws at one size while `opsz`
  is computed from another. The only site in the tree doing this.

## The twelve families, ranked

Ranked by what a user loses, not by line count.

1. **The button** — highest copy count and the only family whose cost is
   *access*: eight bar util buttons, three settings tile grids, the icon
   picker, both Android toggle badges, the lock media buttons, three bar
   pills, the Phone feature card — none keyboard-reachable.
   `lint_clickable_cursor.py` already mechanised one symptom for one
   directory; outside the bar there are 37 clickable raw `MouseArea`s, 19
   with no `cursorShape`. **Supply is split** (`RippleButtonWithIcon` vs
   `IconAndTextToolbarButton`) and must be reconciled first.
2. **The catalogue row** — ~22 hand-rolled copies of `CatalogueRow` across
   15 files, with measured drift in sub-label spacing, description colour
   and the `titleFillsWidth`/`titleElides` split the component was
   extracted to settle.
3. **The dialog's content padding** — one line, four dialogs (item 3
   above). Cheapest correct change in the census.
4. **The bar written twice** — five idioms for "draw this in a column",
   two live bugs (items 1 and 2), and 124 dead lines in `Resources.qml`
   whose cause is `BarWidgetSwitcher` requiring four `Component`s with no
   fallback.
5. **The notice banner** — ~20 hand-rolled instances; `NoticeBox` has zero
   users outside `welcome.qml` and the Phone tab. Several messages
   physically cannot wrap today (`ServicesConfig.qml:636`,
   `SessionScreen`'s clipped `DescriptionLabel`, the OSD banner that
   widens instead of wrapping).
6. **Lists, flickables and scrollbars** — 16 surfaces bypass
   `StyledListView`/`StyledFlickable` and therefore ignore the user's own
   `Config.options.interactions.scrolling` settings; three hand-rolled
   scrollbars; a raw `Text` beside `NativeRendering` code in the same
   gutter.
7. **The toolbar over a canvas** — three hand-rolled against two correct,
   one of them beside its converted sibling in the same directory.
8. **The titled card** and **the empty state** — large copy counts, latent
   drift (`space150 * 2 == 24` today; no placeholder is currently squeezed
   enough for the `dropIconWhenCramped` guard to bite).
9. **Badges and pills** — **supply split four ways** (`Badge`, `FilterChip`,
   `Pill`, `MaterialPill` — the last with zero call sites anywhere).
   Resolve the overlap before touching call sites.
10. **The metric card** — three copies with three different warning
    thresholds; the overlay's resources widget never turns red.
11. **The notification card and its swipe** — the proposal's subject; the
    arithmetic is in its fifth copy.

## The vendored mirror

`modules/common/plugins/designsystem/widgets/` (70 files, 10,239 lines) is
a third-party expressive widget library (nandoroid, AGPL) imported
wholesale. **It is not protected**: no plugin isolation, no frozen API, no
sandbox, no qmldir constraint. 64 of the 70 import `qs.modules.common`
anyway; its own `RippleButton` imports `qs.modules.common.widgets`; and ten
files import **both** mirrors in one compilation unit, told apart only by
an `Expressive.` alias.

- **54 of 70 files — 7,034 lines, 69% — are unreachable** from any live
  entry point, and are compiled and maintained every suite run.
- **Only 3 pairs** (`MaterialShape`, `MaterialSymbol`, `StyledText`) are
  reached by name from outside the mirror.
- **13 widgets are live and have no mainline counterpart** — the four
  `Desktop*Widget` entry points, `SpanTravel`, `SpanFade`, `WidgetCard`,
  `WidgetElevation`, `CustomIcon`, `StyledSlider`, `StyledToolTip`,
  `StyledToolTipContent`, `WavyLine`. These *are* the design system.
- The precedent for deleting the rest already exists and is written down:
  `tests/lint_no_stale_widget_canvas.py` — *"the point is to fail on it
  while it is still dead, which is the state nothing else in the suite can
  see."*

## Two lint holes the census exposed

- **`lint_spacing.py` cannot see the designsystem dialect.** It has no
  exemption and passes — because its matcher only fires when the whole
  right-hand side is a bare integer, and `6 * Appearance.effectiveScale` is
  an expression. 667 of the tree's 674 `effectiveScale` references live in
  the mirror.
- **It also misses the group form.** `PROP` matches only dotted
  `anchors.margins`, anchored at line start, so
  `anchors { fill: parent; margins: 14 }` escapes entirely. Exactly one
  site walks past it — and it is a seventh copy of the settings card.

## Dead supply

Eleven shared widgets have **zero call sites anywhere** (~591 lines):
`AddressBar`, `CalendarView`, `ThemeCarousel`, `CircularProgress`,
`StyledPopupMenu`, `Fab`, `MaterialPill`, `NavigationRailExpandButton`,
`BarIsland`, `BoxLayout`, `VibrantToolbarButton`. Plus
`bar/StyledPopupHeaderRow.qml`, whose sibling has five users and whose own
header is hand-rolled three times inside `PrivacyIndicatorPopup.qml`.

`StyledPopupMenu` is worth its own look: AGENT.md names it as one of
`quickshell:popup`'s two live surfaces, and nothing instantiates it —
either the doc is stale or a surface stopped being built.

## Where duplication is legitimate

Recorded so a sweep does not flatten something deliberate:

- The two quick-toggle styles — the behaviour is already shared in
  `common/models/quickToggles`; the two presentations are a user choice.
- `AndroidQuickToggleButton`'s icon chip — its chip is an independent hit
  target; `CatalogueRow` is deliberately non-interactive.
- `QuickSliders`' own slider — carries the entrance fill-sweep state
  machine; the dialog case correctly uses the shared one.
- The OSD `indicators/*.qml` — nine short config files over two shapes.
  (The two *shapes* disagree about shadows; the config files are fine.)
- `Repeater` rather than `StyledListView` on settings pages — `ContentPage`
  is a `StyledFlickable`, and nesting a view steals the wheel.
- `ConfigSwitch`'s write-back at 159 call sites — the call site owns the
  value by design (#158).
- The clock-depth `#ffffff`/`#101010` — every `Appearance` colour is
  derived from the wallpaper, so a token there is a colour the picture
  already contains. (Their *sizes*, 18 vs 22, are drift.)

## Sequencing

1. The six one-sided fixes and the standalone defects above — small, each
   independently correct, no supply questions.
2. Resolve the two split supplies (button; badge/pill).
3. Sweep the families in rank order, deletions first.
4. Delete the mirror's unreachable 54 files, with their `qmldir` lines and
   the per-lint special cases that name them.
5. **Then** the lint — a ratchet over a tree that is already clean.
   `tests/test_shared_widget_contracts.py` is the natural home; no check
   anywhere currently enforces "use the shared component."

## Coverage

Both surveys were explicit about gaps. `bar/` 45 of 51 read in full;
`sidebarRight/` all 67; `overlay/` 17 of 18; `settings/` 4 in full and 18
scanned by primitive; `background/`, `notificationPopup/`, `screensaver/`,
most of `editMode/` and six `aiChat/` files not opened. The mirror census
read full body diffs for 9 of the 38 pairs and characterised the rest by
declarations; it did not do a shape-similarity pass for copies under a
different name.

Neither census would catch duplication that hides *without* raw
primitives — two pages configuring one shared component with divergent
property sets. One instance was found by hand (`PluginsPage` vs
`PluginStorePage` byline placement); there are likely others.
