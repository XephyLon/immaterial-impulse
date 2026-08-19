# Proposal: Phone Connect (KDE Connect / Valent integration)

> Draft / tracking proposal. The service, its sidebar surface and
> signal-driven updates are implemented; the slices below are what remains.

## Goal

Surface a paired phone inside the shell — battery, notifications, media, file
send, clipboard, find-my-phone — backed by either **KDE Connect** or **Valent**,
whichever the user has installed.

## Current state

The first slice exists on this branch:

- `services/PhoneConnect.qml` — `busctl --json=short` transport (the
  recommendation below), backend detection from the bus name list, one
  normalized device/battery model for both daemons, ring/ping/clipboard
  actions, clean degraded state when neither daemon runs.
- Sidebar surface: a quick toggle (classic + android styles) and a device
  dialog, following the Tailscale surface pattern rather than a bundled
  plugin — the toggle hides when no daemon runs (classic) or is opt-in
  (android), so the "dead widget for phoneless users" concern is answered
  without plugin packaging. A bundled *desktop-widget* plugin remains a
  possible follow-up, not a replacement.
- Config (`networking.phoneConnect`) + settings rows, and a contract test
  keeping the service's parser logic byte-for-byte in sync with the QML
  suite's logic-only double.

**Slice 1 (signal-driven updates) has landed.** KDE Connect's state now
arrives when it changes rather than on the next tick:

- One `busctl --user --json=short monitor --match=…` per daemon appearance,
  subscribed to `type='signal',sender='org.kde.kdeconnect.daemon',
  path_namespace='/modules/kdeconnect'`. The filter is at the BUS because it
  has to be: `busctl monitor` reports a signal's sender as the unique name it
  arrived on (`:1.55`, captured live), so nothing in QML can tell the daemon's
  signals from anyone else's on the same path.
- The event set came from introspecting a live daemon rather than from the
  fork's source — `/modules/kdeconnect` emits `deviceAdded`, `deviceRemoved`,
  `deviceListChanged`, `deviceVisibilityChanged`, `pairingRequestsChanged`; a
  device path emits `reachableChanged`, `pairStateChanged`, `nameChanged`,
  `typeChanged`, `pluginsChanged`; the battery leaf emits `refreshed`. It is an
  allowlist because the SMS plugin's conversation signals share the device
  path. A signal restarts a 120ms settle rather than sweeping: one device
  leaving the network emitted **seven** signals within a millisecond of each
  other on the live daemon.
- Lifetime, which is what CONTRIBUTING.md forbids getting wrong: no `running`
  binding, capped exponential backoff (1s…30s), a retry ceiling of five per
  daemon appearance, and a healthy-run reset so one daemon restart in a long
  session does not spend the ceiling. Past the ceiling the poll is the whole
  update path again. Measured: `busctl` handed a match rule the bus rejects
  exits in milliseconds (`Invalid match rule`, exit 1), which is exactly the
  respawn loop the rule exists for.
- The poll did **not** go away. Nothing announces a daemon *appearing* (there
  is no monitor running to hear it on), and a daemon that dies without a
  parting signal would freeze the model — so the timer stays on, gated exactly
  as before, at a reconcile cadence while the stream is live.
- **Valent still polls, explicitly.** No live Valent daemon was reachable to
  verify its signal set, so `monitorMatchRule("valent")` is `""` and nothing
  spawns a monitor for it. A signal path that only works for one backend is a
  regression in the other. Verifying it is the prerequisite for changing this,
  and the shape is already there: an ObjectManager `InterfacesAdded`/`Removed`
  plus `PropertiesChanged` on the device paths and `org.gtk.Actions.Changed`
  are the *plausible* rule, and plausible is not verified.
- Covered by `tests/tst_phone_connect.qml` (the match rule, the monitor-line
  parser against verbatim captured lines, the event allowlist, the backoff
  ladder and the restart plan), `tests/test_phone_connect_contract.py` (the
  lifetime as source shape) and `tests/test_phone_connect_monitor_runtime.py`
  (a real shell against a fake `busctl` that streams in one case and exits
  instantly in the other, with the spawn timestamps read back).

One finding worth carrying into slice 2: the monitor's gate was first written
as a `readonly property bool` read from `onBackendChanged`, which is AGENT.md's
change-handler trap — it answered with the previous backend, the monitor never
started, and nothing showed it because the poll kept the model correct. It is a
function now.

## Prior art: P3DROVFX/ii-p3drovfx

Recorded because the next slice is decided from it, not because any of it is
imported. [ii-p3drovfx](https://github.com/P3DROVFX/ii-p3drovfx) is a
standalone illogical-impulse derivative (GPL-3.0, branch `dev`) with a full
KDE Connect phone tab. Its phone feature landed in `c43837f07` (2026-06-22,
"feat: bunch of things") and was iterated through `e31a3b00d` (2026-08-17);
the commits worth reading are `74c5df003` (dedupe kdeconnectd's own desktop
notifications), `4af16caf0` (`qdbus` binary resolution), `3a7f653b4` (SFTP
target directory) and `5688f2fbe` (contacts). Paths below are relative to its
`dots/.config/quickshell/ii/`, checked against a local clone at that head.

**Transport — where we differ, and should keep differing.**

- KDE Connect only. No Valent, no backend abstraction: `org.kde.kdeconnect`
  is hardcoded in `scripts/kdeconnect/monitor.py:18-24`, and availability is
  `command -v kdeconnect-cli` (`services/KdeConnectService.qml:292`).
- Reads go through a Python + Gio sidecar. `services/KdeConnectService.qml`
  (~1947 lines) spawns `scripts/kdeconnect/monitor.py`, which does an initial
  `GetAll` dump per device (`monitor.py:168-193`) and then subscribes to
  signals: `deviceAdded`/`deviceRemoved`/`deviceVisibilityChanged`/
  `pairingRequestsChanged` on the daemon (`monitor.py:388-391`),
  `PropertiesChanged` on the device, `battery.refreshed`,
  `connectivity_report.refreshed`, the four `notifications.*` signals,
  `share.shareReceived` and `pairStateChanged` per device
  (`monitor.py:284-334`). Events are JSON-per-line on stdout, parsed by a
  `SplitParser` (`KdeConnectService.qml:426-448`). Needs PyGObject
  (`monitor.py:41-45`). On exit the service restarts it from a 4 s one-shot
  timer with no backoff (`KdeConnectService.qml:460-478`), preceded by a
  `pkill -f kdeconnect/monitor.py` (`:410`).
- Writes go through `qdbus`, resolved at call time and interpolated into
  `Quickshell.execDetached(["bash", "-c", ...])` with a home-grown
  `_shellQuote` (`_call()` at `KdeConnectService.qml:1429-1442`,
  `_shellQuote` at `:1500-1502`; `acceptPairing`/`declinePairing` at
  `:990-1018` splice `devId` in unquoted). That is a string-built shell for
  every action. A second one-shot script, `scripts/kdeconnect/
  fetch_notifications.py`, exists because `qdbus` wraps replies in
  `[Variant(QString): "..."]` and broke `JSON.parse` (its module docstring,
  and `KdeConnectService.qml:820-826`).

Ours is the stronger transport on every axis that matters here: `busctl
--json=short` with argv arrays and no shell (`services/PhoneConnect.qml:182-
184`), no sidecar and no Python dependency, both daemons behind one model, and
a parser held byte-for-byte to a test double
(`tests/test_phone_connect_contract.py`). What it lacks is the *shape* of the
feature above the transport, which is what the fork has and we borrow.

**Feature surface (what a finished phone tab looks like).**

- Device list with a persisted active device and an MRU list
  (`Persistent.states.sidebar.policies.phone.{activeDeviceId, recentDeviceIds}`,
  `KdeConnectService.qml:34-58, 712-737`), and a per-device
  `cachedNotificationsJson` so the tab is not empty on startup
  (`:1769-1813`).
- Pairing requests surfaced as accept/decline banners in the tab
  (`modules/ii/sidebarPolicies/phone/Phone.qml:760,780`), fed by both
  `pairingRequestsChanged` and `pairStateChanged == 2` (`monitor.py:236-244,
  329-334`). This answers our open question: pairing *is* driveable from the
  shell, and it is two D-Bus methods on the device path.
- Battery plus cellular type/strength from `connectivity_report`
  (`monitor.py:190-193, 292-297`); `reachableAddresses` is read off the
  device (`monitor.py:180`) and later reused for wireless ADB. Low-battery
  hooks: `activeDeviceBatteryLow` at <20% not charging, `Recovered` at ≥25%
  or charging (`KdeConnectService.qml:615-628`).
- Actions: `findmyphone.ring`, `ping.sendPing`, `clipboard.sendClipboard`,
  `share.shareUrl`, `share.shareText` (`:957-988`); file send via
  kdialog/zenity picker or a `DropArea`, each path sent as
  `share.shareUrl("file://…")` (`:1401-1427`, `Phone.qml:1125`); incoming
  `share.shareReceived` re-emitted as a signal (`:552-553`).
- Full notification mirroring: list, group by app
  (`modules/common/widgets/RemoteNotification{ListView,Group,Item}.qml`),
  inline reply via `notifications.sendReply` with a delayed re-fetch because
  the phone updates the body after the daemon's `notificationUpdated`
  (`:929-955`), package extracted from `internalId` `0|<pkg>|…`
  (`monitor.py:222-228`), "open on phone" via scrcpy plus `adb shell monkey`
  (`:1239-1282`). Dismiss calls the *leaf* method
  `notifications.notification.dismiss` on
  `/…/notifications/<publicId>`; the comment at `:883-901` records that
  `sendAction(key, "cancel")` is a no-op because "cancel" is not a registered
  Android action, which is the kind of finding worth not re-learning. And it
  hides kdeconnectd's own desktop notifications while the tab is live:
  `services/Notifications.qml:206-215` drops any notification whose
  `appName` is `kdeconnect`/`kde connect`/`org.kde.kdeconnect` or equals a
  paired device's name, but only when the phone tab is enabled and the active
  device is reachable — otherwise the daemon's notification is the only one
  the user would get.
- SFTP mount/unmount/browse (`:1027-1043`), contacts read from
  `~/.local/share/kpeoplevcard/kdeconnect-*` vCards
  (`scripts/kdeconnect/contacts_monitor.py:27-40`), and scrcpy/adb/droidcam
  glue (`scripts/phone/`, `services/Phone{Scrcpy,Camera,Mic}Service.qml`) —
  the last group is out of our scope.
- Not implemented there either: `mprisremote`, `mousepad`, telephony/SMS,
  `systemvolume`, `lockdevice`, `runcommand`, clipboard *receive*.

UI: sidebar Policies → Phone tab (`modules/ii/sidebarPolicies/phone/*`), a bar
indicator (`modules/ii/bar/widgets/indicators/PhoneScrcpyIndicator.qml`), a
dock widget (`modules/ii/dock/DockPhoneWidget.qml`), the dynamic island as a
drop target (`modules/ii/dynamicIsland/DynamicIslandPanel.qml:1151-1172`),
desktop battery widgets (`modules/ii/background/widgets/bluetooth/
MobileBatteryWidget.qml` and siblings), and a settings page
(`modules/settings/configs/DevicesPhoneConfig.qml`). Config lives under
`Config.options.phone.*` with a `policies.phone` gate.

Other Quickshell implementations worth a glance before the notification
slice: AvengeMedia/dms-plugins `DankKDEConnect` (which carries a
`ValentService.qml`, the only one seen so far) and
noctalia-dev/legacy-v4-plugins `kde-connect` and `valent-connect`.

## Next slices

Ordered by value. Each borrows the fork's shape and none of its transport:
every read is a `busctl` argv, every write goes through `runAction`, and both
backends stay behind the one model.

**Slice 1 (signal-driven updates) is done** — see "Current state" above. The
next slice is now notification mirroring, and it inherits the stream: its
signals go in `signalChangesDevices`' allowlist and the match rule already
covers the whole `/modules/kdeconnect` namespace, so nothing about the
transport has to be rebuilt for it. What is still open from slice 1 is Valent:
its signal set was not verifiable and it keeps the poll until it is.

1. **Notification mirroring.** Borrow: the leaf `notification.dismiss` (not
   `sendAction("cancel")`), `sendReply` with a re-fetch, `internalId` →
   package, group-by-app, and the dedupe rule against kdeconnectd's own
   desktop notifications with its "only while we are showing them" gate. Not:
   the second `RemoteNotification*` list — the "Approach" below still says
   route through the shell's own notification system, and that is the
   decision to make first; the parallel-list design is what makes the dedupe
   necessary. Not: the qdbus/`fetch_notifications.py` split; one `busctl`
   `GetAll` per leaf covers it. Not: "open on phone" — that is scrcpy+adb,
   out of scope.
2. **`connectivity_report` and `reachableAddresses`.** One more `GetAll` on
   the device path and one more signal, both already in the fork's event set;
   the model gains cellular type/strength. Cheap now the stream exists.
3. **Pairing requests.** Accept/decline banners in the device dialog, fed by
   `pairingRequestsChanged` and `pairStateChanged`; the calls are
   `acceptPairing`/`cancelPairing` on the device path. This closes the "Open
   questions" item — the fork shows it wraps cleanly. Not: interpolating
   `devId` into a shell string; the id is validated (`validDeviceId`) and
   passed as an argument.
4. **Send and receive.** `share.shareUrl("file://…")` for file send, drop
   target on the drop shelf (`modules/imi/dropShelf/`) rather than a picker
   dialog, and `share.shareReceived` surfaced as a notification. Not: the
   kdialog/zenity picker chain.
5. **SFTP mount/browse.** `sftp.mount`/`unmount` plus a file-manager open;
   the fork's `3a7f653b4` records that the mount root is not the user's
   storage — open `<mount>/storage/emulated/0` when it exists.
6. **Persisted active device, MRU, and low-battery hooks.** Small; take the
   thresholds (<20% not charging, recover at ≥25% or charging) as they are.

Still open regardless: media (`mprisremote`), clipboard *receive*, and Valent
action coverage beyond `findmyphone.ring` (its other action names were not
verifiable without a live Valent daemon — ping/clipboard are KDE Connect-only
for now). None of these have prior art in the fork.

## Transport constraint (read this first)

**The shell has no D-Bus binding today.** Every service integrates by shelling
out through `Process` — see `services/Brightness.qml:71,90,134` for the pattern.
Both KDE Connect and Valent are D-Bus daemons, so this proposal has to pick a
transport rather than assume one:

- **CLI wrapper** (`kdeconnect-cli`) — matches every existing service, no new
  dependency, but polling-only and awkward for live notification streams.
- **`busctl --json=short` via `Process`** — still shells out, so it fits the
  established pattern, and `busctl monitor` can stream signals rather than
  poll. Structured JSON output parses cleanly.
- **A real D-Bus binding** — cleanest for a notification-mirroring feature, but
  it is a new integration primitive for this codebase and should be justified
  on its own rather than smuggled in with a feature.

Recommendation: `busctl --json` via `Process`, because the interesting features
(notification mirroring, battery updates) are event-driven, and polling them
would be both laggy and wasteful.

## Why

- A phone panel is one of the most-requested desktop-shell features and one of
  the few remaining reasons to keep a separate KDE Connect tray applet running
  alongside the shell.
- Both daemons expose the same conceptual objects (device, battery, notification,
  share, clipboard), so a single abstraction can cover both rather than picking
  a winner and alienating users of the other.
- Valent is the actively maintained GNOME-side implementation; KDE Connect is
  the incumbent. Supporting only one would be a coin flip.

## Approach

- New `services/PhoneConnect.qml`: detects which daemon is running, normalizes
  both onto one device model (`id`, `name`, `type`, `reachable`, `paired`,
  `battery`, `charging`), and exposes actions (`ping`, `ring`, `sendFile`,
  `sendClipboard`).
- Backend detection at startup, with the chosen backend exposed as a read-only
  property so the UI can say which one is in use and degrade honestly when
  neither is installed.
- A right-sidebar surface for device state, plus a quick toggle following the
  existing `modules/common/models/quickToggles/` pattern.
- Notification mirroring routes through the shell's existing notification
  system rather than introducing a parallel one.
- Ship it as a **bundled plugin**, not a hardcoded surface, so users without a
  phone are not carrying a dead widget. This also exercises the plugin API on a
  non-trivial integration.

## Open questions

- Whether pairing should be driveable from the shell or deferred to the
  daemon's own UI. Pairing involves a confirmation on both ends and is
  security-relevant; wrapping it badly is worse than not wrapping it.
- Whether file-send should accept drops onto the drop shelf
  (`modules/imi/dropShelf/`), which already handles mid-drag interaction.

## Out of scope

- Implementing the KDE Connect protocol directly.
- Any feature requiring a companion app change on the phone.
