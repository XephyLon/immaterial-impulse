pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import "bar_popup_unroll.js" as BarPopupUnroll

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
            //
            // It reads the card's INPUTS - the open height, the width and the
            // driver - rather than its drawn height and opacity, and that is
            // load-bearing rather than tidiness. The drawn ones are derived, and
            // the card's own across-the-bar coordinate is derived from the
            // window's size, so a predicate reading them closes a circle through
            // this very property: measured as `Binding loop detected for
            // property "visible"` on a real compositor, twice per window, where
            // the same probe against the assigned geometry logged nothing.
            visible: overlayWindow.current !== null
                || overlayWindow.outgoing !== null
                || overlayWindow.exiting
                || card.openProgress > 0
                || card.width > 0
                || card.openHeight > 0
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
            // Where along the bar the card collapses to on exit. Remembered
            // rather than recomputed, because the popup that owns it may have
            // been destroyed by the time the exit runs. One number, not a
            // rectangle: the card's across-the-bar coordinate is derived from
            // its live size, so nothing about the parked square is stored.
            property var exitAnchor: null
            readonly property bool morphing: card.alongBarAnim.running || card.widthAnim.running
                || card.openAnim.running

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
                exitTimer.stop();
                overlayWindow.exiting = false;
                // No opacity or progress write here: retarget() drives the one
                // scalar, one turn of the event loop from now, and it is the
                // only place that knows what the card is opening to. Reversing
                // an exit from here would ramp the card back up against the
                // outgoing popup's height for a frame.
                //
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
                    arriving.parent = contentSlot;
                    arriving.anchors.centerIn = contentSlot;
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
                if (card.width <= 0 || card.openHeight <= 0) overlayWindow.park();
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

                // The clamp reads the SETTLED size, never the card's animating
                // one: a rect measured from the far edge of a box that is still
                // moving crawls behind it.
                if (overlayWindow.barVertical) {
                    const base = target.QsWindow.mapFromItem(target, 0, (target.height - cardHeight) / 2).y;
                    card.alongBar = Math.max(margin, Math.min(base, overlayWindow.height - cardHeight - margin - 15));
                } else {
                    const base = target.QsWindow.mapFromItem(target, (target.width - cardWidth) / 2, 0).x;
                    card.alongBar = Math.max(margin, Math.min(base, overlayWindow.width - cardWidth - margin - 10));
                }

                card.width = cardWidth;
                card.openHeight = cardHeight;
                card.heroHeight = BarPopupUnroll.heroSectionHeight(content.children, popup.contentPadding);
                // The driver, written last and only here: the hero and the full
                // height it interpolates between have to be the arriving
                // popup's before the ramp can mean anything. Writing 1 while it
                // is already 1 is not a restart - Qt drops a Behavior write of
                // the value it is already animating to.
                card.openProgress = 1;
                overlayWindow.exitAnchor = overlayWindow.anchorAlongBar();
            }

            // Where the card parks: the point ALONG the bar, centred on the
            // widget the card belongs to. The coordinate across the bar is not
            // part of it - that one is derived from the card's live size, so
            // the far edges keep their bar-adjacent edge still by construction
            // rather than by two Behaviors happening to share a curve.
            function anchorAlongBar() {
                const popup = overlayWindow.current ?? overlayWindow.outgoing;
                const target = popup?.hoverTarget;
                if (!target?.QsWindow?.window) return overlayWindow.exitAnchor;

                const centre = target.QsWindow.mapFromItem(target, target.width / 2, target.height / 2);
                return (overlayWindow.barVertical ? centre.y : centre.x) - card.parkedSize / 2;
            }

            function park() {
                const anchor = overlayWindow.anchorAlongBar();
                if (anchor === null || anchor === undefined) return;
                card.animate = false;
                card.openProgress = 0;
                card.heroHeight = 0;
                card.openHeight = card.parkedSize;
                card.width = card.parkedSize;
                card.alongBar = anchor;
                card.animate = true;
                overlayWindow.exitAnchor = anchor;
            }

            // Shrink toward the owning widget and fade, on the one scalar, then
            // collapse. The collapse is not cosmetic: an opacity-0 card still
            // publishes a full-size input region and would eat every click in
            // its rectangle.
            function beginExit() {
                if (overlayWindow.exiting) return;
                // Already idle. Returning rather than collapsing again matters:
                // finishExit() vacates the slot, which re-enters here.
                if (!overlayWindow.current && !overlayWindow.outgoing
                        && card.width <= 0 && card.openHeight <= 0) return;
                if (card.width <= 0 && card.openHeight <= 0) {
                    overlayWindow.finishExit();
                    return;
                }
                const anchor = overlayWindow.anchorAlongBar();
                if (anchor === null || anchor === undefined) {
                    overlayWindow.finishExit();
                    return;
                }
                // Before the progress write, not after: the card's rest height
                // becomes the parked square's here, and at progress 1 that
                // changes nothing, so the exit starts where the card already is.
                overlayWindow.exiting = true;
                if (overlayWindow.current?.contentItem)
                    overlayWindow.current.contentItem.enabled = false;
                card.alongBar = anchor;
                card.width = card.parkedSize;
                card.openProgress = 0;
                exitTimer.restart();
            }

            function finishExit() {
                exitTimer.stop();
                contentEnter.stop();
                contentExit.stop();

                const leaving = overlayWindow.current;
                overlayWindow.release(overlayWindow.outgoing);
                overlayWindow.release(leaving);
                overlayWindow.outgoing = null;
                overlayWindow.current = null;
                overlayWindow.exiting = false;

                card.animate = false;
                card.openProgress = 0;
                card.heroHeight = 0;
                // The card's height is derived, so emptying the input region
                // means emptying what it is derived FROM: a zero open height is
                // zero at every progress.
                card.openHeight = 0;
                card.width = 0;
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

            // One timer where there were two chained ones. The shrink and the
            // fade were staged so they would not fight over the same frames;
            // riding one scalar makes them the same motion, so what is left to
            // wait for is that motion finishing. The interval is the driver's
            // own tier, which is also how the motion multiplier reaches it - a
            // Timer is one of the two things a Behavior's scaled duration does
            // not cover.
            Timer {
                id: exitTimer
                interval: Appearance.animation.elementMove.duration
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

            // Derived here for the same reason barEdge is: the card's own
            // across-the-bar coordinate is a binding now, and a binding that
            // reached through whichever popup currently holds the card would
            // re-evaluate against a null popup on every takeover.
            readonly property bool barVertical: Config.options.bar.vertical
            readonly property real barThickness: overlayWindow.barVertical
                ? Appearance.sizes.verticalBarWidth
                : Appearance.sizes.barHeight

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

                // THE driver. One `real` 0 -> 1 that the fade and the unroll
                // both ride, so they cannot disagree about where the card is in
                // its own transition. Everything derivable from it is derived,
                // never animated a second time: a second Behavior on a quantity
                // this one already carries is a second timing to keep in step,
                // and the one place they would visibly differ is mid-flight,
                // which is the only place nobody looks.
                property real openProgress: 0
                // What the card unrolls between. Assigned by retarget(), which
                // is a turn of the event loop behind the takeover because an
                // unparented tree does not polish and its implicit size is
                // stale until it does.
                property real openHeight: 0
                property real heroHeight: 0
                // The parked square on the bar, which the card grows out of and
                // collapses back into.
                readonly property real parkedSize: Appearance.sizes.elevationMargin * 2
                // The card's coordinate ALONG the bar. The only travel left:
                // the across-the-bar one is derived below.
                property real alongBar: 0

                width: 0
                height: BarPopupUnroll.cardHeight(card.openHeight, card.heroHeight,
                    card.parkedSize, overlayWindow.exiting, card.openProgress)
                // Bindings, not assignments, and that is what the driver bought.
                // On the bottom and right edges the bar-adjacent coordinate is a
                // function of the animating size, which is why this used to be
                // assigned: two Behaviors easing x and width apart put the
                // card's edge where its content is not. Deriving it from the
                // size the driver already produces cannot drift from it, and
                // neither carries a Behavior of its own, so nothing here is a
                // target that moves every frame.
                x: overlayWindow.barVertical
                    ? (overlayWindow.barEdge === "right"
                        ? overlayWindow.width - overlayWindow.barThickness - Appearance.sizes.elevationMargin - card.width
                        : overlayWindow.barThickness + Appearance.sizes.elevationMargin)
                    : card.alongBar
                y: overlayWindow.barVertical
                    ? card.alongBar
                    : (overlayWindow.barEdge === "bottom"
                        ? overlayWindow.height - overlayWindow.barThickness - Appearance.sizes.elevationMargin - card.height
                        : overlayWindow.barThickness + Appearance.sizes.elevationMargin)
                // Clamped because the spatial tier overshoots past 1 and
                // undershoots below 0 on the way back; the geometry keeps the
                // overshoot deliberately, an alpha cannot use it.
                opacity: Math.max(0, Math.min(1, card.openProgress))
                visible: width > 0 && height > 0

                color: Appearance.colors.colLayer1Base
                radius: Appearance.rounding.normal + 4
                border.width: Appearance.borderWidth.standard
                border.color: Appearance.colors.colLayer0Border

                // Every tier is taken WHOLE - duration, easing type and curve
                // together, from the tier's own component. Naming the created
                // objects is what lets `morphing` ask whether the card is still
                // travelling: the focus grab must not arm while the card is
                // still the parked square, and a Behavior does not publish its
                // own animation until after completion.
                readonly property NumberAnimation openAnim: Appearance.animation.elementMove.numberAnimation.createObject(card)
                readonly property NumberAnimation alongBarAnim: Appearance.animation.elementMove.numberAnimation.createObject(card)
                readonly property NumberAnimation widthAnim: Appearance.animation.elementMove.numberAnimation.createObject(card)

                // The only Behavior on the driver, and the one tier serves both
                // directions. A Behavior's animation cannot be swapped after
                // construction (Qt refuses the second write), so a directional
                // pair would have to be a duration and a curve written onto a
                // bare NumberAnimation - half a tier, which is silently
                // Easing.Linear the day someone drops the curve.
                Behavior on openProgress {
                    enabled: card.animate
                    animation: card.openAnim
                }
                Behavior on alongBar {
                    // See StyledPopup.contentDrivesSize: a popup animating its
                    // own size must not be chased by the card.
                    enabled: card.animate && !(overlayWindow.current?.contentDrivesSize ?? false)
                    animation: card.alongBarAnim
                }
                Behavior on width {
                    enabled: card.animate && !(overlayWindow.current?.contentDrivesSize ?? false)
                    animation: card.widthAnim
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

                    // The content's own box, held at the SETTLED height for the
                    // whole unroll and pinned to the top of the host.
                    //
                    // Centring the content in a host that is shrinking would
                    // show the middle band of it while the card is short, so the
                    // first section - the one the card opens at the height of -
                    // would be the one thing not on screen on frame one. Holding
                    // the box still is the other half: a block re-centred
                    // through every intermediate height reads as being squeezed
                    // rather than as being revealed, and it is the same reason a
                    // one-tree widget pins a fading block to its own span's box.
                    Item {
                        id: contentSlot
                        width: parent.width
                        height: Math.max(0, card.openHeight
                            - 2 * (overlayWindow.current?.contentPadding ?? 0))
                    }
                }
            }
        }
    }
}
