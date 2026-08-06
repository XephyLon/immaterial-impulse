import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets.widgetCanvas

AbstractWidget {
    id: root

    required property string configEntryName
    required property int screenWidth
    required property int screenHeight
    required property int scaledScreenWidth
    required property int scaledScreenHeight
    required property real wallpaperScale
    property bool visibleWhenLocked: Config.options.lock.showWidgets
    property var configEntry: Config.options.background.widgets[configEntryName]
    property string placementStrategy: configEntry.placementStrategy
    property real targetX: Math.max(0, Math.min(configEntry.x, scaledScreenWidth - width))
    property real targetY : Math.max(0, Math.min(configEntry.y, scaledScreenHeight - height))
    x: targetX
    y: targetY
    visible: opacity > 0
    opacity: (GlobalStates.screenLocked && !visibleWhenLocked) ? 0 : 1
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    scale: (draggable && containsPress) ? 1.05 : 1
    Behavior on scale {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    // Per-widget interaction, layered over the one global toggle. Both default
    // off, so a widget that sets neither behaves exactly as it did before.
    //
    // `positionLocked` pins this widget alone. It ORs with the global switch
    // rather than overriding it: "Lock widget positions" must never *unlock*
    // something the user deliberately pinned, in either direction.
    //
    // `clickThrough` is the stronger of the two - the widget leaves pointer
    // routing altogether, so the click continues to whatever sits behind it
    // *within the same surface*: on the background that is the desktop's own
    // right-click area (Background.qml). This is deliberately not a Wayland
    // input region - the surface is shared by every desktop widget, and masking
    // it would blind all of them at once.
    //
    // Dragging is pointer input, so a click-through widget is necessarily
    // locked as well; the reverse does not hold, and a locked-but-clickable
    // widget (pinned media controls, say) stays a useful state.
    property bool positionLocked: false
    property bool clickThrough: false
    readonly property bool interactionLocked: clickThrough || positionLocked
        || Config.options.background.widgetsLocked

    // Two gates, because one property name means two different things here and
    // neither covers the other.
    //
    // This root is a `MouseArea` (AbstractWidget), and `MouseArea.enabled` is
    // MouseArea's own property shadowing `Item.enabled`: it stops *this* area
    // handling events - the drag, and the right-click that toggles the global
    // lock - and disables nothing underneath it. It is still needed: without
    // it a click-through widget would swallow the right-click meant for the
    // desktop menu and flip the global lock with it.
    //
    // A plain `Item` does cascade `enabled` to its whole subtree, and Qt skips
    // disabled items when routing pointer events. So everything a subclass
    // declares is parented into one, and that Item carries the same gate - the
    // half that was missing, which left any control a widget drew for itself
    // (a plugin's buttons, a text field) taking clicks with click-through on.
    //
    // The gate is `clickThrough`, not `interactionLocked`: pinning a widget
    // must not deaden its controls, which is the entire reason the lock and
    // click-through are two switches instead of one.
    //
    // `contentItem` fills this widget and takes no part in sizing it, so
    // geometry is unchanged - PluginWidget still derives its own width and
    // height from PluginNode's implicit size, and PluginNode's Loader stays
    // unanchored (anchoring it is a binding loop).
    default property alias contentData: contentItem.data

    Item {
        id: contentItem
        anchors.fill: parent
        enabled: !root.clickThrough
    }

    enabled: !clickThrough
    draggable: placementStrategy === "free" && !interactionLocked
    // Overridable: subclasses with conditional positioning (e.g. the clock's
    // forceCenter) re-bind x/y with their own expression after a drag ends.
    function restoreXYBinding() {
        root.x = Qt.binding(() => root.targetX);
        root.y = Qt.binding(() => root.targetY);
    }

    function clampX(v) { return Math.max(0, Math.min(v, scaledScreenWidth - width)); }
    function clampY(v) { return Math.max(0, Math.min(v, scaledScreenHeight - height)); }

    onReleased: root.commitPosition()

    // The one write-back path for a finished move. A real release runs it via
    // the handler above; a group drag runs it on every follower through
    // WidgetCanvas.widgetDragEnded, because a follower never gets a release
    // event of its own. Keeping both routes on one function is what stops the
    // released-drag path and the group path drifting apart (a clamp added to
    // one but not the other); PluginWidget overrides this same function for
    // its PluginState persistence.
    function commitPosition() {
        // Write configEntry FIRST, then rebind targetX/targetY THROUGH it (the
        // binding reads the fresh value, so the widget doesn't snap back to the
        // pre-drag position). Binding through configEntry means an external
        // config change - loading a preset, importing settings - moves the
        // widget with no extra plumbing (upstream's approach, superseding the
        // earlier explicit-pin + Connections version).
        //
        // configEntry is undefined for widgets whose configEntryName isn't a
        // pre-declared key under Config.options.background.widgets (e.g. plugin
        // widgets, whose dynamic per-plugin/per-monitor positions are persisted
        // by PluginState.qml instead) - those keep a plain pinned position.
        if (configEntry) {
            configEntry.x = root.x;
            configEntry.y = root.y;
            root.targetX = Qt.binding(() => root.clampX(configEntry.x));
            root.targetY = Qt.binding(() => root.clampY(configEntry.y));
        } else {
            root.targetX = root.x;
            root.targetY = root.y;
        }
        root.restoreXYBinding();
    }

    property bool needsColText: false
    property color dominantColor: Appearance.colors.colPrimary
    property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
    property color colText: {
        const onNormalBackground = (GlobalStates.screenLocked && Config.options.lock.blur.enable)
        const adaptiveColor = ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12))
        return onNormalBackground ? Appearance.colors.colOnLayer0 : adaptiveColor;
    }

    property bool wallpaperIsVideo: Config.options.background.wallpaperPath.endsWith(".mp4") || Config.options.background.wallpaperPath.endsWith(".webm") || Config.options.background.wallpaperPath.endsWith(".mkv") || Config.options.background.wallpaperPath.endsWith(".avi") || Config.options.background.wallpaperPath.endsWith(".mov")
    property string wallpaperPath: wallpaperIsVideo ? Config.options.background.thumbnailPath : Config.options.background.wallpaperPath
    
    onWallpaperPathChanged: refreshPlacementIfNeeded()
    onPlacementStrategyChanged: refreshPlacementIfNeeded()
    Connections {
        target: Config
        function onReadyChanged() { refreshPlacementIfNeeded() }
    }
    function refreshPlacementIfNeeded() {
        if (!Config.ready) return;
        if (root.placementStrategy === "free" && !root.needsColText) return;
        leastBusyRegionProc.wallpaperPath = root.wallpaperPath;
        leastBusyRegionProc.running = false;
        leastBusyRegionProc.running = true;
    }
    Process {
        id: leastBusyRegionProc
        property string wallpaperPath: root.wallpaperPath
        // TODO: make these less arbitrary
        property int contentWidth: 300
        property int contentHeight: 300
        property int horizontalPadding: 200
        property int verticalPadding: 200
        command: [Quickshell.shellPath("scripts/images/least-busy-region-venv.sh") // Comments to force the formatter to break lines
            , "--screen-width", Math.round(root.scaledScreenWidth) //
            , "--screen-height", Math.round(root.scaledScreenHeight) //
            , "--width", contentWidth //
            , "--height", contentHeight //
            , "--horizontal-padding", horizontalPadding //
            , "--vertical-padding", verticalPadding //
            , wallpaperPath //
            , ...(root.placementStrategy === "mostBusy" ? ["--busiest"] : [])
            // "--visual-output",
        ]
        stdout: StdioCollector {
            id: leastBusyRegionOutputCollector
            onStreamFinished: {
                const output = leastBusyRegionOutputCollector.text;
                // console.log("[Background] Least busy region output:", output)
                if (output.length === 0) return;
                const parsedContent = JSON.parse(output);
                root.dominantColor = parsedContent.dominant_color || Appearance.colors.colPrimary;
                if (root.placementStrategy === "free") return;
                root.targetX = parsedContent.center_x * root.wallpaperScale - root.width / 2;
                root.targetY  = parsedContent.center_y * root.wallpaperScale - root.height / 2;
            }
        }
    }
}
