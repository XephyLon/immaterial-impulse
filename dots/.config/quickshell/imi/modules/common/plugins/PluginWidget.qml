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
import "../functions/edit_mode.js" as EditMode
import "gridSizes.js" as GridSizes
import "resize-tension.js" as Tension
import "gridResize.js" as GridResize

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
    // stay visible while locked when `lock.showWidgets` - which exists to hide
    // the *other* desktop widgets - is off, and to centre itself there, which
    // is what `lock.centerClock` has always done.
    //
    // Which widgets the lock shows is two decisions now, and this is a BRANCH
    // rather than a disjunction because the second one has to be able to say
    // no. `lock.showWidgets` is the master gate over the feature ("does the
    // lock show desktop widgets at all"); with it off, a widget's own
    // `visibleWhenLocked` opt-in is the whole answer, exactly as before. With
    // it on, the per-widget choice is - inherited from the desktop's enabled
    // set until the user picks something on the Lockscreen tab
    // (layout_surfaces.js), so every widget shows, exactly as before, until
    // then. An `||` here would leave the clock's row in that picker unable to
    // do anything: the toggle would go off and the clock would stay on the
    // lock screen, which is a control that lies rather than a widget that is
    // protected. Nothing about the upgrade changes - the branch and the
    // disjunction agree on every state reachable before the first pick.
    visibleWhenLocked: Config.options.lock.showWidgets
        ? PluginState.lockWidgetEnabled(rootWidget.manifest?.id ?? "")
        : pluginNode.wantsVisibleWhenLocked
    // Am I on screen only because the LOCK asked for me? That is the one case
    // the desktop has to filter, and it is deliberately narrower than "not in
    // plugins.enabled": a widget being removed from BOTH is in neither list,
    // and hiding it from here would race the host loader's exit fade to zero
    // and cut the transition short.
    readonly property bool lockOnlyWidget: Config.options.lock.showWidgets
        && PluginState.lockWidgetEnabled(rootWidget.manifest?.id ?? "")
        && !Config.options.plugins.enabled.includes(rootWidget.manifest?.id ?? "")
    visibleOnDesktop: !rootWidget.lockOnlyWidget
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
    // Whether this widget travels with the desktop's parallax pan. Same
    // manifest-seeds-the-default shape as the four above, but the seed reads
    // `!== false` rather than `=== true`: following is the default, and a
    // manifest can only opt out of it.
    readonly property bool followParallax: manifest
        ? PluginState.option(manifest.id, "followParallax", manifest.desktopWidget?.followParallax !== false)
        : true
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
    // The grip is armed for EVERY grid-sized widget, not only the resizable
    // ones: with a single offered span the elastic walk finds no next size,
    // so the whole drag becomes the clamped rubber-band bow and the release
    // commits the span the widget already has (which pushes no undo entry).
    // The pull is part of how the desktop feels ("the elastic effect...
    // does not exist for Notes"), and a widget with one span deserves the
    // same give as its neighbours. The Size row and the edit stepper stay
    // gated on gridResizable - they act on a CHOICE, and one span is none.
    readonly property bool gripArmed: rootWidget.gridSized
    // Stored -> manifest default -> null, which is the content-sized path.
    readonly property var storedGridSize: GridSizes.resolveSize(rootWidget.gridSpec,
        manifest ? PluginState.gridSize(manifest.id, screenName) : undefined)
    // The span the grip's drag is currently previewing, null when no resize is
    // in flight. The widget resizes as the pointer moves, so the size on screen
    // is the size a release commits - and Escape cancels by clearing this, with
    // the widget falling straight back to its stored span.
    property var previewGridSize: null
    readonly property bool resizingGrid: previewGridSize !== null
    readonly property var gridSize: previewGridSize ?? storedGridSize
    readonly property bool gridSized: rootWidget.gridSize !== null && rootWidget.gridSize !== undefined
    readonly property int gridCols: gridSize ? gridSize.cols : 0
    readonly property int gridRows: gridSize ? gridSize.rows : 0
    readonly property real gridSpanWidth: gridSize ? Appearance.sizes.widgetGridSpanX(gridCols) : 0
    readonly property real gridSpanHeight: gridSize ? Appearance.sizes.widgetGridSpanY(gridRows) : 0

    // The span change is a spatial move, so it is drawn as one rather than
    // snapped. Two things make a Behavior the right mechanism here and the
    // wrong one on this widget's x/y (see `animatePosition` below): the target
    // is discrete - it moves when the resolved span moves and at no other time
    // - and Qt does not restart a running Behavior for a write of the value it
    // is already animating to. That matters because the grip re-previews on
    // every mouse move and hands `previewGridSize` a fresh object each time, so
    // the width binding re-evaluates per frame while the *value* it produces
    // changes only at a span boundary.
    //
    // Only while the size is a span: a content-sized widget's width follows its
    // content, which may well move every frame, and that is the shape a
    // Behavior freezes solid.
    //
    // ...and only once the store has answered. A widget whose stored span is
    // not its manifest default resolves it the moment plugin-state.json lands,
    // and animating that would have every resized widget on the desktop grow or
    // shrink on login for a size nobody just chose.
    readonly property bool gridResizeAnimated: rootWidget.gridSized && PluginState.ready
    readonly property int gridResizeDuration: GridResize.resizeDurationMs(
        rootWidget.resizingGrid,
        Appearance.animation.elementMoveSmall.duration,
        Appearance.animation.elementMove.duration)
    readonly property var gridResizeCurve: rootWidget.resizingGrid
        ? Appearance.animationCurves.expressiveFastSpatial
        : Appearance.animationCurves.expressiveDefaultSpatial

    // In flight whenever the drawn box differs from the span's settled box, or
    // while the grip is bowing it. Published so a widget can drop the work that
    // is not worth doing mid-motion - the shadow's blurred copy of its own
    // body, which otherwise re-renders into a reallocating FBO every frame of
    // every resize.
    readonly property bool boxInMotion: rootWidget.resizingGrid
        || Math.abs(rootWidget.width - rootWidget.settledWidth) > 0.5
        || Math.abs(rootWidget.height - rootWidget.settledHeight) > 0.5

    Behavior on width {
        enabled: rootWidget.gridResizeAnimated
        NumberAnimation {
            duration: rootWidget.gridResizeDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: rootWidget.gridResizeCurve
        }
    }
    Behavior on height {
        enabled: rootWidget.gridResizeAnimated
        NumberAnimation {
            duration: rootWidget.gridResizeDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: rootWidget.gridResizeCurve
        }
    }

    // The span the CONTENT is currently drawn as, which is not always the span
    // the widget IS.
    //
    // A manifest only offers several spans when it has a design per span
    // (docs/widget-grid.md): media loads a different layout file per span,
    // weather and currency switch branches inside one file. So the content has
    // to change identity somewhere during the move, and both ends are a pop -
    // hand the new name down at the start and the incoming layout is drawn
    // inside the outgoing box for the whole animation; hand it down at the end
    // and the outgoing one is. It changes at the midpoint instead, under a fade
    // out and back in, which is the one moment the swap is not visible.
    //
    // The host cannot know which of those two kinds of widget it is holding,
    // and it does not need to: a swap it did not have to make costs a fade
    // nobody can distinguish from the resize it sits inside.
    readonly property string targetGridSpan: GridSizes.formatSize(rootWidget.gridSize)
    property string shownGridSpan: ""

    onTargetGridSpanChanged: {
        // A widget that repositions its own elements gets the new span
        // immediately and no dissolve: the fade exists to hide a destroy, and
        // a one-tree widget has nothing to hide - its shared elements follow
        // the animating box instead (spec 2026-08-11, §5).
        if (pluginNode.wantsOwnSpanTransition) {
            spanSwap.stop();
            pluginNode.opacity = 1;
            rootWidget.shownGridSpan = rootWidget.targetGridSpan;
            return;
        }
        if (!rootWidget.gridResizeAnimated
                || !GridResize.animatesSpanSwap(rootWidget.shownGridSpan, rootWidget.targetGridSpan)) {
            spanSwap.stop();
            pluginNode.opacity = 1;
            rootWidget.shownGridSpan = rootWidget.targetGridSpan;
            return;
        }
        spanSwap.restart();
    }

    SequentialAnimation {
        id: spanSwap
        // The span the widget loads with is adopted rather than animated into,
        // and `onTargetGridSpanChanged` only ever sees changes. Declared on the
        // animation that owns every later value of `shownGridSpan` rather than
        // in the host's own `Component.onCompleted`, which stays the single
        // call `tests/test_presets.py` pins.
        Component.onCompleted: rootWidget.shownGridSpan = rootWidget.targetGridSpan
        NumberAnimation {
            target: pluginNode
            property: "opacity"
            to: 0
            duration: GridResize.contentSwapHalfMs(rootWidget.gridResizeDuration)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
        }
        ScriptAction { script: rootWidget.shownGridSpan = rootWidget.targetGridSpan }
        NumberAnimation {
            target: pluginNode
            property: "opacity"
            to: 1
            duration: GridResize.contentSwapHalfMs(rootWidget.gridResizeDuration)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
        }
    }

    // The size the widget is resizing *to*. Everything that has to agree with
    // where the widget ends up - the position clamp, and the grip's own press
    // measurement - reads this rather than `width`, which is a frame of an
    // animation for half a second after every span change.
    readonly property real settledWidth: rootWidget.gridSized ? rootWidget.gridSpanWidth : rootWidget.width
    readonly property real settledHeight: rootWidget.gridSized ? rootWidget.gridSpanHeight : rootWidget.height
    clampWidth: rootWidget.settledWidth
    clampHeight: rootWidget.settledHeight

    function commitGridSize(size) {
        if (!manifest || !size) return;
        // A span commit is one of spec §7.3's five committed mutations. The
        // undo closure captures plain data and the PluginState singleton,
        // never `rootWidget` - the stack outlives any widget the mode can
        // destroy - and an unchanged span pushes nothing, so a commit of the
        // span the widget already has does not spend an entry.
        const id = manifest.id;
        const screen = rootWidget.screenName;
        // The surface, captured now - see commitPosition for why the closure
        // must not resolve it at pop time.
        const surface = PluginState.currentSurface;
        const next = GridSizes.formatSize(size);
        const before = PluginState.gridSize(id, screen, surface) ?? null;
        if (before !== next)
            GlobalStates.editUndoPush(EditMode.swap(
                () => PluginState.gridSize(id, screen, surface) ?? null,
                (value) => PluginState.setGridSize(id, screen, value, surface),
                before));
        PluginState.setGridSize(id, screen, next, surface);
    }

    function beginGridResize() {
        rootWidget.previewGridSize = rootWidget.storedGridSize;
    }

    // ---- elastic resize (spec 3d) ---------------------------------------
    //
    // The grip no longer picks the nearest span - it accumulates PULL. The
    // widget holds its span while tension builds; each whole breakaway steps
    // one span in the pulled direction and the remainder carries, so a long
    // drag walks several spans in one gesture. At a wall (no offered span
    // further out) the leftover pull is held, clamped to one breakaway, so
    // the bow rubber-bands against the limit instead of winding up unbounded.
    //
    // `resizeBow` is what the widget's cards render: the edge distortion in
    // pixels, derived from the *unconsumed* pull. Zero the instant the drag
    // ends - the settle back to the committed span is the box animation's job.
    property real resizePullX: 0
    property real resizePullY: 0
    readonly property point resizeBow: Qt.point(
        rootWidget.resizingGrid ? Tension.bow(rootWidget.resizePullX) : 0,
        rootWidget.resizingGrid ? Tension.bow(rootWidget.resizePullY) : 0)

    // The gesture is ABSOLUTE: the size follows where the cursor IS.
    //
    // Two relative-pull models shipped before this and both failed the same
    // review: accumulated pull works anywhere, so the cursor could sit at
    // the monitor's edge and a 60px twitch there still resized the widget.
    // What the hand expects is positional - the widget's edge chases the
    // cursor, gives happen where the widget is, and far away there is no
    // boundary left to cross, so movement out there does nothing.
    //
    // Growing: the cursor pulls past the CURRENT edge by the breakaway.
    // Shrinking: the cursor comes back INSIDE the smaller span's edge - into
    // the widget's own space. The two conditions are disjoint (grow needs
    // target > edge + BREAK, shrink needs target <= the smaller edge), so
    // the walk cannot oscillate within one event. (resizePullX/Y and
    // resizeBow are declared with the elastic block above.)
    function previewGridResize(targetWidth, targetHeight) {
        if (!rootWidget.resizingGrid) return;
        let current = rootWidget.previewGridSize;
        for (;;) {
            const edge = Appearance.sizes.widgetGridSpanX(current.cols);
            if (targetWidth > edge + Tension.BREAK_PX) {
                const up = Tension.stepSize(rootWidget.offeredGridSizes, current, 1, 0);
                if (up === current) break;
                current = up;
                continue;
            }
            const down = Tension.stepSize(rootWidget.offeredGridSizes, current, -1, 0);
            // STRICTLY inside: at exactly the smaller edge the size stays. An
            // x-only grow can raise the row count (2x1 -> 3x2 is diagonal in
            // span space), leaving the untouched y target sitting exactly ON
            // the old row edge - with <=, the y loop immediately stepped the
            // rows back down and the whole grow netted to nothing.
            if (down !== current
                    && targetWidth < Appearance.sizes.widgetGridSpanX(down.cols)) {
                current = down;
                continue;
            }
            break;
        }
        for (;;) {
            const edge = Appearance.sizes.widgetGridSpanY(current.rows);
            if (targetHeight > edge + Tension.BREAK_PX) {
                const up = Tension.stepSize(rootWidget.offeredGridSizes, current, 0, 1);
                if (up === current) break;
                current = up;
                continue;
            }
            const down = Tension.stepSize(rootWidget.offeredGridSizes, current, 0, -1);
            if (down !== current
                    && targetHeight < Appearance.sizes.widgetGridSpanY(down.rows)) {
                current = down;
                continue;
            }
            break;
        }
        rootWidget.previewGridSize = current;
        // The bow is the live tension toward the next boundary, clamped to
        // one breakaway - at a wall the cursor may be far out, and the bow
        // holds at full rather than winding up.
        rootWidget.resizePullX = Math.max(-Tension.BREAK_PX, Math.min(Tension.BREAK_PX,
            targetWidth - Appearance.sizes.widgetGridSpanX(current.cols)));
        rootWidget.resizePullY = Math.max(-Tension.BREAK_PX, Math.min(Tension.BREAK_PX,
            targetHeight - Appearance.sizes.widgetGridSpanY(current.rows)));
    }

    function endGridResize() {
        const chosen = rootWidget.previewGridSize;
        rootWidget.previewGridSize = null;
        rootWidget.resizePullX = 0;
        rootWidget.resizePullY = 0;
        rootWidget.commitGridSize(chosen);
    }

    function cancelGridResize() {
        rootWidget.previewGridSize = null;
        rootWidget.resizePullX = 0;
        rootWidget.resizePullY = 0;
    }

    // The mode's right-click (AbstractWidget raises it only while the canvas
    // is editing). The point is mapped to the SCENE - which on the full-screen
    // background surface is the screen - through Qt's own transform chain, so
    // the mode's scale, the drawer's shift and the press scale are all
    // composed by the same arithmetic that draws the widget. Multiplying a
    // viewport scale in by hand here is the compensation the contract forbids,
    // and it would be wrong at every scale but 1.
    onContextMenuRequested: (atX, atY) => {
        if (!manifest) return;
        const point = rootWidget.mapToItem(null, atX, atY);
        GlobalStates.editWidgetMenuPluginId = manifest.id;
        GlobalStates.editWidgetMenuScreenName = rootWidget.screenName;
        GlobalStates.editWidgetMenuX = point.x;
        GlobalStates.editWidgetMenuY = point.y;
        GlobalStates.editWidgetMenuOpen = true;
    }

    // ---- dragging a widget back into the drawer (the inverse of §8.3) -----
    //
    // The drawer's rows drag OUT onto the desktop; a widget on the desktop
    // dragged back over the drawer and let go there leaves the desktop. The
    // rectangle is the chrome surface's own, published per screen because it
    // lives in another window (GlobalStates.editDrawerReveals), and the
    // pointer is mapped to the SCENE through Qt's transform chain for the same
    // reason the right-click above is: the mode's scale and the drawer's shift
    // are already in it, and multiplying a viewport scale in by hand is the
    // compensation the contract forbids.
    readonly property var editDrawerReveal:
        GlobalStates.editDrawerReveals[rootWidget.screenName] ?? null

    // Takes SCREEN coordinates, because its two callers reach them differently
    // and only one of them may map through this item - see the drag handler
    // below.
    function dropWouldRemoveAt(screenX, screenY) {
        if (!GlobalStates.editMode || !GlobalStates.editDrawerOpen || !manifest)
            return false;
        // The hint and the write ask the ONE question, membership included.
        // `EditModeDrawerDrop` declines an id the desktop does not hold, and a
        // widget can be on screen and draggable without being in that list -
        // `lockOnlyWidget` above is exactly one, drawn on the Lockscreen tab
        // and still a live MouseArea at opacity 0 on the Desktop tab. Without
        // this term the drawer lit up, the release swallowed the commit on the
        // strength of it, and the drop was then declined: one gesture under a
        // panel promising a removal, and nothing happening anywhere.
        if (!Config.options.plugins.enabled.includes(manifest.id))
            return false;
        return EditMode.pointInDrawerReveal(rootWidget.editDrawerReveal,
            screenX, screenY);
    }

    // The drawer lights up while the release would remove rather than move -
    // the widget itself cannot say so, because it is drawn on the surface
    // BELOW the chrome and passes under the panel it is being carried into.
    //
    // The pointer comes from `dragPointerParentX/Y` rather than from this
    // event's own `mouse.x/y`: a base class's handlers run first, so
    // AbstractWidget has already moved the item those coordinates are relative
    // to, and mapping them out again overshoots the pointer by that event's
    // delta. Measured - with `mouse.x/y` the hint never lit up on a drag that
    // ends on the drawer, while the release, whose handler moves nothing, was
    // exact.
    onPositionChanged: {
        if (!rootWidget.dragging) return;
        const point = rootWidget.parent.mapToItem(null,
            rootWidget.dragPointerParentX, rootWidget.dragPointerParentY);
        GlobalStates.editDrawerDropScreen =
            rootWidget.dropWouldRemoveAt(point.x, point.y)
                ? rootWidget.screenName : "";
    }

    // Runs BEFORE AbstractBackgroundWidget's commit, which is why the decision
    // is a function that handler asks rather than a release handler of its own.
    // Nothing about the position is written: the store still holds where the
    // widget was, and that is exactly what makes undoing the removal put it
    // back there rather than at the drawer or at a default - the same
    // arrangement the menu's Remove already relies on.
    //
    // This one DOES map through the item, and correctly: nothing moves the
    // widget on a release (the drag Binding stands down with RestoreNone), so
    // the event's own coordinates are the pointer's. It needs no "was this a
    // drag" term either - the chrome surface's input mask covers the reveal, so
    // a press can never land there, and the only way a release reaches it is a
    // gesture that began somewhere else and kept the implicit grab.
    function releaseRemovesWidget(mouseX, mouseY) {
        const point = rootWidget.mapToItem(null, mouseX, mouseY);
        if (!rootWidget.dropWouldRemoveAt(point.x, point.y)) return false;
        rootWidget.restoreXYBinding();
        GlobalStates.editWidgetDroppedOnDrawer(manifest.id);
        return true;
    }

    // The hint is cleared by the END OF THE GESTURE rather than by a release
    // handler of its own, which covers the release, the cancel and Edit Mode
    // ending mid-drag in one place - and keeps this file free of the second
    // `onReleased` test_widget_group_selection.py refuses, because a widget
    // with two release paths is how the write-back came to have two copies.
    // It runs BEFORE the base's commit branch (a base class's handlers run
    // first), and the removal re-asks the pointer rather than reading this, so
    // the order costs nothing.
    onDraggingChanged: {
        if (!rootWidget.dragging)
            GlobalStates.editDrawerDropScreen = "";
    }

    // A widget destroyed while its menu is open must not strand the menu - the
    // BarContent.filterLayout shape: disabling a plugin (the menu's own Remove
    // included) tears this instance down while the menu still points at it, so
    // the declaring object vacates on its way out. Keyed on the screen as well
    // as the id, because every monitor holds an instance of this plugin and
    // only the one the menu was opened on may close it.
    Component.onDestruction: {
        if (manifest && GlobalStates.editWidgetMenuOpen
                && GlobalStates.editWidgetMenuPluginId === manifest.id
                && GlobalStates.editWidgetMenuScreenName === rootWidget.screenName)
            GlobalStates.editWidgetMenuOpen = false;
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
    //
    // The clamp is AbstractBackgroundWidget's own, rather than the same
    // expression written again: the placement frame is the one both ends of
    // this agree on (ParallaxMath), so the range is the same range for every
    // widget and there is no reason for two copies of it to exist.
    function applyPersistedPosition() {
        const nextX = currentConfig.x !== undefined ? currentConfig.x : 100;
        const nextY = currentConfig.y !== undefined ? currentConfig.y : 100;
        rootWidget.targetX = rootWidget.clampX(nextX);
        rootWidget.targetY = rootWidget.clampY(nextY);
    }

    onCurrentConfigChanged: applyPersistedPosition()
    Component.onCompleted: applyPersistedPosition()

    // A widget resized near a screen edge no longer fits where it is stored,
    // and the two halves of that go wrong in different directions. Where the
    // widget is *drawn* is already handled: committing a span writes plugin
    // state, which re-evaluates `currentConfig` and re-runs the clamp above -
    // now against the span being animated to rather than the frame's width, so
    // the widget slides in while it grows instead of settling outside the
    // screen. The *store* keeps the old number, which is 705e9006d's
    // disagreement reached from the other side, so the same repair the settle
    // timer runs is run again here.
    //
    // Keyed on the span as a string, not on `storedGridSize`: that binding
    // hands out a fresh object on every plugin-state write, so a widget being
    // dragged somewhere else on the desktop would re-run every other widget's
    // repair. Both the grip and the Size row land here, because both write the
    // same stored span.
    //
    // Deferred by one turn of the event loop, because the repair *writes*
    // plugin state and this handler runs inside the evaluation of a binding
    // that reads it - Qt reports that as a binding loop on `storedGridSize`
    // and drops the re-evaluation. Nothing is lost by the delay: what the
    // widget is drawn at is already clamped by the line above.
    readonly property string storedGridSpan: GridSizes.formatSize(rootWidget.storedGridSize)
    onStoredGridSpanChanged: storedSpanRepair.restart()

    Timer {
        id: storedSpanRepair
        interval: 0
        onTriggered: rootWidget.repairUnreachableStoredPosition()
    }

    // A stored position the screen will never honour, written back so it stops
    // being a lie.
    //
    // The drag is unclamped - deliberately, it is the release that decides -
    // but until now only the *load* clamped, so a drag that ended outside the
    // screen stored a number the widget was then drawn nowhere near. It is
    // silent, permanent, and it reads exactly as the widget moving on its own:
    // the author's `visualizer` sat at `x: -852` on a 5120px screen and was
    // drawn at 0 every session.
    //
    // Note what this is not. The corrupt values that motivated it cannot be
    // *repaired* - the offset each one absorbed depends on which workspace was
    // showing and whether a sidebar was open at that instant, and it accrued
    // over an unknown number of releases, so there is no arithmetic that
    // recovers the intended position. Nor are they reset to the default, which
    // would move a widget to somewhere the user never put it. They are pinned
    // to what is already on screen, which is the one answer that changes
    // nothing visible.
    //
    // It runs once, on a settle timer, and only where the clamp actually bites
    // - a write-back on every load is the ConfigSpinBox trap in AGENT.md, and
    // the guard against it here is that `width` has to have arrived first.
    function repairUnreachableStoredPosition() {
        if (!manifest || !PluginState.ready) return;
        // The settle timer below waits for a real size before calling; the
        // resize path calls straight from a span change, where a screen that
        // has not arrived yet would clamp every widget to 0,0 and store it.
        if (rootWidget.settledWidth <= 0 || rootWidget.scaledScreenWidth <= 0) return;
        const stored = rootWidget.currentConfig;
        const nextX = rootWidget.clampX(stored.x);
        const nextY = rootWidget.clampY(stored.y);
        if (nextX === stored.x && nextY === stored.y) return;
        PluginState.setPosition(manifest.id, screenName, {
            x: nextX,
            y: nextY,
            placementStrategy: rootWidget.placementStrategy
        });
    }

    Timer {
        id: storedPositionRepair
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            if (!PluginState.ready || rootWidget.width <= 0 || rootWidget.height <= 0)
                return;
            storedPositionRepair.running = false;
            rootWidget.repairUnreachableStoredPosition();
        }
    }

    // `forceCenter` overrides the persisted position for as long as it is set,
    // without disturbing it - the widget returns to where the user left it the
    // moment the condition clears.
    readonly property real placedX: rootWidget.forceCenter
        ? ((scaledScreenWidth - width) / 2) : targetX
    readonly property real placedY: rootWidget.forceCenter
        ? ((scaledScreenHeight - height) / 2) : targetY

    // The widget canvas is a sibling of the wallpaper viewport and its x/y ARE
    // the widget parallax (Background.qml), so every widget on it travels
    // whether or not it wants to. Opting out is therefore a cancellation, not
    // a smaller offset - see ParallaxMath.parallaxCancel. Found by walking the
    // parent chain rather than passed down, the same way AbstractWidget already
    // reaches its canvas for drag bookkeeping.
    readonly property Item parallaxCanvas: rootWidget.findCanvas(rootWidget.parent)
    readonly property real parallaxCancelX: ParallaxMath.parallaxCancel(
        rootWidget.parallaxCanvas ? rootWidget.parallaxCanvas.x : 0, rootWidget.followParallax)
    readonly property real parallaxCancelY: ParallaxMath.parallaxCancel(
        rootWidget.parallaxCanvas ? rootWidget.parallaxCanvas.y : 0, rootWidget.followParallax)

    // The cancellation is not a move, and it must not go through the position
    // Behaviors: the canvas pans over 600ms, so an opted-out widget's x/y
    // binding re-evaluates on every frame of it, and a Behavior whose target
    // moves every frame restarts every frame and never ticks. Measured, not
    // reasoned about - with the Behaviors on, x sat at its pre-pan value for
    // the whole 600ms while the canvas travelled under it, so the widget moved
    // the *full* pan on screen and only slid back afterwards. The animation is
    // what an opted-out widget gives up for holding still; the drag is
    // unaffected, since the Behaviors are already off while dragging.
    animatePosition: rootWidget.followParallax

    // The 12px lattice is what makes widgets line up with each other, and they
    // line up at rest - so it belongs to the placement frame, not to the drawn
    // one. Snapping the drawn coordinate leaves an opted-out widget's stored
    // position off the lattice by whatever fraction the pan happened to be
    // holding, which is what put `x: 95.04000000000033` in a real
    // plugin-state.json.
    snapOffsetX: rootWidget.parallaxCancelX
    snapOffsetY: rootWidget.parallaxCancelY

    // Dragging assigns x/y directly and so breaks these bindings;
    // AbstractBackgroundWidget calls restoreXYBinding() on release for exactly
    // this case, so the override has to be restored there too or a single drag
    // disables centring for the rest of the session.
    x: ParallaxMath.drawnFromPlacement(rootWidget.placedX, rootWidget.parallaxCancelX)
    y: ParallaxMath.drawnFromPlacement(rootWidget.placedY, rootWidget.parallaxCancelY)

    function restoreXYBinding() {
        rootWidget.x = Qt.binding(() => ParallaxMath.drawnFromPlacement(
            rootWidget.placedX, rootWidget.parallaxCancelX));
        rootWidget.y = Qt.binding(() => ParallaxMath.drawnFromPlacement(
            rootWidget.placedY, rootWidget.parallaxCancelY));
    }

    // Overrides AbstractBackgroundWidget's release path, which calls this on a
    // real release - and which WidgetCanvas calls on every group-drag follower,
    // since a follower never gets a release event. One function on purpose:
    // restoreXYBinding() keeps forceCenter and external position changes alive
    // after the drag broke the x/y bindings, and setPosition is what makes the
    // move survive a restart.
    function commitPosition() {
        // The cancellation is taken back out: `x` is where the widget is drawn
        // on the canvas, the persisted position is where it was PLACED (see
        // ParallaxMath). Storing the drawn coordinate would fold the current
        // pan into the saved position, so an opted-out widget would walk by one
        // pan's worth every time it was dragged. It is clamped here as well as
        // on the way back in, so the store can never hold a position the
        // widget is not drawn at.
        const beforeX = rootWidget.targetX;
        const beforeY = rootWidget.targetY;
        rootWidget.targetX = rootWidget.clampX(ParallaxMath.placementFromDrawn(
            rootWidget.x, rootWidget.parallaxCancelX));
        rootWidget.targetY = rootWidget.clampY(ParallaxMath.placementFromDrawn(
            rootWidget.y, rootWidget.parallaxCancelY));
        rootWidget.restoreXYBinding();
        rootWidget.commitPlacement(beforeX, beforeY);
    }

    // The store write, from targetX/targetY rather than from the drawn
    // coordinate. Split out because a nudge has no drawn coordinate to read:
    // `x` carries a position Behavior, so a keyboard step that assigned to it
    // and committed in the same turn read the value the animation had not left
    // yet, wrote it back as the target, and the widget snapped home - a move
    // that looked like the keys doing nothing at all.
    function commitPlacement(beforeX, beforeY) {
        if (!manifest) return;
        // A drag's release is a committed mutation (spec §7.3), and this is
        // its one commit path - the leader's release and every group-drag
        // follower both land here. The closure captures plain values and the
        // PluginState singleton only; a commit that moved nothing (every
        // click on a draggable widget releases through here) pushes nothing,
        // or the stack would fill with entries that undo to where the widget
        // already is. A group drag therefore records one entry per member -
        // one entry per committed mutation is the spec's grain.
        const id = manifest.id;
        const screen = rootWidget.screenName;
        // The surface this drag happened on, captured NOW: the undo closure
        // runs later, from whichever tab the user is on then, and a closure
        // that resolved the surface at pop time would write a lock position
        // into the desktop store (or the reverse).
        const surface = PluginState.currentSurface;
        if (beforeX !== rootWidget.targetX || beforeY !== rootWidget.targetY) {
            const before = {
                x: beforeX,
                y: beforeY,
                placementStrategy: rootWidget.placementStrategy
            };
            GlobalStates.editUndoPush(EditMode.swap(
                () => PluginState.position(id, screen, surface),
                (value) => PluginState.setPosition(id, screen, value, surface),
                before));
        }
        PluginState.setPosition(id, screenName, {
            x: rootWidget.targetX,
            y: rootWidget.targetY,
            placementStrategy: rootWidget.placementStrategy
        }, surface);
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
    // Two states stand the per-widget frost down, and naming the condition
    // rather than either cause is what let the second one join without a second
    // gate.
    //
    // The lock, while it blurs the wallpaper (Background.qml's blurLoader shows
    // a blurred + zoomed wallpaper): the widget's translucent panel then shows
    // that lock background through it, so the frost stays consistent with the
    // lock screen. If the lock does NOT blur, keep blurring per widget so a
    // blur-enabled widget stays frosted against the sharp wallpaper.
    //
    // Edit Mode, unconditionally: the whole desktop is drawn under a scale
    // transform there, and a frost is a ShaderEffectSource sampling the
    // wallpaper at a rect computed from three frames that the transform does
    // not move together. Measured on a live desktop with a Wallpaper Engine
    // scene, cards that are visibly frosted at rest render as flat tinted
    // panels under the transform - so this is not a frost the mode is choosing
    // to give up, it is one it would only appear to have.
    readonly property bool frostSuspended: (GlobalStates.screenLocked
            && Config.options.lock.blur.enable)
        || GlobalStates.editMode
    Repeater {
        model: rootWidget.frostBlur && rootWidget.blurEnabled && !rootWidget.frostSuspended
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
            // A region may carry its own mask item (a non-rounded-rect card's
            // outline); absent, the surface builds its radius Rectangle.
            maskItem: modelData.mask ?? null
            wallpaperWidth: rootWidget.wallpaperRect.width
            wallpaperHeight: rootWidget.wallpaperRect.height
            surfaceX: rootWidget.frostSampleOrigin.x + x
            surfaceY: rootWidget.frostSampleOrigin.y + y
        }
    }

    // The layer lives on this wrapper rather than on the node so its texture
    // is a ring larger than the widget: a layer clips at its item's bounds,
    // and the resize bow deliberately draws up to 2*BOW_PX outside the card -
    // on the node's own layer the bulge came back with its edge sliced flat.
    // The node keeps its exact geometry (centred both ways cancels out), so
    // every coordinate that references it - blur regions included - is
    // untouched.
    Item {
        id: nodeLayerFrame
        z: 1
        anchors.centerIn: parent
        width: pluginNode.width + Tension.BOW_PX * 4
        height: pluginNode.height + Tension.BOW_PX * 4
        // Render package widgets on a bounded texture above the blur backdrop.
        // This avoids the background layer swallowing package content on some
        // Wayland scene-graph paths while keeping the texture widget-sized.
        layer.enabled: pluginNode.width > 0 && pluginNode.height > 0
        layer.smooth: true

    PluginNode {
        id: pluginNode
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
        //
        // The host's animating size rather than the span it is heading for, so
        // the content is the box on every frame of a resize: handed the target
        // instead, it would paint outside the widget while the box grows into
        // it and leave a gap inside it while the box shrinks. This is not the
        // circular sizing PluginNode's Loader comment warns about - the branch
        // that reads this widget's `width` is the one where `width` comes from
        // the span and not from the node.
        gridWidth: rootWidget.gridSized ? rootWidget.width : 0
        gridHeight: rootWidget.gridSized ? rootWidget.height : 0
        // ...and hand the span down by name too, for a widget that has a
        // different layout per size rather than one that stretches. The span
        // the content is *showing*, which lags the widget's own by half a
        // resize - see shownGridSpan.
        gridSize: rootWidget.shownGridSpan
        resizeBow: rootWidget.resizeBow
        hostDragging: rootWidget.dragging
        hostBoxInMotion: rootWidget.boxInMotion
        anchors.centerIn: parent
    }
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
        // Hover-revealed normally; up for the whole of Edit Mode, which is the
        // mode's point - a widget whose only sign that it can be resized is a
        // corner that appears when the pointer is already on it is not a
        // discoverable one.
        opacity: (GlobalStates.editMode || rootWidget.containsMouse
                || resizeArea.containsMouse || rootWidget.resizingGrid)
            ? 0.5 : 0
        visible: opacity > 0 && rootWidget.gripArmed && !rootWidget.interactionLocked

        // The whole tier, not just its duration. Taking the number and leaving
        // the curve hands the animation Qt's default, which is Easing.Linear -
        // a generic curve, which docs/M3_GUIDELINES.md §2 forbids outright - so
        // every grip in this shell has faded linearly beside neighbours easing
        // on expressiveEffects. Entering Edit Mode reveals every resizable
        // widget's grip at once, which is where one linear fade stops being one
        // control's private detail.
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFaster.numberAnimation.createObject(this)
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

            // The pointer is tracked in the widget's PARENT frame against its
            // position at the press. Two things decide that frame. It must not
            // be this item or the widget, which resize underneath the gesture -
            // a delta read from a moving item folds the resize back into it.
            // And it must not be the scene either, once Edit Mode draws the
            // canvas under a scale transform: a scene delta is in screen
            // pixels, so the same gesture would resize by 1/scale as much as
            // the pointer travelled over the widget. The parent is static in
            // both senses, and it is the frame AbstractWidget's drag already
            // computes in.
            property real pressFrameX: 0
            property real pressFrameY: 0
            property real pressWidth: 0
            property real pressHeight: 0

            onPressed: mouse => {
                const pressPoint = resizeArea.mapToItem(rootWidget.parent, mouse.x, mouse.y);
                resizeArea.pressFrameX = pressPoint.x;
                resizeArea.pressFrameY = pressPoint.y;
                // The span being animated to, not the frame's width: pressing
                // the grip again while the last resize is still travelling
                // would otherwise measure the gesture from a size the widget
                // is in the middle of leaving, and every span the drag
                // previewed would be off by whatever the animation had left.
                resizeArea.pressWidth = rootWidget.settledWidth;
                resizeArea.pressHeight = rootWidget.settledHeight;
                rootWidget.beginGridResize();
                resizeHandle.forceActiveFocus();
            }
            onPositionChanged: mouse => {
                if (!rootWidget.resizingGrid) return;
                const point = resizeArea.mapToItem(rootWidget.parent, mouse.x, mouse.y);
                rootWidget.previewGridResize(
                    resizeArea.pressWidth + point.x - resizeArea.pressFrameX,
                    resizeArea.pressHeight + point.y - resizeArea.pressFrameY);
            }
            // A release after Escape commits nothing: the cancel already
            // cleared the preview, and endGridResize has nothing to store.
            //
            // The focus the press took for Escape is handed back at the end of
            // the gesture. Qt would drop it anyway once the grip fades out and
            // goes invisible, but until then `keyboardFocusRequested` reads a
            // decorative corner as an editing widget and keeps the whole
            // background surface asking the compositor for keyboard focus.
            onReleased: {
                rootWidget.endGridResize();
                resizeHandle.focus = false;
            }
            onCanceled: {
                rootWidget.cancelGridResize();
                resizeHandle.focus = false;
            }
        }
    }

}
