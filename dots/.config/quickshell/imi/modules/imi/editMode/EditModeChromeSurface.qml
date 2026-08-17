import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.plugins
import "../../common/functions/edit_mode.js" as EditMode
import "../../common/plugins/gridSizes.js" as GridSizes

/**
 * One screen's worth of Edit Mode's chrome: a full-screen layer surface that is
 * transparent everywhere except the toolbar and the tab bar on it.
 *
 * ---- why it is not on the background surface -------------------------------
 *
 * The desktop stays where it is (spec §2.3): it is where the wallpaper and the
 * `WidgetCanvas` already are, and moving it would cost the live-wallpaper frost
 * a `ShaderEffectSource` can only reach in its own scene graph. But that surface
 * is `quickshell:background` on `WlrLayer.Bottom`, and the bar and the dock stay
 * in place at full size, above it - measured on the live session, the three
 * layers come out as background / dock+bar / screenCorners+barPopup. Chrome
 * drawn on the background would be under the bar. So the chrome takes a surface
 * of its own on `Overlay`, and the viewport does not move.
 *
 * ---- the three things a surface this size has to get right ------------------
 *
 * **Input.** A screen-sized surface that accepts input everywhere makes the
 * desktop underneath unclickable - and the desktop underneath is the thing being
 * edited. The mask is the two chrome rects and nothing else, so every other
 * pixel falls through to the widgets. The surface also does not exist at all
 * while the mode is off (`EditModeChrome.qml`'s loader), which is the state
 * nobody looks at and therefore the dangerous one.
 *
 * **Blur.** `rules.lua`'s catch-all is `blur = true` with `ignore_alpha = 0.05`
 * for every `quickshell:*` namespace, under which a screen-sized surface of
 * transparent pixels asks the compositor to blur the entire screen. So the
 * namespace is minted AND listed there, at `ignore_alpha = 1`: the two toolbar
 * bodies are opaque (`m3surfaceContainer`), so they are the only thing blurred
 * and their shadows and the whole transparent remainder are left alone. That is
 * the same treatment `quickshell:recordingRegion` and `quickshell:overlay`
 * carry, for the same shape of surface. Reusing `quickshell:popup` was the other
 * temptation and `BarPopupOverlay.qml:53-69` records why not - its
 * `ignore_alpha = 1` is inherited by every xdg-popup opened from the surface,
 * which is how the tray menus stopped being blurred.
 *
 * **Keyboard.** `None`, deliberately. Escape is answered by `WidgetCanvas` on
 * the background surface, through `edit_mode.js`'s ladder; a chrome surface
 * taking `OnDemand` focus would sit in front of it and swallow the key.
 */
PanelWindow {
    id: root

    // A literal, and it has to stay one: a window colour bound to a
    // transparency-derived token latches the surface opaque the first time its
    // alpha crosses 255 and costs it its blur for the life of the process
    // (deba3e3f6).
    color: "transparent"
    WlrLayershell.namespace: "quickshell:editMode"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0

    // All four edges and no margins, so this window's coordinate space is the
    // screen's. On a layer surface position IS `margins`, so a toolbar animating
    // into place through them would reconfigure the surface every frame - the
    // create-map-destroy loop BarPopupOverlay exists to avoid. The chrome moves
    // inside the surface instead.
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // The same pure function, on the same inputs, that `Background.qml` builds
    // the desktop's transform out of. Re-derived rather than published across
    // the window boundary (which is what the clock depth layer's viewport has to
    // do) because every input is available on both sides: this surface is the
    // same screen, `GlobalStates.editProgress` is the one animated scalar, and
    // the drawer width, the margin and the toolbar's height are `Appearance`
    // tokens. There is no live state here that only the other window can see.
    //
    // The one input that is NOT re-derived is what the bar and the dock occupy:
    // that comes from `Config.options.bar.*` and `Config.options.dock.*` through
    // `dock_geometry.js`, and a second file working it out is a second answer to
    // where the dock is. `EditModeInsets` is that one answer.
    readonly property var insets: EditModeInsets.insetsFor(root.screen?.name ?? "")
    readonly property var viewport: EditMode.viewportGeometry({
        screenWidth: root.width,
        screenHeight: root.height,
        drawerWidth: Appearance.sizes.editModeDrawerWidth,
        margin: Appearance.sizes.editModeMargin,
        chromeThickness: Appearance.sizes.toolbarHeight,
        insetTop: root.insets.top,
        insetBottom: root.insets.bottom,
        insetLeft: root.insets.left,
        insetRight: root.insets.right
    })

    // The desktop's sideways travel while the drawer is open - the same term
    // Background.qml applies, from the same module, times the same scalar, so
    // the chrome keeps framing the desktop the drawer pushed aside.
    readonly property real editShift: EditMode.drawerTravel(root.viewport)
        * GlobalStates.editDrawerProgress

    mask: Region {
        item: chrome.toolbarItem
        Region {
            item: chrome.tabBarItem
        }
        // The drawer's REVEAL: a closed drawer is a zero-width item, so this
        // region is empty and the edge it lives on keeps its clicks - the
        // collapse rule every permanently-mapped surface here follows.
        Region {
            item: chrome.drawerItem
        }
    }

    // What the drop writes, and the only file in the mode that writes it. The
    // drawer reports gestures; the surface owns the geometry that turns a
    // release into a canvas point, and the two stores the catalogue may touch
    // - `plugins.enabled` (presence on the desktop, the same write Settings >
    // Widgets makes) and `PluginState`'s placement keys. That boundary is
    // spec §9's, and `lint_edit_mode_scope.py` polices it.
    function enabledWithout(id) {
        const next = [];
        for (let i = 0; i < Config.options.plugins.enabled.length; i++) {
            if (Config.options.plugins.enabled[i] !== id)
                next.push(Config.options.plugins.enabled[i]);
        }
        return next;
    }

    function enablePlugin(id) {
        if (Config.options.plugins.enabled.includes(id))
            return;
        const next = root.enabledWithout(id);
        next.push(id);
        Config.setNestedValue("plugins.enabled", next);
    }

    function togglePlugin(manifest) {
        if (Config.options.plugins.enabled.includes(manifest.id))
            Config.setNestedValue("plugins.enabled", root.enabledWithout(manifest.id));
        else
            root.enablePlugin(manifest.id);
    }

    // The span the widget will come up at, for centring the drop on the
    // pointer. Resolved the way the host resolves it - stored choice, then
    // manifest default - and null (the content-sized path) is a zero-size box,
    // which keeps the centring and the clamp exact for a widget whose pixel
    // size exists only once it instantiates.
    function spanSizeFor(manifest) {
        const span = GridSizes.resolveSize(manifest.grid,
            PluginState.option(manifest.id, "__gridSize", ""));
        if (!span)
            return { width: 0, height: 0 };
        return {
            width: Appearance.sizes.widgetGridSpanX(span.cols),
            height: Appearance.sizes.widgetGridSpanY(span.rows)
        };
    }

    function addWidgetAt(manifest, dropX, dropY) {
        // A release back over the drawer is the gesture being abandoned, not
        // an instruction to add the widget at the drawer.
        const reveal = chrome.drawer;
        if (dropX >= reveal.x && dropX <= reveal.x + reveal.width
                && dropY >= reveal.y && dropY <= reveal.y + reveal.height)
            return;
        const point = EditMode.canvasPointFromScreen(root.viewport,
            GlobalStates.editProgress, root.editShift, dropX, dropY);
        const span = root.spanSizeFor(manifest);
        const placed = EditMode.dropPosition({
            canvasX: point.x,
            canvasY: point.y,
            widgetWidth: span.width,
            widgetHeight: span.height,
            screenWidth: root.width,
            screenHeight: root.height
        });
        // The position is written BEFORE the enable: a newly enabled plugin
        // mounts at whatever the store holds, so writing it after would flash
        // the widget up at the default position and then move it (spec §8.3 -
        // an added widget is placed the moment it is added, and there is no
        // "unplaced" state to park it in).
        PluginState.setPosition(manifest.id, root.screen?.name ?? "",
            { x: placed.x, y: placed.y, placementStrategy: "free" });
        root.enablePlugin(manifest.id);
    }

    EditModeChromeContent {
        id: chrome
        anchors.fill: parent
        card: EditMode.cardRect(root.viewport, GlobalStates.editProgress,
            root.width, root.height, root.editShift)
        drawer: EditMode.drawerRect(root.viewport, GlobalStates.editProgress,
            GlobalStates.editDrawerProgress, root.width, root.height)
        // The part of the screen the bar and the dock have not taken, closing in
        // at the same rate the card shrinks out of it. The chrome is placed
        // between the two rectangles, so it clears both panels by construction
        // rather than by a literal measured against one of them.
        area: EditMode.areaRect(root.viewport, GlobalStates.editProgress,
            root.width, root.height)
        // The second of the mode's two stand-down gates, the other being the
        // loader that creates this window at all. Either alone hides the
        // chrome, which is exactly why both are named in
        // tests/test_edit_mode_contract.py: a frame comparison passes happily
        // on a tree with one of them deleted, and then the surviving one gets
        // deleted as redundant.
        opacity: GlobalStates.editProgress
        onDoneRequested: GlobalStates.editMode = false
        onDrawerToggleRequested: GlobalStates.editDrawerOpen = !GlobalStates.editDrawerOpen
        onWidgetDropRequested: (manifest, dropX, dropY) => root.addWidgetAt(manifest, dropX, dropY)
        onWidgetToggleRequested: (manifest) => root.togglePlugin(manifest)
    }
}
