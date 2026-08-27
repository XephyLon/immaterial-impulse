# Phone tab — design

Status: approved for implementation (maintainer, 2026-08-27). Supersedes the
"surface" paragraphs of `docs/proposals/phone-connect.md`; that proposal's
transport constraint still governs every KDE Connect read and write.

## Goal

A **Phone** tab in the LEFT sidebar (beside Intelligence / Translator /
Media / Anime) that reproduces the fork's phone panel
(P3DROVFX/ii-p3drovfx, `modules/ii/sidebarPolicies/phone/`) on our tokens
and our transport. Top to bottom, exactly the reference screenshot:

1. Header: device chip (name + `expand_more`) that opens the roster; a
   connection pill (`wifi`, label = cellular type such as "LTE", else the
   first reachable address, else "Connected"/"Offline"); a battery pill with
   the charge and a charging mark.
2. One row of **six** round actions: ring (`phone_in_talk`), ping
   (`notifications_active`), send clipboard (`content_paste`), send file
   (`file_upload`), share link/text from clipboard (`link`), browse files
   over SFTP (`folder_shared`). Each enabled only when the device is
   reachable and the backend answers the action.
3. Two navigation cards: **Contacts** ("150 contacts", `contacts` glyph)
   and **Android Apps** ("scrcpy 4.x App Mode", `apps` glyph), each with
   `chevron_right`, opening a sub-page that slides over the tab.
4. The notification area owning the remaining height: phone notifications
   grouped by app (dismiss, reply, actions, copy), with the empty state
   "No notifications / Make sure KDE Connect has Notification Access on
   your phone".
5. Footer toolbar: sync (`sync`), a "N notif." pill, clear (`delete_sweep`).
6. Bottom card stack: **Install scrcpy** (when scrcpy is missing; opens the
   install guide), **Phone Webcam** ("Tap to start · settings to
   configure"), **Phone Microphone** ("Tap to start · uses scrcpy or
   DroidCam"). Pairing-request cards join this stack when a peer asks.

Everything the fork does with `qdbus` / `python-dbus` / `gi` we do with
`busctl --json=short` argv through the existing `PhoneConnect` queue. Every
external process is supervised the way `services/DiscordVoice.qml` and
`services/PhoneConnect.qml` are (`process-lifecycle: restart-safe` marker,
no `running` binding on a streaming process, backoff + ceiling).

## Non-goals (this round)

- Android launcher icon extraction (`android_icon_extractor.py`); apps show
  the `android` glyph. Follow-up.
- The bar indicator and dock widget for scrcpy. Follow-up.
- Valent parity beyond what `PhoneConnect` already has (Valent keeps
  ring only; every other action is hidden on that backend).
- Implementing the KDE Connect protocol, or anything needing a phone-side
  app change.

## Decisions

- **The tab replaces the right-sidebar dialog.** The `phoneConnect` quick
  toggle's menu opens the left sidebar on the Phone tab
  (`GlobalStates.sidebarLeftTab = "phone"`, consumed by
  `SidebarLeftContent`); `PhoneConnectDialog.qml` and the `ToggleDialog`
  wiring are deleted. Shared pieces move to `modules/imi/phone/` (chip,
  action button, device item, pairing card) and are imported from there.
- **Dedicated notification list, deduped.** The tab draws its own
  phone-notification list (the design the maintainer rated). To stop the
  same notification arriving twice, `services/Notifications.qml` drops a
  desktop notification whose `appName` is `kdeconnect` / `kde connect` /
  `org.kde.kdeconnect` or equals a paired device's name — **only while**
  the Phone tab is enabled and the active device is reachable (the fork's
  gate).
- **One monitor stream.** Notification signals join
  `signalChangesDevices`' allowlist in `PhoneConnect`; `PhoneNotifications`
  subscribes to `PhoneConnect`'s coalesced change, then fetches. No second
  `busctl monitor`.
- **Send file uses the house picker** (`kdialog --getopenfilename`, the
  pattern at `SidebarRightContent.qml:113`), plus a `DropArea` over the tab
  that shares dropped `file://` URLs. The drop shelf question in the
  proposal is answered: both.
- **Sub-pages** are `Item`s hosted by `Phone.qml`'s overlay loader:
  `PhoneSubPage { title; signal back() }` slides in with the sidebar's
  motion tiers; Escape and the back button pop it.
- **Config** goes under `Config.options.phone.*` (new JsonObject, append-only
  at the end of `Config.qml`'s options), with `sidebar.phone.enable` beside
  `sidebar.media.enable`. Persistent state under
  `Persistent.states.phone.*`.
- **Dependencies stay optional.** Nothing new is added to the installer's
  hard dependency lists. Each capability probes with `command -v` at
  service start (lint `lint_capability_probe_gating.py` applies) and the
  UI says exactly what is missing with per-distro install commands
  (arch / fedora / debian), copied from the fork's `InstallGuidePopup`.
  `sdata/deps-info.md` gains a "Phone (optional)" paragraph.

## Components and ownership

Five workstreams. Phase 1 (parallel, services + scripts + tests, no UI
beyond what already exists), then Phase 2 (parallel UI in
`modules/imi/sidebarLeft/phone/`). File ownership is exclusive; shared
files are listed with the owner.

### W1 — `PhoneConnect` actions: share, SFTP, persisted device, battery hooks

Owner of `services/PhoneConnect.qml` action region, its shim
`tests/imports/testservices/PhoneConnect.qml`, `tests/test_phone_connect_contract.py`,
`tests/tst_phone_connect.qml`, `docs/proposals/phone-connect.md` (slices 4–6).

Model additions (kdeconnect only; Valent hides them):

- `canShare`, `canBrowseFiles` (readonly bool).
- `shareUrls(device, urls)` → one `org.kde.kdeconnect.device.share.shareUrl`
  per `file://` or `http(s)://` entry, serialized through `runAction`.
- `shareText(device, text)` → `share.shareText`.
- `shareClipboard(device)` — reads `wl-paste --no-newline`; URL heuristic
  `/^https?:\/\//i` or `/^[\w.-]+\.\w{2,}(\/|$)/` → `shareUrls`, else
  `shareText`; empty clipboard → `lastActionError = "Clipboard is empty"`.
- `pickAndSendFiles(device)` — `kdialog --getopenfilename $HOME --multiple`
  through a `Process`, one `shareUrl` per line.
- `browseFiles(device)` — `sftp.mount`, then read `mountPoint`
  (`org.kde.kdeconnect.device.sftp.mountPoint` method), prefer
  `<mount>/storage/emulated/0` when it exists, open with `xdg-open`.
  `sftpMounted` (bool) tracks the answer of `sftp.isMounted`.
- Persisted active device: `Persistent.states.phone.activeDeviceId` and
  `recentDeviceIds` (MRU, max 5). `selectDevice(id)` writes both;
  `activeDevice` prefers the persisted id when that device is paired and
  reachable, else the existing rule.
- Low-battery hooks: `notify-send -i phone -u normal "Low battery: <name>"
  "Charge is at <n>%."` once when charge < 20 and not charging; recovery
  notice at ≥ 25 or charging. Thresholds are literal per the proposal.
- `lastActionError` (string) and `actionFeedback(message, ok)` signal for
  toasts.

Tests: extend the contract (`MODEL_ACTIONS` grows; every argv still an
array; `wl-paste` and `kdialog` are constant argv, nothing interpolated into
a shell string), the QML unit suite (URL heuristic, MRU rule, battery
threshold edge cases 19/20/24/25 and charging), and the dialog runtime
harness becomes the tab runtime harness in Phase 2 (W1 leaves the current
one green).

### W2 — Notification mirroring: `services/PhoneNotifications.qml`

Owner of the new singleton, its shim `tests/imports/testservices/PhoneNotifications.qml`,
`tests/tst_phone_notifications.qml`, `tests/test_phone_notifications_contract.py`,
the allowlist hunk in `services/PhoneConnect.qml` (`signalChangesDevices`
only — coordinate: append the four notification signal names and the
`org.kde.kdeconnect.device.notifications` interface; nothing else in that
file), and the dedupe hunk in `services/Notifications.qml`.

Reads (busctl argv, serialized through its own queue built like
`PhoneConnect`'s):

- `org.kde.kdeconnect.device.notifications.activeNotifications` at
  `/modules/kdeconnect/devices/<id>/notifications` → list of public ids.
- `org.freedesktop.DBus.Properties.GetAll` on
  `/modules/kdeconnect/devices/<id>/notifications/<publicId>`, interface
  `org.kde.kdeconnect.device.notifications.notification`: `internalId`,
  `appName`, `ticker`, `title`, `text`, `iconPath`, `dismissable`,
  `hasReplyAction`, `replyId`, `silent`, `actions` (string list).
  Package = `internalId.split("|")[1]`.

Model: `notifications` (array of `{publicId, deviceId, internalId, package,
appName, title, text, ticker, iconPath, dismissable, replyId, actions,
receivedAt}`), `count`, `groupsByAppName`, `appNameList` (same derivation
as `services/Notifications.qml`), `activeDeviceId` follows
`PhoneConnect.activeDevice`.

Writes through `runAction`-style argv:

- `dismiss(publicId)` → leaf `…notifications.notification.dismiss` (never
  `sendAction("cancel")` — the fork's `KdeConnectService.qml:892-901`
  records why).
- `dismissAll()` loops `dismiss`.
- `reply(publicId, text)` → device-level `notifications.sendReply
  <replyId> <text>`, then a 800 ms delayed refetch.
- `sendAction(publicId, key)` → `notifications.sendAction <key>`.
- `refresh()` — full refetch; the footer's sync button.

Triggers: `PhoneConnect` exposes `signal deviceChangeSettled()` fired from
`signalSettle` (W2 adds the one signal and its emit; W1 does not touch
`signalSettle`). `PhoneNotifications` refetches on it, on
`activeDeviceChanged`, and on a 60 s reconcile timer.

Dedupe in `services/Notifications.qml` `notifServer.onNotification`:
drop when `PhoneNotifications.mirrorActive` and the incoming `appName` is
one of the kdeconnect names or a paired device's name. `mirrorActive =
Config.options.sidebar.phone.enable && PhoneConnect.activeDevice?.reachable`.

Persistence: `Persistent.states.phone.cachedNotificationsJson` (per active
device, saved 2 s after change, restored at boot so the tab is not empty
before the first sweep).

Tests: unit (parse of a captured `activeNotifications` reply and one leaf
`GetAll`, package extraction, group derivation, dedupe predicate), contract
(argv-only, leaf dismiss, reply refetch delay is a declared constant, the
shim's parser region byte-identical), and a runtime harness
`PhoneNotificationsRuntimeTest.qml` over a fake busctl that serves two
notifications and records the dismiss call on the leaf path.

### W3 — scrcpy: mirror, app mode, webcam, microphone

Owner of `scripts/phone/scrcpy_session_manager.py`,
`scripts/phone/droidcam_session.sh`, `scripts/phone/droidcam_status.sh`,
`scripts/phone/setup_droidcam_input.sh`, `scripts/phone/teardown_droidcam_input.sh`,
`scripts/phone/install_droidcam.sh`, `services/PhoneScrcpy.qml`,
`services/PhoneCamera.qml`, `services/PhoneMic.qml`,
`services/PhoneDeps.qml`, their shims, `tests/test_phone_scrcpy_manager.py`
(drives the Python supervisor with a fake `scrcpy`/`adb` on PATH),
`tests/tst_phone_scrcpy.qml`, `tests/test_phone_sessions_contract.py`,
`Config.qml` (the new `phone` JsonObject — W3 owns the whole block; W1/W2/W4
put nothing in Config), `Persistent.qml` (the `phone` JsonObject — W3 owns;
W1 and W2 tell W3 their keys: `activeDeviceId`, `recentDeviceIds`,
`cachedNotificationsJson`, and W3 declares them), `sdata/deps-info.md`.

`scripts/phone/scrcpy_session_manager.py` — NDJSON supervisor on
stdin/stdout, ported from the fork (`launch`, `stop`, `stop_all`, `focus`,
`list_apps`; events `started`, `exited`, `error`, `apps_list`,
`apps_error`). Exact scrcpy line:
`scrcpy [-s <serial>] --window-title=imi-phone-<type>-<id> <extra...>`.
`focus` uses `hyprctl dispatch focuswindow title:^<title>$`. Target
resolution: `adb devices`; a USB serial (no `:`) wins over `ip:port`.
App list: `scrcpy <target> --list-apps`, regex
`^\s*([\*\-])\s+(.+?)\s+([a-zA-Z0-9_]+\.[a-zA-Z0-9_.]+)\s*$`, fallback
`adb shell pm list packages -3`; cached at
`~/.cache/immaterial-impulse/phone/apps/<deviceId>.json`.

`services/PhoneDeps.qml` — one probe singleton: `scrcpy`, `adb`,
`droidcam-cli`, `v4l2-ctl`, `pactl`, `mpv`, `kdialog`, `wl-paste`
presence (`command -v`, started at construction), `v4l2loopback` loaded /
installed (`lsmod`, `modinfo`), scrcpy major version (`scrcpy --version`),
`distro` (`/etc/arch-release`, `/etc/fedora-release`, `/etc/debian_version`),
and `missingFor(feature)` → `[{key, name, description, commands: {arch,
fedora, debian}}]` with the fork's exact command table. `recheck()`.

`services/PhoneScrcpy.qml` — `mirrorRunning`, `mirrorLaunching`,
`sessions` (ListModel of `{id, type, title, pid, package}`),
`apps` (`[{name, package, system}]`), `appsLoading`, `appsError`,
`appModeSupported` (major ≥ 4), `launchMirror()`, `stopMirror()`,
`focusMirror()`, `refreshApps()`, `launchApp(package)`, `stopApp(package)`,
`stopAllApps()`, `focusApp(package)`, `toggleFavorite(package)`,
`favorites` (Config), `recents` (Persistent, max 20), `lastError`. Mirror
flags from `Config.options.phone.scrcpy.*` (the fork's table); app mode
adds `--start-app=<pkg>` and, with `flexDisplay`,
`--new-display=WxH/density --flex-display [--keep-active]
[--no-vd-system-decorations]`. Manager process is started on demand and
stopped by a 10 s idle timer when no session is live; `onExited` follows
the DiscordVoice ladder.

`services/PhoneCamera.qml` — DroidCam webcam: `available` (droidcam-cli +
v4l2loopback), `state` (`unavailable|offline|connecting|ready|active`),
`device` (`/dev/videoN` from `v4l2-ctl --list-devices`), `start()`,
`stop()`, `flip()`, `mirror(bool)`, `openPreview()` (mpv →
ffplay → vlc fallback). Command:
`droidcam-cli -nocontrols [-size=WxH] [-hflip] [-vflip] {adb <port> | <ip> <port>}`
via `droidcam_session.sh launch video …` so it survives a shell restart
(the pidfile is the binary's). USB-first: `adb get-state` = `device` →
`adb <port>`; else the phone's first `reachableAddresses` entry (KDE
Connect's own report), else `Config.options.phone.webcam.wifiIp`.

`services/PhoneMic.qml` — `available` (pactl + (scrcpy | droidcam-cli)),
`state`, `backend` (`scrcpy|droidcam`), `muted`, `gain`, `isDefaultInput`,
`start()`, `stop()`, `toggleMute()`, `setGain(pct)`, `setAsDefaultInput()`,
`restoreDefaultInput()`. Routing exactly as the fork: `setup_droidcam_input.sh`
loads `module-null-sink sink_name=DroidCam-Mic`; scrcpy backend runs
`scrcpy --no-video --no-window --audio-source=mic --audio-buffer=50 [-s
<serial>]` with the default sink temporarily swapped to `DroidCam-Mic`
(original persisted in `Persistent.states.phone.mic.originalDefaultSink`,
restored once the stream appears); droidcam backend runs
`env PULSE_SINK=DroidCam-Mic droidcam-cli -a -nocontrols …`. Boot
reconciliation restores a leftover default sink. Teardown unloads
loopbacks and the null sink.

Config (`Config.options.phone`, defaults = the fork's table in the research
map): `showPeripheralCards`, `contacts.{enabled, favoriteIds, sortBy,
hideUnnamed}`, `scrcpy.{stayAwake, turnScreenOff, noPowerOn, noAudio,
showTouches, fullscreen, alwaysOnTop, maxFps, bitRate, maxSize,
videoBuffer, useWireless, autoWirelessIp, wirelessIp, wirelessPort}`,
`scrcpy.appMode.{enabled, flexDisplay, displayWidth, displayHeight,
density, keepActive, systemDecorations, favoritePackages}`,
`webcam.{cameraFacing, resolution, mirrorHorizontally, rotateDegrees,
connection, wifiIp, port}`, `microphone.{connection, wifiIp, port,
micGain, setAsDefault}`. Plus `Config.options.sidebar.phone.enable`,
which ships **`false`** until W5: it also gates the mirror's dedupe, and
on before there is a list to read them in, the phone's notifications
would stop arriving anywhere. W5 flips it to `true` with the tab.

Tests: the Python supervisor test with fake binaries (launch/exit/focus/
list_apps parsing incl. the `pm list packages` fallback); QML unit tests
for flag assembly (`mirrorArgs()`, `appModeArgs()` are pure functions),
state ladders, and the URL of every command (argv arrays; the only shell
strings are the constant probes); contract test pinning the
`process-lifecycle` marker on every long-running process, the idle timer,
and that no `Process` here has a `running` binding.

### W4 — Contacts

Owner of `scripts/phone/contacts_monitor.py`, `services/PhoneContacts.qml`,
its shim, `tests/test_phone_contacts_monitor.py` (feeds a temp
`kpeoplevcard/kdeconnect-<id>/` with vCards, incl. a nameless one),
`tests/tst_phone_contacts.qml`.

`contacts_monitor.py --device <id> [--once]`: source dir
`$XDG_DATA_HOME/kpeoplevcard` (default `~/.local/share/kpeoplevcard`),
subdir `kdeconnect-<deviceId>` else the newest `kdeconnect-*`; parse
`*.vcf` (FN, N, TEL with types, EMAIL, PHOTO as data URI when inline,
UID), emit NDJSON `ready {sourcePath, count}`, `snapshot {contacts}` only
when the SHA-256 of the set changes, `error {code: "no_contact_source"}`.
Without `--once`, watch with `gio monitor -d`, 250 ms debounce, 3 s poll
fallback.

`services/PhoneContacts.qml`: `ready`, `count`, `contacts`, `query`,
`filtered` (name/number match, `hideUnnamed` honoured, favorites never
hidden), `favorites` (Config `phone.contacts.favoriteIds`),
`toggleFavorite(uid)`, `openDialer(number)` →
`adb [-s <serial>] shell am start -a android.intent.action.DIAL -d tel:<n>`,
`composeSms(number)` → `… SENDTO -d sms:<n>`, both refused with
`lastError` when adb is not reachable. Sort by `sortBy` (first/last).
Monitor process follows the lifecycle rule (restart-safe marker).

### W5 — The tab (Phase 2, after W1–W4 land)

Owner of `modules/imi/sidebarLeft/phone/*`, `modules/imi/phone/*` (moved
shared pieces), `SidebarLeftContent.qml`, `modules/imi/bar/LeftSidebarButton.qml`,
`GlobalStates.qml` (`sidebarLeftTab`), the quick-toggle retarget in
`sidebarRight/`, deletion of `sidebarRight/phoneConnect/PhoneConnectDialog.qml`
and its `ToggleDialog`, `modules/imi/settings/pages/SidebarsPanelsConfig.qml`
(the Phone switch) and a new `modules/imi/settings/pages/PhoneConfig.qml`
("Devices & Phone": the fork's `DevicesPhoneConfig` + `KdeConnectConfig`
rows, on the row grammar from #310), the tab runtime harness
`PhoneTabRuntimeTest.qml` + `tests/test_phone_tab_runtime.py`, and the
tab-set pin `tests/test_sidebar_left_tabs.py`.

Files in `modules/imi/sidebarLeft/phone/`:

- `Phone.qml` — the tab root (`Item`, accepts focus), the ColumnLayout in
  the order above, the `DropArea`, the toast (`actionFeedback`), the
  sub-page overlay loader, `StaggerWave` entrance keyed to the sidebar's
  open flag like `SidebarLeftContent`'s.
- `PhoneHeader.qml`, `PhoneActionsRow.qml` (six `PhoneActionButton`s from
  `modules/imi/phone/`), `PhoneNavCards.qml`, `PhoneNotificationList.qml`
  (group-by-app, swipe dismiss, reply field, action chips, copy; reuses
  `NotificationGroup`'s shape on `PhoneNotifications` data),
  `PhoneFooterBar.qml`, `PhoneFeatureCard.qml` (state machine
  `unavailable|offline|connecting|ready|active`, expands when active with
  detail line + Stop + chips), `PhoneFeatureCards.qml` (the three cards +
  pairing cards), `InstallGuidePopup.qml` (distro pills, per-dep command
  box with copy, Re-check), `PhoneSubPage.qml` (title bar + back),
  `PhoneContactsPage.qml`, `PhoneAppsPage.qml`, `PhoneWebcamPage.qml`,
  `PhoneMicPage.qml`.

Strings through `Translation.tr`; every dimension, radius, duration from
`Appearance.*`; motion on the tiers (lints will refuse literals). The
contract test's `SURFACE` widens to both directories and its dialog-shaped
assertions become tab-shaped: one `id: actionRow` with six buttons in the
order `ring, ping, sendClipboard, pickAndSendFiles, shareClipboard,
browseFiles`, one `Layout.fillHeight: true` on the notification list.

## Verification

- Suite green on each branch (`./tests/run_tests.sh` from the shell dir);
  runtime harnesses bring their own weston + session bus.
- Maintainer verifies live after deploy: pair state, LTE pill, six
  actions against the real phone, contacts count = 150, app list via USB
  adb, webcam device appears in `v4l2-ctl --list-devices`, mic source
  `DroidCam-Mic` in `pactl list sources short`.

## Merge order

W1 → W2 → W3 → W4 (each rebased onto the previous; `PhoneConnect.qml`
hunks are disjoint by construction), then W5.
