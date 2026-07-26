# Upstream triage — `end-4/dots-hyprland` issues & PRs vs Immaterial Impulse

> Date: 2026-07-26. Source: 442 open issues + 169 open PRs on `end-4/dots-hyprland`
> (our fork's illogical-impulse shell ancestor — same QML lineage, so its shell
> bugs largely apply). Each candidate was verified against our actual code.
> `file:line` refers to our fork under `dots/.config/quickshell/ii/`.
> "Fix PR" = an open upstream PR that already implements the fix (logic to port —
> we can't cherry-pick directly, our git upstream is `pctrade/end4-pC`).

## A. Bugs confirmed present in our fork (fix these)

Priority order — top ones are small, local, high-impact.

| # | Bug | Where (our code) | Fix direction | Upstream fix PR |
|---|-----|------------------|---------------|-----------------|
| 3425 | **All sidebars/panels blink open→shut**: `onCleared` dismisses with no debounce; a ToplevelHandle activation transiently clears the focus grab | `services/GlobalFocusGrab.qml:67-69` | ~100ms debounce Timer; only dismiss if grab still inactive | — |
| 3508 | **AppSearch CPU storm**: O(n²) `findIndex` dedup + eager `Fuzzy.prepare` over all entries, recomputed on every `DesktopEntries` change | `services/AppSearch.qml:44-59` | Dedup via Map keyed on `id`; lazy/memoized prepare | #3539, #3447 |
| 3512 / 3240 | **Lag on kitty open/close & workspace switch**: `HyprlandData.updateAll()` fires on *every* Hyprland event, spawning 5 `hyprctl -j` procs, no debounce | `services/HyprlandData.qml:86-94` | Debounce/coalesce events; skip more noise event types | #3539 (related) |
| 2885 | **Notification vanishes on 50ms unfocus**: mouse-leave calls `timeoutNotification()` → `popup=false` with zero delay | `modules/common/widgets/NotificationGroup.qml:43-51`; `services/Notifications.qml:230` | Configurable cooldown Timer on the leave branch | #3251 (related) |
| 1595 | **Media title disappears for fully-bracketed songs**: anchored bracket-strip reduces e.g. `[BLEED BLOOD]` to `""` → shows "No media" | `modules/common/functions/StringUtils.qml:191-205`; `modules/ii/bar/Media.qml:354` | If cleaned string empty, return original title | #3529 |
| 3399 | **Media box stays visible when bar auto-hides** | `modules/ii/mediaControls/MediaControls.qml:103-105`; `modules/ii/bar/Bar.qml:54` | Clear `mediaControlsOpen` on bar hide | #3395 |
| 1862 | **SysTray overflow popup stays open when bar auto-hides** | `modules/ii/bar/SysTray.qml:44-59` | Close overflow / release focusGrab on `!mustShow` | — |
| 2883 | **Offline random-wallpaper persists a truncated `wallpaperPath`** (`…random_wallpaper.`) → blank/black lock bg + corrupt config | `scripts/colors/switchwall.sh:270`; `scripts/colors/random/random_konachan_wall.sh:34-43` | `[ -f ]` / valid-image guard before `set_wallpaper_path`; curl sanity check, keep previous wall on failure | #3494 (related) |
| 1493 | **Battery flaps + low-battery notify spam** on transient UPower `displayDevice` swaps; no debounce | `services/Battery.qml:12,63-89` | Debounce device/percentage before deriving `available`/`isLow` and notifying | — |
| 2976 | **Cheatsheet double-lists keybinds** defined in both default + custom Lua (concat, no dedup) — milder than upstream (our Lua has no `unbind`) | `services/HyprlandKeybinds.qml:22-27` | Dedup on mods+key, custom wins | #2815 (related) |

## B. Reported upstream but NOT our code / not fixable in our QML

- **#1746** fd/`sync_file` leak — Quickshell/Qt render layer, not editable config.
- **#2935** 100%-core on paste — external `wl-paste --watch`/`cliphist` watcher.
- **#2000 / #1510** tray icons missing at startup / after restart — Quickshell SNI-host lifecycle timing.
- **#2971** general "laggy" — no root cause named, nothing to confirm.
- **#2567** GPU-saturation freeze — **conditionally fixed**: we set `QSG_RENDER_LOOP=threaded`
  only in the optional Wallpaper Engine wrapper (`sdata/subcmd-install/4.wallpaperengine.sh:103`).
  **Base installs (no WE) remain exposed** → worth exporting it in the main launch path too.

## C. Already handled by prior fork work (do NOT re-implement)

Network speed indicator (#1825/#675), synced lyrics (#3109), global search (#3168),
disk usage in Resources (#3126), GPU usage/temp — NVIDIA only (#2498), OpenWeatherMap
migration (#1918), dock-on-empty-workspace (#917), notification grouping (#1220),
clipboard fuzzy search + image previews (base of #2666), MPRIS dedup rewrite (#1508),
minus-zero weather temp (#3091), XDG_DATA_DIRS literal (#3354), lockscreen desktop-leak
(#2698), wallpaper pixelation / stretch (#3036/#1185), monochrome matugen (#1321),
matugen tty glitch guard (#3317), wallpaper thumbnail fallback (#1902), content-aware
widget placement on wall change (#1445), video-wallpaper pipeline (#3019), launcher word
splitting (#2816), cheatsheet Lua parser — immune to hyprctl-parse bugs (#3390/#3534/#3333).

## D. Features worth adding — MISSING

| # | Feature | Notes | Ready upstream PR |
|---|---------|-------|-------------------|
| 3220 | Bluetooth connect **pending/busy feedback** (spinner) | small, clean win; static label now | #3221 |
| 528 / 2898 | **Caps/Num Lock OSD** | we have volume/brightness/gamma/layout OSDs, none for lock keys | #3008 |
| 1691 | **Auto dark/light theme by system time** | only manual toggle + wallpaper-derived; Hyprsunset drives gamma not theme | — |
| 2914 | Setting: **show only current-monitor workspaces** in bar | bars per-monitor but show fixed group; no filter toggle | — |
| 1402 | **ICS calendar events** | calendars are date grids only, no event model | #1887 (extended calendar) |
| 2902 | **OLED screensaver** / pixel-shift anti-burn-in | none present | — |
| — | **Lock screen media controls** | frequently requested; not in our lock UI | #3521, #3462, #2719 |
| — | **File/folder search** in launcher | LauncherSearch has no file provider | #3276, #3307 |
| — | **VPN toggles** in right sidebar + bar status | absent | #1813, #2749, #3048 |

## E. PARTIAL features worth finishing

| # | Have | Gap | Ready PR |
|---|------|-----|----------|
| 3272 / 2492 | Full pomodoro+stopwatch in right sidebar | promote to a **bar pill / dynamic-island** | #2757, #3362 |
| 2666 | Clipboard fuzzy search, previews, wipe | add **pinning/favorites** | #3546, #2739 |
| 3389 | Translated weekday names; `firstDayOfWeek` in DatePicker only | wire `firstDayOfWeek` into **main sidebar/background calendars** (hardcoded Monday) | — |
| 2498 | GPU usage/temp NVIDIA-only (`nvidia-smi`) | add **AMD/Intel hwmon** path | #1915, #1858 |
| 1918 | OWM weather, key hardcoded | provider-choice setting + un-hardcode key | #3400 |

## F. Other ready-patch feature PRs worth porting

Bluetooth battery indicator (#3538), Tailscale exit-node selector (#3501), Wi-Fi rescan
button (#3480), OpenRGB integration (#3415), bar shadow option (#3217), package-update
count in bar (#2084/#2845/#2732), keyboard-brightness keybinds (#2419), wallhaven source
in wallpaper menu (#3218), dock context-menu + drag-reorder (#3045), clipboard "clear"
buttons (#3546), submap indicator in bar (#2225), auto-inhibit sleep on external monitor
(#2109).
