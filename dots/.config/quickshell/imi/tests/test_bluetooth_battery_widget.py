#!/usr/bin/env python3
"""The Bluetooth battery widget reads one battery lookup, and follows the bar's rules.

A Bluetooth device's battery comes from two places - BlueZ's Battery1
interface, or the UPower power_supply that carries the device's MAC when
BlueZ has nothing (HID controllers). `BluetoothStatus.batteryLevelOf` is the
one place that knows both; the quick-toggle suffix, At-a-glance and the bar
widget all read it. At-a-glance used to filter on `batteryAvailable` alone,
which is how a controller vanished from it - the drift this file exists to
keep from growing back in the third consumer.

The widget itself follows the resource monitor's ring vocabulary (outlined
ring, filled under M3 - the Docker spelling, checked by the ring contract),
collapses to nothing when no device reports a level, and deep-links its
click to the Bluetooth dialog through GlobalStates.sidebarRightDialog.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
WIDGET = ROOT / "modules/imi/bar/BluetoothBattery.qml"
POPUP = ROOT / "modules/imi/bar/BluetoothBatteryPopup.qml"
SERVICE = ROOT / "services/BluetoothStatus.qml"
AT_A_GLANCE = ROOT / "modules/common/plugins/designsystem/widgets/AtAGlance.qml"
ICONS = ROOT / "modules/common/Icons.qml"
CATALOGUE = ROOT / "modules/common/plugins/BarWidgets.qml"
GLOBAL_STATES = ROOT / "GlobalStates.qml"
SIDEBAR = ROOT / "modules/imi/sidebarRight/SidebarRightContent.qml"


def source(path):
    return re.sub(r"//.*", "", path.read_text(encoding="utf-8"))


class OneBatteryLookupTests(unittest.TestCase):
    def test_the_service_owns_the_lookup_and_the_suffix_formats_it(self):
        service = source(SERVICE)
        self.assertIn("function batteryLevelOf(device)", service)
        suffix = service.split("function formatBatterySuffix(device)", 1)[1].split("\n    }", 1)[0]
        self.assertIn("batteryLevelOf(device)", suffix,
                      "the suffix must format the shared level, not look the battery up again")
        self.assertNotIn("UPower", suffix)
        self.assertIn("property list<var> batteryDevices: connectedDevices.filter(d => batteryLevelOf(d) >= 0)",
                      service)
        self.assertIn("property var lowestBatteryDevice:", service)

    def test_every_other_reader_takes_the_level_from_the_service(self):
        for path in (WIDGET, POPUP, AT_A_GLANCE):
            text = source(path)
            with self.subTest(file=path.name):
                self.assertIn("BluetoothStatus.batteryLevelOf(", text)
                self.assertNotIn("Quickshell.Services.UPower", text,
                                 "the UPower fallback lives in the service, nowhere else")
                self.assertNotIn("batteryAvailable", text,
                                 "gating on batteryAvailable is the copy that lost the controllers")
        self.assertIn("BluetoothStatus.batteryDevices", source(WIDGET))
        self.assertIn("BluetoothStatus.batteryDevices", source(AT_A_GLANCE))

    def test_a_controller_maps_to_its_own_glyph(self):
        icons = source(ICONS)
        body = icons.split("function getBluetoothDeviceMaterialSymbol", 1)[1].split("\n    }", 1)[0]
        self.assertIn('includes("gaming")', body)
        self.assertIn('return "stadia_controller"', body)
        self.assertLess(body.index('"stadia_controller"'), body.index('return "bluetooth"'),
                        "the gamepad branch has to come before the fallback")


class WidgetContractTests(unittest.TestCase):
    def setUp(self):
        self.widget = source(WIDGET)

    def test_the_catalogue_offers_it_with_a_translation_literal(self):
        self.assertRegex(source(CATALOGUE),
                         r'\{\s*id:\s*"bluetoothBattery",\s*name:\s*Translation\.tr\("Bluetooth battery"\)')
        self.assertTrue(WIDGET.is_file(), "the id resolves to BluetoothBattery.qml by capitalisation")

    def test_both_bars_can_orient_it(self):
        self.assertIn("property bool vertical: false", self.widget)

    def test_the_ring_follows_the_style_rule_once_per_orientation(self):
        self.assertIn("readonly property bool isMaterial: Config.options.bar.cornerStyle === 3", self.widget)
        self.assertEqual(self.widget.count("sourceComponent: root.isMaterial ? filledRing : outlineRing"), 2)
        outline = self.widget.split("id: outlineRing", 1)[1].split("Component {", 1)[0]
        self.assertIn("ClippedOutlineCircularProgress {", outline)
        filled = self.widget.split("id: filledRing", 1)[1].split("Loader {", 1)[0]
        self.assertIn("ClippedFilledCircularProgress {", filled)

    def test_nothing_to_draw_collapses_the_slot(self):
        self.assertIn("visible: root.populated", self.widget)
        self.assertRegex(self.widget, r"implicitWidth: !root\.populated \? 0 :")
        self.assertRegex(self.widget, r"implicitHeight: !root\.populated \? 0 :")

    def test_low_is_the_laptop_batterys_own_threshold(self):
        self.assertIn("Config.options.battery.low / 100", self.widget)
        self.assertNotIn("Config.options.bar.bluetoothBattery", self.widget,
                         "no options of its own - the design has none")

    def test_hover_is_the_popup_and_click_is_the_dialog(self):
        self.assertIn("cursorShape: Qt.PointingHandCursor", self.widget)
        self.assertIn("hoverEnabled: !Config.options.bar.tooltips.clickToShow", self.widget)
        self.assertRegex(self.widget, r"BluetoothBatteryPopup \{\s*hoverTarget: root")
        self.assertNotIn("property bool popupOpen", self.widget,
                         "hover-driven: no click-held state, so no anchor indicator")
        click = self.widget.split("onClicked: {", 1)[1].split("}", 1)[0]
        self.assertIn('GlobalStates.sidebarRightDialog = "bluetooth"', click)
        self.assertIn("GlobalStates.sidebarRightOpen = true", click)
        self.assertLess(click.index("sidebarRightDialog"), click.index("sidebarRightOpen"),
                        "the request is written before the open edge that consumes it")


class DeepLinkTests(unittest.TestCase):
    def test_the_sidebar_consumes_the_request_on_every_road_in(self):
        self.assertIn('property string sidebarRightDialog: ""', source(GLOBAL_STATES))
        sidebar = source(SIDEBAR)
        self.assertIn("function consumeDialogRequest()", sidebar)
        body = sidebar.split("function consumeDialogRequest()", 1)[1].split("\n    }", 1)[0]
        self.assertIn('GlobalStates.sidebarRightDialog === "bluetooth"', body)
        self.assertIn("root.showBluetoothDialog = true", body)
        self.assertIn('GlobalStates.sidebarRightDialog = ""', body, "consumed means cleared")
        # Completion (the content is a Loader built on the open edge), the
        # open edge itself, and a write while already open.
        self.assertGreaterEqual(sidebar.count("root.consumeDialogRequest()"), 3)
        self.assertIn("function onSidebarRightDialogChanged()", sidebar)


class PopupContractTests(unittest.TestCase):
    def test_the_popup_lists_every_connected_device_and_names_the_worst(self):
        popup = source(POPUP)
        self.assertIn("BluetoothStatus.lowestBatteryDevice", popup)
        self.assertIn("BluetoothStatus.connectedDevices", popup,
                      "a connected device with no battery report is still listed")
        self.assertIn('Translation.tr("No battery report")', popup)
        self.assertIn("id: bluetoothHeaderRow", popup)
        self.assertIn("id: deviceCards", popup)

    def test_a_battery_card_alarms_at_empty_not_at_full(self):
        # ResourceCard was written for usage, where 100% is the problem; a
        # full battery drawn in the error colour alarms at the state that is
        # fine (the maintainer's 100%-charge-is-not-danger-red, 2026-09-03).
        card = source(ROOT / "modules/common/widgets/ResourceCard.qml")
        self.assertIn("property bool lowIsWarning: false", card)
        self.assertIn("readonly property real strain: root.lowIsWarning ? 1 - root.value : root.value", card)
        self.assertNotRegex(card, r"border\.(width|color): root\.value >",
                            "the warning border reads strain, never value")
        popup = source(POPUP)
        cards = popup.split("id: deviceCards", 1)[1]
        self.assertIn("lowIsWarning: level >= 0", cards,
                      "empty is the alarm - unless there is no level to alarm about")
        self.assertIn("warnAt: 1 - Config.options.battery.low / 100", cards,
                      "the card alarms at the same threshold as the ring on the bar")
        health = source(ROOT / "modules/imi/bar/BatteryPopup.qml").split('Translation.tr("Health")', 1)[1].split("}", 1)[0]
        self.assertIn("lowIsWarning: true", health, "battery health is a level too")


if __name__ == "__main__":
    unittest.main()
