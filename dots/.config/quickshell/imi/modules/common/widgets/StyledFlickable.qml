import QtQuick
import QtQuick.Controls
import qs.modules.common

Flickable {
    id: root
    maximumFlickVelocity: 3500

    property real touchpadScrollFactor: Config?.options.interactions.scrolling.touchpadScrollFactor ?? 100
    property real mouseScrollFactor: Config?.options.interactions.scrolling.mouseScrollFactor ?? 50
    property real mouseScrollDeltaThreshold: Config?.options.interactions.scrolling.mouseScrollDeltaThreshold ?? 120
    // Accumulated scroll destination so wheel deltas stack while animating
    property real scrollTargetY: 0
    // Opt-in M3 Expressive springy scroll. In-bounds wheel scrolling settles on
    // a spatial curve; scrolling past an edge that's already at the end pushes a
    // damped overshoot and springs back (rubber-band) - works on a mouse wheel,
    // not just drag. Off by default so other scroll surfaces are unchanged.
    property bool expressiveScroll: false
    property real maxOverscroll: 56

    // Opt-in true-inertia trackpad scrolling. Two-finger pixelDelta moves the
    // content 1:1 with the fingers; when the fingers lift, libinput's zero-delta
    // scroll-stop event (px==0 && ang==0) hands the velocity built up during the
    // stroke to Flickable.flick(), so it glides and decelerates via the native
    // flickDeceleration. A short idle-gap timer is the fallback for devices that
    // don't emit that stop event. Classic mouse wheels (angleDelta, no pixelDelta)
    // fall through to a plain discrete step. Off by default so other scroll
    // surfaces are unchanged.
    property bool momentumScroll: false
    property real momentumFactor: 1.0        // trackpad tracking-speed multiplier
    property real momentumMinVelocity: 40    // below this (px/s) don't bother flicking
    property real _lastWheelTime: 0
    property real _scrollVelocity: 0

    boundsBehavior: root.expressiveScroll ? Flickable.OvershootBounds : Flickable.DragOverBounds

    ScrollBar.vertical: StyledScrollBar {}

    // ── Non-expressive path: accumulating animated-decel wheel (unchanged) ──
    MouseArea {
        visible: !root.expressiveScroll && !root.momentumScroll && Config?.options.interactions.scrolling.fasterTouchpadScroll
        enabled: visible
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: function(wheelEvent) {
            const delta = wheelEvent.angleDelta.y / root.mouseScrollDeltaThreshold;
            var scrollFactor = Math.abs(wheelEvent.angleDelta.y) >= root.mouseScrollDeltaThreshold ? root.mouseScrollFactor : root.touchpadScrollFactor;

            const maxY = Math.max(0, root.contentHeight - root.height);
            const base = scrollAnim.running ? root.scrollTargetY : root.contentY;
            var targetY = Math.max(0, Math.min(base - delta * scrollFactor, maxY));

            root.scrollTargetY = targetY;
            root.contentY = targetY;
            wheelEvent.accepted = true;
        }
    }

    Behavior on contentY {
        enabled: !root.expressiveScroll && !root.momentumScroll
        NumberAnimation {
            id: scrollAnim
            duration: Appearance.animation.scroll.duration
            easing.type: Appearance.animation.scroll.type
            easing.bezierCurve: Appearance.animation.scroll.bezierCurve
        }
    }

    onContentYChanged: {
        if (!scrollAnim.running && !root.expressiveScroll) {
            root.scrollTargetY = root.contentY;
        }
    }

    // ── Expressive path: animated in-bounds scroll + rubber-band at edges ──
    MouseArea {
        visible: root.expressiveScroll
        enabled: visible
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: function(wheelEvent) {
            const maxY = Math.max(0, root.contentHeight - root.height);
            var scrollFactor = Math.abs(wheelEvent.angleDelta.y) >= root.mouseScrollDeltaThreshold ? root.mouseScrollFactor : root.touchpadScrollFactor;
            const delta = wheelEvent.angleDelta.y / root.mouseScrollDeltaThreshold;

            const anchoredY = (settleAnim.running || bounceAnim.running) ? root.scrollTargetY : root.contentY;
            const raw = anchoredY - delta * scrollFactor;
            const scrollingDown = raw > anchoredY; // moving toward the bottom
            const atBottom = anchoredY >= maxY - 0.5;
            const atTop = anchoredY <= 0.5;

            // Rubber-band ONLY when already pinned to an edge and pushing past it.
            // Every other scroll (including the step that reaches an edge) just
            // settles springily at the clamped target.
            if ((scrollingDown && atBottom) || (!scrollingDown && atTop)) {
                const bound = scrollingDown ? maxY : 0;
                const overshoot = Math.min(Math.abs(raw - bound) * 0.35, root.maxOverscroll);
                root.scrollTargetY = bound;
                settleAnim.stop();
                bounceAnim.overshootY = bound + (scrollingDown ? overshoot : -overshoot);
                bounceAnim.boundY = bound;
                bounceAnim.restart();
            } else {
                const target = Math.max(0, Math.min(raw, maxY));
                root.scrollTargetY = target;
                bounceAnim.stop();
                settleAnim.stop();
                settleAnim.to = target;
                settleAnim.start();
            }
            wheelEvent.accepted = true;
        }
    }

    // In-bounds settle (springy fast-spatial curve).
    NumberAnimation {
        id: settleAnim
        target: root
        property: "contentY"
        duration: Appearance.animationCurves.expressiveFastSpatialDuration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
    }

    // Edge rubber-band: quick push out, then a springy settle back to the bound.
    SequentialAnimation {
        id: bounceAnim
        property real overshootY: 0
        property real boundY: 0
        NumberAnimation {
            target: root; property: "contentY"; to: bounceAnim.overshootY
            duration: Appearance.animationCurves.expressiveEffectsDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
        NumberAnimation {
            target: root; property: "contentY"; to: bounceAnim.boundY
            duration: Appearance.animationCurves.expressiveDefaultSpatialDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
        }
    }

    // ── Momentum path: 1:1 finger tracking + inertial flick on burst-end ──
    // WheelHandler (not a child MouseArea): the Flickable grabs the wheel before
    // a lower-z MouseArea in its contentItem ever sees it, so onWheel never fired.
    // A pointer handler receives the wheel reliably over the scrolling content.
    WheelHandler {
        id: momentumWheel
        enabled: root.momentumScroll
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function(wheelEvent) {
            const maxY = Math.max(0, root.contentHeight - root.height);
            const px = wheelEvent.pixelDelta.y;
            const ang = wheelEvent.angleDelta.y;

            // Finger-lift: libinput/Hyprland send a zero-delta scroll-stop event
            // (px==0 && ang==0) when the fingers leave the trackpad. That's the
            // moment to launch the inertial flick with the velocity built up
            // during the stroke — NOT to reset it.
            if (px === 0 && ang === 0) {
                var vEnd = root._scrollVelocity;
                root._scrollVelocity = 0;
                root._lastWheelTime = 0;
                if (Math.abs(vEnd) >= root.momentumMinVelocity) {
                    vEnd = Math.max(-root.maximumFlickVelocity, Math.min(vEnd, root.maximumFlickVelocity));
                    root.flick(0, vEnd);
                }
                wheelEvent.accepted = true;
                return;
            }

            // Classic mouse wheel: no pixelDelta but a real angleDelta. Plain
            // discrete step, no inertia.
            if (px === 0) {
                root.cancelFlick();
                const step = ang / 120 * root.mouseScrollFactor;
                root.contentY = Math.max(0, Math.min(root.contentY - step, maxY));
                root._scrollVelocity = 0;
                wheelEvent.accepted = true;
                return;
            }

            // Trackpad move: track content 1:1 with the fingers, measure velocity.
            const now = Date.now();
            var dt = (now - root._lastWheelTime) / 1000;
            root._lastWheelTime = now;
            // First event of a burst, or a gap: don't derive a bogus huge velocity.
            if (dt <= 0 || dt > 0.1) dt = 0.016;

            root.cancelFlick();
            const move = px * root.momentumFactor;
            root.contentY = Math.max(0, Math.min(root.contentY - move, maxY));

            const instant = move / dt;
            root._scrollVelocity = 0.6 * root._scrollVelocity + 0.4 * instant;
            // Fallback for devices that don't emit an explicit scroll-stop event.
            momentumEndTimer.restart();
            wheelEvent.accepted = true;
        }
    }

    Timer {
        id: momentumEndTimer
        interval: 60   // no wheel event for this long ⇒ fingers lifted
        onTriggered: {
            var v = root._scrollVelocity;
            root._scrollVelocity = 0;
            if (Math.abs(v) < root.momentumMinVelocity)
                return;
            v = Math.max(-root.maximumFlickVelocity, Math.min(v, root.maximumFlickVelocity));
            root.flick(0, v);
        }
    }
}
