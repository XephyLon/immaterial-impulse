import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.functions
import qs.modules.common.widgets
import "../../../../common/functions/layout_ops.js" as LayoutOps

GroupButton {
    id: root
    
    required property int buttonIndex
    required property var buttonData
    required property bool expandedSize
    required property real baseCellWidth
    required property real baseCellHeight
    required property real cellSpacing
    required property int cellSize
    property var dropIndicatorRef: null
    property bool isUnused: false 
    property var gridRef: null
    // The pager protocol (spec 2026-08-31): the panel owning the pages, and
    // which page this tile calls home. The drag's cross-page half lands in
    // the follow-up commit; until then these only ride along.
    property var pagerRef: null
    property int pageIndex: 0

    signal openMenu()
    // What a tile asks of the panel that holds the stored toggle list: to be
    // moved onto another tile's slot after a drag, or added from the unused
    // shelf. The list is the config's; the tile has no business writing it.
    signal moveRequested(int fromIndex, int toIndex)
    signal addRequested(string type)
    signal removeRequested(int index)
    signal resizeRequested(int index, int size)
    signal moveAcrossRequested(int fromIndex, int toPage, int toIndex)
    // Whether the sidebar this tile sits in is open, for the entrance: a
    // tile built while the panel is closed appears at once.
    property bool panelOpen: false

    property QuickToggleModel toggleModel
    property string name: toggleModel?.name ?? ""
    property string statusText: (toggleModel?.hasStatusText) ? (toggleModel?.statusText || (toggled ? Translation.tr("On") : Translation.tr("Off"))) : ""
    property string tooltipText: toggleModel?.tooltipText ?? ""
    property string buttonIcon: toggleModel?.icon ?? "close"
    property bool available: toggleModel?.available ?? true
    toggled: toggleModel?.toggled ?? false
    property var mainAction: toggleModel?.mainAction ?? null
    altAction: toggleModel?.hasMenu ? (() => root.openMenu()) : (toggleModel?.altAction ?? null)

    property bool editMode: false

    baseWidth: root.baseCellWidth * cellSize + cellSpacing * (cellSize - 1)
    baseHeight: root.baseCellHeight
    enableImplicitWidthAnimation: !editMode && root.hovered
    enableImplicitHeightAnimation: !editMode && root.hovered
    Behavior on baseWidth {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    Behavior on baseHeight {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    // The tile's arrival is the panel's convergent wave. `appear` is
    // INHERITED - RippleButton declares it and folds it into the opacity
    // binding that also carries the disabled dim - and this file must not
    // declare it again. It did, back when GroupButton was rooted on Button
    // and had no `appear` of its own, and it inherited a second one the day
    // GroupButton moved onto RippleButton. QML then carried TWO properties
    // of that name: the wave wrote this one while the base's opacity
    // binding, compiled in the base's scope, read the other. Nothing
    // errored; the tiles simply stopped fading in. StaggerEntrance had also
    // stopped dressing them, because it leaves opacity and scale to any
    // control exposing `interactionMotion` - which a RippleButton does - so
    // between the two nothing drove the entrance at all.
    // No Behavior on opacity: the wave animates `appear` and opacity is a
    // binding on it, so a Behavior here is a second animation on the same
    // channel. The one left behind by the self-fade's retirement turned
    // park()'s snap-to-invisible into a 200ms on-stage fade-out (measured:
    // appear=0 with drawn opacity still 1.000 at the open, dimmest at
    // ~140ms, and pinned at 0.15 by per-frame retargets while `appear`
    // animated - b710ef731's frozen-Behavior shape - so the tile landed
    // ~200ms after its own wave slot). That was the "toggles visible, then
    // the animation begins" pause.

    // A tile born mid-session - edit mode adding it, a config change - used
    // to pop in at full strength in one frame: the dresser dresses arrivals,
    // but only an enter() animates them, and none is running. So a tile
    // created while the panel is on screen parks itself and runs the one
    // fade the retired self-fade used to be. The check is deferred a turn
    // because of the one case where every tile is "late": a tree built with
    // the panel already open (keepRightSidebarLoaded off). There the panel's
    // wave enters right after the model sync, so by the time this looks, the
    // wave is running (or armed) and the tile stands down - one writer on
    // `appear`, always.
    Component.onCompleted: {
        root.appear = 0;
        Qt.callLater(() => {
            const wave = root.gridRef?.entranceWave ?? null;
            if (wave && (wave.active.length > 0 || wave.pendingEnter))
                return;
            if (!root.panelOpen) {
                root.appear = 1;
                return;
            }
            lateArrival.restart();
        });
    }
    NumberAnimation {
        id: lateArrival
        target: root
        property: "appear"
        to: 1
        duration: Appearance.animation.elementMoveFast.duration
        easing.type: Appearance.animation.elementMoveFast.type
        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
    }

    // The grid is one flat container and a tile places itself in it, so a
    // reorder is a delegate travelling to another slot rather than a row of
    // delegates being rebuilt. Both terms come from the SETTLED pack - a slot
    // counts the cells consumed before this tile, never a neighbour's live
    // width - so the Behaviors have a target that rests between edits. Keyed
    // on anything the press bounce moves they would restart every frame and
    // never tick at all (b710ef731).
    x: (root.buttonData?.layoutSlot ?? 0) * (root.baseCellWidth + root.cellSpacing)
    y: (root.buttonData?.layoutRow ?? 0) * (root.baseCellHeight + root.cellSpacing)
    Behavior on x {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    Behavior on y {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    // The press bounce widens the tile while its slot stays where it is, so
    // left alone the tile would grow into whatever sits to its right. A
    // transform is not `x`: it composes after placement, so it may move every
    // frame without reaching the Behavior above.
    transform: Translate {
        x: -(root.width - root.baseWidth) / 2
    }

    enabled: available || editMode
    padding: Appearance.spacing.space100
    horizontalPadding: padding
    verticalPadding: padding

    colBackground: Appearance.colors.colLayer2
    colBackgroundToggled: (altAction && expandedSize) ? Appearance.colors.colLayer2 : Appearance.colors.colPrimary
    colBackgroundToggledHover: (altAction && expandedSize) ? Appearance.colors.colLayer2Hover : Appearance.colors.colPrimaryHover
    colBackgroundToggledActive: (altAction && expandedSize) ? Appearance.colors.colLayer2Active : Appearance.colors.colPrimaryActive
    buttonRadius: toggled ? Appearance.rounding.large : height / 2
    buttonRadiusPressed: Appearance.rounding.normal
    property color colText: (toggled && !(altAction && expandedSize) && enabled) ? Appearance.colors.colOnPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer2, enabled ? 0 : 0.7)
    property color colIcon: expandedSize ? ((root.toggled) ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3) : colText

    onClicked: {
        if (root.expandedSize && root.altAction) root.altAction();
        else root.mainAction();
    }

    contentItem: RowLayout {
        spacing: Appearance.spacing.space50
        anchors {
            centerIn: root.expandedSize ? undefined : parent
            fill: root.expandedSize ? parent : undefined
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }

        MouseArea {
            id: iconMouseArea
            hoverEnabled: true
            acceptedButtons: (root.expandedSize && root.altAction) ? Qt.LeftButton : Qt.NoButton
            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: true
            Layout.topMargin: root.verticalPadding
            Layout.bottomMargin: root.verticalPadding
            implicitHeight: iconBackground.implicitHeight
            implicitWidth: iconBackground.implicitWidth
            cursorShape: Qt.PointingHandCursor
            onClicked: root.mainAction()

            Rectangle {
                id: iconBackground
                anchors.fill: parent
                implicitWidth: height
                radius: root.radius - root.verticalPadding
                color: {
                    const baseColor = root.toggled ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                    const transparentizeAmount = (root.altAction && root.expandedSize) ? 0 : 1
                    return ColorUtils.transparentize(baseColor, transparentizeAmount)
                }
                Behavior on radius { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

                MaterialSymbol {
                    anchors.centerIn: parent
                    fill: root.toggled ? 1 : 0
                    iconSize: root.expandedSize ? 22 : 24
                    color: root.colIcon
                    text: root.buttonIcon
                }

                Loader {
                    anchors.fill: parent
                    active: (root.expandedSize && root.altAction)
                    sourceComponent: Rectangle {
                        radius: iconBackground.radius
                        color: ColorUtils.transparentize(root.colIcon, iconMouseArea.containsPress ? 0.88 : iconMouseArea.containsMouse ? 0.95 : 1)
                        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                    }
                }
            }
        }

        Loader {
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
            visible: root.expandedSize
            active: visible
            sourceComponent: Column {
                spacing: -Appearance.spacing.space25
                StyledText {
                    anchors { left: parent.left; right: parent.right }
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    font.weight: 600
                    color: root.colText
                    elide: Text.ElideRight
                    text: root.name
                }
                StyledText {
                    visible: root.statusText
                    anchors { left: parent.left; right: parent.right }
                    font { pixelSize: Appearance.font.pixelSize.smaller; weight: 100 }
                    color: root.colText
                    elide: Text.ElideRight
                    text: root.statusText
                }
            }
        }
    }

    // Edit mode
    Item {
        id: editModeInteraction
        visible: root.editMode && !root.isUnused
        anchors.fill: parent

        property bool isDragging: false

        DragHandler {
            id: dragHandler
            target: null

            // Every tile is a direct child of one flat page grid, so this
            // is a filter rather than a walk - parameterised by GRID now,
            // because a drag that crossed a page edge scores its drop
            // against the page under the pointer, not the one it left.
            function siblingsIn(grid) {
                const siblings = [];
                if (!grid) return siblings;
                for (let i = 0; i < grid.children.length; i++) {
                    const sib = grid.children[i];
                    if (!sib || !sib.visible || !sib.buttonData) continue;
                    siblings.push(sib);
                }
                return siblings;
            }

            // The dragged tile is a hole rather than a candidate on its own
            // page; on another page it is simply absent. Compared by id
            // rather than by type, because a config naming one type twice
            // would otherwise punch two holes.
            function findNearestIn(grid, sceneX, sceneY) {
                const siblings = siblingsIn(grid);
                const centres = siblings.map(sib =>
                    sib.buttonData.itemId === root.buttonData.itemId
                        ? null
                        : sib.mapToItem(null, sib.width / 2, sib.height / 2));
                const nearest = LayoutOps.indexAt(centres, Qt.point(sceneX, sceneY), null);
                return nearest === -1 ? null : siblings[nearest];
            }

            function crossingPages() {
                return root.pagerRef && root.pagerRef.currentPage !== root.pageIndex;
            }

            onActiveChanged: {
                editModeInteraction.isDragging = active;
                if (root.pagerRef) root.pagerRef.dragActive = active;

                if (!active) {
                    if (root.dropIndicatorRef) root.dropIndicatorRef.visible = false;
                    const landing = root.pagerRef?.currentIndicator() ?? null;
                    if (landing) landing.visible = false;
                    const sceneX = centroid.scenePosition.x;
                    const sceneY = centroid.scenePosition.y;
                    if (crossingPages()) {
                        // The drop commits an insertion index into the page
                        // under the pointer; an empty page takes index 0.
                        const grid = root.pagerRef.currentGrid();
                        const nearest = grid ? findNearestIn(grid, sceneX, sceneY) : null;
                        let insertAt = 0;
                        if (nearest) {
                            const centre = nearest.mapToItem(null, nearest.width / 2, 0).x;
                            insertAt = nearest.buttonIndex + (sceneX > centre ? 1 : 0);
                        }
                        root.moveAcrossRequested(root.buttonIndex,
                            root.pagerRef.currentPage, insertAt);
                    } else {
                        // The model carries each row's index in the stored
                        // list, so the request addresses the entry the tile
                        // was built from.
                        const nearest = findNearestIn(root.gridRef, sceneX, sceneY);
                        if (nearest)
                            root.moveRequested(root.buttonIndex, nearest.buttonIndex);
                    }
                    if (root.pagerRef) root.pagerRef.dragEnded();
                }
            }

            onCentroidChanged: {
                if (!active) return;
                const sceneX = centroid.scenePosition.x;
                const sceneY = centroid.scenePosition.y;
                if (root.pagerRef) root.pagerRef.dragHoverAt(sceneX);

                const crossing = crossingPages();
                const grid = crossing ? root.pagerRef.currentGrid() : root.gridRef;
                const indicator = crossing ? root.pagerRef.currentIndicator()
                                           : root.dropIndicatorRef;
                if (root.dropIndicatorRef && indicator !== root.dropIndicatorRef)
                    root.dropIndicatorRef.visible = false;
                if (!grid || !indicator) return;

                const nearest = findNearestIn(grid, sceneX, sceneY);
                if (nearest) {
                    const centre = nearest.mapToItem(null, nearest.width / 2, 0).x;
                    const goesAfter = sceneX > centre;
                    const nearestLocal = nearest.mapToItem(grid, 0, 0);
                    indicator.x = goesAfter
                        ? nearestLocal.x + nearest.width + 1
                        : nearestLocal.x - 5;
                    indicator.y = nearestLocal.y;
                    indicator.height = nearest.height;
                    indicator.visible = true;
                } else if (crossing) {
                    // An empty page: the indicator stands at its origin so
                    // the drop has a visible home.
                    indicator.x = 0;
                    indicator.y = 0;
                    indicator.height = root.baseCellHeight;
                    indicator.visible = true;
                } else {
                    indicator.visible = false;
                }
            }
        }

        HoverHandler {
            cursorShape: editModeInteraction.isDragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        }
    }

    MouseArea {
        visible: root.editMode && root.isUnused
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.addRequested(root.buttonData.type)
    }

    // del
    Rectangle {
        id: deleteBtn
        visible: root.editMode && !root.isUnused
        z: 10
        width: 20
        height: 20
        radius: Appearance.rounding.full
        color: deleteHover.containsMouse ? Appearance.colors.colError : ColorUtils.transparentize(Appearance.colors.colError, 0.15)
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: -Appearance.spacing.space100
        anchors.leftMargin: -Appearance.spacing.space100

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: "close"
            iconSize: 13
            color: Appearance.colors.colOnError 
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        MouseArea {
            id: deleteHover
            anchors.fill: parent
            anchors.margins: -Appearance.spacing.space50
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.removeRequested(root.buttonIndex)
        }
    }

    // resize
    Rectangle {
        id: resizeBtn
        visible: root.editMode && !root.isUnused
        z: 10
        width: 20
        height: 20
        radius: Appearance.rounding.unsharpenslight
        color: resizeHover.containsMouse ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colPrimary, 0.15)
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.bottomMargin: -Appearance.spacing.space100
        anchors.rightMargin: -Appearance.spacing.space100

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: "open_in_full"
            iconSize: 13
            color: Appearance.colors.colOnPrimary
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        MouseArea {
            id: resizeHover
            anchors.fill: parent
            anchors.margins: -Appearance.spacing.space50
            hoverEnabled: true
            cursorShape: Qt.SizeFDiagCursor
            preventStealing: true

            property real pressSceneX: 0
            property real pressSize: 1

            onPressed: event => {
                const scene = resizeBtn.mapToItem(null, event.x, event.y);
                pressSceneX = scene.x;
                pressSize = root.cellSize;
            }
            onPositionChanged: event => {
                if (!pressed) return;
                const scene = resizeBtn.mapToItem(null, event.x, event.y);
                const dx = scene.x - pressSceneX;
                const steps = Math.round(dx / root.baseCellWidth);
                const newSize = Math.max(1, Math.min(3, pressSize + steps));
                if (newSize !== root.cellSize)
                    root.resizeRequested(root.buttonIndex, newSize);
            }
        }
    }

    StyledToolTip {
        extraVisibleCondition: root.tooltipText !== ""
        text: root.tooltipText
    }
}