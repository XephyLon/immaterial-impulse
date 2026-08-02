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

    function republish() {
        if (!root.targetWindow)
            return;
        root.targetWindow.BackgroundEffect.blurRegion = null;
        root.targetWindow.BackgroundEffect.blurRegion = root.region;
    }

    onRegionChanged: settleTimer.restart()

    Timer {
        id: settleTimer
        interval: 96
        repeat: false
        onTriggered: root.republish()
    }

    Connections {
        target: root.targetWindow ?? null
        ignoreUnknownSignals: true
        function onVisibleChanged() {
            if (root.targetWindow.visible)
                settleTimer.restart();
        }
        function onWidthChanged() {
            settleTimer.restart();
        }
        function onHeightChanged() {
            settleTimer.restart();
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
