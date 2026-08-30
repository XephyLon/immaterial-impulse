import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import Quickshell.Bluetooth
import QtQuick
import QtQuick.Layouts

DialogListItem {
    id: root
    required property var device
    // " • 80%" or "", worked out by whoever has the battery sources; the
    // row only appends it.
    property string batterySuffix: ""
    property bool expanded: false
    pointingHandCursor: !expanded

    onClicked: expanded = !expanded
    altAction: () => expanded = !expanded
    
    component ActionButton: DialogButton {
        colBackground: Appearance.colors.colPrimary
        colBackgroundHover: Appearance.colors.colPrimaryHover
        colRipple: Appearance.colors.colPrimaryActive
        colText: Appearance.colors.colOnPrimary
    }

    contentItem: ColumnLayout {
        anchors {
            fill: parent
            topMargin: root.verticalPadding
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        spacing: 0

        RowLayout {
            // Name
            spacing: Appearance.spacing.space150

            MaterialSymbol {
                iconSize: Appearance.font.pixelSize.larger
                text: Icons.getBluetoothDeviceMaterialSymbol(root.device?.icon || "")
                color: Appearance.colors.colOnSurfaceVariant
            }

            ColumnLayout {
                spacing: Appearance.spacing.space25
                Layout.fillWidth: true
                // The device's own advertised name is the only thing telling
                // two of the same model apart, and a Bluetooth name is
                // routinely long enough to reach this row's width - the
                // sibling status line below is this repo's own short string
                // and stays elided.
                MarqueeText {
                    Layout.fillWidth: true
                    color: Appearance.colors.colOnSurfaceVariant
                    text: root.device?.name || Translation.tr("Unknown device")
                }
                StyledText {
                    visible: (root.device?.connected || root.device?.paired) ?? false
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    text: {
                        if (!root.device?.paired) return "";
                        const statusText = root.device?.connected ? Translation.tr("Connected") : Translation.tr("Paired");
                        return statusText + root.batterySuffix;
                    }
                }
            }

            MaterialSymbol {
                text: "keyboard_arrow_down"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer3
                rotation: root.expanded ? 180 : 0
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }

        RowLayout {
            visible: root.expanded
            Layout.topMargin: Appearance.spacing.space100
            Item {
                Layout.fillWidth: true
            }
            ActionButton {
                readonly property bool p: root.device?.paired ?? false
                colBackground: p ? Appearance.colors.colError : ColorUtils.transparentize(Appearance.colors.colLayer3, 1)
                colBackgroundHover: p ? Appearance.colors.colErrorHover : ColorUtils.transparentize(Appearance.colors.colLayer3, 1)
                colRipple: p ? Appearance.colors.colErrorActive : Appearance.colors.colLayer3Hover
                colText: p ? Appearance.colors.colOnError : Appearance.colors.colPrimary

                buttonText: p ? Translation.tr("Forget") : Translation.tr("Always connect")
                onClicked: {
                    if (root.device?.paired) {
                        root.device?.forget();
                    } else {
                        root.device?.pair();
                    }
                }
            }
            ActionButton {
                readonly property int deviceState: root.device?.state ?? BluetoothDeviceState.Disconnected
                readonly property bool busy: deviceState === BluetoothDeviceState.Connecting || deviceState === BluetoothDeviceState.Disconnecting

                enabled: !busy
                buttonText: {
                    if (deviceState === BluetoothDeviceState.Connecting) return Translation.tr("Connecting…");
                    if (deviceState === BluetoothDeviceState.Disconnecting) return Translation.tr("Disconnecting…");
                    return root.device?.connected ? Translation.tr("Disconnect") : Translation.tr("Connect");
                }

                onClicked: {
                    if (root.device?.connected) {
                        root.device.disconnect();
                    } else {
                        root.device.connect();
                    }
                }
            }
        }
        Item {
            Layout.fillHeight: true
        }
    }
}
