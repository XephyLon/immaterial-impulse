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
    // The other half of the same question, now that the lock's widget CHOICE
    // can fork from the desktop's: a widget picked for the lock alone is built
    // on both surfaces - the host cannot instantiate it for one and not the
    // other - so the desktop needs a filter of its own, or it draws a widget
    // the desktop was never asked for. Defaults true, so a widget that states
    // nothing behaves exactly as it did.
    property bool visibleOnDesktop: true
    property var configEntry: Config.options.background.widgets[configEntryName]
    property string placementStrategy: configEntry.placementStrategy
    property real targetX: Math.max(0, Math.min(configEntry.x, scaledScreenWidth - width))
    property real targetY : Math.max(0, Math.min(configEntry.y, scaledScreenHeight - height))
    x: targetX
    y: targetY
    visible: opacity > 0
    // `editLockPreview` beside the real lock: Edit Mode's Lockscreen tab shows
    // the widgets the lock screen will show, through this same filter rather
    // than a second one that could disagree with it. One expression asks which
    // surface is on screen and then that surface's own filter, so neither
    // answer can leak into the other.
    opacity: (GlobalStates.lockLookActive ? visibleWhenLocked : visibleOnDesktop) ? 1 : 0
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
    //
    // Edit Mode subtracts the GLOBAL term and only that one. The per-widget pin
    // survives, which is the same invariant read the other way round: an editor
    // that unpinned everything would be unlocking exactly what the user pinned
    // on purpose. And it subtracts rather than writing `widgetsLocked = false`,
    // which would destroy a stored preference and leave the desktop unlocked
    // after the mode ended.
    property bool positionLocked: false
    property bool clickThrough: false
    readonly property bool interactionLocked: clickThrough || positionLocked
        || (Config.options.background.widgetsLocked && !GlobalStates.editMode)

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

    // The size the clamp measures this widget by. `width`/`height` for
    // everything that changes size in one frame - but a subclass whose size
    // *animates* overrides them with the size the animation is heading for,
    // because a clamp taken mid-flight is taken against a size the widget is
    // about to leave, and nothing runs again once the animation lands: the
    // widget settles past the screen edge and stays there (PluginWidget's span
    // resize). Two properties rather than an extra argument on the clamp - a
    // call site that forgets to pass one clamps against the wrong size in
    // silence, and this function exists so there is one clamp and not several.
    property real clampWidth: root.width
    property real clampHeight: root.height

    function clampX(v) { return Math.max(0, Math.min(v, scaledScreenWidth - clampWidth)); }
    function clampY(v) { return Math.max(0, Math.min(v, scaledScreenHeight - clampHeight)); }

    // A release a subclass answers ITSELF instead of committing a placement.
    // The one caller is Edit Mode's drop back into the drawer, which takes the
    // widget off the desktop rather than moving it - and a placement committed
    // on the way out would store the drawer's own coordinates as where the
    // user left the widget, so undoing the removal would bring it back under
    // the panel it was dropped on.
    //
    // Declared here because this is the one release handler in the tree, and
    // because a subclass cannot get in front of it: signal handlers declared at
    // two levels of one component both run, base first, so a `onReleased` on
    // PluginWidget would arrive after the commit it needs to prevent. Answered
    // false by everything that is not a plugin widget, which commits exactly as
    // before. The point is this item's own, and whoever answers maps it onward
    // (the same contract `contextMenuRequested` carries).
    function releaseRemovesWidget(mouseX, mouseY) { return false; }

    // A cancelled gesture swallows exactly its own release: see dragCancelled
    // in AbstractWidget for why the release still arrives at all.
    onReleased: (mouse) => {
        if (root.dragCancelled) {
            root.dragCancelled = false;
            return;
        }
        if (root.releaseRemovesWidget(mouse.x, mouse.y))
            return;
        root.commitPosition();
    }

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
