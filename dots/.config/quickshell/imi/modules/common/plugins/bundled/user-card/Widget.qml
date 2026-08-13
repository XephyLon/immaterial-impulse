pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.plugins
import qs.modules.common.plugins.designsystem.widgets as Expressive

Item {
    id: root

    // The host's drag, forwarded to the elevation so the widget lifts while it
    // is handled. A body never told about the drag silently never lifts.
    property bool hostDragging: false

    // The visual is a card with an avatar bubble straddling its top edge, plus
    // the name lines sitting on the bare wallpaper - not one continuous surface.
    // Naming both surfaces keeps the host's frost off the empty corners and off
    // the name text.
    readonly property bool blurEnabled: PluginState.option("user-card", "blurEnabled", false)
    readonly property real backgroundOpacity: PluginState.effectiveBackgroundOpacity("user-card")
    readonly property bool managesBlurTint: true
    readonly property var blurRegions: [
        { x: contentBox.x, y: contentBox.y, width: contentBox.width,
            height: contentBox.height, radius: contentBox.radius },
        { x: avatarRect.x, y: avatarRect.y, width: avatarRect.width,
            height: avatarRect.height, radius: avatarRect.radius }
    ]

    // A 2x2 component-grid tile (276x228). The built-in was 276x252: the width
    // is already exactly spanX(2), and the 24px of height the span does not have
    // comes out of the empty strip above the avatar, so no element changes size.
    // The card is pinned to the bottom of the tile with the avatar hanging off
    // its top edge, exactly as before. The host (PluginWidget) sizes us from the
    // manifest `grid` and stretches this root to fill it; the implicit size is
    // only a fallback for standalone use. See docs/widget-grid.md.
    implicitWidth: Appearance.sizes.widgetGridSpanX(2)
    implicitHeight: Appearance.sizes.widgetGridSpanY(2)
    anchors.fill: parent

    property int blurMargin: Appearance.spacing.space250
    property int avatarSize: 64
    property string hostname: SystemInfo.hostname
    property string username: Config.options.profile.displayName === "" ? SystemInfo.username : Config.options.profile.displayName
    property string userDisplay: username.length > 10 ? username : (username + "@" + hostname)
    property var currentQuip: weatherQuip()

    function weatherQuip() {
        const desc = (Weather.data?.description ?? "").toLowerCase();
        const temp = Weather.data?.temp ?? "--";
        if (desc.includes("rain"))
            return { text: `• raining, grab a coffee`, icon: "coffee" };
        if (desc.includes("clear"))
            return { text: `• good day to touch grass`, icon: "eco" };
        if (desc.includes("cloud"))
            return { text: `• a bit cloudy today`, icon: "cloud" };
        if (desc.includes("snow"))
            return { text: `• snowing`, icon: "ac_unit" };
        return { text: `• ${Weather.data?.description ?? ""}`, icon: "thermostat" };
    }

    // The tokens, not the component. Three surfaces sit on this widget - a
    // rounded card, a bordered circular avatar straddling its top edge, and two
    // name lines on the bare wallpaper - and one shadow has always covered all
    // three, which is what makes the bubble read as fastened to the card and
    // keeps the names legible off it. A WidgetCard renders ONE surface and has
    // no border, so taking the component here would mean three of them, two
    // shadows and no shadow at all under the names.
    Expressive.WidgetElevation {
        id: outerRect
        anchors.fill: parent
        dragging: root.hostDragging

        Rectangle {
            id: contentBox
            anchors {
                left: parent.left
                bottom: parent.bottom
                leftMargin: root.blurMargin
                bottomMargin: root.blurMargin
            }
            width: 240
            color: root.blurEnabled
                ? ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 1 - root.backgroundOpacity)
                : Appearance.colors.colPrimaryContainer
            radius: Appearance.rounding.large
            implicitHeight: contentColumn.implicitHeight + 30

            ColumnLayout {
                id: contentColumn
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    margins: Appearance.spacing.space200
                }
                Layout.topMargin: root.avatarSize / 2 + 4
                spacing: Appearance.spacing.space150

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.avatarSize / 2
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.spacing.space100

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: Appearance.spacing.space25
                        iconSize: Appearance.font.pixelSize.normal
                        text: root.currentQuip.icon
                        color: Appearance.colors.colOnPrimaryContainer
                        opacity: 0.85
                    }

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        // Carries the weather provider's own description string,
                        // so it must not be parsed as markup.
                        textFormat: Text.PlainText
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnPrimaryContainer
                        opacity: 0.85
                        text: root.currentQuip.text
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Appearance.spacing.space50
                    spacing: Appearance.spacing.space100

                    Rectangle {
                        id: lockButton
                        Layout.fillWidth: true
                        implicitHeight: 40
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colOnPrimaryContainer

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: Appearance.spacing.space50
                            MaterialSymbol {
                                iconSize: Appearance.font.pixelSize.normal
                                text: "lock"
                                color: Appearance.colors.colPrimaryContainer
                            }
                            StyledText {
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colPrimaryContainer
                                text: GlobalStates.screenLocked ? "Locked" : "Lock"
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: GlobalStates.screenLocked = true
                        }
                    }

                    Rectangle {
                        id: settingsButton
                        implicitWidth: 40
                        implicitHeight: 40
                        radius: Appearance.rounding.full
                        color: "transparent"
                        border.width: Appearance.borderWidth.standard
                        border.color: Appearance.colors.colOnPrimaryContainer
                        MaterialSymbol {
                            anchors.centerIn: parent
                            iconSize: Appearance.font.pixelSize.normal
                            text: "settings"
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: GlobalStates.settingsOpen = true
                        }
                    }

                    Rectangle {
                        id: sessionButton
                        implicitWidth: 40
                        implicitHeight: 40
                        radius: Appearance.rounding.full
                        color: "transparent"
                        border.width: Appearance.borderWidth.standard
                        border.color: Appearance.colors.colOnPrimaryContainer
                        MaterialSymbol {
                            anchors.centerIn: parent
                            iconSize: Appearance.font.pixelSize.normal
                            text: "power_settings_new"
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: GlobalStates.sessionOpen = true
                        }
                    }
                }
            }
        }

        Rectangle {
            id: avatarRect
            x: root.blurMargin + 16
            y: contentBox.y - root.avatarSize / 2
            width: root.avatarSize + 10
            height: root.avatarSize + 10
            radius: width / 2
            color: root.blurEnabled
                ? ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 1 - root.backgroundOpacity)
                : Appearance.colors.colPrimaryContainer
            border.width: Appearance.borderWidth.heavy
            border.color: Appearance.colors.colLayer1
            z: 2

            Image {
                id: avatarImage
                anchors.fill: parent
                anchors.margins: Appearance.spacing.space50
                source: Config.options.profile.avatarPath !== ""
                    ? "file://" + Config.options.profile.avatarPicture
                    : "file:///home/" + (Quickshell.env("USER") ?? "user") + "/.face"
                sourceSize.width: avatarImage.width * 2
                sourceSize.height: avatarImage.height * 2
                fillMode: Image.PreserveAspectCrop
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: avatarRect.width - 6
                        height: avatarRect.height - 6
                        radius: (avatarRect.width - 6) / 2
                    }
                }
                onStatusChanged: {
                    if (status === Image.Error)
                        visible = false
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: "account_circle"
                iconSize: 32
                color: Appearance.colors.colOnPrimaryContainer
                visible: avatarImage.status === Image.Error
            }
        }

        ColumnLayout {
            id: identityColumn
            x: avatarRect.x + avatarRect.width + 13
            y: avatarRect.y + (avatarRect.height - implicitHeight) / 2 + 20
            spacing: 0
            z: 2

            StyledText {
                // The display name comes from the user's own config or from the
                // system account record, so it must not be parsed as markup.
                textFormat: Text.PlainText
                text: root.userDisplay
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                text: "Up • " + DateTime.uptime
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer1
                opacity: 0.6
            }
        }
    }
}
