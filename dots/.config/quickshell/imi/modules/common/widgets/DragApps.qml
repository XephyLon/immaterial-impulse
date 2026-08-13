import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Io
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import "../../imi/dock/dock_geometry.js" as DockGeometry

Item {
    id: root

    readonly property string dockEdge: DockGeometry.normalizedEdge(
        Config.options?.dock.edge ?? "bottom")
    // The reorder is one axis and one comparison, chosen here. It used to be
    // x throughout - a column of slots that lays out perfectly while every
    // drag compares the one coordinate that never changes.
    readonly property bool vertical: DockGeometry.isVertical(root.dockEdge)

    property real btnSize: 46
    property real btnSpacing: Appearance.spacing.space25
    property real buttonPadding: Appearance.spacing.space50
    property var pinnedApps: Config.options?.dock.pinnedApps ?? []
    property real maxWindowPreviewHeight: 200
    property real maxWindowPreviewWidth: 300
    property real windowControlsHeight: 30
    property Item lastHoveredButton: null
    property bool buttonHovered: false
    // Shared DockContextMenu instance (provided by the dock window)
    property var contextMenu: null
    property bool requestDockShow: previewPopup.show
    signal orderChanged(var newOrder)
    property var  _workOrder: pinnedApps.slice()
    property int  activeDragVisualIndex: -1
    property bool _dragging: false

    onPinnedAppsChanged: {
        if (!_dragging) {
            _workOrder = pinnedApps.slice()
        }
    }

    // How far the slots reach along the strip; across it the widget takes
    // whatever the dock's thickness leaves.
    readonly property real slotRun: _workOrder.length * btnSize
        + Math.max(0, _workOrder.length - 1) * btnSpacing
    implicitWidth:  root.vertical ? (parent?.width ?? btnSize) : slotRun
    implicitHeight: root.vertical ? slotRun : (parent?.height ?? btnSize)

    // Where the preview popup centres itself on the hovered button: along the
    // strip, so it is an x at a horizontal edge and a y at a vertical one.
    function popupCenterForButton(button) {
        if (!button || !root.QsWindow) return 0
        const centre = root.QsWindow.mapFromItem(button, button.width / 2, button.height / 2)
        return root.vertical ? centre.y : centre.x
    }

    function swapSlots(fromPos, toPos) {
        if (fromPos === toPos) return
        if (fromPos < 0 || fromPos >= _workOrder.length) return
        if (toPos   < 0 || toPos   >= _workOrder.length) return
        let arr = _workOrder.slice()
        let tmp = arr[fromPos]
        arr[fromPos] = arr[toPos]
        arr[toPos]   = tmp
        _workOrder = arr
    }

    function commitOrder() {
        const newOrder = _workOrder.slice()
        Config.options.dock.pinnedApps = newOrder
        orderChanged(newOrder)
    }

    Repeater {
        id: slotRepeater
        model: root._workOrder.length

        delegate: Item {
            id: slotItem
            required property int index

            property string appId:     root._workOrder[index] ?? ""
            property var    appEntry:  TaskbarApps.apps.find(a => a.appId === appId) ?? null
            property var    deskEntry: liveDeskEntry.entry
            property bool   appActive: appEntry?.toplevels?.find(t => t.activated) !== undefined
            property int    _lastFocused: -1

            LiveDesktopEntry {
                id: liveDeskEntry
                appId: slotItem.appId
            }

            // Slot i sits i steps along the strip; the other axis is the
            // dock's whole thickness.
            readonly property real slotOffset: index * (root.btnSize + root.btnSpacing)
            width:  root.vertical ? root.implicitWidth : root.btnSize
            height: root.vertical ? root.btnSize : root.implicitHeight
            x:      root.vertical ? 0 : slotOffset
            y:      root.vertical ? slotOffset : 0

            Behavior on x {
                enabled: root.activeDragVisualIndex !== slotItem.index
                animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
            }
            Behavior on y {
                enabled: root.activeDragVisualIndex !== slotItem.index
                animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
            }

            opacity: (root.activeDragVisualIndex === index) ? 0.0 : 1.0
            scale:   (root.activeDragVisualIndex === index) ? 0.7 : 1.0
            Behavior on opacity { NumberAnimation { duration: Appearance.animation.elementMoveFaster.duration; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: Appearance.animation.elementMoveFaster.duration; easing.type: Easing.OutCubic } }

            Item {
                visible: dragHandler.active
                z: 1000
                width:  root.btnSize
                height: root.btnSize
                anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
                anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined

                // The ghost follows the pointer along the strip only, so a
                // sideways wobble does not drag the icon out of the dock.
                readonly property point localPointer: dragHandler.active
                    ? slotItem.mapFromItem(null,
                        dragHandler.centroid.scenePosition.x,
                        dragHandler.centroid.scenePosition.y)
                    : Qt.point(0, 0)
                x: root.vertical ? 0 : (dragHandler.active ? localPointer.x - width / 2 : 0)
                y: root.vertical ? (dragHandler.active ? localPointer.y - height / 2 : 0) : 0

                scale: dragHandler.active ? 1.15 : 0.9
                Behavior on scale {
                    NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                }

                IconImage {
                    id: ghostIcon
                    anchors.centerIn: parent
                    source: Quickshell.iconPath(
                        AppSearch.guessIcon(root._workOrder[root.activeDragVisualIndex] ?? ""),
                        "image-missing")
                    implicitSize: root.btnSize * 0.65
                    opacity: 0.85

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowVerticalOffset: dragHandler.active ? 7 : 4
                        shadowBlur: dragHandler.active ? 0.85 : 0.65
                        shadowColor: "#80000000"

                        Behavior on shadowVerticalOffset { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Behavior on shadowBlur { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    }
                }
            }

            DockButton {
                id: dockBtn
                anchors.fill: parent

                property var appToplevel: slotItem.appEntry

                insetInward:  Appearance.sizes.hyprlandGapsOut + Appearance.spacing.space100
                insetOutward: Appearance.sizes.hyprlandGapsOut + Appearance.spacing.space100

                hoverEnabled: true
                onHoveredChanged: {
                    if (hovered) {
                        root.lastHoveredButton = dockBtn
                        root.buttonHovered = true
                    } else {
                        root.buttonHovered = false
                    }
                }

                onClicked: {
                    const entry = slotItem.appEntry
                    if (!entry || entry.toplevels.length === 0) {
                        DockLaunchTracker.markLaunching(slotItem.appId)
                        slotItem.deskEntry?.execute()
                        return
                    }
                    const next = (slotItem._lastFocused + 1) % entry.toplevels.length
                    slotItem._lastFocused = next
                    entry.toplevels[next].activate()
                }

                middleClickAction: () => {
                    DockLaunchTracker.markLaunching(slotItem.appId)
                    slotItem.deskEntry?.execute()
                }
                altAction:         () => {
                    if (root._dragging) return
                    if (root.contextMenu) {
                        root.contextMenu.open(dockBtn, slotItem.appEntry, slotItem.appId)
                    } else {
                        TaskbarApps.togglePin(slotItem.appId)
                    }
                }

                contentItem: DockIconMotion {
                    id: pinnedIconMotion
                    anchors.fill: parent
                    hovered: dockBtn.hovered
                    pressed: dockBtn.down
                    dragging: root._dragging
                    launching: DockLaunchTracker.isLaunching(slotItem.appId)

                    Component.onCompleted: {
                        if (DockLaunchTracker.firstAppearance(slotItem.appId))
                            playAppear();
                    }

                    Item {
                        anchors.centerIn: parent
                        width: 33
                        height: 33

                        IconImage {
                            id: appIcon
                            anchors.centerIn: parent
                            source: Quickshell.iconPath(
                                AppSearch.guessIcon(slotItem.appId),
                                "image-missing")
                            implicitSize: 33
                        }

                        Loader {
                            active: Config.options.dock.monochromeIcons
                            anchors.fill: appIcon
                            sourceComponent: Item {
                                Desaturate {
                                    id: desaturatedIcon
                                    visible: false
                                    anchors.fill: parent
                                    source: appIcon
                                    desaturation: 0.8
                                }
                                ColorOverlay {
                                    anchors.fill: desaturatedIcon
                                    source: desaturatedIcon
                                    color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.9)
                                }
                            }
                        }

                        Flow {
                            spacing: Appearance.spacing.space50
                            // The running dots sit between the icon and the
                            // screen edge, so they swap sides with the dock -
                            // and stack beside the icon at a side edge, where
                            // a row under it points into the next icon.
                            //
                            // These are the PINNED apps' dots. DockAppButton
                            // carries a second copy for the running unpinned
                            // ones, and a dock of pinned icons shows nothing of
                            // a change made only there.
                            readonly property string dotSide: DockGeometry.outwardSide(root.dockEdge)
                            flow: root.vertical ? Flow.TopToBottom : Flow.LeftToRight
                            anchors {
                                top: dotSide === "bottom" ? appIcon.bottom : undefined
                                bottom: dotSide === "top" ? appIcon.top : undefined
                                left: dotSide === "right" ? appIcon.right : undefined
                                right: dotSide === "left" ? appIcon.left : undefined
                                topMargin: dotSide === "bottom" ? Appearance.spacing.space25 : 0
                                bottomMargin: dotSide === "top" ? Appearance.spacing.space25 : 0
                                leftMargin: dotSide === "right" ? Appearance.spacing.space25 : 0
                                rightMargin: dotSide === "left" ? Appearance.spacing.space25 : 0
                                horizontalCenter: root.vertical ? undefined : parent.horizontalCenter
                                verticalCenter: root.vertical ? parent.verticalCenter : undefined
                            }
                            Repeater {
                                model: Math.min(slotItem.appEntry?.toplevels?.length ?? 0, 3)
                                delegate: Rectangle {
                                    required property int index
                                    readonly property real pillLength:
                                        (slotItem.appEntry?.toplevels?.length ?? 0) <= 3 ? 10 : 4
                                    radius:         Appearance.rounding.full
                                    implicitWidth:  root.vertical ? 4 : pillLength
                                    implicitHeight: root.vertical ? pillLength : 4
                                    color: slotItem.appActive
                                           ? Appearance.colors.colPrimary
                                           : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4)
                                    Behavior on implicitWidth {
                                        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                                    }
                                    Behavior on implicitHeight {
                                        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                                    }
                                    Behavior on color {
                                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            DragHandler {
                id: dragHandler
                target: null
                grabPermissions: PointerHandler.CanTakeOverFromAnything

                onActiveChanged: {
                    if (active) {
                        root._dragging = true
                        root.activeDragVisualIndex = index
                        root.buttonHovered = false
                        return
                    }
                    root.activeDragVisualIndex = -1
                    root._dragging = false
                    root.commitOrder()
                }

                // Everything below compares ONE coordinate: the one the slots
                // are laid out along. Comparing x in a column is not a subtly
                // wrong reorder, it is an inert one - every centre has the
                // same x, so the nearest slot is always whichever the loop
                // reached first and nothing ever swaps.
                function alongAxis(point) {
                    return root.vertical ? point.y : point.x
                }

                onCentroidChanged: {
                    if (!active) return
                    const currentVisualIdx = root.activeDragVisualIndex
                    if (currentVisualIdx < 0) return

                    const dragPos = alongAxis(dragHandler.centroid.scenePosition)
                    let minDist    = Infinity
                    let nearestIdx = currentVisualIdx

                    for (let i = 0; i < slotRepeater.count; i++) {
                        if (i === currentVisualIdx) continue
                        const child = slotRepeater.itemAt(i)
                        if (!child) continue
                        const cc   = child.mapToItem(null, child.width / 2, child.height / 2)
                        const dist = Math.abs(dragPos - alongAxis(cc))
                        if (dist < minDist) { minDist = dist; nearestIdx = i }
                    }

                    if (nearestIdx !== currentVisualIdx) {
                        const neighbor = slotRepeater.itemAt(nearestIdx)
                        if (!neighbor) return
                        const nc = alongAxis(
                            neighbor.mapToItem(null, neighbor.width / 2, neighbor.height / 2))
                        const shouldSwap = (nearestIdx > currentVisualIdx)
                            ? (dragPos >= nc)
                            : (dragPos <= nc)

                        if (shouldSwap) {
                            root.swapSlots(currentVisualIdx, nearestIdx)
                            root.activeDragVisualIndex = nearestIdx
                        }
                    }
                }
            }
        }
    }

    PopupWindow {
        id: previewPopup
        property var appTopLevel: root.lastHoveredButton?.appToplevel ?? null

        property bool shouldShow: (popupMouseArea.containsMouse || root.buttonHovered)
                                  && !root._dragging
                                  && !(root.contextMenu?.isOpen ?? false)
                                  && appTopLevel
                                  && appTopLevel.toplevels
                                  && appTopLevel.toplevels.length > 0

        property bool show: false
        // The hovered button's centre ALONG the strip - an x at a horizontal
        // edge, a y at a vertical one.
        property real cachedCenter: 0

        Connections {
            target: root
            function onLastHoveredButtonChanged() {
                if (root.lastHoveredButton && root.QsWindow)
                    previewPopup.cachedCenter = root.popupCenterForButton(root.lastHoveredButton)
            }
            function onButtonHoveredChanged() {
                if (root.buttonHovered && root.lastHoveredButton && root.QsWindow)
                    previewPopup.cachedCenter = root.popupCenterForButton(root.lastHoveredButton)
                updateTimer.restart()
            }
        }

        onShouldShowChanged: {
            updateTimer.restart()
        }

        Timer {
            id: updateTimer
            interval: 100
            onTriggered: {
                previewPopup.show = previewPopup.shouldShow
            }
        }

        // The corner of the dock's own surface the popup hangs off, and the
        // way it grows from there - both inward, or it opens into the screen
        // edge and the compositor clips it. Named sides come from the one
        // derivation; only the mapping onto Quickshell's flags is local,
        // because a .pragma library has no QML enums in scope.
        readonly property var anchorSides: DockGeometry.popupAnchorSides(root.dockEdge)
        function edgeFlags(names) {
            let flags = 0
            for (const name of names) {
                flags |= name === "top" ? Edges.Top
                    : name === "bottom" ? Edges.Bottom
                    : name === "left" ? Edges.Left : Edges.Right
            }
            return flags
        }

        anchor {
            window: root.QsWindow.window
            adjustment: PopupAdjustment.None
            gravity: previewPopup.edgeFlags(previewPopup.anchorSides.gravity)
            edges: previewPopup.edgeFlags(previewPopup.anchorSides.edges)
        }

        visible: popupBackground.opacity > 0
        color: "transparent"
        // The popup spans the dock's own long axis so the card can be placed
        // anywhere along it, and is content-sized across.
        implicitWidth: root.vertical
            ? popupMouseArea.implicitWidth + Appearance.sizes.elevationMargin * 2
            : (root.QsWindow.window?.width ?? 1)
        implicitHeight: root.vertical
            ? (root.QsWindow.window?.height ?? 1)
            : popupMouseArea.implicitHeight
                + root.windowControlsHeight
                + Appearance.sizes.elevationMargin * 2

        MouseArea {
            id: popupMouseArea
            // Pinned to the popup's own inward side, which is the side facing
            // the dock.
            readonly property string dockSide: DockGeometry.outwardSide(root.dockEdge)
            anchors.bottom: dockSide === "bottom" ? parent.bottom : undefined
            anchors.top: dockSide === "top" ? parent.top : undefined
            anchors.left: dockSide === "left" ? parent.left : undefined
            anchors.right: dockSide === "right" ? parent.right : undefined
            implicitWidth:  popupBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
            implicitHeight: root.maxWindowPreviewHeight
                            + root.windowControlsHeight
                            + Appearance.sizes.elevationMargin * 2
            hoverEnabled: true
            x: root.vertical ? 0 : previewPopup.cachedCenter - width / 2
            y: root.vertical ? previewPopup.cachedCenter - height / 2 : 0

            StyledRectangularShadow {
                target: popupBackground
                opacity: previewPopup.show ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            Rectangle {
                id: popupBackground
                property real padding: Appearance.spacing.space100
                opacity: previewPopup.show ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                clip: true
                color: Appearance.m3colors.m3surfaceContainer
                radius: Appearance.rounding.normal
                // Pushed off the side facing the dock by the elevation margin,
                // so the shadow has somewhere to fall.
                readonly property var cardMargins: DockGeometry.directedSides(
                    root.dockEdge, 0, Appearance.sizes.elevationMargin)
                anchors.bottom: popupMouseArea.dockSide === "bottom" ? parent.bottom : undefined
                anchors.top: popupMouseArea.dockSide === "top" ? parent.top : undefined
                anchors.left: popupMouseArea.dockSide === "left" ? parent.left : undefined
                anchors.right: popupMouseArea.dockSide === "right" ? parent.right : undefined
                anchors.bottomMargin: cardMargins.bottom
                anchors.topMargin: cardMargins.top
                anchors.leftMargin: cardMargins.left
                anchors.rightMargin: cardMargins.right
                anchors.horizontalCenter: root.vertical ? undefined : parent.horizontalCenter
                anchors.verticalCenter: root.vertical ? parent.verticalCenter : undefined
                implicitHeight: previewRowLayout.implicitHeight + padding * 2
                implicitWidth:  previewRowLayout.implicitWidth  + padding * 2
                Behavior on implicitWidth {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on implicitHeight {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                RowLayout {
                    id: previewRowLayout
                    anchors.centerIn: parent

                    Repeater {
                        model: ScriptModel {
                            values: previewPopup.appTopLevel?.toplevels ?? []
                        }

                        RippleButton {
                            id: windowButton
                            Layout.fillHeight: true
                            required property var modelData
                            padding: 0

                            middleClickAction: () => { windowButton.modelData?.close() }
                            onClicked: { windowButton.modelData?.activate() }

                            contentItem: ColumnLayout {
                                implicitWidth:  screencopyView.implicitWidth
                                implicitHeight: screencopyView.implicitHeight

                                ButtonGroup {
                                    contentWidth: parent.width - anchors.margins * 2

                                    StyledText {
                                        Layout.margins: Appearance.spacing.space100
                                        Layout.fillWidth: true
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        text: windowButton.modelData?.title
                                        elide: Text.ElideRight
                                        color: Appearance.m3colors.m3onSurface
                                    }

                                    GroupButton {
                                        id: closeButton
                                        colBackground: ColorUtils.transparentize(
                                            Appearance.colors.colSurfaceContainer)
                                        baseWidth:    root.windowControlsHeight
                                        baseHeight:   root.windowControlsHeight
                                        buttonRadius: Appearance.rounding.full
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            horizontalAlignment: Text.AlignHCenter
                                            text: "close"
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: Appearance.m3colors.m3onSurface
                                        }
                                        onClicked: { windowButton.modelData?.close() }
                                    }
                                }

                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    implicitHeight: screencopyView.height
                                    implicitWidth:  screencopyView.width

                                    ScreencopyView {
                                        id: screencopyView
                                        anchors.centerIn: parent
                                        captureSource: windowButton.modelData
                                        live: true
                                        paintCursor: true
                                        constraintSize: Qt.size(
                                            root.maxWindowPreviewWidth,
                                            root.maxWindowPreviewHeight)
                                        layer.enabled: true
                                        layer.effect: OpacityMask {
                                            maskSource: Rectangle {
                                                width:  screencopyView.width
                                                height: screencopyView.height
                                                radius: Appearance.rounding.small
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
