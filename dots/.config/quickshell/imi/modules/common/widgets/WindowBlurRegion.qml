import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * Publishes an ext-background-effect blur region for a panel window, so the
 * compositor blurs only `regionItem`'s rect (the opaque panel body) instead of
 * the whole layer surface. A panel that draws its drop shadow in the surface's
 * margin can then keep that shadow crisp: it sits outside the region, so the
 * compositor's blur never touches it (#82). Requires the compositor to
 * implement ext_background_effect_manager_v1 (Hyprland ≥ 0.51); on others
 * setting the region is a harmless no-op, matching the unblurred fallback.
 *
 * Quickshell's BackgroundEffect re-applies the region across surface
 * creation/map internally, but a region committed while the surface is mid
 * (re)configure can still be dropped compositor-side; the settle timer
 * re-publishes shortly after map/resize to cover that race (the same
 * "kick after geometry settles" DankMaterialShell's WindowBlur does).
 */
Item {
    id: root
    visible: false

    required property var targetWindow
    property Item regionItem
    property int regionRadius: 0

    // The published region. Defaults to regionItem's rect; a caller whose body
    // is not a single rect (the bar's background + center pill, say) can
    // replace it with a composed Region whose children Combine into a union.
    property Region region: Region {
        item: root.regionItem
        radius: root.regionRadius
    }

    // A body whose rects are not known until runtime: the notification stack
    // paints one card per app and they come and go. A declared Region cannot
    // express that - `regions` is a default list filled at construction, and
    // Repeater only produces Items - so build the children here and assign the
    // list, which Quickshell's Region does accept.
    //
    // Callers use either this or regionItem/region, not both.
    property var regionItems: []
    property int regionItemsRadius: 0

    Component {
        id: subRegionComponent
        Region {}
    }

    property var subRegions: []

    function rebuildFromItems() {
        // regionItems defaults to [], so this handler fires once at
        // construction for EVERY instance, including the great majority that
        // use regionItem and never touch the dynamic path. Assigning an empty
        // list to their region's children wipes the declared region and the
        // panel loses its blur entirely - which is what happened to the bar,
        // the overview and the sidebars. Leave the declared region alone
        // unless this instance is actually using regionItems.
        if (root.subRegions.length === 0 && (root.regionItems?.length ?? 0) === 0)
            return;

        // Nothing else owns these, so they have to be torn down explicitly or
        // every card that ever appeared leaks a Region.
        for (const stale of root.subRegions)
            if (stale)
                stale.destroy();

        let built = [];
        for (const item of (root.regionItems ?? [])) {
            if (!item)
                continue;
            built.push(subRegionComponent.createObject(root, {
                item: item,
                radius: root.regionItemsRadius
            }));
        }
        root.subRegions = built;
        root.region.regions = built;
        root.republish();
    }

    onRegionItemsChanged: root.rebuildFromItems()

    function republish() {
        if (!root.targetWindow)
            return;
        root.targetWindow.BackgroundEffect.blurRegion = null;
        root.targetWindow.BackgroundEffect.blurRegion = root.region;
    }

    onRegionChanged: root.publishNow()

    Timer {
        id: settleTimer
        interval: 96
        repeat: false
        onTriggered: root.republish()
    }

    // Publish at once and schedule the settle as well, rather than only
    // scheduling it. The timer exists for a region dropped mid-(re)configure,
    // which is a race worth re-covering - but waiting on it is a guaranteed
    // 96ms of surface-up-and-unblurred, which on a panel that opens on demand
    // is a visible flash of sharp wallpaper before the blur lands. Measured at
    // 7 frames of a 60fps capture on the overview and the search bar.
    function publishNow(): void {
        root.republish();
        settleTimer.restart();
    }

    Connections {
        target: root.targetWindow ?? null
        ignoreUnknownSignals: true
        function onVisibleChanged() {
            if (root.targetWindow.visible)
                root.publishNow();
        }
        function onWidthChanged() {
            root.publishNow();
        }
        function onHeightChanged() {
            root.publishNow();
        }
    }

    Component.onCompleted: {
        if (targetWindow)
            targetWindow.BackgroundEffect.blurRegion = region;
        settleTimer.restart();
    }
    Component.onDestruction: {
        if (targetWindow && targetWindow.BackgroundEffect)
            targetWindow.BackgroundEffect.blurRegion = null;
    }
}
