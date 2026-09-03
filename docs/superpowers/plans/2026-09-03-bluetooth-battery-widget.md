# Bluetooth battery bar widget — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A bar widget drawing one level ring per connected Bluetooth device that reports a battery, with a hover popup and a click that opens the Bluetooth dialog.

**Architecture:** One numeric lookup on the existing `BluetoothStatus` singleton (`batteryLevelOf`, `batteryDevices`, `lowestBatteryDevice`) feeds the quick-toggle suffix, At-a-glance and the new widget. The widget follows the resource monitor's ring vocabulary and the Docker widget's M3 branch; the popup follows `BatteryPopup`'s hero + cascade layout; the click deep-links through a new `GlobalStates.sidebarRightDialog` consumed by `SidebarRightContent`.

**Tech Stack:** Quickshell QML (Quickshell.Bluetooth, Quickshell.Services.UPower), qmltestrunner tests, Python unittest contracts wired into `tests/run_tests.sh`.

Spec: `docs/superpowers/specs/2026-09-03-bluetooth-battery-widget-design.md`.
All paths below are under `dots/.config/quickshell/imi/` unless they start with `AGENT.md`, `CHANGELOG.md` or `docs/`.

---

### Task 1: The numeric battery API on BluetoothStatus (TDD)

**Files:**
- Modify: `services/BluetoothStatus.qml`
- Modify: `tests/mocks/Quickshell/Bluetooth/BluetoothDevice.qml` (add `icon`)
- Test: `tests/tst_bluetooth_status.qml`

- [ ] **Step 1: Write the failing tests** — append to `tests/tst_bluetooth_status.qml` before the final `}`:

```qml
    function test_battery_level_comes_from_bluez_then_upower_then_nothing() {
        compare(BluetoothStatus.batteryLevelOf(null), -1)
        compare(BluetoothStatus.batteryLevelOf(undefined), -1)
        compare(BluetoothStatus.batteryLevelOf(keyboard), -1)
        compare(BluetoothStatus.batteryLevelOf({ batteryAvailable: true, battery: 0.85 }), 0.85)
        compare(BluetoothStatus.batteryLevelOf({ batteryAvailable: false, battery: 0.5 }), -1)

        UPower.devices.values = [
            { isLaptopBattery: true, nativePath: "BAT0", percentage: 0.99 },
            { isLaptopBattery: false, nativePath: "ps-controller-battery-14:3a:9a:7c:45:47", percentage: 0.45 }
        ]
        compare(BluetoothStatus.batteryLevelOf({ batteryAvailable: false, address: "14:3A:9A:7C:45:47" }), 0.45)
        compare(BluetoothStatus.batteryLevelOf({ batteryAvailable: true, battery: 0.6, address: "14:3A:9A:7C:45:47" }), 0.6)
        compare(BluetoothStatus.batteryLevelOf({ batteryAvailable: false, address: "AA:BB:CC:DD:EE:FF" }), -1)
        // The suffix is the level, formatted - never a second lookup.
        compare(BluetoothStatus.formatBatterySuffix({ batteryAvailable: false, address: "14:3A:9A:7C:45:47" }), " • 45%")
        UPower.devices.values = []
    }

    function test_battery_devices_are_the_connected_ones_with_a_level_in_sort_order() {
        UPower.devices.values = [
            { isLaptopBattery: false, nativePath: "hid-14:3a:9a:7c:45:47-battery", percentage: 0.3 }
        ]
        Bluetooth.devices.values = [
            { name: "Zeta Buds", connected: true, paired: true, batteryAvailable: true, battery: 0.9 },
            { name: "Pad", connected: true, paired: true, batteryAvailable: false, address: "14:3A:9A:7C:45:47" },
            { name: "Mute Mouse", connected: true, paired: true, batteryAvailable: false, address: "AA:BB:CC:DD:EE:FF" },
            { name: "Away Keys", connected: false, paired: true, batteryAvailable: true, battery: 0.1 }
        ]
        compare(BluetoothStatus.batteryDevices.map(d => d.name), ["Pad", "Zeta Buds"])
        compare(BluetoothStatus.lowestBatteryDevice.name, "Pad")

        Bluetooth.devices.values = []
        compare(BluetoothStatus.batteryDevices.length, 0)
        verify(BluetoothStatus.lowestBatteryDevice === null)
        UPower.devices.values = []
    }
```

- [ ] **Step 2: Run to verify they fail** — `cd dots/.config/quickshell/imi && tests/run_tests.sh` is too slow for one case; run the QML runner directly:
  `qmltestrunner -import tests/mocks -import tests/imports -input tests/tst_bluetooth_status.qml` (the runner path is resolved in `run_tests.sh:195`). Expected: FAIL, `batteryLevelOf is not a function`.

- [ ] **Step 3: Implement** — in `services/BluetoothStatus.qml`, replace the `formatBatterySuffix` block (lines 19–37) with:

```qml
    // The one battery lookup every consumer shares - the quick toggle and
    // the device dialog through formatBatterySuffix, At-a-glance, the bar's
    // BluetoothBattery widget: 0..1 when known, -1 when neither source does.
    // Primary source is Quickshell.Bluetooth's BluetoothDevice (BlueZ Battery1
    // interface): `batteryAvailable` gates it, `battery` is a 0..1 fraction.
    // Many devices never get Battery1 (HID controllers like the DualSense, or
    // bluetoothd without Experimental=true), but the kernel exposes them as a
    // power_supply that UPower picks up with the MAC in its nativePath - fall
    // back to that, matched by address.
    function batteryLevelOf(device) {
        if (device?.batteryAvailable)
            return device.battery;
        const addr = device?.address?.toLowerCase() ?? "";
        if (addr) {
            const fallback = (UPower.devices?.values ?? []).find(d =>
                d && !d.isLaptopBattery && (d.nativePath ?? "").toLowerCase().includes(addr));
            if (fallback)
                return fallback.percentage;
        }
        return -1;
    }

    // " • NN%" for a device whose battery level is known, "" otherwise.
    function formatBatterySuffix(device) {
        const level = batteryLevelOf(device);
        return level < 0 ? "" : ` • ${Math.round(level * 100)}%`;
    }
```

  and after `connectedDevices` add:

```qml
    // Connected devices with a known level, in the same order - what the bar
    // widget draws a ring for. A binding: batteryLevelOf reads each device's
    // batteryAvailable/battery and UPower.devices inside it, so a level that
    // arrives after the connection re-evaluates the list.
    readonly property list<var> batteryDevices: connectedDevices.filter(d => batteryLevelOf(d) >= 0)
    readonly property var lowestBatteryDevice: batteryDevices.reduce((low, d) =>
        low === null || batteryLevelOf(d) < batteryLevelOf(low) ? d : low, null)
```

  In the mock `BluetoothDevice.qml` add `property string icon: ""`.

- [ ] **Step 4: Run the QML test file again** — expected: all BluetoothStatusTest cases PASS.
- [ ] **Step 5: Commit** — `git commit --only -- services/BluetoothStatus.qml tests/tst_bluetooth_status.qml tests/mocks/Quickshell/Bluetooth/BluetoothDevice.qml -m "feat(bluetooth): one numeric battery lookup for every consumer"`

### Task 2: Gamepad glyph and At-a-glance consolidation

**Files:**
- Modify: `modules/common/Icons.qml:20-32`
- Modify: `modules/common/plugins/designsystem/widgets/AtAGlance.qml:58,72-81`
- Test: `tests/test_bluetooth_battery_widget.py` (created in Task 5; the assertions for these two files are listed there)

- [ ] **Step 1: Icons** — before `return "bluetooth";` insert:

```qml
        // BlueZ names a controller input-gaming; the fallback glyph hid it
        // behind the generic mark on the bar and in the dialog.
        if (systemIconName.includes("gaming") || systemIconName.includes("gamepad") || systemIconName.includes("joystick"))
            return "stadia_controller";
```

- [ ] **Step 2: AtAGlance** — `property var btDevices: BluetoothStatus.batteryDevices` and:

```qml
    function updateBluetoothInfo() {
        // One lookup for "has a battery" and "how much": BluetoothStatus's,
        // so a controller only UPower knows about counts here too.
        const devices = BluetoothStatus.batteryDevices;
        const percent = d => Math.round(BluetoothStatus.batteryLevelOf(d) * 100) + "%";
        let text = "";
        if (devices.length === 1) {
            text = devices[0].name + " · " + percent(devices[0]);
        } else if (devices.length > 1) {
            text = devices.length + " devices · " + devices.map(percent).join(", ");
        }
```

- [ ] **Step 3: Commit** — `git commit --only -- modules/common/Icons.qml modules/common/plugins/designsystem/widgets/AtAGlance.qml -m "fix(bluetooth): a controller gets its glyph, and At-a-glance reads the shared battery lookup"`

### Task 3: The right-sidebar dialog deep link

**Files:**
- Modify: `GlobalStates.qml` (after `sidebarRightOpen`)
- Modify: `modules/imi/sidebarRight/SidebarRightContent.qml` (function + Connections + Component.onCompleted)

- [ ] **Step 1: GlobalStates**

```qml
    // A dialog the right sidebar opens next time it shows ("bluetooth"),
    // consumed and cleared by SidebarRightContent the way sidebarLeftTab is.
    // A property, not a signal: the sidebar's content is a Loader that only
    // exists while the panel is shown, so a signal fired from the bar before
    // the panel has been built reaches nothing.
    property string sidebarRightDialog: ""
```

- [ ] **Step 2: SidebarRightContent** — add

```qml
    function consumeDialogRequest() {
        if (GlobalStates.sidebarRightDialog === "") return;
        if (GlobalStates.sidebarRightDialog === "bluetooth")
            root.showBluetoothDialog = true;
        GlobalStates.sidebarRightDialog = "";
    }
```

  call it from `Component.onCompleted` (the content is built on the open edge, after `onSidebarRightOpenChanged` has already fired), inside `onSidebarRightOpenChanged` when opening, and from a new `function onSidebarRightDialogChanged() { if (GlobalStates.sidebarRightOpen) root.consumeDialogRequest(); }` in the same `Connections`.

- [ ] **Step 3: Commit** — `git commit --only -- GlobalStates.qml modules/imi/sidebarRight/SidebarRightContent.qml -m "feat(sidebar): a deep link that opens a right-sidebar dialog"`

### Task 4: The widget, its popup and the catalogue row

**Files:**
- Create: `modules/imi/bar/BluetoothBattery.qml`
- Create: `modules/imi/bar/BluetoothBatteryPopup.qml`
- Modify: `modules/common/plugins/BarWidgets.qml:46` (row after `batteryIndicator`)

- [ ] **Step 1: Catalogue row**

```qml
        { id: "bluetoothBattery",  name: Translation.tr("Bluetooth battery"),    icon: "bluetooth_connected" },
```

- [ ] **Step 2: Widget** — `BluetoothBattery.qml` as in the spec: `MouseArea` root, `vertical`, `isMaterial`, `devices: BluetoothStatus.batteryDevices`, collapse to 0 when empty, `RowLayout`/`ColumnLayout` loaders of a `Repeater` whose delegate is a `Loader` picking `root.isMaterial ? filledRing : outlineRing` (one per orientation, so the Docker spelling appears twice) and handing the device over in `onLoaded`; rings sized like `Resource.qml`; error colour at or below `Config.options.battery.low / 100`; `cursorShape: Qt.PointingHandCursor`; `onClicked` sets `GlobalStates.sidebarRightDialog = "bluetooth"` then `GlobalStates.sidebarRightOpen = true`; `BluetoothBatteryPopup { hoverTarget: root }`. Full source is the file itself (written in this task).

- [ ] **Step 3: Popup** — `BluetoothBatteryPopup.qml`: `StyledPopup`, `ColumnLayout` with hero `bluetoothHeaderRow` (ClamShell glyph of the lowest device, its name, `n device(s)` subtitle, its percentage) and cascade `deviceCards` (`GridLayout columns: 2`, `property real appear: 1`, opacity/scale/translate through `bar_popup_unroll.js`, a `Repeater` of `ResourceCard` over `BluetoothStatus.connectedDevices`, sublabel `NN%` or `Translation.tr("No battery report")`).

- [ ] **Step 4: Lints** — `python3 tests/lint_material_icons.py`, `python3 tests/lint_spacing.py`, `python3 tests/lint_clickable_cursor.py`, `tests/lint_qml_imports.sh` all clean.
- [ ] **Step 5: Deploy and look** — `./deploy-shell`, add `bluetoothBattery` to a bar layout, confirm rings, popup, click.
- [ ] **Step 6: Commit** — `git commit --only -- modules/imi/bar/BluetoothBattery.qml modules/imi/bar/BluetoothBatteryPopup.qml modules/common/plugins/BarWidgets.qml -m "feat(bar): a Bluetooth battery widget, one ring per device"`

### Task 5: Contracts and ratchets

**Files:**
- Create: `tests/test_bluetooth_battery_widget.py`
- Modify: `tests/test_bar_icon_ring_contract.py:53` (add the widget to the exact list)
- Modify: `tests/test_bar_popup_section_entrance.py` (SECTION_WAVES entry)
- Modify: `tests/run_tests.sh` (register the new test)

- [ ] **Step 1: New contract test** pins: the widget declares `property bool vertical`, reads `BluetoothStatus.batteryDevices` and `BluetoothStatus.batteryLevelOf`, never imports `Quickshell.Services.UPower` nor reads `batteryAvailable`; `sourceComponent: root.isMaterial ? filledRing : outlineRing` appears twice; `cursorShape: Qt.PointingHandCursor`; the click writes `GlobalStates.sidebarRightDialog = "bluetooth"` and `SidebarRightContent` consumes it; the popup is mounted with `hoverTarget: root`; the catalogue row with its `Translation.tr` literal; `Icons` maps `gaming` to `stadia_controller`; `AtAGlance` reads `batteryDevices` and not `batteryAvailable`; `BluetoothStatus.formatBatterySuffix` calls `batteryLevelOf`.
- [ ] **Step 2: Prove it fails** — run it against a clean `git archive HEAD~N` copy without the widget: expected FAIL.
- [ ] **Step 3: Ratchets** — ring contract list gains `"modules/imi/bar/BluetoothBattery.qml"` (sorted position: after `BatteryIndicator` would be, i.e. first); SECTION_WAVES gains `f"{BAR}/BluetoothBatteryPopup.qml": {"hero_band": ["bluetoothHeaderRow"], "cascades": ["deviceCards"]}`.
- [ ] **Step 4: Register** in `run_tests.sh` next to the applycolor block:

```bash
# The Bluetooth battery widget: one numeric lookup on BluetoothStatus feeds
# the bar rings, At-a-glance and the dialog suffix; the widget follows the
# ring rule and deep-links to the dialog.
echo "Running Bluetooth battery widget contract tests..."
if ! python3 "$SCRIPT_DIR/test_bluetooth_battery_widget.py"; then
    echo "Bluetooth battery widget contract tests failed."
    exit 1
fi
```

- [ ] **Step 5: Commit** — `git commit --only -- tests/test_bluetooth_battery_widget.py tests/test_bar_icon_ring_contract.py tests/test_bar_popup_section_entrance.py tests/run_tests.sh -m "test(bar): pin the Bluetooth battery widget's contracts"`

### Task 6: Docs, changelog, suite

**Files:**
- Modify: `AGENT.md` (bar/ directory-map row; one entry near the icon-ring/PopupAnchorIndicator entries)
- Modify: `CHANGELOG.md` (`[Unreleased]` → `### Added`)

- [ ] **Step 1: AGENT.md** — directory map: name `BluetoothBattery.qml` under `bar/`. Entry: "**A Bluetooth device's battery has one lookup and three readers.**" — `batteryLevelOf` (Battery1 then UPower by MAC, -1 unknown), `batteryDevices`; the readers; the widget draws rings only for levelled devices but lists every connected device in its popup; the click deep-links through `GlobalStates.sidebarRightDialog` (property, not signal — the content Loader). Cite the Task 4 commit subject.
- [ ] **Step 2: CHANGELOG** — `### Added` entry under `[Unreleased]`.
- [ ] **Step 3: Commit** — `git commit --only -- AGENT.md CHANGELOG.md -m "docs: the Bluetooth battery widget and its one battery lookup"`
- [ ] **Step 4: Suite** — `setsid -f bash -c 'cd dots/.config/quickshell/imi && ./tests/run_tests.sh > LOG 2>&1'`; expected `All tests passed successfully!`.
- [ ] **Step 5: Deploy, push branch, open PR** with `Docs: updated AGENT.md §...` and `Changelog: updated` receipts.
