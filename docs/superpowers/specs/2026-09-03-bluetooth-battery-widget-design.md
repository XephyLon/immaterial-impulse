# Bluetooth battery bar widget — design

Approved 2026-09-03 (three questions answered: one ring per device; hover popup
plus click opens the Bluetooth dialog; numeric API on BluetoothStatus with the
drifted copy consolidated).

## Goal

A bar widget that shows the battery of every connected Bluetooth device that
reports one — headphones, mouse, keyboard, controller — as a circled device
glyph with a level ring, in the resource monitor's vocabulary, with a hover
popup listing the devices and a click that opens the existing Bluetooth
device dialog.

## Why now

The battery number is already computed for the quick toggle and the device
dialog (`BluetoothStatus.formatBatterySuffix`), but only as a string, and the
At-a-glance desktop widget re-derived "which devices have a battery" with
`batteryAvailable` alone — so it never sees a controller whose level only
UPower knows. A bar widget is the third consumer; adding it without one
numeric source of truth would be the fourth copy.

## Data: `services/BluetoothStatus.qml`

Additions, all pure over what the singleton already reads:

- `function batteryLevelOf(device) -> real`: `0..1`, or `-1` when neither
  source knows. BlueZ `Battery1` first (`device.batteryAvailable` gates
  `device.battery`), then the UPower device whose `nativePath` contains the
  device's MAC (lower-cased, `!isLaptopBattery`), reading `percentage`.
  `null`/`undefined` device → `-1`.
- `readonly property list<var> batteryDevices`: `connectedDevices` filtered to
  `batteryLevelOf(d) >= 0`, in the existing sort order. A binding, so a
  `battery` change on a device or a UPower device appearing re-evaluates it.
- `readonly property var lowestBatteryDevice`: the `batteryDevices` entry
  with the smallest level, `null` when empty.
- `formatBatterySuffix(device)` becomes ``level < 0 ? "" : ` • ${Math.round(level * 100)}%` ``
  over `batteryLevelOf` — same output as today (the existing tests pin it).

`AtAGlance.qml`'s `updateBluetoothInfo()` reads `BluetoothStatus.batteryDevices`
and `batteryLevelOf` instead of filtering on `batteryAvailable` and reading
`battery` directly. Its `btDevices` trigger property follows `batteryDevices`.

`Icons.getBluetoothDeviceMaterialSymbol` gains a gamepad branch before the
fallback: an icon name containing `gaming` or `gamepad` or `joystick` →
`stadia_controller`. The dialog row, the widget and the popup all use the
mapper, so all three learn it.

## Bar widget: `modules/imi/bar/BluetoothBattery.qml`

Catalogue row in `BarWidgets.qml`:
`{ id: "bluetoothBattery", name: Translation.tr("Bluetooth battery"), icon: "bluetooth_connected" }`.
The resolver turns the id into `BluetoothBattery.qml` by capitalisation, so
the file name is fixed by the id.

Shape, copied from the resource monitor:

- Root is a `MouseArea` (`cursorShape: Qt.PointingHandCursor`, a click
  handler, `hoverEnabled: !Config.options.bar.tooltips.clickToShow`), with the
  duck-typed `property bool vertical: false` both bars write, and
  `readonly property bool isMaterial: Config.options.bar.cornerStyle === 3`.
- One `Repeater` over `BluetoothStatus.batteryDevices` (a `ScriptModel`), in
  a `RowLayout` when horizontal and a `ColumnLayout` when vertical, each
  delegate a ring around the device's glyph
  (`Icons.getBluetoothDeviceMaterialSymbol(device.icon)`), `value` the level.
- The ring is `ClippedOutlineCircularProgress` under every style, and
  `ClippedFilledCircularProgress` only under M3 — chosen by
  `root.isMaterial`, the Docker widget's spelling, once per orientation.
  Ring geometry matches `Resource.qml`: `implicitSize: 20`,
  `lineWidth: Appearance.rounding.unsharpen`, glyph at
  `Appearance.font.pixelSize.normal`, `enableAnimation: false`.
- Colour: `colOnSecondaryContainer` normally (M3: `m3onSecondaryContainer`
  for the glyph); the ring and glyph turn `Appearance.colors.colError` when
  the level is at or below `Config.options.battery.low / 100`, the laptop
  battery's own threshold. No new Config option and no settings row.
- Size contract: horizontal `implicitWidth` is the row's implicit width plus
  `Appearance.spacing.space150` on each side when not M3 (the switcher
  area's `horizontalExtraPadding`), `implicitHeight: Appearance.sizes.barHeight`;
  vertical `implicitWidth: Appearance.sizes.verticalBarWidth`, height the
  column's. With no battery devices both implicit sizes are `0` and the
  widget is `visible: false`, so the group around it collapses.
- Click: `GlobalStates.sidebarRightDialog = "bluetooth"` then
  `GlobalStates.sidebarRightOpen = true`. `GlobalStates` gains
  `property string sidebarRightDialog: ""`, a deep link consumed and cleared
  by `SidebarRightContent` the way `sidebarLeftTab` is (on its own
  completion and on change): `"bluetooth"` sets `showBluetoothDialog`.
  The right sidebar's content is a `Loader` active only while the panel is
  shown, so a property that waits to be consumed is the shape that survives
  the sidebar not existing yet; a signal would be lost.
- M3 pill: the id takes the default tonal role (`colPrimaryContainer`) and
  is not blacklisted.

## Popup: `modules/imi/bar/BluetoothBatteryPopup.qml`

A `StyledPopup { hoverTarget: root }` mounted by the widget, in
`BatteryPopup.qml`'s layout:

- Hero (`id: bluetoothHeaderRow`, never declares `appear`): a
  `MaterialShapeWrappedMaterialSymbol` (ClamShell) with the lowest device's
  glyph, the lowest device's name in the title slot, the subtitle
  `Translation.tr("%1 devices").arg(n)` (or `Translation.tr("1 device")`),
  and the lowest device's percentage large in `colPrimary`.
- Cascade (`id: deviceCards`, `property real appear: 1`, the three entrance
  channels through `bar_popup_unroll.js`): a `Flow`/`RowLayout` of one
  `ResourceCard` per connected device — `label` the device name, `iconText`
  the mapped glyph, `iconShape` Clover4Leaf, `value` the level clamped to
  `0` when unknown, `sublabel` `NN%` or `Translation.tr("No battery report")`
  in `colOnSurfaceVariant`, `cardWidth: 160`. Connected devices with no
  battery are listed here (so a controller BlueZ does not report still
  appears) but do not draw a ring on the bar.

The popup is registered in `test_bar_popup_section_entrance.py`'s
`SECTION_WAVES` with hero `bluetoothHeaderRow` and cascade `deviceCards`.

## Failure modes

- Adapter off or no adapter: `batteryDevices` is empty, widget collapsed,
  nothing else drawn. The popup cannot be reached with nothing to hover.
- A UPower fallback device vanishing mid-session: its level goes to `-1`, the
  ring leaves the bar, the popup row shows "No battery report".
- A device whose `icon` is empty maps to `bluetooth`.
- Mock `BluetoothDevice` gains `property string icon: ""` so tests can name
  a device type.

## Tests

- `tests/tst_bluetooth_status.qml`: `batteryLevelOf` from Battery1, from the
  UPower fallback, `-1` for neither and for `null`; Battery1 wins over the
  fallback; `batteryDevices` keeps only levelled connected devices in sort
  order; `lowestBatteryDevice`; `formatBatterySuffix` parity with
  `batteryLevelOf` (existing cases stay).
- `tests/test_bluetooth_battery_widget.py` (new, wired into `run_tests.sh`):
  the widget and AtAGlance read `BluetoothStatus.batteryDevices` /
  `batteryLevelOf` and neither imports `Quickshell.Services.UPower` or reads
  `batteryAvailable`; the widget declares `property bool vertical`; the
  catalogue row exists with the literal `Translation.tr`; the widget mounts
  its popup with `hoverTarget: root`; the click deep-links through
  `GlobalStates.sidebarRightDialog` and `SidebarRightContent` consumes it;
  `Icons` has the gamepad branch.
- Ratchets updated: `test_bar_icon_ring_contract.py`'s exact user list of
  `ClippedFilledCircularProgress` gains `modules/imi/bar/BluetoothBattery.qml`
  (and the file follows the Docker spelling, asserted in the new test);
  `test_bar_popup_section_entrance.py` gains the popup entry. Catalogue
  count floors (`>= 21`) still hold.
- Existing lints cover the rest: material icon names, spacing tokens,
  pointer cursor, dumb widgets, qmldir/registration, suite registration.

## Docs

- `AGENT.md`: directory-map line under `bar/` naming the widget, and one
  entry: the battery level has one source (`batteryLevelOf`) with three
  consumers (quick toggle + dialog suffix, At-a-glance, bar widget), the
  deep link `GlobalStates.sidebarRightDialog`, and why the widget lists
  battery-less devices in the popup but not on the bar.
- `CHANGELOG.md` `[Unreleased]` → `### Added`.

## Out of scope

Per-device widgets, per-device thresholds, a low-battery notification,
connection-event popups, a settings section of its own.
