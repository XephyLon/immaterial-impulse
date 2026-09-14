import QtQuick
import qs.modules.common

/**
 * The enter/leave lifecycle of a transient overlay surface (desktop menu,
 * screenshot toast, drop shelf): one scalar for the card to draw from, and a
 * surface lifetime that outlives the "open" flag by exactly the leave motion.
 *
 *   OverlayLifecycle { id: life; wanted: GlobalStates.xOpen }
 *   Loader { active: life.alive ... }                 // not GlobalStates.xOpen
 *   card.opacity: life.progress                       // 0 -> 1 -> 0
 *   window.mask: GlobalStates.xOpen ? null : noInput  // input follows the flag
 *
 * `wanted` rising: `alive` becomes true at once and `progress` runs 0 -> 1 on
 * the overlayEnter tier. `wanted` falling: `progress` runs 1 -> 0 on the
 * overlayExit tier and only its finish drops `alive` and fires `closed()`.
 * A host that hides on the flag instead of on `alive` never shows the leave;
 * a host that keeps input on `alive` instead of the flag makes the leave
 * motion 180 ms of dead desktop - tests/lint_overlay_lifecycle.py pins both.
 * Both tiers go through the motion policy, so the speed slider scales them
 * and reduce-motion collapses them to an immediate finish that still fires.
 */
QtObject {
    id: root

    property bool wanted: false
    readonly property bool alive: root._alive
    property bool _alive: false
    property real progress: 0

    signal opened()
    signal closed()

    readonly property NumberAnimation enterAnim: NumberAnimation {
        target: root
        property: "progress"
        to: 1
        duration: Appearance.animation.overlayEnter.duration
        easing.type: Appearance.animation.overlayEnter.type
        easing.bezierCurve: Appearance.animation.overlayEnter.bezierCurve
        onFinished: root.opened()
    }
    readonly property NumberAnimation exitAnim: NumberAnimation {
        target: root
        property: "progress"
        to: 0
        duration: Appearance.animation.overlayExit.duration
        easing.type: Appearance.animation.overlayExit.type
        easing.bezierCurve: Appearance.animation.overlayExit.bezierCurve
        onFinished: {
            // A re-open during the leave restarted the enter; do not tear
            // down under it.
            if (root.wanted) return;
            root._alive = false;
            root.closed();
        }
    }

    onWantedChanged: {
        if (root.wanted) {
            root.exitAnim.stop();
            root._alive = true;
            root.enterAnim.restart();
        } else if (root._alive) {
            root.enterAnim.stop();
            root.exitAnim.restart();
        }
    }
    Component.onCompleted: {
        if (root.wanted) {
            root._alive = true;
            root.enterAnim.restart();
        }
    }

    /** Re-run the entrance on a surface that stays alive (a toast replaced by
        a newer one). */
    function replay() {
        if (!root._alive) return;
        root.exitAnim.stop();
        root.progress = 0;
        root.enterAnim.restart();
    }
}
