import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: root
    property string displayText
    property string url

    property real faviconSize: 20
    // Where the site's icon is on disk and whether it has arrived - both from
    // the message, which asks the Favicons service; this chip cannot fetch.
    property string faviconPath: ""
    property bool faviconReady: false
    implicitHeight: 30
    leftPadding: (implicitHeight - faviconSize) / 2
    rightPadding: Appearance.spacing.space150
    buttonRadius: Appearance.rounding.full
    colBackground: Appearance.colors.colSurfaceContainerHighest
    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
    colRipple: Appearance.colors.colSurfaceContainerHighestActive

    PointingHandInteraction {}
    // Opening the link and closing the sidebar are the chat's decisions.
    signal followed(string url)
    onClicked: if (root.url) root.followed(root.url)

    contentItem: Item {
        anchors.centerIn: parent
        implicitWidth: rowLayout.implicitWidth
        implicitHeight: rowLayout.implicitHeight
        RowLayout {
            id: rowLayout
            anchors.fill: parent
            spacing: Appearance.spacing.space100
            Favicon {
                iconPath: root.faviconPath
                ready: root.faviconReady
                size: root.faviconSize
            }
            StyledText {
                id: text
                horizontalAlignment: Text.AlignHCenter
                text: displayText
                color: Appearance.m3colors.m3onSurface
            }
        }
    }
}
