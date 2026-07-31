# Research: Settings menu structure and reorganization

State of Settings as of v0.4.0, whether it needs reorganizing, and what a
reorganization should look like. Research only - nothing here is implemented.

## Verdict up front

Yes, it needs it - not a rewrite, a re-shelving. Navigation (rail + search +
per-section deep links) is solid; the taxonomy is not. Two pages ("Interface",
"Services") are junk drawers whose names predict nothing, appearance controls
are spread over four pages, and several features live where they were easiest
to add rather than where a user would look (notifications under Bar, OpenRGB
only in Quick, the recorder under Services). Search papers over most of this,
which is also why it drifted so far.

## Current map (9 pages, ~280 controls)

| Page | Lines | Controls | Sections |
|---|---|---|---|
| Quick | 789 | ~25 | Wallpaper & Colors (scheme circles, light/dark, transparency, auto dark/light, **OpenRGB sync**, light color source), Bar & Screen |
| General | 754 | 41 | Time, **Left/Right Sidebar + Quick toggles + Sliders + Corner open**, Battery, Audio, Sounds, Language, **Work safety** |
| Bar | 692 | 45 | Screens, Bar layout, Positioning, **Notifications**, Tray, Divider, Utility buttons, Workspaces, Resources, Media, Tooltips |
| Desktop | 1050 | ~35 | Wallpaper, Centered wallpaper, Clock (3 styles), Quote, Custom Image, Widgets, Canvas |
| Plugins | 443 | - | Available plugins + per-plugin options (Drop Shelf lives here) |
| Interface | **1146** | **73** | Terminal bg image (stray top-level), Overview, Dock, **Icon pack**, Lock screen, Overlay + Crosshair + Floating image, Region selector, OSD, Wallpaper selector, **Fonts**, Terminal, Screenshot popup, **Color generation**, Keep awake, Screensaver |
| Services | 761 | 40 | AI, Networking, Music recognition, **Screen recorder + Instant replay**, **Save paths**, Search, Updates, Weather |
| Hyprland | 723 | ~35 | Displays, Layout, Input, Visual, Blur, Autostart, Animations |
| About | 371 | - | System info, updates, What's new |

## The problems, ranked

1. **"Interface" is a junk drawer.** 1146 lines, 73 controls, ~16 domains
   with nothing in common except "not placed elsewhere". Everything in a
   shell is interface; the name has zero predictive power. It is also the
   page that keeps absorbing new features by default (Screensaver, Keep
   awake, Screenshot popup all landed here historically).
2. **Appearance is fragmented across four pages.** Scheme/light-dark/
   transparency in Quick; Fonts, Icon pack, Color generation, Terminal
   theming in Interface; wallpaper in Desktop; Hyprland blur/rounding in
   Hyprland. "Where do I change the font?" has a four-page search space.
3. **Surface settings have no consistent home.** Bar gets its own page,
   Dock lives in Interface, both Sidebars + quick-toggle layout live in
   General, OSD/Overview/Overlay in Interface, Lock in Interface. The
   Bar/General/Interface trio is an accident of history, not a design.
4. **Notifications are hidden inside Bar.** Top-3 most-hunted setting in
   any shell; nobody's first guess is the Bar page.
5. **OpenRGB sync exists only in Quick.** Quick is meant to be a dashboard
   of shortcuts to full controls; for OpenRGB it is the only home, so a
   "quick" page carries sole ownership of a hardware integration.
6. **Capture is split.** Recorder + replay under Services; screenshot
   popup + region selector under Interface; save paths (recordings and
   screenshots together) under Services. One workflow, three pages.
7. **Vague page names compound it.** Quick/General/Interface/Services are
   four names that could each plausibly hold half the shell. Desktop,
   Bar, Hyprland, Plugins, About - the concrete names - are the pages
   that feel fine.
8. **Search-section metadata is hand-duplicated** in SettingsContent's
   pages list and has drifted twice already (the stale About index that
   broke spec loading; Drop shelf's missing nav entry). Any reorg should
   also kill this duplication, or at least pin it with a generated test.

## Proposed shape (Option A - domain-first, recommended)

Ten pages with concrete nouns; every rename is a re-shelving of existing
sections, no control changes:

- **Quick** - unchanged: dashboard of the most-used controls, each with a
  full home elsewhere. (OpenRGB moves its full home to Appearance and
  keeps a Quick shortcut.)
- **Appearance** - scheme picker, light/dark + auto, transparency, color
  generation, fonts, icon pack, terminal theming, OpenRGB sync.
- **Wallpaper & Desktop** - current Desktop page + wallpaper selector
  options + terminal background image (it configures wallpaper-derived
  art), clock styles, widgets, canvas.
- **Bar & Dock** - current Bar page (minus Notifications) + Dock.
- **Sidebars & Panels** - both sidebars, quick toggles, sliders, corner
  open, OSD, Overview, Overlay/Crosshair/Floating image.
- **Notifications** - promoted out of Bar; popup behavior + sounds.
- **Lock & Idle** - lock screen, screensaver, keep awake, work safety.
- **Capture** - screen recorder + instant replay, screenshot popup,
  region selector, save paths.
- **Services** - AI, networking, weather, music recognition, search,
  updates (now genuinely "things that talk to the outside world").
- **General** - time/language/battery/audio/sounds - the true globals.
- Plugins / Hyprland / About unchanged.

That empties "Interface" entirely (page deleted) and shrinks every page
under ~50 controls, with the worst (Appearance) still under 500 lines.

## Option B - minimal re-shelving (fallback)

Keep the 9 pages, move only the worst offenders: Notifications to its own
page, Capture assembled from Interface+Services, Fonts/Icon pack/Color
generation into Quick (renamed "Appearance"). Cheaper (a day) but keeps
"Interface" alive as a smaller junk drawer, and the vague-name problem
remains.

## Implementation notes (for whenever this is executed)

- Pure moves: every section is a self-contained ContentSection; moving is
  cut/paste plus import dedup. The per-page `goTo(term)` scroll contract
  and `sections:` metadata must move in lockstep - this is where the
  hand-maintained duplication bites, so do it per-page with the
  settings-navigation test run between moves.
- Config keys do NOT move (no migration needed); only QML placement.
- Search must keep matching old vocabulary: keep section titles stable
  where possible ("Icon pack" stays "Icon pack" wherever it lands).
- Kill the metadata drift while at it: derive the `sections:` arrays at
  build/test time from each page's ContentSection titles (the test
  already parses pages; inverting it into a generator is small), or at
  minimum extend `test_settings_navigation.py` to diff page contents
  against declared sections for every page (it already does this - keep
  it green per move, not per batch).
- Estimated effort: Option A ~2-3 sessions of mechanical moves + one
  visual pass; Option B ~1 session.
