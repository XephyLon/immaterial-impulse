pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Quickshell
import QtQuick
import QtQuick.Layouts
import "bar_popup_unroll.js" as BarPopupUnroll

// The Bluetooth battery widget's popup: the device to worry about as the
// hero, every connected device as a card below - including the ones with no
// battery report, which the bar draws no ring for but which are still the
// devices that are connected.
StyledPopup {
    id: root

    readonly property var lowest: BluetoothStatus.lowestBatteryDevice
    readonly property var devices: BluetoothStatus.connectedDevices

    function glyphFor(device) {
        return Icons.getBluetoothDeviceMaterialSymbol(device?.icon || "");
    }

    function percentOf(device) {
        return `${Math.round(BluetoothStatus.batteryLevelOf(device) * 100)}%`;
    }

    ColumnLayout {
        spacing: Appearance.spacing.space150

        // The header row is this popup's HERO - the first drawn section,
        // whose height the card opens at - so it never declares `appear`.
        RowLayout {
            id: bluetoothHeaderRow
            Layout.fillWidth: true
            Layout.leftMargin: Appearance.spacing.space50
            spacing: Appearance.spacing.space100

            MaterialShapeWrappedMaterialSymbol {
                shape: MaterialShape.Shape.ClamShell
                text: root.glyphFor(root.lowest)
                iconSize: Appearance.font.pixelSize.large
                implicitSize: 36
                color: Appearance.colors.colPrimaryContainer
                colSymbol: Appearance.colors.colPrimary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: -Appearance.spacing.space50

                StyledText {
                    text: root.lowest?.name ?? Translation.tr("Bluetooth")
                    font {
                        weight: Font.Medium
                        pixelSize: Appearance.font.pixelSize.normal
                    }
                    color: Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurfaceVariant
                    opacity: 0.6
                    text: root.devices.length === 1
                        ? Translation.tr("1 device connected")
                        : Translation.tr("%1 devices connected").arg(root.devices.length)
                }
            }

            Item { Layout.fillWidth: true }

            StyledText {
                Layout.rightMargin: Appearance.spacing.space100
                font.pixelSize: Appearance.font.pixelSize.huge
                font.weight: Font.Bold
                color: Appearance.colors.colPrimary
                text: root.lowest ? `${Math.round(BluetoothStatus.batteryLevelOf(root.lowest) * 100)}` : ""
            }
        }

        GridLayout {
            id: deviceCards
            property real appear: 1
            opacity: deviceCards.appear
            scale: BarPopupUnroll.entranceScale(deviceCards.appear, root.entranceRise, deviceCards.width)
            transform: Translate { y: BarPopupUnroll.entranceOffset(deviceCards.appear, root.entranceRise) }
            Layout.fillWidth: true
            columns: 2
            rowSpacing: Appearance.spacing.space100
            columnSpacing: Appearance.spacing.space100

            Repeater {
                model: ScriptModel { values: root.devices }
                delegate: ResourceCard {
                    required property var modelData
                    readonly property real level: BluetoothStatus.batteryLevelOf(modelData)
                    label: modelData.name
                    iconText: root.glyphFor(modelData)
                    iconShape: MaterialShape.Shape.Clover4Leaf
                    value: Math.max(0, level)
                    sublabel: level >= 0 ? root.percentOf(modelData) : Translation.tr("No battery report")
                    sublabelColor: Appearance.colors.colOnSurfaceVariant
                    // A level, not a usage: empty is the alarm, and it sounds
                    // at the same threshold as the ring on the bar. A device
                    // with no report has no level to alarm about.
                    lowIsWarning: level >= 0
                    warnAt: 1 - Config.options.battery.low / 100
                    cardWidth: 160
                }
            }
        }
    }
}
