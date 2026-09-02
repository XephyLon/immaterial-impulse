pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import "../../common/plugins/bundled/docker" as DockerPackage

// Native bar adapter for the bundled Docker manager. Its geometry follows the
// same content-driven contract as WeatherBar so BarGroup remains the sole
// owner of the surrounding layout size.
//
// A RippleButton, not a MouseArea: a click here opens the container popup,
// and a bare area answered it with nothing - no ripple, no press, no state
// while the popup was up. The button brings the interaction model (the
// press squish and the ripple from the press point) and a tonal toggled
// container while its popup is open, the tray's overflow button's grammar.
RippleButton {
    id: root

    property bool vertical: Config.options.bar.vertical
    property bool popupOpen: false
    readonly property real horizontalPadding: Appearance.spacing.space100
    readonly property bool isMaterial: Config.options.bar.cornerStyle === 3
    // The circle is a progress ring - running over total - in the resource
    // monitor's vocabulary: the outline ring under every bar style but M3,
    // where the tonal pill is the container and the ring is filled.
    readonly property real containerProgress: DockerPackage.DockerService.totalCount > 0
        ? DockerPackage.DockerService.runningCount / DockerPackage.DockerService.totalCount : 0
    readonly property color tone: DockerPackage.DockerService.dockerAvailable
        ? Appearance.colors.colPrimary : Appearance.colors.colError

    Component {
        id: outlineRing
        ClippedOutlineCircularProgress {
            implicitSize: 25
            lineWidth: Appearance.rounding.unsharpen
            value: root.containerProgress
            colPrimary: root.tone
            enableAnimation: false
            Item {
                anchors.centerIn: parent
                width: 25
                height: 25
                MaterialSymbol {
                    anchors.centerIn: parent
                    fill: 0
                    text: "deployed_code"
                    iconSize: Appearance.font.pixelSize.normal
                    color: root.tone
                }
            }
        }
    }

    Component {
        id: filledRing
        ClippedFilledCircularProgress {
            implicitSize: 25
            lineWidth: Appearance.rounding.unsharpen
            value: root.containerProgress
            colPrimary: root.tone
            accountForLightBleeding: DockerPackage.DockerService.dockerAvailable
            enableAnimation: false
            Item {
                anchors.centerIn: parent
                width: 25
                height: 25
                MaterialSymbol {
                    anchors.centerIn: parent
                    fill: 0
                    text: "deployed_code"
                    iconSize: Appearance.font.pixelSize.normal
                    color: DockerPackage.DockerService.dockerAvailable
                        ? Appearance.colors.colOnPrimary : Appearance.colors.colOnError
                }
            }
        }
    }

    implicitWidth: root.vertical
        ? (contentLoader.item?.implicitWidth ?? 32)
        : (contentLoader.item?.implicitWidth ?? 0) + root.horizontalPadding * 2
    implicitHeight: root.vertical
        ? (contentLoader.item?.implicitHeight ?? 0)
        : Appearance.sizes.barHeight
    toggled: root.popupOpen
    buttonRadius: Appearance.rounding.full
    colBackground: "transparent"
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colRippleToggled: Appearance.colors.colSecondaryContainerActive

    downAction: () => {
        root.popupOpen = !root.popupOpen;
        if (root.popupOpen) DockerPackage.DockerService.refresh();
    }

    contentItem: Item {
        implicitWidth: contentLoader.implicitWidth
        implicitHeight: contentLoader.implicitHeight
        Loader {
            id: contentLoader
            anchors.centerIn: parent
            sourceComponent: root.vertical ? verticalContent : horizontalContent
        }
    }

    Component {
        id: horizontalContent
        RowLayout {
            spacing: Appearance.spacing.space100

            StyledText {
                text: `${DockerPackage.DockerService.runningCount}/${DockerPackage.DockerService.totalCount}`
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: DockerPackage.DockerService.dockerAvailable
                    ? Appearance.colors.colPrimary : Appearance.colors.colError
                Layout.alignment: Qt.AlignVCenter
            }

            Loader {
                Layout.alignment: Qt.AlignVCenter
                sourceComponent: root.isMaterial ? filledRing : outlineRing
            }
        }
    }

    Component {
        id: verticalContent
        ColumnLayout {
            spacing: Appearance.spacing.space25

            Loader {
                Layout.alignment: Qt.AlignHCenter
                sourceComponent: root.isMaterial ? filledRing : outlineRing
            }

            StyledText {
                text: DockerPackage.DockerService.runningCount
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: DockerPackage.DockerService.dockerAvailable
                    ? Appearance.colors.colPrimary : Appearance.colors.colError
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }

    Loader {
        id: popupLoader
        active: root.popupOpen
        sourceComponent: DockerPackage.DockerPopup {
            pinnedOpen: true
            // StyledPopup uses its target for screen-relative positioning;
            // a RippleButton exposes no containsMouse, so this is click-only.
            hoverTarget: root
            // The overlay owns the surface, so it owns the outside-click grab.
            onDismissRequested: root.popupOpen = false
            onPinnedOpenChanged: {
                if (!pinnedOpen) root.popupOpen = false;
            }
        }
    }



}
