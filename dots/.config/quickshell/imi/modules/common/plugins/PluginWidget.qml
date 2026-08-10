import QtQuick
import QtQuick.Window
import Qt5Compat.GraphicalEffects
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.imi.background.widgets
import "../functions/parallax.js" as ParallaxMath
import "gridSizes.js" as GridSizes

AbstractBackgroundWidget {
    id: rootWidget
    required property var manifest
    required property string screenName

    // Set by the background that owns this widget; only forwarded, never read
    // here. The clock draws a "Wallpaper safety enforced" badge from it.
    property bool wallpaperSafetyTriggered: false

    // Desktop-widget behaviours a ported built-in used to set on itself, now
    // opted into by the loaded Widget.qml (see PluginNode). A widget that
    // declares none of them behaves exactly as before.
    //
    // The clock is the only clock the lock screen has, so it must be able to
    // stay visible while locked regardless of `lock.showWidgets` - which
    // exists to hide the *other* desktop widgets - and to centre itself there,
    // which is what `lock.centerClock` has always done.
    visibleWhenLocked: pluginNode.wantsVisibleWhenLocked
        || Config.options.lock.showWidgets
    readonly property bool forceCenter: pluginNode.wantsForceCenter

    // Drives AbstractBackgroundWidget's least-busy-region pass, whose real
    // output for a "free" widget is `dominantColor` -> `colText`: the text
    // colour a widget that draws no panel needs in order to stay readable
    // against whatever part of the wallpaper it happens to sit on.
    needsColText: pluginNode.wantsAdaptiveTextColor
    // The item loads after the host, so the flag arrives late and none of the
    // existing refresh triggers fire for it.
    onNeedsColTextChanged: rootWidget.refreshPlacementIfNeeded()

    // The live in-shell Wallpaper Engine surface (whole-screen), passed down from
    // Background so "blur" frost can sample the animated wallpaper behind each
    // widget. Null when no WE wallpaper is active (static image path).
    property Item weSurfaceItem: null

    // Where the widget canvas and the wallpaper actually are on this monitor,
    // fed live by Background. Two different positions: the canvas travels at
    // `parallax.widgetsFactor` and the wallpaper at 1, which is the parallax.
    // These are the containers' animating x/y rather than the parallax targets,
    // so the frost stays aligned during a pan and not only once it settles.
    property real canvasOffsetX: 0
    property real canvasOffsetY: 0
    property rect wallpaperRect: Qt.rect(0, 0, 0, 0)

    // This widget's top-left in the wallpaper's own coordinates - the space the
    // frost samples in. Sampling at the widget's canvas position instead is
    // issue #157: it happens to be right only where neither pan has moved.
    readonly property var frostSampleOrigin: ParallaxMath.sampleOrigin(
        { x: rootWidget.canvasOffsetX, y: rootWidget.canvasOffsetY },
        { x: rootWidget.x, y: rootWidget.y },
        { x: rootWidget.wallpaperRect.x, y: rootWidget.wallpaperRect.y })

    readonly property bool blurEnabled: manifest
        ? PluginState.option(manifest.id, "blurEnabled", manifest.desktopWidget?.blur === true)
        : false

    // Per-widget lock and click-through (AbstractBackgroundWidget). Same shape
    // as blurEnabled: the manifest seeds the default - a full-bleed widget with
    // nothing to click, like the visualiser, ships `clickThrough` on - and
    // PluginState carries the user's override, so a shipped default stays
    // reversible from Settings > Widgets.
    //
    // These are bindings and nothing may assign them: a direct assignment kills
    // the PluginState binding, and the value would then be frozen for the rest
    // of the session while the settings toggle appears to do nothing.
    positionLocked: manifest
        ? PluginState.option(manifest.id, "positionLocked", manifest.desktopWidget?.locked === true)
        : false
    clickThrough: manifest
        ? PluginState.option(manifest.id, "clickThrough", manifest.desktopWidget?.clickThrough === true)
        : false
    // Exempts this widget from the transparency toggle: with transparency off
    // every other widget's panel is forced fully opaque
    // (PluginState.effectiveBackgroundOpacity) and loses its frost, which is
    // the whole point for a widget that is meant to be see-through. Both
    // halves have to follow the flag together - a translucent panel with the
    // frost still suppressed is exactly the sharp-wallpaper hole the opaque
    // default exists to remove.
    readonly property bool keepTranslucent: manifest
        ? PluginState.option(manifest.id, "keepTranslucent", manifest.desktopWidget?.keepTranslucent === true)
        : false
    // Frost mode is user-selectable: "blur" samples + blurs the wallpaper region
    // behind the widget; "tint" (any non-"blur" value) leaves the widget's own
    // translucent panel to show the sharp wallpaper through it.
    readonly property bool frostBlur: Config.options.plugins.frostMode === "blur"
    // The in-shell live blur (ShaderEffectSource of the WE surface) works while
    // locked too, so this stays true when locked - unlike the old compositor
    // handoff which had to fall back to the static image on lock.
    readonly property bool liveWallpaperActive: rootWidget.weSurfaceItem !== null
    readonly property bool hasBlurSurface: !pluginNode.hasCustomBlurRegions
        || pluginNode.blurRegions.length > 0

    readonly property real widgetRounding: {
        const val = manifest?.desktopWidget?.props?.radius;
        if (typeof val === "string" && val.startsWith("Appearance.rounding.")) {
            return Appearance.rounding[val.substring(20)] ?? Appearance.rounding.large;
        }
        if (typeof val === "number") return val;
        return Appearance.rounding.large;
    }

    // Optional component-grid span declared by the manifest (top-level `grid`).
    // When present, the widget's pixel size is spanX(cols) x spanY(rows); when
    // absent, the widget stays content-sized (legacy behaviour). Position uses
    // the shared fine 12px drag snap (AbstractWidget default) - every span is a
    // whole multiple of 12 (cell 132/108, gap 12), so a grid widget still lands
    // flush against its neighbours without a coarse snap that makes it jump.
    // See docs/widget-grid.md.
    //
    // A manifest may offer several spans (`grid.sizes`), in which case the one
    // in use is the user's stored choice. `__gridSize` is host state, not a
    // plugin setting: the double underscore keeps it out of the manifest's own
    // options namespace (PluginValidator rejects a manifest key starting with
    // it) so it never surfaces as a control in Settings > Widgets.
    readonly property var gridSpec: (manifest && manifest.grid) ? manifest.grid : null
    readonly property var offeredGridSizes: GridSizes.offeredSizes(rootWidget.gridSpec)
    readonly property bool gridResizable: rootWidget.offeredGridSizes.length > 1
    // Stored -> manifest default -> null, which is the content-sized path.
    readonly property var storedGridSize: GridSizes.resolveSize(rootWidget.gridSpec,
        manifest ? PluginState.option(manifest.id, "__gridSize") : undefined)
    // The span the grip's drag is currently previewing, null when no resize is
    // in flight. The widget resizes as the pointer moves, so the size on screen
    // is the size a release commits - and Escape cancels by clearing this, with
    // the widget falling straight back to its stored span.
    property var previewGridSize: null
    readonly property bool resizingGrid: previewGridSize !== null
    readonly property var gridSize: previewGridSize ?? storedGridSize
    readonly property int gridCols: gridSize ? gridSize.cols : 0
    readonly property int gridRows: gridSize ? gridSize.rows : 0
    readonly property real gridSpanWidth: gridSize ? Appearance.sizes.widgetGridSpanX(gridCols) : 0
    readonly property real gridSpanHeight: gridSize ? Appearance.sizes.widgetGridSpanY(gridRows) : 0

    function commitGridSize(size) {
        if (!manifest || !size) return;
        PluginState.setOption(manifest.id, "__gridSize", GridSizes.formatSize(size));
    }

    function beginGridResize() {
        rootWidget.previewGridSize = rootWidget.storedGridSize;
    }

    // The offered spans measured in pixels, which is where Appearance's
    // effectiveScale enters: the snap compares the dragged rectangle against
    // what each span would actually be on this screen, not against cell counts.
    function previewGridResize(targetWidth, targetHeight) {
        if (!rootWidget.resizingGrid) return;
        const nearest = GridSizes.nearestSize(rootWidget.offeredGridSizes.map(size => ({
            cols: size.cols,
            rows: size.rows,
            width: Appearance.sizes.widgetGridSpanX(size.cols),
            height: Appearance.sizes.widgetGridSpanY(size.rows)
        })), targetWidth, targetHeight);
        if (nearest) rootWidget.previewGridSize = nearest;
    }

    function endGridResize() {
        const chosen = rootWidget.previewGridSize;
        rootWidget.previewGridSize = null;
        rootWidget.commitGridSize(chosen);
    }

    function cancelGridResize() {
        rootWidget.previewGridSize = null;
    }

    configEntryName: manifest ? "plugin_" + manifest.id : "plugin_unknown"

    // The background layer surface only accepts keyboard input while it is
    // OnDemand, and the compositor grants that focus to an already-OnDemand
    // surface on click. Arm it while any plugin widget is hovered so the click
    // that lands on an inner input (a TextField, StyledTextArea, ...) grabs
    // Wayland keyboard focus. Stay armed while a descendant keeps focus so
    // moving the pointer off the widget mid-edit does not drop keyboard input.
    hoverEnabled: true
    keyboardFocusRequested: rootWidget.containsMouse || rootWidget.descendantHasFocus
    readonly property bool descendantHasFocus: {
        let focusItem = rootWidget.Window.activeFocusItem;
        while (focusItem) {
            if (focusItem === rootWidget) return true;
            focusItem = focusItem.parent;
        }
        return false;
    }

    // Plugin ids and monitor names are dynamic, so their layout cannot safely live in
    // Config's fixed JsonAdapter schema. PluginState persists it as raw JSON instead.
    property var currentConfig: manifest
        ? PluginState.position(manifest.id, screenName)
        : PluginState.defaultPosition()
    placementStrategy: currentConfig.placementStrategy || "free"

    // Dragging assigns targetX/targetY directly and therefore intentionally
    // breaks their initial bindings. Re-apply persisted geometry whenever the
    // external state file changes so preset switches also move live widgets.
    function applyPersistedPosition() {
        const nextX = currentConfig.x !== undefined ? currentConfig.x : 100;
        const nextY = currentConfig.y !== undefined ? currentConfig.y : 100;
        rootWidget.targetX = Math.max(0, Math.min(nextX, scaledScreenWidth - width));
        rootWidget.targetY = Math.max(0, Math.min(nextY, scaledScreenHeight - height));
    }

    onCurrentConfigChanged: applyPersistedPosition()
    Component.onCompleted: applyPersistedPosition()

    // `forceCenter` overrides the persisted position for as long as it is set,
    // without disturbing it - the widget returns to where the user left it the
    // moment the condition clears. Dragging assigns x/y directly and so breaks
    // these bindings; AbstractBackgroundWidget calls restoreXYBinding() on
    // release for exactly this case, so the override has to be restored there
    // too or a single drag disables centring for the rest of the session.
    x: rootWidget.forceCenter ? ((scaledScreenWidth - width) / 2) : targetX
    y: rootWidget.forceCenter ? ((scaledScreenHeight - height) / 2) : targetY

    function restoreXYBinding() {
        rootWidget.x = Qt.binding(() => rootWidget.forceCenter
            ? ((rootWidget.scaledScreenWidth - rootWidget.width) / 2)
            : rootWidget.targetX);
        rootWidget.y = Qt.binding(() => rootWidget.forceCenter
            ? ((rootWidget.scaledScreenHeight - rootWidget.height) / 2)
            : rootWidget.targetY);
    }

    // Overrides AbstractBackgroundWidget's release path, which calls this on a
    // real release - and which WidgetCanvas calls on every group-drag follower,
    // since a follower never gets a release event. One function on purpose:
    // restoreXYBinding() keeps forceCenter and external position changes alive
    // after the drag broke the x/y bindings, and setPosition is what makes the
    // move survive a restart.
    function commitPosition() {
        rootWidget.targetX = rootWidget.x;
        rootWidget.targetY = rootWidget.y;
        rootWidget.restoreXYBinding();
        if (!manifest) return;
        PluginState.setPosition(manifest.id, screenName, {
            x: rootWidget.targetX,
            y: rootWidget.targetY,
            placementStrategy: rootWidget.placementStrategy
        });
    }

    // A declared grid span drives the pixel size directly; otherwise the widget
    // is sized to its content (with any legacy defaultWidth/Height as a floor).
    width: gridSize ? gridSpanWidth
        : Math.max(manifest ? (manifest.defaultWidth || 0) : 0, pluginNode.width)
    height: gridSize ? gridSpanHeight
        : Math.max(manifest ? (manifest.defaultHeight || 0) : 0, pluginNode.height)

    // In-shell frost: sample + blur the wallpaper region behind each blur region.
    // The sample tracks rootWidget.x/y live so it stays aligned while dragging.
    //
    // While the screen is locked AND the lock blurs the wallpaper
    // (Background.qml's blurLoader shows a blurred + zoomed wallpaper), skip our
    // own blur surface - the widget's translucent panel then shows that lock
    // background through it, keeping the frost consistent with the lock screen.
    // If the lock does NOT blur the wallpaper, keep blurring per widget so a
    // blur-enabled widget stays frosted against the sharp wallpaper.
    readonly property bool lockCoversFrost: GlobalStates.screenLocked
        && Config.options.lock.blur.enable
    Repeater {
        model: rootWidget.frostBlur && rootWidget.blurEnabled && !rootWidget.lockCoversFrost
            && rootWidget.hasBlurSurface
            && (Config.options.appearance.transparency.enable || rootWidget.keepTranslucent)
            ? (pluginNode.hasCustomBlurRegions
                ? pluginNode.blurRegions
                : [{ x: 0, y: 0, width: rootWidget.width,
                    height: rootWidget.height, radius: rootWidget.widgetRounding }])
            : []

        WallpaperBlurSurface {
            required property var modelData
            z: 0
            x: Number(modelData.x || 0)
            y: Number(modelData.y || 0)
            width: Number(modelData.width || 0)
            height: Number(modelData.height || 0)
            wallpaperSource: rootWidget.wallpaperPath
            liveWallpaperActive: rootWidget.liveWallpaperActive
            weSurfaceItem: rootWidget.weSurfaceItem
            cornerRadius: Number(modelData.radius ?? rootWidget.widgetRounding)
            wallpaperWidth: rootWidget.wallpaperRect.width
            wallpaperHeight: rootWidget.wallpaperRect.height
            surfaceX: rootWidget.frostSampleOrigin.x + x
            surfaceY: rootWidget.frostSampleOrigin.y + y
        }
    }

    PluginNode {
        id: pluginNode
        z: 1
        // Render package widgets on a bounded texture above the blur backdrop.
        // This avoids the background layer swallowing package content on some
        // Wayland scene-graph paths while keeping the texture widget-sized.
        layer.enabled: width > 0 && height > 0
        layer.smooth: true
        manifestNode: rootWidget.manifest ? rootWidget.manifest.desktopWidget : null
        pluginId: rootWidget.manifest?.id ?? ""
        optionDefinitions: rootWidget.manifest?.options ?? []
        basePath: rootWidget.manifest?._basePath ?? ""
        screenName: rootWidget.screenName
        hostX: rootWidget.x
        hostY: rootWidget.y
        hostColText: rootWidget.colText
        hostWallpaperSafetyTriggered: rootWidget.wallpaperSafetyTriggered
        hostInteractionLocked: rootWidget.interactionLocked
        // When the manifest declares a grid span, drive the node (and its loaded
        // Widget.qml) to the span size instead of the content's implicit size.
        gridWidth: rootWidget.gridSpanWidth
        gridHeight: rootWidget.gridSpanHeight
        anchors.centerIn: parent
    }

    // Resize grip, for a widget whose manifest offers more than one span. It
    // sits in the host rather than in each plugin, so a manifest opts in by
    // declaring `grid.sizes` and writes no QML for it.
    //
    // Gated on the resolved lock, like the bundled widgets' own grips: a resize
    // changes the widget's geometry exactly as a drag does, so a widget the
    // user pinned - or the global "Lock widget positions" - must disarm both.
    // `visible` is what disarms it, not just what hides it: Qt routes no mouse
    // events into an invisible item (tests/test_widget_grip_lock.py).
    Rectangle {
        id: resizeHandle
        z: 2
        implicitWidth: 16
        implicitHeight: 16
        radius: Appearance.rounding.unsharpenslight
        color: Appearance.colors.colOnPrimaryContainer
        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: Appearance.spacing.space100
        }
        opacity: (rootWidget.containsMouse || resizeArea.containsMouse || rootWidget.resizingGrid)
            ? 0.5 : 0
        visible: opacity > 0 && rootWidget.gridResizable && !rootWidget.interactionLocked

        Behavior on opacity {
            NumberAnimation { duration: Appearance.animation.elementMoveFaster.duration }
        }

        Keys.onEscapePressed: event => {
            rootWidget.cancelGridResize();
            event.accepted = true;
        }

        MouseArea {
            id: resizeArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.SizeFDiagCursor
            // What claims the press from AbstractWidget's drag-to-move - which
            // is this widget's own root MouseArea - is the nesting: an area
            // inside another takes the press, and the root only sees what no
            // child accepted. `preventStealing` is not carrying that, and
            // removing it changes nothing measurable (the runtime harness
            // passes either way): a MouseArea steals a child's grab through its
            // `drag` target, and AbstractWidget deliberately has none, having
            // computed its drag by hand since d2ebb5aeb. It stays because the
            // bundled grips set it and because that is one binding away from
            // being untrue again.
            preventStealing: true

            // The pointer is tracked in scene coordinates against its position
            // at the press, because the grip is anchored to a widget that
            // resizes underneath it: a delta read from this moving item would
            // fold the resize back into the gesture.
            property real pressSceneX: 0
            property real pressSceneY: 0
            property real pressWidth: 0
            property real pressHeight: 0

            onPressed: mouse => {
                const scenePoint = resizeArea.mapToItem(null, mouse.x, mouse.y);
                resizeArea.pressSceneX = scenePoint.x;
                resizeArea.pressSceneY = scenePoint.y;
                resizeArea.pressWidth = rootWidget.width;
                resizeArea.pressHeight = rootWidget.height;
                rootWidget.beginGridResize();
                resizeHandle.forceActiveFocus();
            }
            onPositionChanged: mouse => {
                if (!rootWidget.resizingGrid) return;
                const scenePoint = resizeArea.mapToItem(null, mouse.x, mouse.y);
                rootWidget.previewGridResize(
                    resizeArea.pressWidth + scenePoint.x - resizeArea.pressSceneX,
                    resizeArea.pressHeight + scenePoint.y - resizeArea.pressSceneY);
            }
            // A release after Escape commits nothing: the cancel already
            // cleared the preview, and endGridResize has nothing to store.
            onReleased: rootWidget.endGridResize()
            onCanceled: rootWidget.cancelGridResize()
        }
    }

}
