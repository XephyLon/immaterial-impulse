import QtQuick
import qs
import qs.modules.common
import "../../functions/edit_mode.js" as EditMode

MouseArea {
    id: root
    // The drawn lattice is the one the drag snaps to (AbstractWidget's 12px),
    // with every second line emphasised so the 24px rhythm this used to draw is
    // still readable. Drawing 24 while snapping 12 was honest enough while the
    // grid was only up during a drag; with it up for the whole of Edit Mode, a
    // widget landing between two lines reads as broken snapping.
    property int gridSize: 12
    property bool showGrid: false
    readonly property bool isWidgetCanvas: true
    // Handed in by the surface that owns this canvas - the desktop's, and only
    // the desktop's. The overlay reuses this component and has its own store
    // and its own dismissal, so it must not follow the mode.
    property bool editMode: false
    // Edit Mode's whole purpose is that the affordances stop hiding, so the
    // grid is up for the mode rather than for the gesture. It overrides the
    // config switch, whose meaning is "draw the grid while I drag".
    readonly property bool gridVisible: root.editMode
        || (showGrid && Config.options.background.showGrid)
    // ...and it arrives and leaves rather than appearing. The lattice used to be
    // a Repeater model going straight from 0 to a screen's worth of lines, so it
    // popped on while the desktop eased into the mode beside it - the reading of
    // "not M3E-compliant" that costs nothing to fix. An effects tier because
    // this is an opacity, which is what elementMoveFast is for and what the
    // centre lines in this same file already animate on.
    property real gridStrength: root.gridVisible ? 1 : 0
    Behavior on gridStrength {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

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

    // Escape is the keyboard way out of a selection, and Edit Mode may not take
    // it from that or from a grip resize (PluginWidget handles its own, which
    // gets the key first because the grip has focus during the gesture). The
    // ladder resolves in order and the first match wins; the module owns the
    // precedence so it is checkable without a canvas.
    //
    // The desktop's layer surface only takes keys while it is OnDemand, so a
    // live selection - and the mode - register as keyboard-focus requesters
    // alongside the widgets above. Whether the compositor then delivers the key
    // to a Bottom-layer surface is not established, which is why the mode has a
    // pointer way out as well and no feature depends on this alone.
    focus: root.selectionEnabled
    Keys.onEscapePressed: {
        const action = EditMode.resolveEscape({
            gestureInFlight: root.draggingWidget() !== null,
            selectionCount: root.selectedWidgets.length,
            tab: EditMode.DESKTOP_TAB
        })
        if (action === "cancelGesture") root.cancelActiveDrag()
        else if (action === "clearSelection") root.clearSelection()
        else if (root.editMode) GlobalStates.editMode = false
    }
    readonly property bool keyboardFocusHeld: root.selectedWidgets.length > 0 || root.editMode
    onKeyboardFocusHeldChanged: {
        root.setKeyboardFocusRequest(root, root.keyboardFocusHeld)
        if (root.keyboardFocusHeld) root.forceActiveFocus()
    }
    onSelectedWidgetsChanged: {
        root.setKeyboardFocusRequest(root, root.keyboardFocusHeld)
        if (root.selectedWidgets.length > 0) root.forceActiveFocus()
    }

    // A press that starts ON a widget is that widget's drag - it never reaches
    // this handler. A press on empty canvas (or over a click-through widget,
    // which has left pointer routing) anchors the marquee; releasing it
    // replaces the selection with whatever the band covered, so a plain click
    // - a zero-size band over nothing draggable - is the click-away deselect.
    onPressed: (mouse) => {
        if (!root.selectionEnabled || mouse.button !== Qt.LeftButton) return
        // The mode subtracts the global lock rather than writing it: the stored
        // preference is untouched and the desktop is locked again on the way
        // out. AbstractBackgroundWidget's `interactionLocked` does the same for
        // the widgets themselves.
        if (!root.editMode && Config.options.background.widgetsLocked) return
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
            // Not while editing: the mode suppresses that lock, so the widgets
            // are still live and a cleared selection would be a lie about them.
            if (Config.options.background.widgetsLocked && !root.editMode) root.clearSelection()
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
        // Detach the group before resetting the clamp bounds: the bounds feed
        // the leader's drag Binding, and a re-evaluation mid-teardown must not
        // reach the followers as one more (unclamped) sync.
        const group = root.groupDrag
        if (group && group.leader === widget) root.groupDrag = null
        widget.groupDragMinX = -Infinity
        widget.groupDragMaxX = Infinity
        widget.groupDragMinY = -Infinity
        widget.groupDragMaxY = Infinity
        if (!group || group.leader !== widget) return
        for (const entry of group.followers) {
            entry.widget.groupDragging = false
            if (entry.widget.commitPosition) entry.widget.commitPosition()
        }
    }

    // The cancel half of the drag, which nothing needed until the mode could
    // end in the middle of one. A release COMMITS - clamped and written to the
    // store - and the drag is deliberately unclamped until then, so committing
    // a gesture the user never finished stores an overshoot: exactly the defect
    // 705e9006d ("fix(plugins): stop a widget's stored position disagreeing
    // with where it is drawn") fixed, where a real store held a widget at
    // x: -852 on a 5120px screen.
    function widgetDragCancelled(widget) {
        const group = root.groupDrag
        if (group && group.leader === widget) root.groupDrag = null
        widget.groupDragMinX = -Infinity
        widget.groupDragMaxX = Infinity
        widget.groupDragMinY = -Infinity
        widget.groupDragMaxY = Infinity
        if (!group || group.leader !== widget) return
        for (const entry of group.followers) {
            entry.widget.groupDragging = false
            // Put the follower back and rebind, rather than committing it the
            // way widgetDragEnded does: a follower never gets a release event,
            // so this is the only path that can undo its imperative move.
            entry.widget.x = entry.startX
            entry.widget.y = entry.startY
            if (entry.widget.restoreXYBinding) entry.widget.restoreXYBinding()
        }
    }

    function draggingWidget() {
        for (const widget of root.widgetsUnder(root, []))
            if (widget.dragging) return widget
        return null
    }

    function cancelActiveDrag() {
        const widget = root.draggingWidget()
        if (widget && widget.cancelDrag) widget.cancelDrag()
    }

    // Leaving the mode mid-drag cancels the gesture. It cannot commit: a widget
    // is only clamped on release, and the mode ending is not the user letting
    // go of anything.
    //
    // The selection goes with it, because Done means "stop" (spec §8.2) and a
    // selection halo surviving the mode is a marquee the user has no visible
    // way to clear. Escape never reaches this branch holding one - the ladder
    // clears the selection before it will exit - so this is the exit that Done
    // and the screen being taken away both take.
    onEditModeChanged: if (!root.editMode) { root.cancelActiveDrag(); root.clearSelection() }

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

    // Every second line at full strength, the ones between it fainter: the fine
    // lattice is what the drag actually lands on, and the emphasis is what
    // keeps a screen's worth of 12px lines readable rather than grey.
    readonly property real fineGridOpacity: 0.4

    // The lattice dissolves toward the canvas edges rather than being sliced off
    // at them. Two halves, and both are needed: a gradient ALONG each line so it
    // fades at its own two ends, and a per-line opacity ACROSS the lattice so
    // the lines nearest an edge are the faintest. Either one alone leaves the
    // other axis running full strength into the boundary, which is what read as
    // the grid ending abruptly - a texture pasted onto the desktop rather than
    // something the surface has.
    readonly property real gridFadeFraction: 0.07
    function edgeFade(position, extent) {
        const band = extent * root.gridFadeFraction
        if (band <= 0) return 1
        const distance = Math.min(position, extent - position)
        return distance >= band ? 1 : Math.max(0, distance / band)
    }

    // One gradient object shared by every line on that axis rather than one
    // declared inside each delegate: a screen's worth of 12px lines is several
    // hundred delegates, and four GradientStops apiece is a few thousand objects
    // built at the moment the mode is entered.
    //
    // The far ends are the line's own colour at zero alpha, not "transparent" -
    // a stop interpolating toward #00000000 walks the colour through black on
    // the way, which draws a dark smudge at exactly the edge this exists to
    // make quiet.
    readonly property color gridLineColor: Appearance.colors.colLayer0Border
    readonly property color gridLineFadeColor: Qt.rgba(root.gridLineColor.r,
        root.gridLineColor.g, root.gridLineColor.b, 0)
    readonly property Gradient gridFadeAlongY: Gradient {
        GradientStop { position: 0; color: root.gridLineFadeColor }
        GradientStop { position: root.gridFadeFraction; color: root.gridLineColor }
        GradientStop { position: 1 - root.gridFadeFraction; color: root.gridLineColor }
        GradientStop { position: 1; color: root.gridLineFadeColor }
    }
    readonly property Gradient gridFadeAlongX: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: root.gridLineFadeColor }
        GradientStop { position: root.gridFadeFraction; color: root.gridLineColor }
        GradientStop { position: 1 - root.gridFadeFraction; color: root.gridLineColor }
        GradientStop { position: 1; color: root.gridLineFadeColor }
    }

    // The lattice is a SUBSTRATE: widgets sit on it. That order is declared here
    // rather than left to the order the children happen to be built in, because
    // nothing in this file decides it - the desktop widgets arrive as EXTERNAL
    // children of this canvas (Background.qml's Repeater over the plugin
    // manifests), so which of the two ends up on top is a consequence of when a
    // Repeater's model filled rather than of anything anybody chose. A widget
    // whose panel is translucent - which every desktop widget is, and which the
    // mode makes more so by standing the frost down - then has a crisp full
    // strength line running across it, and reads as being under the grid.
    Item {
        id: lattice
        anchors.fill: parent
        z: -1
        // The delegates outlive the flag so the fade-out has something to fade.
        opacity: root.gridStrength
        visible: root.gridStrength > 0
        // Cannot take input, ever. The canvas's own press is what anchors the
        // marquee and what a widget's drag is measured against.
        enabled: false

        Repeater {
            model: root.gridStrength > 0 ? Math.ceil(root.width / root.gridSize) : 0
            delegate: Rectangle {
                required property int index
                x: index * root.gridSize
                width: 1
                height: root.height
                opacity: (index % 2 === 0 ? 1 : root.fineGridOpacity)
                    * root.edgeFade(x, root.width)
                gradient: root.gridFadeAlongY
            }
        }

        Repeater {
            model: root.gridStrength > 0 ? Math.ceil(root.height / root.gridSize) : 0
            delegate: Rectangle {
                required property int index
                y: index * root.gridSize
                width: root.width
                height: 1
                opacity: (index % 2 === 0 ? 1 : root.fineGridOpacity)
                    * root.edgeFade(y, root.height)
                gradient: root.gridFadeAlongX
            }
        }

        Rectangle {
            id: centerLineV
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