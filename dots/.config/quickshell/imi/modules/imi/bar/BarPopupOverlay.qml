pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets

// One always-mapped layer surface per screen, hosting the single card every bar
// popup morphs. The surface itself never moves, resizes or unmaps: on a
// layer-shell surface position *is* `margins`, so animating a popup along the
// bar reconfigures its surface every frame, which is the create-map-destroy
// loop StyledPopup's imperative positioning already exists to avoid.
//
// The card carries all the motion instead, and `mask: Region { item: card }`
// keeps the rest of the screen click-through. A 0x0 card builds an empty input
// region, which makes Qt mark the whole surface transparent for input - that is
// the invariant that lets a full-screen Overlay surface stay mapped forever.
Scope {
    id: overlayScope

    Variants {
        // Same screen set as both bars: the vertical bar loads the same widget
        // files, so one overlay family entry serves either orientation.
        model: {
            const screens = Quickshell.screens;
            const list = Config.options.bar.screenList;
            if (!list || list.length === 0)
                return screens;
            return screens.filter(screen => list.includes(screen.name));
        }

        PanelWindow {
            id: overlayWindow
            required property ShellScreen modelData

            screen: modelData
            color: "transparent"
            // Mapped only while it has something to show. This is a
            // SCREEN-SIZED surface on the Overlay layer, so leaving it mapped
            // puts a 5120x1440 transparent sheet over every fullscreen window
            // for the whole session - the compositor composites it each frame
            // and the window under it can never be the only thing on the
            // output. Measured with FFXIV's own counter on a static scene:
            // 98 fps with this mapped and idle, 105 with it unmapped.
            //
            // The predicate outlasts the exit deliberately. Unmapping destroys
            // the QQuickWindow, and a popup's content tree is REPARENTED into
            // this window while it shows - so the window may only go once
            // `finishExit()` has released both trees and collapsed the card,
            // which is exactly the state this reads.
            visible: overlayWindow.current !== null
                || overlayWindow.outgoing !== null
                || overlayWindow.exiting
                || card.opacity > 0
                || card.width > 0
                || card.height > 0
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0

            // Anchoring all four edges makes this window's coordinate space the
            // screen's, so no bar-edge arithmetic survives at surface level.
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // Its own namespace, listed in rules.lua's computed-threshold loop
            // beside the bar and the dock. quickshell:popup was reused at first
            // because its ignore_alpha = 1 blurs the card's opaque body and
            // skips its translucent shadow - but a tray item's context menu is
            // an xdg-popup of whatever surface it was opened from, and popups
            // inherit the parent surface's rules. Once tray items moved onto
            // this card their menus inherited that 1, and a translucent menu
            // body sits below it: the menu stopped being blurred at all.
            //
            // The computed threshold serves both, which the constant cannot:
            // it is above the shadow and below the faintest body, so the opaque
            // card blurs, its shadow stays sharp, this surface's transparent
            // pixels are left alone, and the popups opened from the card are
            // blurred like the ones opened from the bar always were. A
            // namespace absent from that loop is the real hazard - it falls
            // through to the catch-all 0.05, under which the transparent pixels
            // ask the compositor to blur the whole screen.
            WlrLayershell.namespace: "quickshell:barPopup"
            WlrLayershell.layer: WlrLayer.Overlay

            mask: Region {
                item: card
            }

            // The popup the card is showing or morphing to, and the one still
            // fading out inside it. Never more than these two content trees are
            // in a window at once.
            property var current: null
            property var outgoing: null
            property bool exiting: false
            // Where the card collapses to on exit. Remembered rather than
            // recomputed, because the popup that owns it may have been
            // destroyed by the time the exit runs.
            property var exitSpot: null
            readonly property bool morphing: xAnim.running || yAnim.running
                || widthAnim.running || heightAnim.running

            readonly property var requested: {
                const popup = GlobalStates.activeBarPopup;
                if (!popup || !popup.popupVisible) return null;
                if (popup.hoverTarget?.QsWindow?.window?.screen !== overlayWindow.modelData) return null;
                return popup;
            }

            onRequestedChanged: {
                if (requested) takeOver(requested);
                else beginExit();
            }

            function takeOver(popup) {
                exitShrinkTimer.stop();
                exitFadeTimer.stop();
                overlayWindow.exiting = false;
                card.opacity = 1;
                // An exit disables the leaving content; a re-hover of the very
                // widget the card was leaving has to hand its controls back.
                if (overlayWindow.current?.contentItem)
                    overlayWindow.current.contentItem.enabled = true;

                if (overlayWindow.current === popup) {
                    retargetTimer.restart();
                    return;
                }

                // A third takeover arriving before the second cross-fade
                // finished would leave a tree parented with nothing left to
                // unparent it, so release it here rather than on its fade.
                if (overlayWindow.outgoing && overlayWindow.outgoing !== popup)
                    overlayWindow.release(overlayWindow.outgoing);
                overlayWindow.outgoing = null;

                const previous = overlayWindow.current;
                if (previous) previous.popupHovered = false;
                overlayWindow.current = popup;

                if (previous && previous !== popup && previous.contentItem) {
                    overlayWindow.outgoing = previous;
                    // The outgoing tree fades as a picture, not as a control:
                    // a click landing on the card mid-morph is aimed at the
                    // content the pointer moved toward.
                    previous.contentItem.enabled = false;
                    contentExit.target = previous.contentItem;
                    contentExit.restart();
                }

                const arriving = popup.contentItem;
                if (arriving) {
                    arriving.parent = contentHost;
                    arriving.anchors.centerIn = contentHost;
                    arriving.enabled = true;
                    arriving.opacity = 0;
                    contentEnter.stop();
                    contentEnter.item = arriving;
                    contentEnter.restart();
                }
                popup.surfaceWindow = overlayWindow;
                popup.popupHovered = cardHover.hovered;

                // Coming from idle there is no geometry to morph from, so put
                // the card at the widget it belongs to before anything animates.
                if (card.width <= 0 || card.height <= 0) overlayWindow.park();
                retargetTimer.restart();
            }

            // The incoming content's implicit size is not readable until it has
            // been parented into a window and polished, so the first correct
            // target is one frame away - the same zero-interval deferral, for
            // the same reason, as the popup window's own updatePosition().
            function retarget() {
                const popup = overlayWindow.current;
                const content = popup?.contentItem;
                const target = popup?.hoverTarget;
                if (!content || !target?.QsWindow?.window) return;

                const margin = Appearance.sizes.elevationMargin;
                const cardWidth = content.implicitWidth + popup.contentPadding * 2;
                const cardHeight = content.implicitHeight + popup.contentPadding * 2;

                let cardX;
                let cardY;
                if (popup.barVertical) {
                    const base = target.QsWindow.mapFromItem(target, 0, (target.height - cardHeight) / 2).y;
                    cardY = Math.max(margin, Math.min(base, overlayWindow.height - cardHeight - margin - 15));
                    cardX = popup.barEdge === "right"
                        ? overlayWindow.width - popup.barThickness - margin - cardWidth
                        : popup.barThickness + margin;
                } else {
                    const base = target.QsWindow.mapFromItem(target, (target.width - cardWidth) / 2, 0).x;
                    cardX = Math.max(margin, Math.min(base, overlayWindow.width - cardWidth - margin - 10));
                    cardY = popup.barEdge === "bottom"
                        ? overlayWindow.height - popup.barThickness - margin - cardHeight
                        : popup.barThickness + margin;
                }

                // Assigned, never bound: nothing the card's geometry feeds may
                // also feed the computation of it, and on the bottom/right
                // edges the fixed axis is a function of the animating size.
                card.width = cardWidth;
                card.height = cardHeight;
                card.x = cardX;
                card.y = cardY;
                overlayWindow.exitSpot = overlayWindow.anchorSpot();
            }

            // The card's exit target: a small square on the bar-adjacent edge,
            // centred on the widget the card belongs to.
            function anchorSpot() {
                const popup = overlayWindow.current ?? overlayWindow.outgoing;
                const target = popup?.hoverTarget;
                if (!target?.QsWindow?.window) return overlayWindow.exitSpot;

                const margin = Appearance.sizes.elevationMargin;
                const floor = margin * 2;
                const centre = target.QsWindow.mapFromItem(target, target.width / 2, target.height / 2);
                if (popup.barVertical) {
                    return {
                        x: popup.barEdge === "right"
                            ? overlayWindow.width - popup.barThickness - margin - floor
                            : popup.barThickness + margin,
                        y: centre.y - floor / 2,
                        width: floor,
                        height: floor
                    };
                }
                return {
                    x: centre.x - floor / 2,
                    y: popup.barEdge === "bottom"
                        ? overlayWindow.height - popup.barThickness - margin - floor
                        : popup.barThickness + margin,
                    width: floor,
                    height: floor
                };
            }

            function park() {
                const spot = overlayWindow.anchorSpot();
                if (!spot) return;
                card.animate = false;
                card.opacity = 0;
                card.x = spot.x;
                card.y = spot.y;
                card.width = spot.width;
                card.height = spot.height;
                card.animate = true;
                card.opacity = 1;
                overlayWindow.exitSpot = spot;
            }

            // Shrink toward the owning widget, then fade, then collapse. The
            // collapse is not cosmetic: an opacity-0 card still publishes a
            // full-size input region and would eat every click in its rectangle.
            function beginExit() {
                if (overlayWindow.exiting) return;
                // Already idle. Returning rather than collapsing again matters:
                // finishExit() vacates the slot, which re-enters here.
                if (!overlayWindow.current && !overlayWindow.outgoing
                        && card.width <= 0 && card.height <= 0) return;
                if (card.width <= 0 && card.height <= 0) {
                    overlayWindow.finishExit();
                    return;
                }
                const spot = overlayWindow.anchorSpot();
                if (!spot) {
                    overlayWindow.finishExit();
                    return;
                }
                overlayWindow.exiting = true;
                if (overlayWindow.current?.contentItem)
                    overlayWindow.current.contentItem.enabled = false;
                card.x = spot.x;
                card.y = spot.y;
                card.width = spot.width;
                card.height = spot.height;
                exitShrinkTimer.restart();
            }

            function finishExit() {
                exitShrinkTimer.stop();
                exitFadeTimer.stop();
                contentEnter.stop();
                contentExit.stop();

                const leaving = overlayWindow.current;
                overlayWindow.release(overlayWindow.outgoing);
                overlayWindow.release(leaving);
                overlayWindow.outgoing = null;
                overlayWindow.current = null;
                overlayWindow.exiting = false;

                card.animate = false;
                card.opacity = 0;
                card.width = 0;
                card.height = 0;
                card.animate = true;

                if (leaving && GlobalStates.activeBarPopup === leaving)
                    GlobalStates.activeBarPopup = null;
            }

            function release(popup) {
                if (!popup) return;
                // Before the reparent, not after: setParentItem() runs
                // derefWindow(), which re-evaluates every binding that read the
                // old window while the item is mid-teardown. A tray menu
                // anchored to that window segfaulted the shell there.
                popup.aboutToRelease();
                const content = popup.contentItem;
                if (content) {
                    content.anchors.centerIn = null;
                    content.parent = null;
                    content.opacity = 1;
                    content.enabled = true;
                }
                popup.popupHovered = false;
                if (popup.surfaceWindow === overlayWindow) popup.surfaceWindow = null;
            }

            function updateHover() {
                if (overlayWindow.current) overlayWindow.current.popupHovered = cardHover.hovered;
            }

            Timer {
                id: retargetTimer
                interval: 0
                onTriggered: overlayWindow.retarget()
            }

            Timer {
                id: exitShrinkTimer
                interval: Appearance.animation.elementMoveExit.duration
                onTriggered: {
                    card.opacity = 0;
                    exitFadeTimer.restart();
                }
            }

            Timer {
                id: exitFadeTimer
                interval: Appearance.animation.elementMoveFast.duration
                onTriggered: overlayWindow.finishExit()
            }

            // Outside-click dismissal belongs to whoever owns the surface, and
            // that is now this overlay rather than the individual widgets.
            //
            // The widgets used to arm their own grabs on their own popup window,
            // which was sized to the popup, so a click anywhere in the popup was
            // inside the grab. Pointed at the shared surface those grabs break:
            // Hyprland classifies a click by the surface's *input region*, and
            // this surface's region is the card. A grab armed while the card is
            // still the parked 2*elevationMargin square treats the next click
            // anywhere as outside and closes the popup. So arm only once the
            // card has stopped moving and is showing content at full size.
            HyprlandFocusGrab {
                id: cardGrab
                active: !!overlayWindow.current?.pinnedOpen
                    && !overlayWindow.exiting
                    && !overlayWindow.morphing
                    && card.width > Appearance.sizes.elevationMargin * 2
                windows: [
                    overlayWindow,
                    overlayWindow.current?.hoverTarget?.QsWindow?.window,
                    ...(overlayWindow.current?.extraGrabWindows ?? [])
                ].filter(window => window)
                onCleared: overlayWindow.current?.dismissRequested()
            }

            // Whatever is on the card can change size while it is shown - the
            // clock ticking a row in, NetworkSpeed's rows changing.
            //
            // Those are one-off changes, and deferring them by a tick lets a
            // burst of them settle into a single retarget. A popup ANIMATING
            // its own size is the opposite case: the size changes every frame,
            // so a timer that is restarted every frame never fires until the
            // animation ends, and the card would sit at its old size for the
            // whole transition while the content grew past its clip. Those
            // popups are retargeted on the spot.
            Connections {
                target: overlayWindow.current?.contentItem ?? null
                ignoreUnknownSignals: true
                function onImplicitWidthChanged() { overlayWindow.retargetNow() }
                function onImplicitHeightChanged() { overlayWindow.retargetNow() }
            }

            function retargetNow() {
                if (overlayWindow.current?.contentDrivesSize) overlayWindow.retarget();
                else retargetTimer.restart();
            }

            // The window is unmapped while it has nothing to show (a mapped
            // screen-sized Overlay surface holds the compositor's fullscreen
            // fast path shut), and a WlrLayershell window that has just gone
            // visible does not have its size yet: measured on the live
            // compositor, it reports 500x500 for the same tick AND through
            // Qt.callLater, and the real 5120x1330 arrives with the configure
            // ~50ms later. retarget()'s clamp reads overlayWindow.width and
            // height, so a retarget on the zero-interval timer ran against
            // 500x500, `min(base, 500 - cardWidth - margin - 10)` went
            // negative, and `max(margin, ...)` pinned the card to the
            // top-left - the calendar card at x=margin under a clock at
            // screen-centre. Re-run when the geometry actually lands.
            onWidthChanged: if (overlayWindow.current) overlayWindow.retarget()
            onHeightChanged: if (overlayWindow.current) overlayWindow.retarget()

            // There is no sensible interpolation between "below the top edge"
            // and "right of the left edge", so an orientation change idles the
            // card rather than morphing across it.
            //
            // Derived here from the config rather than watched on whichever
            // popup currently holds the card. Every popup computes the same
            // value from the same global config, so the per-popup signal says
            // nothing extra - but a popup that is rebuilt on every open (the
            // Docker and Discord adapters' Loaders both do) evaluates its own
            // barEdge binding for the first time *after* a Connections targeting
            // it attaches, and that initial evaluation is indistinguishable from
            // an orientation flip. It called finishExit() in the middle of the
            // takeover that was building the card, stranding it at the parked
            // 20x20 square: the popup opened as a small dot and only rendered
            // when the race happened to fall the other way, which is why it took
            // several clicks (#140).
            readonly property string barEdge: {
                if (!Config.options.bar.vertical)
                    return Config.options.bar.bottom ? "bottom" : "top";
                return Config.options.bar.bottom ? "right" : "left";
            }
            onBarEdgeChanged: overlayWindow.finishExit()

            SequentialAnimation {
                id: contentEnter
                property Item item: null
                // The pause is the slice of the travel the outgoing content's
                // fade owns; the enter then lands exactly as the move settles.
                PauseAnimation {
                    duration: Appearance.animation.elementMove.duration
                        - Appearance.animation.elementMoveEnter.duration
                }
                NumberAnimation {
                    target: contentEnter.item
                    property: "opacity"
                    to: 1
                    duration: Appearance.animation.elementMoveEnter.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                }
            }

            NumberAnimation {
                id: contentExit
                property: "opacity"
                to: 0
                duration: Appearance.animation.elementMoveExit.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
                onFinished: {
                    const leaving = overlayWindow.outgoing;
                    if (leaving && leaving.contentItem === contentExit.target) {
                        overlayWindow.release(leaving);
                        overlayWindow.outgoing = null;
                    }
                }
            }

            StyledRectangularShadow {
                target: card
                visible: card.visible
                opacity: card.opacity
                // A cached shadow renders to an offscreen texture, which a card
                // whose size changes every frame invalidates every frame.
                cached: !overlayWindow.morphing
            }

            Rectangle {
                id: card
                // Gates the Behaviors so the card can be placed instantly when
                // there is no previous geometry to travel from.
                property bool animate: true
                readonly property int motionDuration: overlayWindow.exiting
                    ? Appearance.animation.elementMoveExit.duration
                    : Appearance.animation.elementMove.duration
                readonly property var motionCurve: overlayWindow.exiting
                    ? Appearance.animationCurves.emphasizedAccel
                    : Appearance.animationCurves.expressiveDefaultSpatial

                width: 0
                height: 0
                opacity: 0
                visible: width > 0 && height > 0

                color: Appearance.colors.colLayer1Base
                radius: Appearance.rounding.normal + 4
                border.width: Appearance.borderWidth.standard
                border.color: Appearance.colors.colLayer0Border

                Behavior on x {
                    // Position too, for the same reason as width and height: a
                    // right-anchored card's x is derived from its width, so
                    // easing one while the other tracks the content puts the
                    // card's edge where its content is not.
                    enabled: card.animate && !(overlayWindow.current?.contentDrivesSize ?? false)
                    NumberAnimation {
                        id: xAnim
                        duration: card.motionDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: card.motionCurve
                    }
                }
                Behavior on y {
                    enabled: card.animate && !(overlayWindow.current?.contentDrivesSize ?? false)
                    NumberAnimation {
                        id: yAnim
                        duration: card.motionDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: card.motionCurve
                    }
                }
                Behavior on width {
                    // See StyledPopup.contentDrivesSize: a popup animating its
                    // own size must not be chased by the card.
                    enabled: card.animate && !(overlayWindow.current?.contentDrivesSize ?? false)
                    NumberAnimation {
                        id: widthAnim
                        duration: card.motionDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: card.motionCurve
                    }
                }
                Behavior on height {
                    enabled: card.animate && !(overlayWindow.current?.contentDrivesSize ?? false)
                    NumberAnimation {
                        id: heightAnim
                        duration: card.motionDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: card.motionCurve
                    }
                }
                Behavior on opacity {
                    enabled: card.animate
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                HoverHandler {
                    id: cardHover
                    onHoveredChanged: overlayWindow.updateHover()
                }

                // Clipping is load-bearing: while the card shrinks, the
                // outgoing content is larger than the host and would otherwise
                // paint outside the card's rounded body. Content is inset by
                // contentPadding on every side, so the rectangular clip never
                // reaches the corner radii.
                Item {
                    id: contentHost
                    anchors.fill: parent
                    anchors.margins: overlayWindow.current?.contentPadding ?? 0
                    clip: true
                }
            }
        }
    }
}
