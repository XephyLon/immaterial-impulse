pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Quickshell
import QtQuick
import QtQuick.Layouts

// The battery of every connected Bluetooth device that reports one, as a
// circled device glyph with a level ring - the resource monitor's
// vocabulary: an outlined ring under every bar style but M3, where the
// tonal pill is the container and the ring is filled. The level itself is
// BluetoothStatus.batteryLevelOf, the one lookup the quick toggle, the
// device dialog and At-a-glance share, so a controller only UPower knows
// about is on the bar too. Hover lists the devices; a click deep-links to
// the Bluetooth dialog in the right sidebar.
MouseArea {
    id: root
    property bool vertical: false
    readonly property bool isMaterial: Config.options.bar.cornerStyle === 3
    readonly property var devices: BluetoothStatus.batteryDevices
    readonly property bool populated: root.devices.length > 0
    // The laptop battery's own low threshold: one number for "low" on the bar.
    readonly property real lowLevel: Config.options.battery.low / 100

    // Nothing to draw collapses the whole slot: a zero-size widget lets the
    // group around it close, where a hidden one would leave the padding.
    visible: root.populated
    implicitWidth: !root.populated ? 0 : root.vertical
        ? Appearance.sizes.verticalBarWidth
        : (rowLoader.item?.implicitWidth ?? 0) + (root.isMaterial ? 0 : Appearance.spacing.space150 * 2)
    implicitHeight: !root.populated ? 0 : root.vertical
        ? (colLoader.item?.implicitHeight ?? 0)
        : Appearance.sizes.barHeight

    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    cursorShape: Qt.PointingHandCursor
    onClicked: {
        GlobalStates.sidebarRightDialog = "bluetooth";
        GlobalStates.sidebarRightOpen = true;
    }

    function glyphFor(device) {
        return Icons.getBluetoothDeviceMaterialSymbol(device?.icon || "");
    }

    Component {
        id: outlineRing
        ClippedOutlineCircularProgress {
            id: ring
            property var device: null
            readonly property real level: BluetoothStatus.batteryLevelOf(ring.device)
            readonly property bool low: ring.level <= root.lowLevel
            implicitSize: 20
            lineWidth: Appearance.rounding.unsharpen
            value: Math.max(0, ring.level)
            colPrimary: ring.low ? Appearance.colors.colError : Appearance.colors.colOnSecondaryContainer
            enableAnimation: false
            Item {
                anchors.centerIn: parent
                width: 20
                height: 20
                MaterialSymbol {
                    anchors.centerIn: parent
                    font.weight: Font.DemiBold
                    fill: 1
                    text: root.glyphFor(ring.device)
                    iconSize: Appearance.font.pixelSize.normal
                    color: ring.low ? Appearance.colors.colError : Appearance.colors.colOnSecondaryContainer
                }
            }
        }
    }

    Component {
        id: filledRing
        ClippedFilledCircularProgress {
            id: ring
            property var device: null
            readonly property real level: BluetoothStatus.batteryLevelOf(ring.device)
            readonly property bool low: ring.level <= root.lowLevel
            implicitSize: 20
            lineWidth: Appearance.rounding.unsharpen
            value: Math.max(0, ring.level)
            colPrimary: ring.low ? Appearance.colors.colError : Appearance.colors.colOnSecondaryContainer
            accountForLightBleeding: !ring.low
            enableAnimation: false
            Item {
                anchors.centerIn: parent
                width: 20
                height: 20
                MaterialSymbol {
                    anchors.centerIn: parent
                    font.weight: Font.DemiBold
                    fill: 1
                    text: root.glyphFor(ring.device)
                    iconSize: Appearance.font.pixelSize.normal
                    color: ring.low ? Appearance.colors.colError : Appearance.m3colors.m3onSecondaryContainer
                }
            }
        }
    }

    // Horizontal: a row of rings.
    Loader {
        id: rowLoader
        active: !root.vertical
        visible: active
        anchors.centerIn: parent
        sourceComponent: RowLayout {
            spacing: Appearance.spacing.space75
            Repeater {
                model: ScriptModel { values: root.devices }
                delegate: Loader {
                    required property var modelData
                    Layout.alignment: Qt.AlignVCenter
                    sourceComponent: root.isMaterial ? filledRing : outlineRing
                    onLoaded: item.device = modelData
                }
            }
        }
    }

    // Vertical: the same rings stacked.
    Loader {
        id: colLoader
        active: root.vertical
        visible: active
        anchors.centerIn: parent
        sourceComponent: ColumnLayout {
            spacing: Appearance.spacing.space75
            Repeater {
                model: ScriptModel { values: root.devices }
                delegate: Loader {
                    required property var modelData
                    Layout.alignment: Qt.AlignHCenter
                    sourceComponent: root.isMaterial ? filledRing : outlineRing
                    onLoaded: item.device = modelData
                }
            }
        }
    }

    BluetoothBatteryPopup {
        hoverTarget: root
    }
}
