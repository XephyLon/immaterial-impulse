import QtQuick
import qs.modules.common

/**
 * The runner for a panel fastened to a screen edge: it slides in from that
 * edge and back out, and the SURFACE it lives on stays mapped the whole time.
 *
 * That second half is the reason this exists. A layer surface cannot be
 * reused, so a PanelWindow whose `visible` follows the flag that asks for it
 * is destroyed on close and rebuilt on open - a new render thread, a new GL
 * context, the whole scene graph built from nothing and every glyph uploaded
 * again. The shell has ONE GUI thread for all of its windows, and measured
 * with QSG_RENDER_TIMING on the real session that thread sat blocked for
 * 61ms per open (`blockedForSync=61 ms, polish=0`) - every other window the
 * shell draws frozen for fifteen frames at 240Hz, the "momentary freeze right
 * before they open". The same open with the window kept mapped: 1-3ms.
 *
 * So the slide is QML's rather than the compositor's. The layerrule that
 * used to animate the map (`animation = slide right`) is `no_anim` now, and
 * the tiers here are pinned to what that rule drew: Hyprland's `layersIn` /
 * `layersOut` at speed 4 on `pc_decel` / `pc_accel`. The look did not change;
 * who draws it did.
 *
 * Three things the adopter has to do, because a persistent surface is a
 * surface that can eat input and focus while showing nothing:
 *
 *  - gate the window's `mask` on the gesture's flag, so a closed panel is a
 *    hole the pointer falls through;
 *  - gate `WlrLayershell.keyboardFocus` on it, because an always-mapped
 *    surface with OnDemand focus is a surface that takes the keyboard;
 *  - hide the content on `shown`, not on the flag - `shown` stays true for
 *    the length of the exit, which is the one reason the exit can be seen.
 *
 * A QtObject rather than an Item, for StaggerWave's reason: declared inside
 * the window it drives, an Item would become a member of it. The animations
 * are declared properties because a QtObject has no `data`.
 */
QtObject {
    id: root

    // The gesture's own flag. The runner reads it and never writes it.
    required property bool open

    // How far the panel travels: its own extent along the slide axis, so at
    // progress 0 nothing of it is on screen.
    required property real travel

    // Which way "out" is. +1 for a panel on the right or bottom edge (it
    // leaves toward +x / +y), -1 for one on the left or top.
    property int direction: 1

    // 0 = parked off its edge, 1 = at rest on screen. Declared at 0 and only
    // ever written by the two animations below and by `Component.onCompleted`
    // for a surface created with its panel already open - a start value
    // written through the animated property is what
    // lint_animated_start_write.py exists for.
    property real progress: 0

    // The displacement to apply to the panel, in px along the slide axis.
    readonly property real offset: (1 - root.progress) * root.travel * root.direction

    // The curtain: an opacity for the panel's content that holds low early
    // in the slide and ramps to full late - the sibling fork's `stall`
    // fade-layer curve, derived from the same progress so it cannot drift.
    // This is what makes a composed-under-construction panel possible: the
    // per-widget entrances run while the content is still translucent, so a
    // member not yet arrived is a dim nothing rather than an opaque HOLE in
    // a fully-lit panel - which is exactly what the right sidebar showed
    // (full-res frames: a black void where the toggle grid's later rows
    // were still parked, for ~300ms, reading as an ugly pause). Piecewise
    // rather than a bezier so the endpoints are exact: 30% alpha up to 40%
    // travel, then a linear ramp home.
    readonly property real reveal: root.progress >= 1 ? 1
        : root.progress <= 0 ? 0
        : root.progress < 0.4 ? 0.3 * (root.progress / 0.4)
        : 0.3 + 0.7 * ((root.progress - 0.4) / 0.6)

    // Whether the panel has anything on screen. True through the whole exit,
    // so content gated on it is not hidden under an animation still drawing
    // it; false once the exit has finished, so a Loader gated on it may stand
    // down.
    readonly property bool shown: root.open || root.progress > 0

    onOpenChanged: {
        if (root.open)
            root.arrive();
        else
            root.leave();
    }

    Component.onCompleted: {
        if (root.open)
            root.progress = 1;
    }

    function arrive() {
        root.exitAnim.stop();
        root.enterAnim.start();
    }

    function leave() {
        root.enterAnim.stop();
        root.exitAnim.start();
    }

    // Started animations rather than a Behavior: the gesture can be reversed
    // mid-flight by toggling twice, and a Behavior branching on the flag is
    // the tier race lint_behavior_tier_race.py exists for.
    readonly property NumberAnimation enterAnim: NumberAnimation {
        target: root
        property: "progress"
        to: 1
        duration: Appearance.animation.sidebarSlideEnter.duration
        easing.type: Appearance.animation.sidebarSlideEnter.type
        easing.bezierCurve: Appearance.animation.sidebarSlideEnter.bezierCurve
    }

    readonly property NumberAnimation exitAnim: NumberAnimation {
        target: root
        property: "progress"
        to: 0
        duration: Appearance.animation.sidebarSlideExit.duration
        easing.type: Appearance.animation.sidebarSlideExit.type
        easing.bezierCurve: Appearance.animation.sidebarSlideExit.bezierCurve
    }
}
