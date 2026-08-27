# Proposal: Phone Connect (KDE Connect / Valent integration)

> Draft / tracking proposal. The service, its sidebar surface,
> signal-driven updates, the connectivity report and pairing are
> implemented; the slices below are what remains.

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

**Slices 2 and 3 have landed**, and the sidebar surface was reshaped with
them:

- **`connectivity_report` and `reachableAddresses`** (f7a2952ed
  "feat(phoneConnect): read connectivity_report and reachableAddresses onto
  the device model"). One more `GetAll` per device, at the report's own
  leaf path, plus the device's `reachableAddresses` property it was already
  fetching; the model gains `reachableAddresses` (string entries only),
  `cellularNetworkType` and `cellularNetworkStrength` (-1 when unknown), and
  `connectivity_report.refreshed` joins the monitor's allowlist. Shapes read
  off the live daemon: `reachableAddresses ["192.168.100.179"]`, the report
  `{cellularNetworkType "LTE", cellularNetworkStrength 4}`. The finding
  worth keeping: a `GetAll` naming the report's interface on the *device*
  path is not an error — Qt's adaptor answers with every device property —
  so the contract pins the leaf path, not the interface name. Valent
  carries the fields at their "unknown" values.
- **Pairing requests** (9395932d3 "feat(phoneConnect): surface a peer's
  pairing request, and answer it"). This closes the open question below:
  pairing *is* driveable from the shell, and it is `acceptPairing` /
  `cancelPairing` on `org.kde.kdeconnect.device` at the device path,
  introspected live. A request is `pairState` 2 (`Device::PairState`: 0
  NotPaired, 1 Requested by us, 2 RequestedByPeer, 3 Paired) or the older
  `isPairRequestedByPeer` bool; the model carries `hasPairingRequest` and a
  derived `pairingRequests` list. Neither answer falls back to the active
  device the way `ring()` does — that device is the paired phone, which
  never asked — and the id reaches the path as a validated argument, never
  through a shell string (the fork splices `devId` unquoted into `bash -c`).
  Valent stays at `hasPairingRequest: false`, unverified.
- **The surface** (0c6429028 "feat(phoneConnect): the dialog becomes a device
  chip, pills, one action row and a notification area"). The device dialog
  now follows the layout the maintainer rated on the fork: the device on a
  chip whose arrow opens the roster; a connection pill (the wireless address
  from `reachableAddresses`, or Offline), a battery pill and a cellular
  pill; ONE row of round actions — ring, ping, clipboard, the three the
  model answers, where the fork's other three are scrcpy, a file picker and
  SFTP and are not drawn; the notification area owning the remaining height
  with a real empty state (it says why while there is nothing to show — no
  busctl, no daemon, no devices, not mirrored yet); and the secondary
  features as cards stacked at the bottom, today the pairing request with
  Accept and Decline. The roster row a user picks becomes the device the
  chip, the pills and the actions are about, for the session — the
  persisted choice is slice 6. `tests/test_phone_connect_contract.py` holds
  the surface to the actions the model declares, and
  `tests/test_phone_connect_dialog_runtime.py` builds the real dialog over
  the real service against a fake daemon and reads all of it back,
  including the area growing by exactly a card when that card goes.

**Slices 4, 5 and 6 have landed** on the service; the buttons that reach
them are the Phone tab's (`docs/superpowers/specs/2026-08-27-phone-tab-design.md`,
W5), so the dialog still draws three actions until the tab replaces it.

- **Actions queue** (c7e160da1 "feat(phoneConnect): actions queue behind one
  another instead of killing the one in flight"). Measured first: `Process.exec`
  on a Process still running terminates it (exit 15, status 1, no output), so
  `runAction` fed straight from `exec` kept the last action of a burst and
  killed the rest — and one `shareUrl` per file IS a burst. `runAction` pushes
  onto a queue the Process's own exit pumps. Feedback is one channel
  (d021d10b0 "feat(phoneConnect): lastActionError and an actionFeedback signal
  for toasts"): every action raises `actionFeedback(message, ok)`, every
  failure sets `lastActionError` through one `reportFailure`.
- **Send** (39f359ad4 "feat(phoneConnect): shareUrls and shareText through
  the share plugin"; 8c29fc2be "feat(phoneConnect): share the clipboard as a
  link or as text"; 58f4cd225 "feat(phoneConnect): pick files with kdialog
  and share each as a file URL"). `share.shareUrl`/`shareText` on the
  device's `/share` leaf, one string argument each (busctl signature `s`),
  never a shell — the fork's `_shellQuote` has no counterpart here.
  `shareClipboard` reads `wl-paste --no-newline` as a constant argv and
  decides through the fork's heuristic (`/^https?:\/\//i`, or a host-shaped
  token that is the whole string or starts a path), with one correction: a
  bare host leaves with `https://` on it, because the daemon hands the string
  to a `QUrl` and `example.org` is relative to nothing. The picker is the
  house `kdialog --getopenfilename $HOME --multiple` (the wallpaper picker's
  shape), its lines percent-encoded per segment before `file://` for the same
  `QUrl` reason — a raw `#` in a filename is a fragment. Not taken: the
  zenity fallback, and the proposal's own "drop shelf rather than a picker":
  the spec answered both, the picker here and a `DropArea` on the tab.
- **SFTP** (c487842e4 "feat(phoneConnect): browse the phone over SFTP,
  opening its storage when it has one"). `sftp.mount`, then — on the read
  queue, not the action process — `isMounted` every 600 ms up to ten times
  (`mount()` returns before sshfs is up), then `mountPoint`, then a `test -d`
  argv on `<mount>/storage/emulated/0` (the fork's 3a7f653b4: the mount root
  is not the user's storage), then `xdg-open` on whichever exists.
  `sftpMounted` is the daemon's last `isMounted` answer. Not taken: `gio open`
  ahead of `xdg-open`, and the unmount — nothing in the tab asks for it yet.
- **Persisted device, MRU, battery** (b603cbeb7 "feat(phoneConnect):
  remember the picked device, and the five picked before it"; cdad588f8
  "feat(phoneConnect): a low-battery notice once, and a recovery notice").
  `Persistent.states.phone.{activeDeviceId, recentDeviceIds}`; `activeDevice`
  prefers the persisted device while it is paired and reachable, else the
  rule that was there. The MRU walk goes by index because a `list<string>`
  off a `JsonAdapter` fails `Array.isArray`. The thresholds are the
  proposal's, literally, pinned as numbers in `tests/tst_phone_connect.qml`:
  low once below 20 and not charging, recovered at 25 or on charging; the
  fork's extra guard on the previous charge being ≥ 20 (which kept a phone
  already at 15% at boot silent) is not carried.

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

**Slices 1 (signal-driven updates) through 6 are done** — see "Current
state" above. The next slice is now notification mirroring, and it inherits
the stream and the surface: its signals go in `signalChangesDevices`'
allowlist, the match rule already covers the whole `/modules/kdeconnect`
namespace, and the notification area is already the fill item waiting for
it, so nothing about the transport or the layout has to be rebuilt. What is
still open from slice 1 is Valent: its signal set was not verifiable and it
keeps the poll until it is.

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
2. **`connectivity_report` and `reachableAddresses`.** Done — see "Current
   state". One more `GetAll` per device, at the report's own leaf path, and
   one more signal; the model carries the addresses and the cellular
   type/strength.
3. **Pairing requests.** Done — see "Current state". Accept/decline cards in
   the device dialog, fed by `pairingRequestsChanged` and `pairStateChanged`
   through the stream; the calls are `acceptPairing`/`cancelPairing` on the
   device path, aimed only at a device that asked, with the id validated and
   passed as an argument rather than interpolated into a shell string.
4. **Send and receive.** Done for the send half — see "Current state":
   `share.shareUrl("file://…")` per file, the clipboard as a link or text,
   and the house kdialog picker (the spec overruled "rather than a picker":
   the tab gets a `DropArea` as well). Still open: `share.shareReceived`
   surfaced as a notification, which belongs with notification mirroring.
5. **SFTP mount/browse.** Done — see "Current state". `sftp.mount`, a
   bounded wait on `isMounted`, `mountPoint`, and `<mount>/storage/emulated/0`
   when it exists. Unmount is not wired; nothing asks for it yet.
6. **Persisted active device, MRU, and low-battery hooks.** Done — see
   "Current state", thresholds taken literally.

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

- ~~Whether pairing should be driveable from the shell or deferred to the
  daemon's own UI.~~ Answered by slice 3: it is, as two methods on the device
  path, and the wrapping is narrow on purpose — an answer is refused for any
  device that has not asked, the card says to accept only a pairing the user
  started on that device, and nothing about the id ever reaches a shell.
- ~~Whether file-send should accept drops onto the drop shelf
  (`modules/imi/dropShelf/`), which already handles mid-drag interaction.~~
  Answered by the Phone tab spec: both — the picker landed with slice 4 on
  the service, and the tab carries a `DropArea` that hands dropped `file://`
  URLs to the same `shareUrls`.

## Out of scope

- Implementing the KDE Connect protocol directly.
- Any feature requiring a companion app change on the phone.
