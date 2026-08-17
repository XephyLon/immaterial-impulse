import qs
import qs.modules.common
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property bool vertical: false
    property int currentIndex: 0
    property int totalCount: 0

    // Edit Mode's per-widget affordances, declared HERE because every widget
    // in both bars is wrapped in a BarGroup - one Loader in this file covers
    // both orientations, where a per-delegate copy would be twelve. The
    // delegates pass which bucket this slot draws and which widget id it is;
    // a tree that passes no controller (a test, a future preview) gets no
    // overlay at all.
    property var editController: null
    property string editBucket: ""
    property string editWidgetId: ""
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

    // Which side of the group the monitor edge is on. Config.options.bar.bottom
    // is shared by both orientations: for a horizontal bar it means the bottom
    // of the screen, for a vertical one the right-hand side. Either way it
    // names the far edge, so the near edge (top / left) is the default.
    readonly property bool atFarEdge: Config.options.bar.bottom
    // Hug (cornerStyle 0) is flush against the monitor edge, so it has no
    // margin there; Float (1), Islands (2) and M3 (3) are detached and share
    // one. All four share the opposite-side margin - the gap to the windows
    // below the bar, or beside it when vertical.
    readonly property real edgeMargin: Appearance.sizes.barMarginTop
    readonly property real windowMargin: Appearance.sizes.barMarginBottom

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
            // The tokens are named for a top bar, but what they mean is edge
            // side vs window side, so they follow the bar to whichever monitor
            // edge it is anchored to - bar.bottom flips both orientations.
            topMargin: root.vertical ? 0 : (root.atFarEdge ? root.windowMargin : root.edgeMargin)
            bottomMargin: root.vertical ? 0 : (root.atFarEdge ? root.edgeMargin : root.windowMargin)
            leftMargin: !root.vertical ? 0 : (root.atFarEdge ? root.windowMargin : root.edgeMargin)
            rightMargin: !root.vertical ? 0 : (root.atFarEdge ? root.edgeMargin : root.windowMargin)
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

    // The dragged slot dims so the ghost and the indicator read as "this one
    // is moving". The binding's value changes only at the drag's ends, so the
    // Behavior is safe (the b710ef731 distinction: a target that moves every
    // frame, not a binding that re-evaluates every frame, is the trap).
    opacity: editLoader.item && editLoader.item.dragging ? 0.4 : 1
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Loader {
        id: editLoader
        anchors.fill: parent
        z: 100
        // Gated on the mode itself, not the progress tail: the overlay exists
        // to intercept input, and input during the exit animation belongs to
        // the widgets again. Tearing it down mid-drag is deliberate - the
        // handler dies with the grab and no release can commit.
        active: root.editController !== null && GlobalStates.editMode
        sourceComponent: BarWidgetEditItem {
            controller: root.editController
            bucket: root.editBucket
            widgetId: root.editWidgetId
            visibleIndex: root.currentIndex
        }
    }
}