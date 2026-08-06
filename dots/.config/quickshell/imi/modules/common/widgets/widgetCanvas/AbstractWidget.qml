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
    property bool draggable: true
    property int gridSize: 12
    property bool snapEnabled: true
    readonly property bool dragging: drag.active
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
    drag.target: draggable ? dragProxy : undefined
    cursorShape: (draggable && containsPress) ? Qt.ClosedHandCursor : draggable ? Qt.OpenHandCursor : Qt.ArrowCursor

    onClicked: (mouse) => {
        if (mouse.button === Qt.RightButton) {
            Config.options.background.widgetsLocked = !Config.options.background.widgetsLocked
        }
    }

    // The canvas cannot see this widget's press/drag on its own, so report it.
    // Reported from the press, not from `dragging`: drag.active only flips
    // once the threshold is crossed, by which point the drag Binding has
    // already snapped this widget a step - offsets captured then would bake
    // that jump into every follower. At press nothing has moved yet.
    onPressed: (mouse) => {
        if (mouse.button !== Qt.LeftButton || !root.draggable) return
        const canvas = findCanvas(root.parent)
        if (canvas && canvas.widgetDragStarted) canvas.widgetDragStarted(root)
    }
    onReleased: {
        const canvas = findCanvas(root.parent)
        if (canvas && canvas.widgetDragEnded) canvas.widgetDragEnded(root)
    }
    onCanceled: {
        const canvas = findCanvas(root.parent)
        if (canvas && canvas.widgetDragEnded) canvas.widgetDragEnded(root)
    }

    function center() {
        root.x = (root.parent.width - root.width) / 2
        root.y = (root.parent.height - root.height) / 2
    }

    function snap(value) {
        return Math.round(value / root.gridSize) * root.gridSize
    }

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


    Item {
        id: dragProxy
        parent: root.parent
        x: root.x
        y: root.y

        onXChanged: {
            if (root.dragging) root.updateCenterHighlight()
        }
        onYChanged: if (root.dragging) root.updateCenterHighlight()
    }

    // Snap first, clamp second: clamp-then-snap could round the leader back
    // off the group bound by up to half a grid cell, deforming the cluster at
    // the screen edge by exactly the amount the lattice is meant to guarantee.
    Binding {
        target: root
        property: "x"
        value: Math.max(root.groupDragMinX, Math.min(root.groupDragMaxX,
            root.snapEnabled ? root.snap(dragProxy.x) : dragProxy.x))
        when: root.dragging
        restoreMode: Binding.RestoreNone
    }
    Binding {
        target: root
        property: "y"
        value: Math.max(root.groupDragMinY, Math.min(root.groupDragMaxY,
            root.snapEnabled ? root.snap(dragProxy.y) : dragProxy.y))
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

            if (Config.options.background.showSnapLines)
                canvas.flashLines(verticalLines, horizontalLines)
        }

        dragProxy.x = root.x
        dragProxy.y = root.y
    }

    Behavior on x {
        id: xBehavior
        enabled: !root.dragging && !root.groupDragging
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    Behavior on y {
        id: yBehavior
        enabled: !root.dragging && !root.groupDragging
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
