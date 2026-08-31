import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Quickshell.Widgets
import QtQuick

/**
 * One attachment, as a compact rounded thumbnail: click opens the
 * fullscreen viewer; `removable` adds the tray's X.
 */
ClippingRectangle {
    id: root
    property string path: ""
    property bool removable: false
    signal remove()

    implicitWidth: 108
    implicitHeight: 108
    radius: Appearance.rounding.small
    color: Appearance.colors.colLayer2

    StyledImage {
        anchors.fill: parent
        source: root.path.length > 0 ? Qt.resolvedUrl("file://" + root.path) : ""
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: 256
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: GlobalStates.aiImageViewerSource = root.path
    }

    RippleButton {
        visible: root.removable
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Appearance.spacing.space50
        implicitWidth: 22
        implicitHeight: 22
        buttonRadius: Appearance.rounding.full
        colBackground: ColorUtils.transparentize(Appearance.m3colors.m3scrim ?? "#000", 0.35)
        colBackgroundHover: ColorUtils.transparentize(Appearance.m3colors.m3scrim ?? "#000", 0.15)
        colRipple: Appearance.colors.colLayer2Active
        onClicked: root.remove()
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "close"
            iconSize: Appearance.font.pixelSize.normal
            color: "#ffffff"
        }
    }
}
