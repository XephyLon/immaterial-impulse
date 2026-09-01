import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

/**
 * A generated image, as a first-class transcript block: soft corners,
 * width-fit, and a click that opens the fullscreen viewer.
 */
ClippingRectangle {
    id: root
    property var segmentContent: ""
    // What saveMessage folds back into markdown on edit.
    readonly property var segment: ({ "type": "text", "content": `![generated image](${root.segmentContent})` })

    // StyledToolTip shows while `parent.hovered` is true, and treats a parent
    // WITHOUT a `hovered` property as always-on. A bare ClippingRectangle has
    // none, so the tooltip hung on screen (even past the sidebar) until a
    // click. Give it a real hover flag so the tooltip tracks the pointer.
    property bool hovered: hoverHandler.hovered
    HoverHandler { id: hoverHandler }

    Layout.fillWidth: true
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2
    implicitHeight: image.status === Image.Ready
        ? Math.max(48, image.paintedHeight) : 220

    StyledImage {
        id: image
        anchors.fill: parent
        source: Qt.resolvedUrl("file://" + root.segmentContent)
        fillMode: Image.PreserveAspectFit
        sourceSize.width: 1024
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: GlobalStates.aiImageViewerSource = String(root.segmentContent)
    }

    StyledToolTip { text: Translation.tr("Click to view fullscreen") }
}
