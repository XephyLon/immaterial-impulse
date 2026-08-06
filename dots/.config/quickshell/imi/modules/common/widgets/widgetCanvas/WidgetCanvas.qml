import QtQuick
import qs
import qs.modules.common

MouseArea {
    id: root
    property int gridSize: 24
    property bool showGrid: false
    readonly property bool isWidgetCanvas: true
    readonly property bool gridVisible: showGrid && Config.options.background.showGrid

    // Desktop widgets sit on the background layer surface, which only accepts
    // keyboard input while GlobalStates.desktopWidgetKeyboardFocus flips it to
    // OnDemand. Widgets register their need here so several can hold it at once;
    // the flag stays armed until the last requester releases it, so one widget
    // releasing focus never cuts off another that still needs it.
    property var keyboardFocusRequesters: []
    function setKeyboardFocusRequest(widget, requested) {
        const idx = root.keyboardFocusRequesters.indexOf(widget)
        if (requested && idx === -1) root.keyboardFocusRequesters.push(widget)
        else if (!requested && idx !== -1) root.keyboardFocusRequesters.splice(idx, 1)
        GlobalStates.desktopWidgetKeyboardFocus = root.keyboardFocusRequesters.length > 0
    }

    // Marquee multi-select. Opt-in per canvas: the overlay reuses WidgetCanvas
    // and closes itself on a plain click, so a marquee defaulting on would turn
    // every overlay dismiss-click into a selection gesture. The desktop
    // (Background.qml) is the one canvas that opts in.
    //
    // The selection is session state on this canvas - it does not survive a
    // reload, cannot leak across monitors (each background owns its canvas),
    // and is never persisted anywhere.
    property bool selectionEnabled: false
    property var selectedWidgets: []

    property bool marqueeActive: false
    property real marqueeAnchorX: 0
    property real marqueeAnchorY: 0

    // Escape is the keyboard way out of a selection. The desktop's layer
    // surface only takes keys while it is OnDemand, so a live selection also
    // registers as a keyboard-focus requester alongside the widgets above.
    focus: root.selectionEnabled
    Keys.onEscapePressed: root.clearSelection()
    onSelectedWidgetsChanged: root.setKeyboardFocusRequest(root, root.selectedWidgets.length > 0)

    // A press that starts ON a widget is that widget's drag - it never reaches
    // this handler. A press on empty canvas (or over a click-through widget,
    // which has left pointer routing) anchors the marquee; releasing it
    // replaces the selection with whatever the band covered, so a plain click
    // - a zero-size band over nothing draggable - is the click-away deselect.
    onPressed: (mouse) => {
        if (!root.selectionEnabled || mouse.button !== Qt.LeftButton) return
        if (Config.options.background.widgetsLocked) return
        root.marqueeAnchorX = mouse.x
        root.marqueeAnchorY = mouse.y
        root.marqueeActive = true
    }
    onReleased: {
        if (!root.marqueeActive) return
        root.marqueeActive = false
        root.selectWidgetsInRect(Qt.rect(marqueeRect.x, marqueeRect.y,
            marqueeRect.width, marqueeRect.height))
    }

    // Widgets are found by walking the subtree rather than kept in a registry:
    // on the real background each PluginWidget sits inside its own FadeLoader,
    // and a registry filled from Component.onCompleted would depend on the
    // loader having parented the widget under the canvas by then.
    function widgetsUnder(item, found) {
        for (let i = 0; i < item.children.length; i++) {
            const child = item.children[i]
            if (child.isCanvasWidget === true) found.push(child)
            else root.widgetsUnder(child, found)
        }
        return found
    }

    // `draggable` is the selection filter on purpose: it already folds in
    // everything that must exclude a widget from a group move - the per-widget
    // lock, click-through (the full-bleed visualizer ships it, so it does not
    // select itself on every marquee), the global lock, and a non-free
    // placement strategy. Filtering on anything narrower re-opens one of those.
    function selectWidgetsInRect(rect) {
        const picked = []
        for (const widget of root.widgetsUnder(root, [])) {
            if (!widget.draggable) continue
            const pos = widget.parent.mapToItem(root, widget.x, widget.y)
            if (pos.x < rect.x + rect.width && pos.x + widget.width > rect.x
                    && pos.y < rect.y + rect.height && pos.y + widget.height > rect.y)
                picked.push(widget)
        }
        root.applySelection(picked)
    }

    function applySelection(widgets) {
        for (const widget of root.selectedWidgets) {
            if (widgets.indexOf(widget) === -1) widget.selected = false
        }
        for (const widget of widgets) {
            widget.selected = true
        }
        root.selectedWidgets = widgets
    }

    function clearSelection() {
        root.applySelection([])
    }

    function widgetRemoved(widget) {
        const idx = root.selectedWidgets.indexOf(widget)
        if (idx !== -1) {
            const next = root.selectedWidgets.slice()
            next.splice(idx, 1)
            root.selectedWidgets = next
        }
        if (root.groupDrag && (root.groupDrag.leader === widget
                || root.groupDrag.followers.some(entry => entry.widget === widget)))
            root.groupDrag = null
    }

    // Locking the desktop clears the selection: two widgets still haloed under
    // a lock would look live while doing nothing, then spring back to life the
    // moment the lock lifts.
    Connections {
        target: Config.options.background
        function onWidgetsLockedChanged() {
            if (Config.options.background.widgetsLocked) root.clearSelection()
        }
    }

    // ---- group drag -------------------------------------------------------
    // Dragging any selected widget (the leader) moves the whole selection by
    // one delta. The leader reports its press and release; followers are moved
    // here and committed here, through the same commitPosition path a real
    // release runs - a follower never gets a release event, and a naive
    // "set x" with no commit would leave it with a dead x/y binding.
    property var groupDrag: null

    function widgetDragStarted(widget) {
        if (root.selectedWidgets.indexOf(widget) === -1) {
            // Grabbing a widget outside the selection is a click-away.
            root.clearSelection()
            return
        }
        let deltaMinX = -Infinity
        let deltaMaxX = Infinity
        let deltaMinY = -Infinity
        let deltaMaxY = Infinity
        const followers = []
        for (const member of root.selectedWidgets) {
            // Map through the parent: mapping the widget itself would fold its
            // press-scale transform into the bounds.
            const pos = member.parent.mapToItem(root, member.x, member.y)
            deltaMinX = Math.max(deltaMinX, -pos.x)
            deltaMaxX = Math.min(deltaMaxX, root.width - member.width - pos.x)
            deltaMinY = Math.max(deltaMinY, -pos.y)
            deltaMaxY = Math.min(deltaMaxY, root.height - member.height - pos.y)
            if (member !== widget) {
                member.groupDragging = true
                followers.push({ widget: member, startX: member.x, startY: member.y })
            }
        }
        widget.groupDragMinX = widget.x + deltaMinX
        widget.groupDragMaxX = widget.x + deltaMaxX
        widget.groupDragMinY = widget.y + deltaMinY
        widget.groupDragMaxY = widget.y + deltaMaxY
        root.groupDrag = { leader: widget, startX: widget.x, startY: widget.y, followers: followers }
    }

    function syncGroupFollowers() {
        const group = root.groupDrag
        if (!group) return
        const deltaX = group.leader.x - group.startX
        const deltaY = group.leader.y - group.startY
        for (const entry of group.followers) {
            entry.widget.x = entry.startX + deltaX
            entry.widget.y = entry.startY + deltaY
        }
    }

    function widgetDragEnded(widget) {
        widget.groupDragMinX = -Infinity
        widget.groupDragMaxX = Infinity
        widget.groupDragMinY = -Infinity
        widget.groupDragMaxY = Infinity
        const group = root.groupDrag
        if (!group || group.leader !== widget) return
        root.groupDrag = null
        for (const entry of group.followers) {
            entry.widget.groupDragging = false
            if (entry.widget.commitPosition) entry.widget.commitPosition()
        }
    }

    Connections {
        target: root.groupDrag ? root.groupDrag.leader : null
        function onXChanged() { root.syncGroupFollowers() }
        function onYChanged() { root.syncGroupFollowers() }
    }

    property bool centerXActive: false
    property bool centerYActive: false

    function setDragging(active) {
        root.showGrid = active
        if (!active) {
            root.centerXActive = false
            root.centerYActive = false
        }
    }

    function setCenterActive(xActive, yActive) {
        root.centerXActive = xActive
        root.centerYActive = yActive
    }

    Repeater {
        model: root.gridVisible ? Math.ceil(root.width / root.gridSize) : 0
        delegate: Rectangle {
            required property int index
            x: index * root.gridSize
            width: 1
            height: root.height
            color: Appearance.colors.colLayer0Border
        }
    }

    Repeater {
        model: root.gridVisible ? Math.ceil(root.height / root.gridSize) : 0
        delegate: Rectangle {
            required property int index
            y: index * root.gridSize
            width: root.width
            height: 1
            color: Appearance.colors.colLayer0Border
        }
    }

    Rectangle {
        id: centerLineV
        visible: root.gridVisible
        x: root.width / 2 - width / 2
        width: root.centerXActive ? 2 : 1
        height: root.height
        color: root.centerXActive ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
        opacity: root.centerXActive ? 1 : 0.6

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on width {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    Rectangle {
        id: centerLineH
        visible: root.gridVisible
        y: root.height / 2 - height / 2
        width: root.width
        height: root.centerYActive ? 2 : 1
        color: root.centerYActive ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
        opacity: root.centerYActive ? 1 : 0.6

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on height {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    // The rubber band. Same visual family as the region selector's
    // TargetRegion, but this one is an in-place interaction on the canvas, not
    // a modal overlay. mouseX/mouseY track the pointer for the whole press.
    Rectangle {
        id: marqueeRect
        visible: root.marqueeActive
        z: 10
        x: Math.min(root.marqueeAnchorX, root.mouseX)
        y: Math.min(root.marqueeAnchorY, root.mouseY)
        width: Math.abs(root.mouseX - root.marqueeAnchorX)
        height: Math.abs(root.mouseY - root.marqueeAnchorY)
        color: Qt.alpha(Appearance.colors.colPrimary, 0.08)
        border.color: Appearance.colors.colPrimary
        border.width: Appearance.borderWidth.standard
        radius: Appearance.rounding.unsharpenslight
    }

    Component {
        id: flashLineComponent
        Rectangle {
            id: flashLine
            property bool vertical: true
            property real linePos: 0
            color: Appearance.colors.colPrimary
            x: vertical ? linePos : 0
            y: vertical ? 0 : linePos
            width: vertical ? 2 : root.width
            height: vertical ? root.height : 2

            NumberAnimation on opacity {
                from: 0.9
                to: 0
                duration: 2000
                easing.type: Easing.OutCubic
                running: true
                onFinished: flashLine.destroy()
            }
        }
    }

    function flashLines(verticalPositions, horizontalPositions) {
        for (let i = 0; i < verticalPositions.length; i++)
            flashLineComponent.createObject(root, { vertical: true, linePos: verticalPositions[i] })
        for (let i = 0; i < horizontalPositions.length; i++)
            flashLineComponent.createObject(root, { vertical: false, linePos: horizontalPositions[i] })
    }
}
