import QtQuick
import Quickshell
import qs.modules.common

/*
 * Widget to be placed on a WidgetCanvas
 */
MouseArea {
    id: root
    property alias animateXPos: xBehavior.enabled
    property alias animateYPos: yBehavior.enabled
    // Set false by a subclass whose x/y carry something that is not a move.
    //
    // A `Behavior` handed a target that changes every frame restarts every
    // frame and never gets to tick, so the property sits frozen at its old
    // value for as long as the target keeps moving. That is exactly what the
    // desktop's parallax opt-out feeds it (PluginWidget), and a frozen
    // position is worse than an unanimated one twice over: the widget travels
    // with the pan it was supposed to decline, and every save taken during the
    // pan reads a stale coordinate.
    property bool animatePosition: true
    property bool draggable: true
    property int gridSize: 12
    property bool snapEnabled: true
    // The drag is computed by hand from parent-frame pointer positions instead
    // of MouseArea.drag. QQuickDrag rebases its press origin when the grab is
    // established, silently swallowing the arming move's delta - invisible
    // under a real pointer (a few px, absorbed by the lattice snap) but wrong,
    // and it compounds with the old `dragProxy { x: root.x }` binding fighting
    // QQuickDrag's writes into overshoot. Mapping the pointer through this
    // (moving) item into the static parent frame is exact on every event.
    readonly property bool dragging: dragActive
    property bool dragActive: false
    property real dragPressParentX: 0
    property real dragPressParentY: 0
    property real dragStartX: 0
    property real dragStartY: 0
    // Lets the canvas find widgets in its subtree without walking into them.
    readonly property bool isCanvasWidget: true

    // Marquee selection (WidgetCanvas). The canvas owns the selection set and
    // writes this flag; the widget only renders it (the halo below) and offers
    // itself for hit-testing. Session state - it does not survive a reload.
    property bool selected: false

    // True on every non-leader member while a group drag is in flight. A
    // follower is not `dragging`, so without this second gate its position
    // Behaviors would animate every incremental group step and the cluster
    // would swim behind the pointer.
    property bool groupDragging: false

    // Group-drag clamp bounds, set by the canvas for the drag's leader so the
    // whole selection stops when its first member hits an edge. They reach
    // into the drag Binding below because that Binding is what moves the
    // leader - clamping anywhere else lets the leader walk on while the
    // followers stop, deforming the cluster. Defaults keep a single-widget
    // drag exactly what it was before group drag existed.
    property real groupDragMinX: -Infinity
    property real groupDragMaxX: Infinity
    property real groupDragMinY: -Infinity
    property real groupDragMaxY: Infinity

    // Background desktop widgets can request keyboard focus for their layer
    // surface. The request is registered with the enclosing WidgetCanvas, which
    // ORs every widget's request together so releasing one never cuts off
    // another that still needs it.
    property bool keyboardFocusRequested: false
    onKeyboardFocusRequestedChanged: root.syncKeyboardFocusRequest()
    function syncKeyboardFocusRequest() {
        const canvas = findCanvas(root.parent)
        if (canvas && canvas.setKeyboardFocusRequest)
            canvas.setKeyboardFocusRequest(root, root.keyboardFocusRequested)
    }
    Component.onDestruction: {
        const canvas = findCanvas(root.parent)
        if (canvas && canvas.setKeyboardFocusRequest)
            canvas.setKeyboardFocusRequest(root, false)
        if (canvas && canvas.widgetRemoved)
            canvas.widgetRemoved(root)
    }

    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: (draggable && containsPress) ? Qt.ClosedHandCursor : draggable ? Qt.OpenHandCursor : Qt.ArrowCursor

    onClicked: (mouse) => {
        if (mouse.button === Qt.RightButton) {
            Config.options.background.widgetsLocked = !Config.options.background.widgetsLocked
        }
    }

    // The canvas cannot see this widget's press/drag on its own, so report it.
    // Reported from the press, not from the threshold crossing: at press
    // nothing has moved yet, so the follower offsets and clamp bounds the
    // canvas captures cannot bake a first-step jump into the cluster.
    onPressed: (mouse) => {
        if (mouse.button !== Qt.LeftButton || !root.draggable) return
        root.dragCancelled = false
        const p = root.mapToItem(root.parent, mouse.x, mouse.y)
        root.dragPressParentX = p.x
        root.dragPressParentY = p.y
        root.dragStartX = root.x
        root.dragStartY = root.y
        dragProxy.x = root.x
        dragProxy.y = root.y
        const canvas = findCanvas(root.parent)
        if (canvas && canvas.widgetDragStarted) canvas.widgetDragStarted(root)
    }
    onPositionChanged: (mouse) => {
        if (!root.draggable || !(root.pressedButtons & Qt.LeftButton)) return
        // mouse.x/y are local to this moving item; mapping through it into the
        // parent recovers the pointer's absolute parent-frame position (the
        // current transform, press scale included, cancels itself out).
        const p = root.mapToItem(root.parent, mouse.x, mouse.y)
        const deltaX = p.x - root.dragPressParentX
        const deltaY = p.y - root.dragPressParentY
        if (!root.dragActive
                && Math.abs(deltaX) < drag.threshold && Math.abs(deltaY) < drag.threshold)
            return
        root.dragActive = true
        dragProxy.x = root.dragStartX + deltaX
        dragProxy.y = root.dragStartY + deltaY
    }
    // dragActive drops BEFORE the canvas is told: widgetDragEnded resets the
    // group clamp bounds, and doing that under a still-active drag Binding
    // re-evaluates it without the clamp - the leader jumps past the edge for
    // one frame and the followers commit the deformed cluster.
    onReleased: {
        root.dragActive = false
        const canvas = findCanvas(root.parent)
        if (canvas && canvas.widgetDragEnded) canvas.widgetDragEnded(root)
    }
    onCanceled: {
        root.dragActive = false
        const canvas = findCanvas(root.parent)
        if (canvas && canvas.widgetDragEnded) canvas.widgetDragEnded(root)
    }

    // Put the widget back where the press found it and commit nothing. Called
    // when something ends the gesture that is not the user finishing it - Edit
    // Mode being left mid-drag, and Escape while dragging.
    //
    // Restoring the BINDING is what returns the position: only a commit writes
    // targetX/targetY, so re-binding x/y through them is the pre-press place.
    // A widget with no such binding (the overlay's) is put back by hand.
    property bool dragCancelling: false
    // The pointer is still GRABBED when a gesture is cancelled - the mode ended,
    // the user did not let go - so a release is still coming, and a release
    // commits. It has to commit nothing: what it would write is wherever the
    // restore animation happened to be at that moment, which is a position the
    // widget is not at and the user never chose.
    property bool dragCancelled: false
    function cancelDrag() {
        if (!root.dragActive) return
        root.dragCancelling = true
        root.dragCancelled = true
        root.dragActive = false
        const canvas = findCanvas(root.parent)
        if (canvas && canvas.widgetDragCancelled) canvas.widgetDragCancelled(root)
        if (root.restoreXYBinding) root.restoreXYBinding()
        else {
            root.x = root.dragStartX
            root.y = root.dragStartY
        }
        root.dragCancelling = false
    }

    function center() {
        root.x = (root.parent.width - root.width) / 2
        root.y = (root.parent.height - root.height) / 2
    }

    function snap(value) {
        return Math.round(value / root.gridSize) * root.gridSize
    }

    // The drag snaps through these, so a subclass whose x/y are not the
    // coordinate it stores can move the lattice into the frame it means
    // something in. Per axis because that offset is per axis (PluginWidget:
    // the desktop pans x and y by different amounts, and usually only one of
    // them at all).
    //
    // The subclass hands in an offset rather than doing the snap itself,
    // because the lattice is not reachable from a subclass: `gridSize` is
    // shadowed - PluginWidget declares its own, the component-grid span a
    // manifest offers - so a snap written there reads `{"cols":2,"rows":1}`
    // where it wants 12 and silently produces no lattice at all. Measured:
    // `snap(100)` is 96 from in here and the same widget's `gridSize` is that
    // object from out there. Nothing warns.
    property real snapOffsetX: 0
    property real snapOffsetY: 0
    function snapX(value) { return root.snap(value - root.snapOffsetX) + root.snapOffsetX }
    function snapY(value) { return root.snap(value - root.snapOffsetY) + root.snapOffsetY }

    function findCanvas(item) {
        var p = item
        while (p) {
            if (p.isWidgetCanvas === true) return p
            p = p.parent
        }
        return null
    }

    function updateCenterHighlight() {
        var canvas = findCanvas(root.parent)
        if (!canvas) return
        var widgetCenterX = dragProxy.x + root.width / 2
        var widgetCenterY = dragProxy.y + root.height / 2
        var threshold = root.gridSize
        var nearX = Math.abs(widgetCenterX - canvas.width / 2) < threshold
        var nearY = Math.abs(widgetCenterY - canvas.height / 2) < threshold
        canvas.setCenterActive(nearX, nearY)
    }

    // Carries the unsnapped drag position, in the parent's frame. Deliberately
    // no `x: root.x` binding: a live binding here re-yanks the proxy to the
    // snapped widget position after every drag step; it is synced imperatively
    // at press and at each drag end instead.
    Item {
        id: dragProxy
        parent: root.parent

        onXChanged: if (root.dragging) root.updateCenterHighlight()
        onYChanged: if (root.dragging) root.updateCenterHighlight()
    }

    // Snap first, clamp second: clamp-then-snap could round the leader back
    // off the group bound by up to half a grid cell, deforming the cluster at
    // the screen edge by exactly the amount the lattice is meant to guarantee.
    Binding {
        target: root
        property: "x"
        value: Math.max(root.groupDragMinX, Math.min(root.groupDragMaxX,
            root.snapEnabled ? root.snapX(dragProxy.x) : dragProxy.x))
        when: root.dragging
        restoreMode: Binding.RestoreNone
    }
    Binding {
        target: root
        property: "y"
        value: Math.max(root.groupDragMinY, Math.min(root.groupDragMaxY,
            root.snapEnabled ? root.snapY(dragProxy.y) : dragProxy.y))
        when: root.dragging
        restoreMode: Binding.RestoreNone
    }

    onDraggingChanged: {
        var canvas = findCanvas(root.parent)
        if (canvas) canvas.setDragging(dragging)

        if (!dragging && canvas) {
            var left = root.x
            var right = root.x + root.width
            var top = root.y
            var bottom = root.y + root.height
            var verticalLines = [left, right]
            var horizontalLines = [top, bottom]

            var widgetCenterX = root.x + root.width / 2
            var widgetCenterY = root.y + root.height / 2
            if (Math.abs(widgetCenterX - canvas.width / 2) < root.gridSize / 2)
                verticalLines.push(canvas.width / 2)
            if (Math.abs(widgetCenterY - canvas.height / 2) < root.gridSize / 2)
                horizontalLines.push(canvas.height / 2)

            // A cancelled drag flashes nothing: the lines say "this is where it
            // landed", and it did not land anywhere.
            if (Config.options.background.showSnapLines && !root.dragCancelling)
                canvas.flashLines(verticalLines, horizontalLines)
        }

        dragProxy.x = root.x
        dragProxy.y = root.y
    }

    Behavior on x {
        id: xBehavior
        enabled: root.animatePosition && !root.dragging && !root.groupDragging
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    Behavior on y {
        id: yBehavior
        enabled: root.animatePosition && !root.dragging && !root.groupDragging
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    // Selected-but-not-dragging feedback, distinct from the press scale. Lives
    // on the widget so it tracks a group move with no coordinate mapping.
    Rectangle {
        id: selectionHalo
        visible: root.selected
        anchors.fill: parent
        anchors.margins: -Appearance.spacing.space50
        z: 2
        radius: Appearance.rounding.large
        color: Qt.alpha(Appearance.colors.colPrimary, 0.08)
        border.color: Appearance.colors.colPrimary
        border.width: Appearance.borderWidth.emphasis
    }
}