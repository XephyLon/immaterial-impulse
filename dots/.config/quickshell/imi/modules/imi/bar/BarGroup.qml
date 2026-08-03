import qs.modules.common
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property bool vertical: false
    property int currentIndex: 0
    property int totalCount: 0
    property bool isMaterial: Config.options.bar.cornerStyle === 3
    property bool paintMaterialPill: false
    // Islands is the only style where each group *is* the visible shape, with
    // fully-round ends (radius = height/2 = 16). 4px of flat padding is mostly
    // eaten by that curve, so content ends up sitting on the edge - most
    // visible on short widgets like weather, where the text is the whole pill.
    // The other styles put their groups inside a shared strip with near-square
    // joins, where 4px is correct.
    property real padding: (root.isMaterial && !root.paintMaterialPill) ? 0
        : Config.options.bar.cornerStyle === 2 ? Appearance.spacing.space150
        : Appearance.spacing.space50
    property color bgColor: Appearance.colors.colPrimaryContainer

    readonly property real fullRadius: height / 2
    readonly property real midRadius: Config.options.bar.cornerStyle === 2 ? Appearance.rounding.unsharpenmore + 2 : Appearance.rounding.unsharpenmore
    property real startRadius: {
        if (totalCount <= 1) return fullRadius;
        if (currentIndex === 0) return fullRadius;
        return midRadius;
    }
    property real endRadius: {
        if (totalCount <= 1) return fullRadius;
        if (currentIndex === totalCount - 1) return fullRadius;
        return midRadius;
    }

    implicitWidth: vertical && root.isMaterial ? Appearance.sizes.baseVerticalBarWidth - 6 : (gridLayout.implicitWidth + padding * 2)
    implicitHeight: vertical ? (gridLayout.implicitHeight + padding * 2) : Appearance.sizes.baseBarHeight

    default property alias items: gridLayout.children

    Rectangle {
        id: background
        anchors {
            fill: parent
            topMargin: root.vertical ? 0 : Appearance.sizes.barMarginTop
            bottomMargin: root.vertical ? 0 : Appearance.sizes.barMarginBottom
            // Rotated: for a vertical bar the screen edge is the left side, so
            // the edge/window margins map onto left/right the same way top and
            // bottom do horizontally.
            leftMargin: root.vertical ? Appearance.sizes.barMarginTop : 0
            rightMargin: root.vertical ? Appearance.sizes.barMarginBottom : 0
        }
        color: (root.isMaterial && !root.paintMaterialPill)
            ? "transparent"
            : (root.isMaterial && root.paintMaterialPill)
                ? root.bgColor
                : (Config.options?.bar.borderless === "transparent"
                    ? "transparent"
                    : Config.options.bar.cornerStyle === 2
                        ? Appearance.colors.colLayer0
                        : Appearance.colors.colLayer1)

        topLeftRadius: (root.isMaterial && root.paintMaterialPill) ? root.fullRadius : (Config.options?.bar.borderless === "separated" ? root.fullRadius : root.startRadius)
        bottomLeftRadius: (root.isMaterial && root.paintMaterialPill) ? root.fullRadius : (Config.options?.bar.borderless === "separated" ? root.fullRadius : root.vertical ? root.endRadius : root.startRadius)
        topRightRadius: (root.isMaterial && root.paintMaterialPill) ? root.fullRadius : (Config.options?.bar.borderless === "separated" ? root.fullRadius : root.vertical ? root.startRadius : root.endRadius)
        bottomRightRadius: (root.isMaterial && root.paintMaterialPill) ? root.fullRadius : (Config.options?.bar.borderless === "separated" ? root.fullRadius : root.endRadius)

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    GridLayout {
        id: gridLayout
        columns: root.vertical ? 1 : -1
        anchors.centerIn: parent
        columnSpacing: 0
        rowSpacing: 0
    }
}