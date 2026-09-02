import qs
import qs.modules.common
import QtQuick
import QtQuick.Layouts
import "bar_flip.js" as BarFlip

Item {
    id: root
    property bool vertical: false
    property int currentIndex: 0
    property int totalCount: 0

    // Which widget this slot draws. Not the edit overlay's alone any more -
    // the reposition at the bottom of this file keys its record on it too, and
    // a slot cannot have two answers to which widget it is - so the name lost
    // the `edit` prefix it carried while the overlay was its only reader.
    property string widgetId: ""

    // Edit Mode's per-widget affordances, declared HERE because every widget
    // in both bars is wrapped in a BarGroup - one Loader in this file covers
    // both orientations, where a per-delegate copy would be twelve. The
    // delegates pass which bucket this slot draws; a tree that passes no
    // controller (a test, a future preview) gets no overlay at all.
    property var editController: null
    property string editBucket: ""

    // Where this bar's slots were drawn, handed in by the content tree. A tree
    // that passes none (the edit harness, a preview) simply has no motion -
    // the same opt-out shape as editController.
    property BarFlipRegistry flipRegistry: null
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
    // The ends of a row are decided by which neighbours are SHOWING, not by
    // index: a group beside a collapsed one is the end of the row for as
    // long as that neighbour is gone, and gets the full radius the index
    // arithmetic would only give it if the neighbour were not in the layout
    // at all. Walks the parent's children, which is the Repeater's row order;
    // non-groups (the Repeater itself) carry no widgetId and are skipped. A
    // group with no row around it (a harness, a preview) has no neighbours
    // either way, which is the old `totalCount <= 1` answer.
    function neighbourShowing(step) {
        const siblings = root.parent?.children ?? [];
        let here = -1;
        for (let k = 0; k < siblings.length; k++) {
            if (siblings[k] === root) { here = k; break; }
        }
        if (here < 0) return false;
        for (let k = here + step; k >= 0 && k < siblings.length; k += step) {
            const sibling = siblings[k];
            if (sibling.widgetId === undefined) continue;
            if (!sibling.collapsed) return true;
        }
        return false;
    }
    readonly property bool showingBefore: neighbourShowing(-1)
    readonly property bool showingAfter: neighbourShowing(1)
    property real startRadius: showingBefore ? midRadius : fullRadius
    property real endRadius: showingAfter ? midRadius : fullRadius

    implicitWidth: vertical && root.isMaterial ? Appearance.sizes.baseVerticalBarWidth - 6 : (gridLayout.implicitWidth + padding * 2)
    implicitHeight: vertical ? (gridLayout.implicitHeight + padding * 2) : Appearance.sizes.baseBarHeight

    default property alias items: gridLayout.children

    // The surface a widget's popup-open indicator lies on, when this group
    // paints its pill: the pill. A transparent group (M3 without a material
    // pill, the "No" group style) exposes nothing, and the indicator walks
    // on up to the section's plate or the bar background.
    readonly property Item popupAnchorSurface: background.color.a > 0 ? background : null

    // A group whose content has collapsed to nothing paints nothing. The
    // standalone pills (timer, submap, privacy) animate their implicitWidth
    // to 0 when idle and hide themselves - and this group's padding was
    // left standing around that 0 as a small empty pill beside the
    // neighbour, all day, for every layout that ends in one of them. Read
    // from the grid, which is what those pills drive, on the axis the bar
    // lays out along. Edit mode keeps every group on the bar: an idle pill
    // still has to be there to drag.
    readonly property bool contentEmpty: root.vertical
        ? gridLayout.implicitHeight <= 0
        : gridLayout.implicitWidth <= 0
    readonly property bool collapsed: contentEmpty && !editLoader.active
    visible: !collapsed

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

    // ---- the reposition -----------------------------------------------------
    //
    // FLIP, declared HERE for the reason the edit overlay is: every widget in
    // both bars is wrapped in a BarGroup, so one file turns by the `vertical`
    // flag where a per-delegate copy would be twelve and the two bars would
    // drift the way they already did over widget files (a47462fcc).
    //
    // What moves is a Translate, never `x`/`y`: a slot's coordinates belong to
    // the layout, and writing them would fight it. What is animated is that
    // translate toward zero, which nothing else writes - the layout's own
    // motion is inverted from a measurement rather than eased, precisely
    // because a Behavior handed a target that moves every frame restarts every
    // frame and never ticks (b710ef731).
    property real flipTravel: 0
    property var flipOrigin: null
    property bool flipPending: false
    property var flipChain: []

    transform: Translate {
        x: root.vertical ? 0 : root.flipTravel
        y: root.vertical ? root.flipTravel : 0
    }

    // The tier taken WHOLE - duration, easing type and curve from the tier's
    // own component - and named so the reposition can be retargeted rather
    // than restarted from scratch when a second reflow lands mid-flight.
    readonly property NumberAnimation flipAnim:
        Appearance.animation.elementMoveSmall.numberAnimation.createObject(root)

    // The ancestors between this slot and the registry's frame, each of which
    // can move it without its own x/y changing: the right-hand bucket's
    // section is anchored to the screen's edge and takes its width from its
    // row, so removing a widget moves the section and leaves the slot at
    // row-local 0 exactly where it was. That slot travels the whole width of
    // what left, and nothing on it announces the move.
    function flipWalk() {
        const frame = root.flipRegistry ? root.flipRegistry.frame : null;
        const chain = [];
        let node = root;
        while (node && node !== frame) {
            chain.push(node);
            node = node.parent;
        }
        return chain;
    }

    function flipOriginNow() {
        return BarFlip.chainOrigin(root.flipWalk());
    }

    // What the next slot for this widget inverts from: where this one is
    // DRAWN, translate included, so a reflow interrupting another is continuous
    // rather than starting from the layout position nobody ever saw.
    function flipDrawnOrigin() {
        const origin = root.flipOriginNow();
        return root.vertical
            ? { x: origin.x, y: origin.y + root.flipTravel }
            : { x: origin.x + root.flipTravel, y: origin.y };
    }

    function flipMeasure() {
        // Outside a reposition this slot is inert. A bar widget's content
        // changes width constantly - the clock every minute, the media title
        // per track - and animating every one of those would keep the bar
        // repainting the whole output for reasons the user never asked about.
        if (!root.flipPending && !root.flipAnim.running) return;
        const origin = root.flipOriginNow();
        const step = BarFlip.repositionTravel(root.flipTravel, root.flipOrigin,
                                              origin, root.vertical, BarFlip.MIN_TRAVEL);
        root.flipOrigin = origin;
        root.flipPending = false;
        if (!step.play) return;
        root.flipTravel = step.travel;
        root.flipAnim.restart();
    }

    // A reorder drag is the one motion this must not join. The gesture reads
    // slot centres through `mapToItem`, which composes transforms, so a slot
    // part-way through a reposition would offer the drop arithmetic a centre
    // that moves every frame - and the drag's own ghost and indicator are
    // already the moving parts. The drop's reflow still animates: the
    // controller clears this flag before the layout pass that follows it.
    readonly property bool flipAllowed: !GlobalStates.editBarDragActive
    onFlipAllowedChanged: if (!root.flipAllowed) {
        root.flipAnim.stop();
        root.flipTravel = 0;
        root.flipPending = false;
    }

    Connections {
        target: root.flipAnim
        // `finished`, not `stopped`: a retarget stops the animation to restart
        // it, and standing the reposition down there would end it half way.
        function onFinished() {
            root.flipTravel = 0;
        }
    }

    Component.onCompleted: {
        if (!root.flipRegistry) return;
        root.flipAnim.target = root;
        root.flipAnim.property = "flipTravel";
        root.flipAnim.to = 0;
        root.flipChain = root.flipWalk();
        for (const node of root.flipChain) {
            node.xChanged.connect(root, root.flipMeasure);
            node.yChanged.connect(root, root.flipMeasure);
        }
        const recalled = root.flipAllowed ? root.flipRegistry.recall(root.widgetId) : null;
        if (!recalled) return;
        root.flipOrigin = recalled;
        root.flipPending = true;
    }

    Component.onDestruction: {
        if (!root.flipRegistry) return;
        root.flipRegistry.deposit(root.widgetId, root.flipDrawnOrigin());
        for (const node of root.flipChain) {
            node.xChanged.disconnect(root, root.flipMeasure);
            node.yChanged.disconnect(root, root.flipMeasure);
        }
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
            widgetId: root.widgetId
            visibleIndex: root.currentIndex
        }
    }
}
