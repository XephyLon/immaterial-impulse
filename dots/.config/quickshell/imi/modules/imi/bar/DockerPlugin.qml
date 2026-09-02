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
// press squish and the ripple from the press point); the open state is the
// bar's dashed anchor outline while the popup is up.
RippleButton {
    id: root

    property bool vertical: Config.options.bar.vertical
    property bool popupOpen: false
    // Not `horizontalPadding`: that is a FINAL property of the Control this
    // button is, and redeclaring it stops the whole widget from being created.
    readonly property real sidePadding: Appearance.spacing.space100
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
        : (contentLoader.item?.implicitWidth ?? 0) + root.sidePadding * 2
    implicitHeight: root.vertical
        ? (contentLoader.item?.implicitHeight ?? 0)
        : Appearance.sizes.barHeight
    buttonRadius: Appearance.rounding.full
    colBackground: "transparent"
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active

    // The button's background hugs the content rather than the bar-height
    // hit area: the hover pill and the anchor outline both draw on it, and
    // at bar height the outline was a hoop around the gauge and the count
    // with air above and below. EXPLICIT width and height, not implicit: a
    // Control forces its background to its own size unless the size is set
    // outright, so an implicit size with anchors.centerIn changes nothing -
    // which is why the first attempt at this still filled the hit area.
    background.anchors.centerIn: this
    background.width: root.vertical
        ? (contentLoader.item?.implicitWidth ?? 0) + Appearance.spacing.space50 * 2
        : (contentLoader.item?.implicitWidth ?? 0) + root.sidePadding * 2
    background.height: root.vertical
        ? (contentLoader.item?.implicitHeight ?? 0) + root.sidePadding * 2
        : (contentLoader.item?.implicitHeight ?? 0) + Appearance.spacing.space50 * 2

    // The open state is the dashed anchor outline, not a tonal container: a
    // filled pill behind a bare gauge broke every bar style but M3.
    PopupAnchorOutline {
        parent: root.background
        anchors.fill: parent
        z: 1
        shown: root.popupOpen
        radius: root.buttonRadius
    }

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
