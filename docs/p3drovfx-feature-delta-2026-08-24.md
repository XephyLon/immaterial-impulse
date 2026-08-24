# `P3DROVFX/ii-p3drovfx` — feature delta, 2026-08-24

> Date: 2026-08-24. Research only; nothing was ported.
> Source read: a fresh `git clone` of `https://github.com/P3DROVFX/ii-p3drovfx`
> at `e36428b9` (tip, 2026-08-24) — **226 commits** past `2e318c18`, the tree
> the full survey [`p3drovfx-research-2026-08-16.md`](p3drovfx-research-2026-08-16.md)
> read eight days earlier. This document is a delta against that survey, not a
> replacement for it: §1 re-scores the survey's shortlist against *our* tree
> today, §2 covers only what is new in *theirs* since `2e318c18`, and §3 is the
> merged shortlist. Their paths are relative to `dots/.config/quickshell/ii/`;
> ours to `dots/.config/quickshell/imi/`. Line counts are `wc -l` on the clone.
> Where a conclusion is reasoning rather than reading, it is marked **(inference)**.

---

## 1. The 2026-08-16 shortlist, re-scored against our tree today

Landed here since the survey (verified in-tree, not from memory):

| Survey # | Item | Where it landed |
|---|---|---|
| 1 | Anti-flashbang weak shader | dea752d04 ("fix(antiFlashbang): give the weak rung the shader it has always named") + `tests/lint_shader_paths.py` |
| 3 | XDG sound-theme engine | `services/SoundTheme.qml` + `services/sound_theme.js` + `scripts/sounds/scan-sound-themes.py` (8b31496c3, cbd8e707e, a3a8f65cf) — ours resolves through `Inherits=` with a cycle-safe walk and plays one `pw-play`, deliberately *not* their QtMultimedia player pool (see AGENT.md's sound-event entry for the measured cost of that pool) |
| 4 | Stable settings-page ids | 1c674c8f5 ("fix(settings): address a settings deep link by page id, not by its label") + `tests/test_settings_page_ids.py` |
| 6 | App-search frecency | `services/frecency.js` + `services/AppUsage.qml` |
| 7 | qalc gate + `Qt.callLater` result rebuild | `services/math_query.js`; `LauncherSearch.results` is a plain property with the `resultInputs` tracker |
| 12 | OLED saver completion | afb1c7ea5, a6c57a0b2, 83544dedb — key, per-monitor blank, idle inhibitor on the deliberate path only |

Still open from that shortlist, unchanged by anything in this delta —
PanelSchedule (#2), DNS-over-TLS (#5), launcher system controls (#8),
EasyEffects state verification (#9 — `services/EasyEffects.qml:32` still sets
`active = true` optimistically), local plugin registration + reload verb (#10),
timed keep-awake (#11), CommandsService (#13), `systemd-run` update log (#14),
scratchpad overlay (#15), quick-toggle draft/commit boundary (#16), dynamic
island (#17), screen-shader browser (#18), media downloader (#19), LocalSend
(#20 — but see §2.6, the blocker moved), dock live preview (#21), keyboard
backlight (#22), wizard (#23), video editor (#24), tiling assistant (#25),
phone notification mirroring (#26).

---

## 2. New in their tree since `2e318c18`

The 226 commits are dominated by three efforts: a Modes & Routines automation
engine, a ground-up AI assistant rebuild, and a dictation feature — plus a
steady stream of perf and icon-theming work.

### 2.1 Modes & Routines — the headline

`services/Modes.qml` + `services/modes/` (engine, ~1,600 lines: `ModeSchema.js`
pure `.pragma library`, `ModeWatcher.qml`, `ModeActions.qml`, 29 condition
watchers one file each) + `modules/ii/modes/` (editor UI) — **~11,800 lines
total** with `ModesConfig.qml` (510) as the settings page, a bar `ModeIndicator`,
a quick toggle in both toggle styles, an island widget and a mode-flash popup.
All Scrimas, 2026-08-21/22.

What it is: user-defined **modes** (Gaming, Work, Night…) that arm on
**conditions** — schedule, focused app, game running, battery, Wi-Fi SSID,
Bluetooth device, monitor set, fullscreen, locked, audio device, idle, workspace,
media playing, webcam/mic in use, Discord voice, phone connected, pomodoro,
calendar event, CPU/RAM, VPN, lid, weather, keyboard layout, pending updates,
notification, alarm, a keybind — every one negatable (`not: true`) — and run
**actions** when they engage/disengage: volume, per-app volume, audio device,
brightness, night-light temperature, bar/dock layout, Hyprland options, window
classes, launch/kill, files, notifications, sounds, phone actions, workspace
moves, other modes/routines. **Routines** are the same actions on triggers with
delays/pacing, with starter templates.

Fit for us: the *shape* is exactly this repo's — a pure schema module
(`ModeSchema.js` normalises everything and documents the QML-sequence
`Array.from` trap we know as 109e6d897), one small watcher per condition, each
reading a service we mostly already have (`HyprlandData`, `Battery`, `Network`,
`BluetoothStatus`, `Audio`, `MprisController`, `Weather`, `PhoneConnect`,
`Pomodoro`…). A port is a **rewrite against our services** (their watchers read
their service names), but the engine layer is small; the bulk is the editor UI
(~6k lines), which would be rebuilt on `CatalogueRow`/`GroupedList`/
`ConfigSwitch` anyway. This is the largest genuinely-new capability gap between
the trees after the island. **(inference on sizing:** engine+schema ~1,500
lines here, editor 2–3× that, plus the config schema block and tests.)

### 2.2 AI assistant rebuild

~60 commits rebuild their AI stack end to end: a provider/model **catalog**
(Claude and current Gemini added, "one dialect per format"), conversation
repository with every conversation kept, per-tool **permission scoping per
conversation**, an approval/review flow for tool runs, RAG (`ai_rag.py`),
OpenRouter and Ollama catalog browsing with model pulls, usage/cost dashboard,
a diagnostics page, and **shell-control tools**: window/workspace actions,
wallpaper/theme actions, media control, notes, reversible system controls,
reminders/calendar reads, read-only Gmail, ESPN scores, "attention" hooks that
connect runs to shell surfaces. Settings split into eight `configs/ai/` subpages.

Two things worth stating plainly. First, **they write tests now, for this
cluster**: `scripts/ai/tests/` and `scripts/tests/` hold ~60 `*_contract.py`
files — the survey's "their code arrives with no evidence that it works" is no
longer true of the AI stack specifically (there is still no CI running any of
it). Second, the credential posture the survey flagged is intact: Google OAuth
was *unified into* the plaintext `.env` (2026-08-19 "unify google OAuth
credentials in only one inside .env"), and Google Tasks joins it. Anything
taken from here still routes secrets through `services/KeyringStorage.qml` or
does not come.

For us this is a direction question, not a port: our AI sidebar is a fraction
of this. The transferable *shapes* are the provider/model catalog ("describe
providers and models in one catalog"), the per-tool permission vocabulary, and
the reviewed-mutation pattern (every shell-touching tool goes through an
explicit approval card). Large, its own proposal if ever wanted.

### 2.3 Dictation

`services/DictationService.qml` (750) + `scripts/dictation/voxtype_config.py` +
a bar indicator, an island widget and `DictationConfig.qml` (689). Push-to-talk
speech typed **into the focused window** through [voxtype] (external tool,
Whisper-based; the script does targeted TOML edits to voxtype's own config and
`voxtype setup` for models). Feature-detected the way our Clight/Tailscale are.
Clean candidate: small service, external optional dependency, no credentials.
The 689-line settings page would shrink a lot on our form controls.

### 2.4 Themed icons

`scripts/colors/recolor_icons.py` (954) + `services/IconThemes.qml` (62) +
`ThemedIconsConfig.qml` (118): tint the icon theme's app icons to the generated
Material palette, regenerate on wallpaper/base-theme change, with the KDE
quirks paid for in August's fix stream (SVG-only themes hiding generated PNGs,
raster tinting from the base theme, regeneration races on fast wallpaper
switches, and a revert pair around dock icons going blank — read those five
commits before porting, they are the trap list). We have an icon pack
*selector* (`IconPackSelector.qml`) and no recoloring. The script is standalone
and the service is thin; medium-sized, visually loud.

### 2.5 Workspace auto-compactor

`services/WorkspaceCompactor.qml` (120): closes numbering gaps in occupied
workspaces, with an Auto-Compact mode and a lock-screen guard (2026-08-21 fix).
Small, self-contained, `HyprlandData`-driven. Near-verbatim port material if
the behaviour is wanted.

### 2.6 LocalSend unblocked

The survey's Category-D objection to LocalSend was `localsend_scan.py` — a
254-thread /24 sweep with TLS verification off. That script is gone: 2026-08-19
"migrate to the official localsend-cli backend" + 2026-08-17 mTLS support, with
an installer script for the CLI. The feature now rides an official backend, so
the survey's #20 ranking ("their QML, our discovery") simplifies to "their QML,
the official CLI". Re-read `services/LocalSend.qml` at port time; the panel is
still theirs to rewrite.

### 2.7 Perf ideas worth auditing here, not porting

2026-08-23 "perf: shrink the shell's idle memory footprint" (~100 MB GPU
buffers) + "perf(background): decode the wallpaper at the display's real
scale". The itemised claims, each with an "ours?" note:

- **Screen-sized surfaces painting almost nothing** (their widget layer, their
  bar's full-height reservation). Ours already went through exactly this audit
  (the barPopup overlay stand-down, the background surface deliberately pinned
  mapped — AGENT.md's infinite-animation entry); nothing new to do.
- **Wallpaper decoded at file resolution.** Our `Background.qml:1166` sets
  `sourceSize` on one image; whether *every* wallpaper-file `Image` (lock,
  selector thumbnails, blur backdrops, greeter still) requests a bounded decode
  is worth one audit pass — with AGENT.md's frost caveat in mind: the frost
  shares a decode by matching the wallpaper `Image`'s whole request, so
  changing one request without the other un-shares the decode (33139b688).
- **Both panel families compiled at startup.** We have one family; not applicable.
- **Player pool built while sounds are off.** Ours spawns `pw-play` per event;
  structurally immune.

### 2.8 Smaller items

- **Classic quick toggles are editable now** (their classic style gained the
  catalog/editor treatment) — closes a gap between their two toggle styles;
  changes nothing for us.
- **Google Tasks** (`scripts/google_tasks/api.py` + a settings page) — joins
  the `.env` credential cluster; same verdict as Gmail/TickTick (survey §6).
- **Region-selector/screenshot perf** (Rilivaine): PPM freeze-frames for
  faster open, annotated export encoded through `magick`, skip the JS-side
  grab when nothing was drawn. Idea-level reading if our region selector ever
  feels slow to open; our capture stack is otherwise different.
- **"Keep left sidebar loaded" option** — we solved that class persistently
  (both sidebars' surfaces outlive the gesture since the EdgeSlide work).
- **Settings index generated out of process** + settings results in their
  launcher — we already ship settings search in ours by other means.
- **Presets: separate user data and protect credentials** — their repair of a
  presets hole ours does not have (our presets never carried secrets;
  wallhaven/unsplash/pexels keys live in the keyring).

---

## 3. Merged shortlist — what to migrate, ranked

The survey's ranking logic (user value per unit of work, sizes include the
check each needs) — with landed items dropped, the delta merged in, and one
re-rank from §2.6.

| # | Item | Status/why | Size |
|---|---|---|---|
| 1 | **PanelSchedule + PanelLoader tickets** (survey #2) | Unchanged; measure our startup first | Small |
| 2 | **EasyEffects state verification** (survey #9) | Our toggle still lies on a failed launch | Tiny |
| 3 | **Launcher system controls, two-step confirm** (survey #8) | Unchanged | Small-medium |
| 4 | **DNS-over-TLS** (survey #5) | Unchanged | Small |
| 5 | **Timed keep-awake** (survey #11) | Unchanged; epoch-deadline detail verbatim | Small |
| 6 | **Local plugin registration + reload IPC** (survey #10) | Unchanged | Small-medium |
| 7 | **Workspace auto-compactor** (§2.5, new) | Small, self-contained, real quality-of-life | Small |
| 8 | **Dictation via voxtype** (§2.3, new) | Optional external tool, clean detection story | Medium |
| 9 | **Themed icons** (§2.4, new) | Standalone script + thin service; read their August fix stream first | Medium |
| 10 | **In-UI update log via `systemd-run`** (survey #14) | Unchanged | Medium |
| 11 | **Quick-toggle draft/commit boundary** (survey #16) | Unchanged | Small-medium |
| 12 | **Dynamic island** (survey #17) | Unchanged; we own the morph engine | Medium-large |
| 13 | **Modes & Routines** (§2.1, new) | Largest new capability gap; engine small, editor big; wants its own proposal | Large |
| 14 | **LocalSend** (survey #20, unblocked by §2.6) | Official CLI backend removed the Category-D discovery script | Medium |
| 15 | **Media downloader / screen-shader browser / dock live preview / kbd backlight / CommandsService / scratchpad overlay** (survey #13/15/18/19/21/22) | Unchanged | Small→Medium each |
| 16 | **First-run wizard / video editor / tiling assistant / phone notification mirroring** (survey #23–26) | Unchanged | Large each |
| — | **AI rebuild** (§2.2) | Direction question, not a port; if ever, take the catalog + permission shapes, and no `.env` | Own proposal |

Below the line, unchanged from the survey: touch gestures, OSK auto-show,
workspace profiles, app-usage dashboard, `wrappedFrame`, bar style variants,
Google Tasks/Gmail/TickTick/GDrive, `scripts/buds/`, source switching.

---

## 4. Method and caveats

Read before starting, per this repo's rule: `AGENT.md` and `CONTRIBUTING.md`,
sequentially, in full. The clone was made into the session scratchpad, outside
this repo and every worktree. Every claim about their tree is grounded in a
file or commit that was opened; the "landed here" table in §1 was verified by
grepping our tree per item, not from the survey's text. The survey's own §Appendix
warning stands for this document too: their side was read more closely than
ours, and a "still open" cell is a search that found nothing, not a proof of
absence — before acting on a row, grep our tree for the capability under a name
we would have chosen.
