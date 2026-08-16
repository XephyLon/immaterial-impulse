# `P3DROVFX/ii-p3drovfx` — what is worth taking

> Date: 2026-08-16. Research only; nothing was ported.
> Source read: a full `git clone` of `https://github.com/P3DROVFX/ii-p3drovfx`
> at `2e318c18` (2026-08-16), plus the GitHub API for repository metadata.
> Their paths below are relative to `dots/.config/quickshell/ii/` unless written
> repo-relative; ours are relative to `dots/.config/quickshell/imi/`.
> Line counts are `wc -l` on the cloned tree.
> Where a conclusion is reasoning rather than reading, it is marked **(inference)**.

---

## 1. What it is

**It is not a sibling fork of illogical-impulse. It is a fork of a fork.**

```
end-4/dots-hyprland  →  vaguesyntax/ii-vynx  →  P3DROVFX/ii-p3drovfx
end-4/dots-hyprland  →  pctrade/end4-pC      →  Immaterial Impulse
```

Evidence: their clone carries end-4's whole history back to `16b0d7707` ("Initial
commit", 2023-12-25); the first `ii-vynx` merge is `a36641e01` (2025-12-13, author
`vaguesyntax`); `gh api repos/P3DROVFX/ii-p3drovfx/contributors` reports `end-4`
4082, `vaguesyntax` 962, `P3DROVFX` 843, `clsty` 800. Their README's first line
calls the repo "a powerful and flexible environment manager for
[ii-vynx](https://github.com/vaguesyntax/ii-vynx)". GitHub's `fork` flag is `false`
and `parent` is `null` — it was re-uploaded, not forked in GitHub's sense.

**The last end-4 commit in their tree is `9f882d9f3` (2026-03-27).** Ours starts
from `pctrade`'s squashed `7cfc5cbd8` ("init", 2026-04-07). The shared ancestor is
therefore end-4's shell as of **late March / early April 2026** — a recent common
base. That matters for reading §2: a feature they have and we lack is usually
*their* work, but occasionally it is an end-4 feature `end4-pC` had already
dropped. I checked provenance per feature with `git log --reverse -- <path>` and
the results are in the tables. (`modules/waffle/`, their Windows-recreation panel
family, is one of the inherited ones — 144 files, 12,093 lines, end-4's.)

**Scale.** 8,390 commits; 1,372 QML files; 296,526 QML lines. Ours: 1,862 commits,
921 QML files, 130,263 lines. Their `Config.qml` is 3,390 lines to our 1,591; their
`GlobalStates.qml` is 890 to our 86.

**Activity.** Very much alive. 380 commits in August 2026, 461 in July; the tip
commit is dated the same day as this report. 50 stars, 10 forks, 5 open
issues/PRs, one release (`05.18.2026`). Multi-author — `Scrimas` (326),
`Celestial.y` (185), `jwihardi` (154) land features through PRs on the p3drovfx
repo itself.

**Character.** Feature-maximalist. Where we spent the last four months on a design
system, a morph engine, a plugin platform and a test suite, they spent it on
breadth: a Gmail client, a video editor, per-app energy accounting, phone screen
mirroring, touchscreen gestures, a tiling assistant. Four native helper daemons are
written in **Rust** and **shipped as source only** — the user must
`cargo build --release` them (`scripts/touchGestures/`, `scripts/appStats/`,
`scripts/osk/`, `scripts/hyprland/workspace_profile_manager_src/`).

**Engineering practice, stated plainly.** Their entire test suite is **6 files,
~934 lines, 33 QML test functions** (`tests/quickToggles/` — 4 `tst_*.qml`, plus
`scripts/colors/test_runner.py` and a gdrive script test). There is no runner
script and no documented invocation. `.github/workflows/` holds three files —
`auto-close-issue.yml`, `dist-update-notification.yml`, `dump-github-context.yml` —
and **none of them runs anything against the code**: a PR that breaks
`tst_QuickToggleLayout.qml` merges green. There are no static lints.

This asymmetry is the single most important fact for sizing any port. **Their code
arrives with no evidence that it works, and our repo's rules require that evidence
before it lands.** Every estimate below includes the check the change would need.

---

## 2. What they have that we do not

### 2.1 The dynamic island — their signature feature

`modules/ii/dynamicIsland/` — 18 files, **8,068 lines**. First commit `P3DROVFX`,
2026-07-04, so it is theirs.

A notch-shaped card hangs from the top centre of the focused monitor and morphs in
response to whatever is happening: media, notifications, battery plug-in, keyboard
layout, workspace change, clipboard copy, Bluetooth connect, Wi-Fi, recording,
pomodoro, an AI agent working, a KIO file-copy job, files dragged onto it. Hovering
expands it to show several widgets side by side.

Implementation: `DynamicIslandPanel.qml` (1,842) is **one** `PanelWindow`,
`WlrLayershell.layer: Overlay`, namespace `quickshell:floatingNotch`,
`exclusionMode: Ignore`, with `mask: Region { item: ... }` swapping between a thin
top hover sensor, the card, and the whole window. Routing is a pure-function
registry: `getWidgetDetails(type)` returns `{type, source, contractedW/H,
expandedW/H}` for 18 types; `activeWidgetsList` rebuilds from ~20 service
predicates, each gated by a `Config.options.bar.floatingNotch.disableX` flag; the
card's target size sums or maxes over that list. The shape is
`modules/common/widgets/Notch.qml` (98) — a `Shape`/`ShapePath` with concave top
shoulders — animated by `Behavior on width/height/y` on `OutBack`. Widget sizes
range from `FloatingNotchWifi.qml` (42) to `FloatingNotchMedia.qml` (1,529) and
`FloatingNotchLocalSend.qml` (1,173).

**We have no island.** The only hits for the phrase in our tree are naming:
`modules/imi/bar/TimerPill.qml:8` calls itself "dynamic-island-style" and
`modules/common/Appearance.qml:597` mentions "dynamic-island badges".

**But we already own the engine.** `modules/imi/bar/BarPopupOverlay.qml` (537) is
one always-mapped `Overlay` surface per screen carrying a single card that every
bar popup morphs, with content reparented in from windowless `StyledPopup`
declarations and one global slot (`GlobalStates.activeBarPopup`). Their island is
the same machinery driven by a different selector — activity predicates instead of
hover. Porting the *idea* means instantiating machinery we have, not inventing it.

Two things would fight us if taken wholesale:

- Their island **absorbs the search launcher and the volume/brightness OSD into
  itself** and disables three standalone popups when it is on. That is an exclusive
  shell mode (`modules/common/ShellModePolicy.qml`, 94), a concept we do not have.
- Their island is **single-screen** (focused monitor); our `BarPopupOverlay` is
  per-screen `Variants`. Mixing conventions in one tree is a decision to make up
  front, not to discover later.

### 2.2 Their other one-surface experiment, and their popup zoo

`modules/ii/topLayer/` (2,868) is a per-monitor full-screen `PanelWindow` hosting
the bar, vertical bar, both sidebars, every screen corner, the search drop and the
OSD drop — with two tiny sibling windows that exist purely to own animated
exclusive zones. It loads only in their "Connect" shell mode. It is the closest
analogue to our `BarPopupOverlay` and is ~2.5× the code because it owns far more.

Seven standalone popup modules, all on the same `Scope → LazyLoader → PanelWindow →
Region-masked content` idiom, single-screen:

| Their module | Lines | Ours |
|---|---|---|
| `bluetoothConnectionPopup/` | 572 | **not none** — `modules/imi/sidebarRight/bluetoothDevices/` (`BluetoothDialog.qml` 76 + `BluetoothDeviceItem.qml` 125) is a full pair/connect/disconnect dialog with discovery and Connecting/Disconnecting states. It calls `device.connect()`/`device.disconnect()` on `Quickshell.Bluetooth`'s own `BluetoothDevice` (`BluetoothDeviceItem.qml:102-118`), which is why `services/BluetoothStatus.qml` (58) carries no such signals — that observation was true and the conclusion drawn from it was not. What we lack is the *popup on a connection event*, not the ability to connect |
| `keyboardLayoutTransitionPopup/` | 422 | yes, as an OSD indicator — `modules/imi/onScreenDisplay/indicators/KeyboardLayoutIndicator.qml` |
| `localSendPopup/` | 479 | none |
| `colorPickerPopup/` | 1,026 | none — we just `execDetached(["hyprpicker","-a"])`, from three places: `modules/imi/bar/UtilButtons.qml:63` and `:69`, and the `ColorPickerToggle` quick toggle (`modules/common/models/quickToggles/ColorPickerToggle.qml:24`) |
| `screenshotOverlay/` | 463 | yes — `modules/imi/screenshotResult/ScreenshotResultPanel.qml` (242) |
| `scratchpadOverlay/` | 167 | none |
| `alarmRingingPopup/` | 137 | none |

Three of these are island fallbacks: with the notch on, Bluetooth, keyboard-layout
and LocalSend popups are suppressed and the island renders them instead.

### 2.3 Search launcher

Their README calls this their flagship. Partly overstated, partly real.

**Overstated:** the math/unit/currency evaluation is `qalc -t` (libqalculate)
shelled out to — the same call end-4 already made and the same call we already make
(`services/LauncherSearch.qml:271-296`). "Currency conversion" is a qalc
capability, not their code; there is no currency code and no network call anywhere
in their tree for it.

**Real, and worth having:**

| Capability | Their location | Ours |
|---|---|---|
| **System controls + two-step confirm** — `lock`/`suspend`/`reboot`/`poweroff`/`restart` from the search bar; the first Enter re-renders the row as "Reboot PC (Are you sure?)" and the second executes | `services/LauncherSearch.qml:195, 281, 927-998`; `modules/ii/overview/SearchItem.qml:137-146, 1033-1041` | none |
| **qalc gating** — `isMathQuery()` decides before spawning | `LauncherSearch.qml:33-42, 269-280` | none: ours calls `nonAppResultsTimer.restart()` from *inside* the `results` binding (`services/LauncherSearch.qml:470`), so **every** non-prefixed query spawns a `qalc` process |
| **Structured math display** — split qalc's output on `=`, render `expr → value` | `SearchItem.qml:60-86, 651-700` | none |
| **Window search (`#`)** — filter `HyprlandData.windowList`, focus / close / move-here | `LauncherSearch.qml:348-358, 583-626` | none |
| **File *browser* (`~`) — directory walking**; selecting a folder rewrites the query to descend | `LauncherSearch.qml:221-230, 327-345, 627-682` | different — our `services/FileSearch.qml` (107) is a recursive `fd` scan, not navigation |
| **Frecency ranking** — five time-window buckets over launch history | `services/AppUsage.qml` (190) + `services/AppSearch.qml:77-140` | none — our `services/AppSearch.qml:71` ranks on `Levendist.computeScore` alone, and `services/DockLaunchTracker.qml` (87) persists nothing |
| **Aliases, module shortcuts, shell snippets, now-playing bubble, suggestions panel** | `LauncherSearch.qml:786-1155`, `SuggestionsPanel.qml` (378) | none |
| **Debounced result recomputation** — `results` is a plain property rebuilt via `Qt.callLater`, not a live binding | `LauncherSearch.qml:418-438` | ours is still a live binding (`LauncherSearch.qml:298`) |

Two prefixes we have and they do not: keybind search (`<`) and Prism modpacks
(`%`, `services/PrismLauncher.qml`).

Two of their mechanisms are **not** to be copied. `eval()` on the query for the
fast arithmetic path (`LauncherSearch.qml:59`) is held up entirely by a character
whitelist one edit away from being exploitable. And
``bash -c `ls -1 -p "${path}"` `` with the user's typed path interpolated
(`LauncherSearch.qml:334`) is a live command-injection surface — our
`services/FileSearch.qml:65` passes the pattern as `$1` positionally and documents
that it has no shell-injection surface; do not regress that.

### 2.4 Window management and session behaviour

| Feature | Their files | Lines (core / total) | Provenance | Ours |
|---|---|---|---|---|
| **OLED saver** — a key blacks out one monitor as a true-black layer surface, holding its own sleep inhibitor separate from the user's keep-awake | `modules/ii/oledSaver/OledSaver.qml` | 178 / 280 | Scrimas, 2026-07-14 | **we have this** — `modules/imi/screensaver/` (`Screensaver.qml` 103 + `ScreensaverContent.qml`), an OLED blackout by design (`ScreensaverContent.qml:22`: "pixels off for OLED burn-in protection in both modes"), already one `Overlay` surface per screen (`Variants` over `Quickshell.screens`, namespace `quickshell:screensaver`, `WlrKeyboardFocus.Exclusive`), with a black/drifting-clock pixel-shift mode, an arming timer so mapping it under the cursor cannot self-dismiss it, config at `Config.qml:1257` and a settings row at `LockIdleConfig.qml:177`, **and** `show`/`hide`/`toggle` IPC verbs (`Screensaver.qml:83-102`). Three real deltas: (1) nothing binds those verbs to a key — no `GlobalShortcut` in the module and no `screensaver` binding anywhere in `dots/.config/hypr/`, so the only caller today is `hypridle.conf`'s 240s listener; (2) it arms every screen at once, not one chosen monitor; (3) it holds no idle inhibitor, so hypridle's ladder (lock 300s, DPMS off 600s, suspend 900s) runs on underneath it |
| **Tiling assistant** — KDE-style snap zones on `SUPER`+drag, keyboard tiling, divider drag | `services/TilingAssistant.qml`, `modules/common/functions/tiling.js` (659), `modules/ii/tilingAssistant/`, `scripts/hyprland/drag_monitor.py` (538) | 1,125 / ~3,600 | Scrimas, 2026-08-03 | none |
| **Touch gestures** — edge swipes on a physical touchscreen with a follow-the-finger overlay | `services/TouchGestureService.qml`, `modules/common/TouchGestureActionRegistry.qml` (250), Rust helper (601) | 867 / ~3,160 | P3DROVFX, 2026-08-14 | none |
| **Workspace profiles** — snapshot/restore named window layouts | `services/WorkspaceProfileService.qml`, Rust `workspace_profile_manager` (951) | 533 / ~4,600 | Scrimas, 2026-06-19 | none |
| **Per-app usage & energy** — screen time, watt-hours, CPU/GPU time per app, from a Rust daemon over `/proc`, DRM fdinfo and RAPL | `services/AppStats.qml`, `modules/ii/usage/` (4,032), Rust (2,263) | 806 / ~8,600 | Scrimas, 2026-08-01 | none |
| **Dock live preview** — a pinned live miniature of a chosen window in the dock | `services/DockLivePreviewService.qml` | 219 / ~920 | — | none in the dock. We use `ScreencopyView` in five other places (`Magnifier.qml`, `RegionSelection.qml`, `ScreenTranslatorPanel.qml`, `OverviewWindow.qml`, `DragApps.qml`) |
| **Screen-shader browser** — one owner of `decoration:screen_shader`, merging built-ins, extra dirs and `hyprshade`'s catalogue | `services/ScreenShader.qml` | 298 / ~790 | — | `services/HyprlandAntiFlashbangShader.qml` (56) is the whole feature for us |
| **OSK auto-show** — raise the on-screen keyboard only when a text field is focused by finger or pen, via a `zwp_input_method_v2` observer | `services/OskAutoShow.qml` (172) + Rust (257) | 172 / 430 | — | we have the OSK, no auto-show |
| **Idle: timed keep-awake** — `inhibitFor(minutes)` on an absolute epoch deadline (deliberately not a decrementing timer, so suspend cannot skew it), pre-expiry warning, MRU duration chips | `services/Idle.qml` (282) | ~180 net-new | — | our `services/Idle.qml` (101) instead has `autoOnExternalMonitor`. The two halves compose |
| **`wrappedFrame`** — `fakeScreenRounding` mode 3: a solid inset border on all four edges with real exclusive zones, so the desktop looks matted | `modules/ii/wrappedFrame/` | 443 | vaguesyntax, 2025-12-21 | none |

`tiling.js` deserves naming separately: 659 lines of pure zone geometry, ~38
exported functions, no Qt dependency. That is exactly the shape this repo already
prefers (`dock_geometry.js`, `parallax.js`, `shape_morph.js`) and the one part of
the tiling assistant that would port without argument.

### 2.5 Phone and audio devices

Their phone cluster is **~17,000 lines** (6 QML singletons = 4,863; 13 UI files =
8,909; 8 helper scripts = 3,291). Ours (`services/PhoneConnect.qml` + UI + tests)
is ~1,000. They are not the same feature: ours is *paired-phone state plus three
actions over D-Bus*; theirs is *a phone control panel that drives the phone over
adb and scrcpy*.

| Capability | Theirs | Ours |
|---|---|---|
| Notification mirroring (reply, actions, dismiss, grouping) | yes — `services/KdeConnectService.qml` (1,931) + `RemoteNotification{Group,Item,ListView}.qml` (1,407) | no |
| Pairing accept/decline from the shell | yes | no |
| Share URL/text/file, SFTP mount and browse | yes | no |
| Screen mirroring, per-app scrcpy windows | yes — `PhoneScrcpyService.qml` (399) + `scrcpy_session_manager.py` (286) | no |
| Phone as webcam | yes — `PhoneCameraService.qml` (817) | no |
| Phone as microphone | yes — `PhoneMicService.qml` (1,328) | no |
| Contacts, dial, SMS compose | yes — `PhoneContactsService.qml` (219) + `contacts_monitor.py` (351) | no |
| Android launcher icons | yes — `android_icon_extractor.py` (1,186), a full ARSC/AXML parser | no |
| **Valent backend** | **no** — zero occurrences in their tree | **yes** |
| One normalized device model across backends | no | yes |
| Logic-only test double kept byte-for-byte in sync | no | yes — `tests/test_phone_connect_contract.py` |
| argv-array D-Bus calls, no shell string interpolation | no — `qdbus` through `bash -c`, device id interpolated into the object path | yes |

Audio is where the picture reverses:

| Feature | Theirs | Ours |
|---|---|---|
| **XDG sound theme engine** — scans `/usr/share/sounds` and `~/.local/share/sounds`, follows `Inherits=` chains, plays in-process through QtMultimedia with a player pool, per-category rate limits, startup grace windows, per-event overrides, theme install from tarball | `services/SoundService.qml` (389) | **nothing.** `services/Audio.qml:117` `playSystemSound()` spawns `ffplay` **twice** — once for `.oga`, once for `.ogg` — and lets one fail silently |
| **Mono downmix** accessibility toggle via `module-remap-sink` | `services/MonoAudioService.qml` (90) | none |
| **Keyboard backlight** — `/sys/class/leds/*kbd_backlight`, OSD, idle-off with restore | `services/KeyboardBacklight.qml` (234) | none |
| EasyEffects control | `services/EasyEffects.qml` (130) — detects native-vs-Flatpak once, verifies real state 1.5 s after a toggle | ours (61) retries the flatpak path on *every* call and sets `active` optimistically, so the toggle lies whenever the launch fails |
| Earbud ANC | `services/BudsService.qml` (126) over **17,863 lines of vendored, unattributed GJS** | none. See §6 |

### 2.6 Integrations

| Feature | Their files | Lines | Ours |
|---|---|---|---|
| **DNS-over-TLS** — per-link DoT on systemd-resolved via `resolvectl dns <link> <ip>#<name>`, reverted with `resolvectl revert` so NetworkManager settings are never mutated; re-applies on default-route change; ships a polkit rule and a leak-check probe | `services/DnsOverTls.qml` | 321 | none — `resolvectl` appears nowhere in our tree |
| **LocalSend** — send/receive to phones over LAN | `services/LocalSend.qml` (520) + `localsend_scan.py` (145) + popup (483) | ~1,150 | none |
| **Media downloader** — a full `yt-dlp` GUI: thumbnail preview, format/resolution/codec chips, queue, live progress, cancel | `services/MediaDownloaderService.qml` (594) + `MediaDownloaderPanel.qml` (1,654) | ~2,400 | none |
| **Video editor** — trim/crop/compress with live scrubbing and an ffmpeg engine that *estimates* output size by encoding a sample first | `modules/ii/videoEditor/VideoEditor.qml` (1,007) + `scripts/videos/compress_video.py` (473) | ~1,700 | none |
| **Calendar with CalDAV** — `khal` + `vdirsyncer`, read *and* write, `.ics` import | `services/CalendarService.qml` (366) | 366 | `services/IcsCalendar.qml` (126) + `ics_parser.js` — remote `.ics` over `curl`, read-only, no sync, no event creation |
| **Command snippet library** — user-authored, taggable, importable snippets behind a cheatsheet page, persisted through an `atomicWrites` FileView with a missing-file grace period | `services/CommandsService.qml` | 198 | none |
| **At-a-Glance** — pure aggregator over Weather/MPRIS/Calendar/Battery for one widget, zero new dependencies | `services/AtAGlanceService.qml` | 291 | none |
| **Water reminder** | `services/WaterReminderService.qml` | 130 | none |
| **AI agent status** — `pgrep -a -f` for Claude/Gemini/Aider/Goose, `/proc/<pid>/stat` CPU ticks and child-process shape to infer "this agent is working", surfaced in the island | `services/AiStatusService.qml` (99) + `ai_status_monitor.py` (196) | ~300 | none |
| **First-run wizard** — 31 files: displays, keyboard layout, language/time, personalise, shell-mode choice, keybind cards, tutorials | `modules/welcome/` | **6,033** | `welcome.qml` (493) |
| **Sports scores** (unauthenticated ESPN endpoint), **Gmail client** (11,472 lines), **TickTick sync**, **Google Drive backup** | various | ~18,000 | none. See §4 Category D and §6 |

### 2.7 Infrastructure — the part that is easiest to miss and cheapest to take

| Their file | Lines | What it does | Ours |
|---|---|---|---|
| **`modules/common/PanelSchedule.qml`** | **42** | Hands out numbered slots, one per 8 ms tick, so ~40 panels do not all build in a single event-loop pass per monitor. `PanelLoader` takes a ticket the first time it wants to exist and gates on `PanelSchedule.released >= ticket`. The header explains why Quickshell's async incubation is not an option: an `IpcHandler` finalised from the incubation controller crashes in post-reload registration, and most panels declare one | our `panelFamilies/PanelLoader.qml` is **9 lines** — `active: Config.ready && extraCondition`. Every panel builds at once |
| **`modules/common/SettingsPageRegistry.qml`** | 367 | Pages addressed by a stable string `id`, with untranslated `name` keys translated at display time, separate `groups`, `hidden` pages, `aliases`, `subPages` | ours is inline at `modules/imi/settings/SettingsContent.qml:167-183` and addressed **by translated name**: `SettingsContent.qml:135` compares `p.name.toLowerCase()` where `name` is `Translation.tr(...)`. See §3.3 |
| **`services/SearchRegistry.qml`** | 555 | Indexes the settings pages by reading each `.qml` **off disk at runtime** through a `FileView` and brace-matching `ContentSection` blocks, re-indexing on language change | ours hand-maintains `sections:`/`searchTerms:` arrays per page. Theirs cannot drift; ours costs nothing at runtime and is greppable. A trade, not a win |
| **`modules/common/BarComponentRegistry.qml`** | 286 | A catalog of the 21 bar widgets carrying, beyond id/icon/title, a per-widget `styleOptions` list (Default / Expressive / Material / Neural) and a `configPage` deep link | ours is `modules/imi/settings/pages/BarConfig.qml:49-70`, a flat `{id,name,icon}` array — but **more dynamic than theirs**, since line 40 merges `PluginManager.availablePlugins`. What we lack is the style-variant and deep-link metadata |
| **`modules/common/ShellModePolicy.qml`** | 94 | Centralises the compatibility constraints between their two shell modes, refuses illegal transitions in `setMode()`, and exposes a `*BlockedReasonKey` so the UI can explain *why* a control is disabled | no equivalent, and no shell-mode concept. The transferable pattern is: when N settings constrain each other, put the constraint **and its human-readable reason** in one object rather than in each `enabled:` binding |
| **Quick-toggle edit controller** — `QuickToggleCatalog.js` (219), `QuickToggleLayout.js` (318, a pure first-fit packer), `QuickToggleEditController.qml` (366), `StableQuickToggleModel.qml` (125) | ~1,030 | A draft/transaction model: `beginTransaction` deep-clones into `draftPages`, every preview mutates only the draft, and `persist()` is the single write path, validating shape, duplicate ids and catalog size legality before assigning and emitting `rejected(reason)` otherwise. The controller deliberately does **not** import `Config` — it takes the `JsonObject` as `property var config`, so the write boundary is explicit and testable against a plain JS fake. The delegate model is always the *persisted* order; the draft only supplies `layoutX/layoutY`, so delegates animate rather than reorder | ours is swap-only, single-page, 1-D. See §3.3 |
| **`services/WidgetExtensionManager.qml`** (548) + `scripts/widget_extensions.py` (385) | ~930 | Desktop-widget extensions installed by `git clone` from a GitHub URL, discovered by a GitHub code search for the topic `ii-desktop-widget`, updated with `git pull --ff-only` behind a backup | our `modules/common/plugins/` (~28,600 lines across ~230 files) is a categorically more serious artifact — see §3.1. Two things of theirs are better, both about author experience: **local in-place registration** (point at an absolute path, no copy, plus `reloadLocalWidget()` and an IPC `reload` verb) and **zero-infrastructure discovery** via a GitHub topic |
| **`services/HyprlandSettings.qml`** | 89 | The *ephemeral* half of Hyprland control — live, non-persistent `hyprctl eval` changes behind a 29-name leaf allowlist and charset allowlists — kept separate from `HyprlandConfig.qml` (52), which writes persisted overrides | we have only the persisted half (`services/HyprlandConfig.qml`, 64). The split is the idea, and it is what a live-preview slider in settings would need. Note the counterweight: **their `HyprlandConfig.set()` interpolates key and value into a `bash -c` string; ours passes an argv array to `python3` and never builds a shell string** |
| **In-UI updater with a live log** — `modules/settings/configs/AboutConfig.qml` (1,067) + `setup-ii-p3drovfx.sh` (2,636) | ~3,700 | Switch between fork and upstream from Settings > About, with a real-time log. The interesting engineering: the script kills Quickshell mid-run, so a plain `Process` (a Quickshell child) dies one line after staging. They wrap the whole run in a transient systemd user unit — `systemd-run --user --collect --wait --unit=... --property=KillMode=process --property=StandardOutput=file:...` — and `tail -F` the log file, mapping SGR codes onto **theme roles** (`colError`, `colPrimary`) rather than fixed hex so it reads in both themes. `KillMode=process` is required or systemd reaps the cgroup and takes the newly started shell down with it | our `modules/imi/settings/pages/About.qml` (371) `execDetached`s `kitty --hold fish -c "curl .../get.sh \| bash"`. We have `VERSION`, an in-app `CHANGELOG.md`, an `IMI_REF` pin, a persistent git checkout and `repo-status` (330) — all of which they lack — but no in-UI log, no update-available indicator, and hardcoded `kitty`/`fish` |

Two of their infrastructure ideas are **not** worth taking, for the record:
`services/ChangelogService.qml` (95) is a bash-plus-inline-Python heredoc embedded
in a QML property string — the exact construct several of our lints exist to
prevent. And `sidebarPolicies`/`sidebarDashboard` is not a restructure: `f5253a4a3`
is a pure 5-file rename of `sidebarLeft`/`sidebarRight`, named after end-4's
existing `Config.options.policies` feature-gate keys, and it is half-applied — their
`GlobalStates.qml:13-14` still carries
`property alias sidebarLeftOpen: root.policiesPanelOpen // Until all sidebars naming is fixed`.

---

## 3. What we have that is better — and where they beat us

### 3.1 Where we are ahead

**The whole design-system layer has no counterpart there.** They have
`modules/common/widgets/MaterialShape.qml` and a `shapes/` directory; we have
`modules/common/plugins/designsystem/` with `shapes/shape_morph.js` (one owner of
bounds, endpoint short-circuit and Morph cache for every morphing container),
`SpanTravel`/`SpanFade` (one spelling of how a shared element travels between
spans, replacing twenty-three hand-written `NumberAnimation`s), `WidgetCard` +
`WidgetElevation` (one card surface and one alpha-shaped shadow, replacing seven
hand-rolled tint pairs and five hand-rolled shadows), and
`modules/common/interaction_motion.js` + `InteractionMotion.qml` (five interaction
states, per-transition duration and curve, written onto the animation before the
target so the Behavior cannot carry the previous tier). Each is enforced by a check
— `test_expressive_design_system.py`, `lint_widget_card_tint.py`,
`lint_interaction_motion_double.py`, `lint_disabled_opacity.py`.

**The plugin platform.** `modules/common/plugins/` — 6 entry points across 4
surfaces (theirs: 1), a declarative JSON node path with a 16-type component
whitelist and a 12-target binding whitelist, an explicit permission vocabulary, 6
typed option kinds, `apiVersion` gating, a curated registry with offline cache,
`schemaVersion: 2` state with migrations, and an installer
(`scripts/plugins/install_plugin.py`) enforcing HTTPS-only, same-origin for every
file URL, per-file checksums, 8 MiB/32 MiB/64-file caps, path-traversal blocking and
atomic staging with restore-on-failure. Their `WidgetExtensionManager` validates
that `name` and a component path exist, then `Qt.createComponent()`s unrestricted
QML into the shell process — no permission model, no checksums, no path-traversal
guard, and no test touching it.

**Blur discipline.** `WindowBlurRegion.qml`, `services/PopupBlurThreshold.qml` and
`lint_blur_region_pairing.py` — per-panel blur regions paired with generated
Hyprland layer rules so the compositor never frosts a drop shadow. Nothing
comparable in their tree.

**Security posture on the things both trees do.** Our `services/KeyringStorage.qml`
(190) is theirs (139) plus a legacy-attribute fallback that lazily re-keys
pre-rebrand secrets, and ours has no parallel plaintext path. Our
`services/OnlineWallpapers.qml` (248) covers Wallhaven + Unsplash + Pexels with all
three keys in the keyring, against their `WallpaperBrowser.qml` (412) which reads
the Wallhaven key from plaintext `Config.options.wallhaven.apiKey`. Our
`services/Vpn.qml` builds every `nmcli` invocation as an argv array with escaped
connection names; theirs adds NordVPN/ProtonVPN backends at some cost in that
discipline.

**Straight wins on specific services.** `services/Tailscale.qml` (204) handles the
non-operator case explicitly with a documented `pkexec` rationale, against their
bare `pkexec systemctl start tailscaled` (185). Our `modules/imi/bar/NetworkSpeed.qml`
(165) reads `/proc/net/dev` directly; theirs (89) forks `nmcli` per poll and is
Wi-Fi only. Our Docker support is a bundled plugin at 804 lines against their 370.
Our `services/AutoTheme.qml` (118) adds a `"sunset"` mode driven by
`Weather.data.sunrise/sunset` and a `lastRequestedDark` latch so a mid-session
manual override survives to the next scheduled transition; their
`DarkModeService.qml` (101) instead hard-resets `automatic = false` on every
startup as its guard against acting on QML defaults before `Config.ready` — we
solve that with `enabled: (Config?.ready ?? false) && mode !== "off"`, which does
not discard the user's setting.

**The idle-inhibitor fix.** Both trees hit the same Hyprland behaviour — an idle
inhibitor whose surface has not committed a buffer is dropped at creation. They
retry: a `_surfaceReady` gate plus destroy-and-recreate up to four times on a 2 s
timer. We give the inhibitor a reliably-mapped 1×1 transparent input-masked
background layer surface. **(Inference, but a confident one:** theirs is a retry
loop around a symptom; ours removes the cause.)

**Tests and lints.** 757 qmltestrunner checks, 25 static lints, 24 runtime
harnesses, a `Docs:` receipt gate, doc-citation linting, CI on every PR. They have
6 test files and no CI job that runs anything.

**One honest caveat on that last claim**, since the comparison should cut both
ways: several of our heaviest checks *skip* rather than fail where the environment
is missing. `DesignSystemCompile.qml` skips without `WAYLAND_DISPLAY` — i.e.
always, on a GitHub runner — and every weston-bound runtime harness skips where
weston is absent. So the layer that actually gates a PR is the 25 static lints plus
the pure-logic `tst_*.qml`; the runtime layer gates local runs on a Wayland box.
`tests/run_tests.sh` is already candid about this in its own comments. That is
still categorically more than zero, and the static-lint category — 25 scripts each
targeting a bug class we actually shipped — has no counterpart on their side at
all.

### 3.2 Where they beat us — stated plainly

1. **`services/SoundService.qml`.** Our sound-event support is
   `services/Audio.qml:117` spawning `ffplay` twice and letting one fail. Theirs is
   a real XDG sound-theme engine. This is not close.
2. **`modules/common/PanelSchedule.qml`.** 42 lines that stop ~40 panels building
   in one event-loop pass per monitor. Our `PanelLoader.qml` is 9 lines and gates
   only on `Config.ready`.
3. **Stable settings-page ids.** Theirs are strings; ours are translated display
   names. See §3.3.
4. **The quick-toggle draft/commit controller.** A real transaction boundary —
   validation and a cancel path — where each of our editor's gestures is its own
   write straight to the config. A capability we lack, not a bug of ours; see
   §3.3, which spells out why the in-place mutation itself is *not* the finding.
5. **`services/AppUsage.qml` frecency.** Our app search ranks purely on edit
   distance. 190 lines and five call sites for a launcher that stops offering the
   wrong Firefox.
6. **qalc gating and the `Qt.callLater` result rebuild.** We spawn `qalc` for every
   non-prefixed query, from inside a live binding that re-evaluates per keystroke.
   Both of their fixes are small and both are correctness, not polish.
7. **`services/EasyEffects.qml`.** Theirs verifies the daemon's real state 1.5 s
   after a toggle; ours sets `root.active` optimistically, so our toggle lies when
   the launch fails.
8. **Local plugin registration and hot reload.** They can point the extension
   manager at a working directory and reload it over IPC. We install from an HTTPS
   manifest URL only — there is no develop-in-place loop, which is plausibly why
   third-party widgets exist there and not here. **(Inference.)**
9. **The `systemd-run` updater log.** They solved "the updater kills the shell that
   is displaying the updater's output" properly. We sidestepped it with
   `kitty --hold fish -c`.
10. **First-run experience.** 6,033 lines against our 493. Ours works; theirs
    onboards.
11. **`services/CalendarService.qml`.** Two-way CalDAV through `khal`/`vdirsyncer`
    against our read-only remote-`.ics` fetch. More capable, at the cost of two
    external tools.
12. **The scrcpy session-manager pattern** (`scripts/phone/scrcpy_session_manager.py`):
    QML holds no process handles and speaks NDJSON to one long-lived supervisor
    that owns lifecycle and reports `started`/`exited`/`error`. If we ever
    supervise external processes, that is the shape — the idea, not the file.
13. **Capture-baseline-then-refactor.** Their quick-toggle rewrite shipped with
    `tests/quickToggles/PHASE0_BEHAVIOR.md` and a
    `fixtures/phase0-scenarios.json` captured *before* the refactor. That
    discipline is worth stealing independently of the feature.

### 3.3 Findings in *our* tree, surfaced by the comparison

None of these were fixed here — this is a research branch. Each is worth its own
issue. Note that #1, #2 and #4 are defects; **#3 is a gap in our design, not a
defect**, and an earlier draft of this section got that wrong — the correction is
written out there because it is the kind of finding that gets re-raised.

1. **The anti-flashbang weak shader does not exist.**
   `services/HyprlandAntiFlashbangShader.qml:13` declares
   `weakShaderPath: Quickshell.shellPath("services/hyprlandAntiFlashbangShader/anti-flashbang-weak.glsl")`.
   That directory contains only `anti-flashbang.glsl`, and no file of that name
   exists anywhere in the repo. `modules/common/models/quickToggles/AntiFlashbangToggle.qml:14`
   calls `cycle()`, whose first branch is `enableWeak()` — so **the first click of
   the anti-flashbang quick toggle points `decoration:screen_shader` at a file that
   does not exist.**
2. **Settings deep links compare translated page names.**
   `modules/imi/settings/SettingsContent.qml:135` does
   `root.pages.findIndex(p => p.name.toLowerCase() === pageName.toLowerCase())`,
   and every `p.name` in the page list at `:169-182` is a `Translation.tr(...)`.
   Any stored or IPC-supplied `GlobalStates.settingsPage` value — `"Bar & Dock"` —
   stops resolving the moment the user switches language.
3. **The quick-toggle layout editor has no validation and no cancel path.**
   `modules/imi/sidebarRight/quickToggles/androidStyle/AndroidQuickToggleButton.qml`
   edits `Config.options.sidebar.quickToggles.android.toggles` at four sites — a
   swap (`:217-219`), an add (`:262`), a delete (`:304`) and a resize (`:363`) —
   and each gesture is its own write straight to the config. Nothing sits between
   the drag and the stored layout: no shape or duplicate check, no legality check
   against the catalog, no batching of a session of edits, and no way to abandon
   one. Their `QuickToggleEditController`'s `beginTransaction`/`persist`/`rejected`
   boundary is therefore a **feature we do not have**, worth considering on its own
   merits. It is not a repair for a defect.

   **Explicitly not a finding: the in-place mutation.** An earlier draft of this
   section read "the quick-toggle editor mutates the config array in place" and
   called the missing reassignment a defect. It is not, and this repo already
   settled it. 031cd3d32 ("fix(sidebar): make quick toggle edits actually notify")
   made exactly the change that framing recommends — an `updateToggles()` helper
   that copies the list, applies the edit and assigns the result back, at all four
   sites — and 26b625905 reverted it, having measured against a real `Config` that
   a QML list property **does** notify on in-place mutation: `push`, `splice`,
   element assignment, mutating a property of an element, and whole-list assignment
   all emit the change signal. The revert also deleted
   `tests/lint_config_list_mutation.py`, added by the same series, as a lint
   enforcing a rule that does not exist and rejecting correct code. (That revert's
   own subject carries quotes, so it is not written here in the usual
   `<sha> ("<subject>")` citation form; it is
   `Revert "fix(sidebar): make quick toggle edits actually notify" and follow-ups`.)

   The bug that series was chasing — every tile rendering the *previous* tile's
   icon, name and action — was the delegate.
   81379796b ("fix(sidebar): choose a delegate for the toggle each row entry now holds")
   is the fix: `DelegateChooser` picks a component only when a delegate is
   *created* and never re-picks for one that survives, while `ScriptModel` exists
   precisely to keep delegates alive across updates, so a row entry that changed
   identity in place kept the old component while carrying the new entry's data.
   The row `ScriptModel`s became plain array models, which reset the `Repeater`.
   e4a0a1f3f ("test(sidebar): render the quick toggle panel through real layout edits")
   covers it by driving the real panel through the edits that reflow rows — a
   cross-row swap of differently sized toggles, a resize, a remove and an add
   (`tests/test_quick_toggles_layout_runtime.py` + `QuickTogglesLayoutRuntimeTest.qml`).
   So: reassigning the array is a change that was tried, measured and undone.
   Anything ported here adds a transaction boundary for validation and cancel; it
   must not be justified as fixing the mutation.
4. **`get.sh` can silently discard local commits.** `get.sh:29-31` does
   `git fetch --depth 1 origin "$REF"` then `git reset --hard FETCH_HEAD` into
   `~/.local/share/immaterial-impulse/src`. Anyone who has committed in that
   checkout loses it with no warning. Their updater is less careful than ours in
   most respects and more careful in exactly this one.

---

## 4. Portable vs. rewrite

Our architecture makes three specific demands, and every candidate sorts against
them:

- **A widget's surface, elevation, morph and interaction motion come from the shared
  components.** A ported widget that paints its own tint, spells its own
  `NumberAnimation`, or writes a hover-conditioned `scale` inside a control that
  already applies the model does not merely look different — it fails
  `lint_widget_card_tint.py`,
  `test_the_trees_share_one_spelling_of_the_span_animations` and
  `lint_interaction_motion_double.py`.
- **Anything with a compositor surface must obey the blur-region pairing and the
  literal window clear colour** (`lint_blur_region_pairing.py`,
  `lint_window_clear_color.py`).
- **New behaviour needs a check that would have caught the bug**, and the PR needs a
  `Docs:` receipt.

### Category A — near-verbatim ports (their code is already the right shape)

- `modules/common/PanelSchedule.qml` (42) + the `PanelLoader` ticket gate. Pure
  scheduling; touches nothing visual.
- ~~`modules/ii/oledSaver/OledSaver.qml` (178)~~ — **not a port at all; see §2.4.**
  We already have the module, and it is the same shape: one `GlobalStates`
  property, a `Variants` blackout window, an `IpcHandler`. Dropping their file in
  would ship a second screensaver. What is worth taking is the two pieces ours
  lacks — their `IdleInhibitor` and their `GlobalShortcut` — plus a monitor
  selector, moved into `modules/imi/screensaver/`.
- `services/DnsOverTls.qml` (321) + the polkit rule. No UI beyond a quick toggle.
- `services/AppUsage.qml` (190). Pure logic, atomic writes, trivially unit-testable
  — which our rules will want anyway.
- `services/MonoAudioService.qml` (90), `services/WaterReminderService.qml` (130),
  `services/CommandsService.qml` (198).
- `modules/ii/scratchpadOverlay/` (167). Self-contained; needs only `HyprlandData`.
- `services/AtAGlanceService.qml` (291) — glue, with our service names substituted.
- `modules/common/functions/tiling.js` (659), if the tiling assistant is ever taken.
- `scripts/videos/compress_video.py` (473) — the video editor's whole engine,
  standalone.

### Category B — take the idea, write our own

- **The dynamic island.** Take the widget registry, the notch shape and the
  activity-predicate selector. Do *not* take `DynamicIslandPanel.qml`: 1,842 lines
  of which a large fraction is `centerInBar`, search absorption, LocalSend
  drag-drop and debug logging, and whose morph/retarget logic we already have in
  `BarPopupOverlay.qml`.
- **Search launcher upgrades.** The system-controls state machine and the qalc gate
  are ideas of 20–90 lines each; the `eval()` fast path and the `bash -c` file
  browser must be rewritten, not copied.
- **Settings page ids.** Take stable string ids; our inline page list is otherwise
  fine and is already more dynamic than their bar registry.
- **`services/ScreenShader.qml`.** We already independently reached its central
  insight — write the option through `HyprlandConfig`, not `hyprctl keyword`,
  because keyword values are runtime-only and this shell reloads on every option
  change. What is worth taking is the *browser*.
- **The `systemd-run` update log.** Take the mechanism (transient unit,
  `KillMode=process`, file output, `tail -F`, SGR→theme-role mapping); the
  surrounding 1,067-line `AboutConfig.qml` is theirs.
- **Local plugin development loop.** Their design is a `git clone` installer; ours
  is a checksummed same-origin installer. Add a `local` install kind that registers
  a path in place plus a reload IPC verb — do not adopt their validation model.
- **`services/MediaDownloaderService.qml`.** The service is clean and argv-based;
  the 1,654-line panel is written against their overview module and would be a
  `WidgetCard`-based rewrite here.
- **Phone notification mirroring.** The feature is worth wanting; their transport —
  a PyGObject daemon with a respawn loop that retries on *any* exit code — is
  precisely the streaming-`Process` hazard `CONTRIBUTING.md` warns about, and
  taking it forces us to revisit the deliberate polling choice in
  `services/PhoneConnect.qml`.
- **The first-run wizard.** Copy the shape — a page registry, per-page cards, a
  displays step, tutorials. The 6,033 lines are written against their settings
  framework, which we do not have.

### Category C — rewrites, not ports

- **Tiling assistant, touch gestures, workspace profiles, app usage.** Each is a
  QML module + a service + a config schema block + a settings page written against
  *their* settings framework + (for three of them) an unshipped Rust binary the
  user must build. The settings page is a total rewrite every time — their
  `TilingConfig.qml` alone is 725 lines, `TouchGesturesConfig.qml` 633.
- **The full 2-D paged quick-toggle editor.** Their catalog + packer + controller
  is ~1,030 lines and assumes a `{id, type, sizeW, sizeH}` schema with pages; ours
  is `{type, size}`, single-page. A full port needs a config migration and lands at
  2,500–3,500 lines. A *staged* version — the `EditController`'s draft/commit
  boundary wrapped around our existing swap-and-splice, no pages, no 2-D resize —
  is 400–600 lines and adds the part we genuinely lack (§3.3 item 3): validation
  and a cancel. It repairs nothing — our swap-and-splice is correct as written.
- **`wrappedFrame`.** 443 lines that read cheap and are the most coupled item
  surveyed: it imports their bar modules, reads `BarThemes`/`barBackgroundStyle`,
  and depends on eight `GlobalStates` properties (`animatedLeftSidebarWidth`,
  `leftSidebarAnimating`, …) our 86-line `GlobalStates` does not publish.
- **Bar per-widget style variants.** The registry is trivial; the work is
  implementing a second visual style for each of 21 widgets, and every one of them
  multiplies the surface our design-system lints must cover. A design decision, not
  a port.

### Category D — do not take

- **`scripts/buds/`** — see §6.
- **EmailService, TickTickService, GoogleDriveService** — see §6.
- **`services/PhoneCameraService.qml`** — requires the `v4l2loopback` kernel module
  and runs `sudo -n modprobe v4l2loopback || pkexec modprobe v4l2loopback` inline on
  first camera start; its installer downloads and `sudo`-installs a third-party
  binary from `files.dev47apps.net`.
- **`services/SoundcoreService.qml`** — hardcoded to one headphone model and a
  user-installed Rust CLI.
- **`services/MusicVideoService.qml`** — a YouTube search per track change plus
  `pkill -9 -f mpvpaper` teardown.
- **`localsend_scan.py` as written** — a 254-thread /24 sweep that POSTs a
  fabricated device record naming your hostname to every host on the LAN, with TLS
  verification disabled wholesale (`CERT_NONE`, `check_hostname=False`). The
  *feature* is worth having; this discovery script is not.
- **`services/ChangelogService.qml`** — bash and inline Python inside a QML property
  string.
- **Source switching itself.** Wrong shape for us (we keep a real git checkout;
  they deploy a `.git`-stripped tree) and it is the piece with the code-execution
  hole: a custom URL is accepted on a client-side `^https?://github\.com/` regex,
  the cloned repo's `scripts/` are `chmod +x`'d, and its own
  `setup-ii-p3drovfx.sh` is copied over your installed manager. No checksums, no
  signature verification, no version pinning, and rollback is manual.

---

## 5. Ranked shortlist

Ordered by value to the user per unit of work. Sizes are new-code estimates for
*our* tree, including the check each one needs.

| # | Item | Why | Size |
|---|---|---|---|
| 1 | **Fix our anti-flashbang weak-shader path** (§3.3 #1) | A shipped quick toggle whose first click sets a nonexistent shader | Tiny — one file, one test |
| 2 | **`PanelSchedule` + `PanelLoader` tickets** | 42 lines against a whole-desktop startup stall. Measure our startup first; if we have the stall, this is the best ratio in the survey | Small, ~60 lines, one afternoon |
| 3 | **`SoundService`** — an XDG sound-theme engine | Replaces `Audio.qml:117`'s double-`ffplay` hack; every OSD, notification and toggle gains a correct sound path | Medium, ~400 lines + settings rows |
| 4 | **Stable settings-page ids** (§3.3 #2) | Our deep links break on a language switch, today | Small, ~150 lines |
| 5 | **DNS-over-TLS** | Fills a real privacy gap; no credentials, no network calls of its own, one polkit rule, one quick toggle | Small, ~350 lines |
| 6 | **App-search frecency (`AppUsage`)** | The launcher stops offering the wrong app; pure logic, trivially testable | Small, ~200 lines + 4 call sites |
| 7 | **Launcher: qalc gate + `Qt.callLater` result rebuild** | Stops spawning a `qalc` process per keystroke from inside a live binding — the biggest correctness win available in our launcher | Small, ~60 lines |
| 8 | **Launcher: system controls with two-step confirm** | Real, useful, no external dependency. Needs a `key` on `LauncherSearchResult`, a guard on our unconditional overview close (`SearchItem.qml:108-110`), and a `restart` that is `qs -c imi`-aware rather than a bare `Quickshell.reload()` | Small-medium, ~120 lines |
| 9 | **EasyEffects state verification** | Fixes a toggle of ours that lies when the launch fails | Tiny, ~70-line diff |
| 10 | **Local plugin registration + reload IPC verb** | The friction that keeps third-party widgets from existing; does not weaken our installer's security model | Small-medium, ~200 lines |
| 11 | **Idle: timed keep-awake sessions** | Composes with our `autoOnExternalMonitor`; the absolute-epoch-deadline detail is worth copying verbatim | Small, ~180 net-new + chips UI |
| 12 | **OLED saver: finish the one we have** (§2.4) | Not a new module — bind a key to the `show`/`hide`/`toggle` verbs `modules/imi/screensaver/` already exposes, let it target one monitor instead of all of them, and give it an idle inhibitor so a deliberate blank does not fall through hypridle's lock/DPMS/suspend ladder. Ranked here, not at 8: that rank priced it as a new module on a survey row that wrongly read "none" | Small, ~80–120 lines against an existing module |
| 13 | **`CommandsService` + a cheatsheet page** | A genuinely new feature with no equivalent anywhere in ours | Medium, ~550 lines |
| 14 | **In-UI update log via `systemd-run`** | Solves the shell-kills-its-own-updater problem properly and removes hardcoded `kitty`/`fish`. Pair with an update-available indicator, which is *easier* for us since we keep a real checkout | Medium, ~330 lines |
| 15 | **Scratchpad-empty overlay** | Cheapest self-contained module in their tree | Small, ~170 lines |
| 16 | **Quick-toggle draft/commit boundary, staged** (§3.3 #3) | Adds validation and a cancel to layout editing that has neither. Ranked here, not at 9 as an earlier draft had it: it repairs nothing — the in-place mutation it was said to fix is correct (26b625905) — so it buys a cancel and a guard rail for ~500 lines | Small-medium, ~400–600 lines |
| 17 | **Dynamic island** (minimal: surface + registry + 5–6 widgets, on our card) | Their signature feature and the most visible thing they have that we do not; we already own the morph engine. Decide single-screen vs per-screen up front, and do **not** absorb search or the OSD | Medium-large, ~600–900 lines |
| 18 | **Screen-shader browser** | Turns our one-shader feature into a catalogue, and is the right place to land #1 | Medium, ~470 lines + dialog |
| 19 | **Media downloader** (their service, our panel) | High user value, clean argv, `yt-dlp` + `ffmpeg` only | Medium, ~600 lines + our own panel |
| 20 | **LocalSend** (their QML, our discovery) | Phone file transfer without a browser; rewrite `localsend_scan.py` | Medium, ~1,100 lines |
| 21 | **Dock live preview** | Their service (219) is clean; the widget needs redoing against our `dock_geometry.js` edge model | Medium, ~920 lines |
| 22 | **Keyboard backlight** | Self-contained, `brightnessctl` only — but needs hardware we may not have to test on | Small-medium, ~300 lines |
| 23 | **First-run wizard, restructured** | Take the page-registry shape, not the 6,033 lines | Large; a project of its own |
| 24 | **Video editor** | Python engine ports free; the 1,007-line editing surface is the cost | Large, ~1,700 lines |
| 25 | **Tiling assistant** | Real gap and genuinely wanted, but ~3,600 lines plus a Python drag monitor plus companion keybinds plus a settings-page rewrite | Large |
| 26 | **Phone notification mirroring** | Biggest UX jump on the phone side; forces the polling-vs-streaming decision | Large, weeks |

**Below the line, with reasons.** Touch gestures and OSK auto-show — only with a
touchscreen; both need a `cargo build` and `input`-group membership. Workspace
profiles and the app-usage dashboard — each is effectively a separate application
(4,600 and 8,600 lines). `wrappedFrame` — cosmetic, deepest coupling of anything
surveyed. `MusicVideoService`, `SportsService`, `SoundcoreService`, `BudsService`,
phone camera and mic — §4 Category D. `EmailService`, `TickTickService`,
`GoogleDriveService` — §6. Source switching, `ChangelogService`, the
`sidebarPolicies` rename, bar style variants — §4 Categories C and D. And Docker,
SongRec, the preview caches, the wallpaper browser, Tailscale, VPN,
`NetworkSpeed`, `KeyringStorage`, `Updates`, `DarkModeService` and the whole AI
provider layer, where we already have an equal or better implementation.

---

## 6. Licensing and attribution

**The base case is clean.** Both repositories are **GPL-3.0** (`LICENSE` in each is
the GPLv3 text; `gh api` reports `"license": "GPL-3.0"` for
`P3DROVFX/ii-p3drovfx`, `vaguesyntax/ii-vynx` and ours). Both carry the same
`licenses/` directory with `LGPL-3.0.txt`, `MIT.txt` and a `README.md` reading
"This repository contains code from other repositories. Files containing such code
should include a license notice, and a copy should be stored in this folder."
Taking QML from their tree into ours is therefore **licence-compatible without
qualification**.

**Attribution is what we would owe.** No file in their QML tree carries a copyright
header (`grep -rl "Copyright" --include=*.qml` returns nothing across 1,372 files),
so there is no per-file notice to preserve. What there *is* is authorship: their
history names the author of every feature. If we take a feature substantially as
written, the honest form is a credit line in the commit body naming the repository,
the commit and the author — the same way `AGENT.md` already treats end-4 and
pctrade ("Attribution to `end-4` and `pctrade` stays in `LICENSE`, `licenses/`, and
the README credits — the project is GPL-3.0 and the ancestry is real"). Our
`README.md:5-6` currently credits only `end4-pC` and illogical-impulse; a
substantive port would warrant adding `P3DROVFX/ii-p3drovfx` (and, where the
feature predates their fork, `vaguesyntax/ii-vynx`) to that line.

**One hard blocker, and it is not ours to inherit.**
`dots/.config/quickshell/ii/scripts/buds/` is **17,863 lines of GJS across 113
files** with **no LICENSE file and no copyright header anywhere in it**. It is a
vendored copy of the **BudsLink** GNOME Shell extension — the evidence is in the
code: `lib/devices/profileManager.js:8` declares
`SERVICE_PATH = '/io/github/maniacx/BudsLink/Profile'` and every GObject class is
named `BudsLink_*`. GNOME Shell extensions are typically **GPL-2.0-or-later**, and
**if that upstream is GPL-2.0-*only* it is incompatible with our GPL-3.0 tree** and
could not be included at all. Combined with `services/BudsService.qml` (126 lines)
using perhaps 2% of what is vendored, the answer is straightforward: **do not take
`scripts/buds/`.** If earbud ANC is ever wanted, depend on upstream BudsLink as an
optional external tool.

**Two more provenance notes.** Their `services/CalendarService.qml` header states
it is lifted from **DankMaterialShell**, so a port of that file inherits a second
upstream to check and credit. And `services/GoogleCloud.qml` plus
`services/gCloud/token_from_key.py` are **byte-identical to ours** — shared end-4
ancestry, not a taking in either direction.

**Credential handling is a licensing-adjacent hazard, because it would arrive with
the code.** Their `<shellconfig>/.env` holds the Gmail OAuth
`client_id`/`client_secret` and `TICKTICK_CLIENT_ID`/`SECRET`/`ACCESS_TOKEN` in
plaintext, read by `services/GoogleDriveService.qml:591`,
`scripts/email/gmail_config.py`, `scripts/email/get_gmail_credentials.py` and
`scripts/ticktick/backup_env.py`. `scripts/email/oauth_server.py:105` prints the
full refresh token to stdout, which the shell captures into its log, and
`oauth_server.py:143` hardcodes `~/.config/quickshell/ii`. Their OAuth scopes are
`gmail.modify` + `gmail.send` — full read/write/delete on the mailbox.
`services/TickTickService.qml:48-80` interpolates the bearer token into a `bash -c`
string (visible in `ps` to any local process) and splices the task title into a
single-quoted `-d '<json>'`. If anything from those clusters ever comes over, its
credentials go through `services/KeyringStorage.qml` exclusively and the `.env`
pattern does not come with it — particularly given that the directory in question
is the one our updater has historically wiped.

---

## Appendix — method

Read in full before starting: `AGENT.md` (2,128 lines) and `CONTRIBUTING.md` (416),
sequentially, per their own instruction.

Their repository was cloned to `/tmp/p3drovfx` — outside this repo and any
worktree. Six parallel read-only investigations covered the dynamic island and
popup cluster; the search launcher; phone and audio devices; window management and
session behaviour; settings and configuration infrastructure; and the long tail of
integrations. Every claim above is grounded in a file that was opened; the four
findings in §3.3 were each re-verified by hand in our tree.

`tests/run_tests.sh` on this branch: **757 passed, 0 failed, 0 skipped**.
