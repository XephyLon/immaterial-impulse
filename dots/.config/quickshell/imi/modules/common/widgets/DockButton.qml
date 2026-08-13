import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import "../../imi/dock/dock_geometry.js" as DockGeometry

RippleButton {
    id: root

    readonly property string dockEdge: DockGeometry.normalizedEdge(
        Config.options?.dock.edge ?? "bottom")
    readonly property bool dockVertical: DockGeometry.isVertical(root.dockEdge)

    // The insets are named by DIRECTION, not by side. `topInset` runs across
    // the dock's thickness at a horizontal edge and along the strip at a
    // vertical one, so a caller spelling it out is correct at two edges and
    // silently wrong at the other two - it eats into the row of icons instead
    // of into the dock's depth.
    property real insetInward: 0
    property real insetOutward: 0
    readonly property var dockInsets: DockGeometry.directedSides(
        root.dockEdge, root.insetInward, root.insetOutward)
    topInset: root.dockInsets.top
    bottomInset: root.dockInsets.bottom
    leftInset: root.dockInsets.left
    rightInset: root.dockInsets.right

    // The same for the layout margin, which used to be a bare Layout.topMargin
    // of elevationMargin - hyprlandGapsOut: the amount the body's asymmetric
    // margins pull the button back off the shadow side.
    property real crossMargin: Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut
    readonly property var dockCrossMargins: DockGeometry.directedSides(
        root.dockEdge, root.crossMargin, 0)
    Layout.topMargin: root.dockCrossMargins.top
    Layout.bottomMargin: root.dockCrossMargins.bottom
    Layout.leftMargin: root.dockCrossMargins.left
    Layout.rightMargin: root.dockCrossMargins.right

    // The strip's long axis is the layout's to fill; the button measures
    // itself across the dock's thickness.
    Layout.fillHeight: !root.dockVertical
    Layout.fillWidth: root.dockVertical

    // 50 across the thickness, plus whatever the insets take out of the
    // surface. At a horizontal edge that is a height and the width follows; at
    // a vertical one the two swap, which is why neither can be written as
    // "width from height".
    property real span: 50
    implicitWidth: root.dockVertical ? root.span + leftInset + rightInset : root.span
    implicitHeight: root.dockVertical ? root.span : root.span + topInset + bottomInset

    buttonRadius: Appearance.rounding.normal
}
