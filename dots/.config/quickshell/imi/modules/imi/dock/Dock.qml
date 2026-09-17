import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import QtQuick.Shapes
import "dock_geometry.js" as DockGeometry

Scope {
    id: root
    property bool pinned: Config.options?.dock.pinnedOnStartup ?? false

    // Which edge the dock lives on. Everything positional derives from this
    // one value; nothing below names a side directly.
    readonly property string edge: DockGeometry.normalizedEdge(
        Config.options?.dock.edge ?? "bottom")

    // One tree, not two modules. An orientation change reflows the icons in
    // place, so icon state, hover state and DockLaunchTracker's bookkeeping
    // survive it - the bar rebuilds instead, and loses all three.
    readonly property bool vertical: DockGeometry.isVertical(root.edge)

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: dockRoot
            required property var modelData
            screen: modelData
            // The Lockscreen tab rides the lock's own teardown (spec §1.5).
            // Destroying the surface is this line's existing, deliberate cost
            // - the dock embeds no renderer - and the tab inherits it per
            // flip; holding the dock ON screen for the mode's Desktop tab
            // still goes through `reveal` below, never through this property.
            visible: !GlobalStates.screenLocked
                && !GlobalStates.editLockPreview

            property var monitor: WM.monitorFor(modelData)
            property bool fullscreenOnThisMonitor: WM.fullscreenOnMonitor(monitor?.name)

            property bool reveal: {
                // The dock is edited in place (spec §4.2), so the mode holds it
                // revealed - through this expression, which is a centre offset
                // on the content, never through the surface's `visible`. First
                // in the chain so a fullscreen window cannot hide the dock out
                // from under the user arranging it.
                if (GlobalStates.editMode)
                    return true
                if (dockContextMenu.isOpen)
                    return true
                if (fullscreenOnThisMonitor)
                    return Config.options?.dock.hoverToReveal && dockMouseArea.containsMouse
                return root.pinned
                    || (Config.options?.dock.hoverToReveal && dockMouseArea.containsMouse)
                    || activeAppsArea.requestDockShow
                    || dragSlots.requestDockShow
                    || (!ToplevelManager.activeToplevel?.activated)
            }

            // Everything positional comes from one derivation
            // (dock_geometry.js), so the four places that used to spell the
            // margin pair out by hand cannot drift apart.
            readonly property real dockThickness: DockGeometry.thickness(
                Config.options?.dock.height ?? 60,
                Appearance.sizes.elevationMargin, Appearance.sizes.hyprlandGapsOut) + dockRoot.splitRoom
            readonly property var dockMargins: DockGeometry.margins(
                root.edge, Appearance.sizes.elevationMargin, Appearance.sizes.hyprlandGapsOut)

            // The zone is the dock's own derivation (DockReservation.zone). In
            // frame mode a pinned dock also moves its whole surface in from
            // the screen edge to where the attached tab meets the frame's
            // band (DockReservation.frameOffset) - and the compositor adds
            // that anchored-edge margin to the zone by itself, so nothing
            // inside the surface moves. Floating is not a second surface
            // position: the pill lifts INSIDE the surface (splitLift below),
            // so the switch is drawn rather than reconfigured, and the zone
            // alone steps - reserving the union of where the pill is and
            // where it goes (splitZoneExtra below). Only while pinned:
            // an unpinned dock hides and reveals from the screen edge, and
            // its hover sliver has to stay AT the edge - moved in, the pointer
            // slammed to the edge would land on the band, which takes no input.
            readonly property bool reserves: root.pinned && !fullscreenOnThisMonitor
            exclusiveZone: dockRoot.reserves ? DockReservation.zone + dockRoot.splitZoneExtra : 0
            readonly property var frameMargins: DockGeometry.directedSides(
                root.edge, 0, dockRoot.reserves ? DockReservation.frameOffset : 0)
            margins {
                top: dockRoot.frameMargins.top
                bottom: dockRoot.frameMargins.bottom
                left: dockRoot.frameMargins.left
                right: dockRoot.frameMargins.right
            }
            // Attached, the pill is a tab of the band: the band's colour, no
            // border, its outward corners squared at the seam; the blur region
            // stays (the bar plate in the same colour is blurred, and the tab
            // has to read as that plate, not as unfrosted translucency).
            // Unpinned too, while the band is the gap: an unpinned dock sits a
            // gap from the edge, so on the default band a rounded, bordered
            // pill there rested on the band like a pill on a line, and as a
            // tab it comes out of the band and slides back into it. On any
            // other band an unpinned dock cannot be moved to meet it (its
            // hover sliver has to stay at the edge), so it keeps the pill.
            readonly property bool attached: DockReservation.attached && !fullscreenOnThisMonitor
                && (dockRoot.reserves || DockReservation.frameOffset === 0)

            // The attached <-> floating switch is the split
            // (docs/proposals/motion-split.md §6): the band is the island
            // and the pill is the child, attached is the joined state, and
            // the pill is the one body that travels. ONE scalar per
            // direction - 0 fused, 1 apart - on the split tier taken whole,
            // whose curve accelerates into the seam (0.5) and decelerates
            // out of it. Every other piece of the motion below (the lift,
            // the corners, the neck, the look, the zone) is a function of
            // this number, never a second animation that has to agree with
            // it. Driven by the CONFIGURED choice (`splitTarget`): the
            // fullscreen term in `attached` is a state the user never
            // toggled, and following it replayed a landing on every
            // fullscreen exit.
            //
            // The pause is the reference's sequencing: effects and space
            // never overlap. On a LANDING from rest (target 0, the pill
            // fully apart) the look lands first - the tab's colour, no
            // border, on the effects tier - and only then does the outline
            // move; on a lift there is nothing to wait for, since the look
            // changes after the pill has landed apart (attachedLook below),
            // and neither is there on a lift reversed mid-flight, whose look
            // is still the tab's - a pause there parked the pill in the air.
            // Read off the Behavior's own target, which is set before the
            // animation starts, and the scalar's live value, rather than off
            // a binding that may not have re-evaluated yet. The tier is
            // written out rather than taken from its factory because the
            // pause is direction-dependent and a factory cannot carry one;
            // the three properties are the tier's, whole.
            //
            // The target is the frame option and the PIN: pinning a floating
            // dock is a lift off the band (the travel appears, and the scalar
            // is at 0), not a jump to a lifted pill. Never `reserves`, which
            // folds in the fullscreen term - a scalar on it replayed the lift
            // on every fullscreen exit; fullscreen reaches the lift through
            // the travel alone, while the dock is hidden.
            readonly property real splitTarget: FrameGeometry.enabled && root.pinned && !DockReservation.attached ? 1 : 0
            property real splitProgress: dockRoot.splitTarget
            // Whether the lift under way began as the TAB. A pinned attached
            // dock going floating splits: tab look until it has landed
            // apart, a neck at the seam. A floating dock being pinned, or
            // the frame switching on under a floating one, rises too - the
            // travel appears - but nothing was fused: it rises as the pill
            // it already is, no neck, corners round. Decided at the target's
            // rising edge from WHAT ROSE IT: the option (pin and frame both
            // as they were at the last edge) means a tab is on screen;
            // anything else means a pill. Not from the look itself, whose
            // own terms re-evaluate on the same edge in an order nothing
            // orders - read that way, the old latch fed itself back.
            property bool liftFromTab: true
            property bool pinnedAtLastEdge: root.pinned
            property bool framedAtLastEdge: FrameGeometry.enabled
            onSplitTargetChanged: {
                if (dockRoot.splitTarget === 1)
                    dockRoot.liftFromTab = root.pinned === dockRoot.pinnedAtLastEdge
                        && FrameGeometry.enabled === dockRoot.framedAtLastEdge;
                dockRoot.pinnedAtLastEdge = root.pinned;
                dockRoot.framedAtLastEdge = FrameGeometry.enabled;
            }
            Behavior on splitProgress {
                id: splitBehavior
                // No lift, no spatial tier: an unpinned dock at the default
                // band, or the frame switching off, changes its LOOK and
                // that runs on the effects tier alone (lookApart below).
                enabled: dockRoot.splitTravel > 0
                SequentialAnimation {
                    PauseAnimation { duration: splitBehavior.targetValue === 0 && dockRoot.splitProgress >= 1 ? Appearance.animation.elementMoveFast.duration : 0 }
                    NumberAnimation {
                        duration: Appearance.animation.split.duration
                        easing.type: Appearance.animation.split.type
                        easing.bezierCurve: Appearance.animation.split.bezierCurve
                    }
                }
            }
            // The lift: the compositor's gap - the distance between "on the
            // band" and "a gap above it" - while the dock reserves its edge.
            // An unpinned dock never lifts (its hover sliver stays at the
            // edge), so at the default band it takes the look change alone.
            readonly property real splitTravel: DockGeometry.splitTravel(FrameGeometry.enabled, dockRoot.reserves, Appearance.sizes.hyprlandGapsOut)
            readonly property real splitLift: dockRoot.splitTravel * dockRoot.splitProgress
            // The pill lifts into its own inward elevation margin; a gap bigger
            // than that margin grows the strip by the shortfall (nothing at
            // the defaults) so the lifted pill stays inside its surface.
            readonly property real splitRoom: DockGeometry.splitRoom(Appearance.sizes.hyprlandGapsOut, Appearance.sizes.elevationMargin)
            // What the zone reserves beyond the attached one: the lift, while
            // the pill is up or asked to go up - a boolean that flips at the
            // start of a lift and the end of a landing, so windows are never
            // against a floating pill and the compositor re-tiles twice per
            // gesture at most, on its own animation.
            readonly property real splitZoneExtra: DockGeometry.splitZoneExtra(dockRoot.splitTravel, dockRoot.splitTarget === 1, dockRoot.splitProgress)
            // The look is the tab's until the pill has landed apart: on a
            // lift the colour and the border change AFTER the motion, on the
            // effects tier; on a landing `attached` flips first and the pause
            // above holds the outline for that tier's length. With no lift
            // the look IS the switch: `attached` alone, on the effects tier,
            // corners included, through a scalar of its own.
            readonly property bool attachedLook: dockRoot.splitTravel > 0 ? (dockRoot.attached || (dockRoot.splitProgress < 1 && dockRoot.liftFromTab)) : dockRoot.attached
            property real lookApart: dockRoot.attached ? 0 : 1
            Behavior on lookApart {
                // Read only while there is no lift; idle otherwise.
                enabled: dockRoot.splitTravel <= 0
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            readonly property real apart: dockRoot.splitTravel > 0 ? dockRoot.splitProgress : dockRoot.lookApart
            // The icons ride the pill: the strip is centred in the box and
            // the pill, lifted, is not.
            readonly property var liftOffset: DockGeometry.liftOffset(root.edge, dockRoot.splitRoom, dockRoot.splitLift)

            anchors {
                top: DockGeometry.anchors(root.edge).top
                bottom: DockGeometry.anchors(root.edge).bottom
                left: DockGeometry.anchors(root.edge).left
                right: DockGeometry.anchors(root.edge).right
            }
            WlrLayershell.namespace: "quickshell:dock"
            color: "transparent"

            // The thickness lands on whichever axis the anchors left free;
            // the other one is spanned and the compositor ignores what is
            // asked for there.
            implicitWidth: root.vertical ? dockRoot.dockThickness : dockBackground.implicitWidth
            implicitHeight: root.vertical ? dockBackground.implicitHeight : dockRoot.dockThickness

            mask: Region { item: dockMouseArea }

            // Blur only the painted dock body — its surface carries an
            // elevation margin for the drop shadow, and the whole-surface
            // layerrule blur frosted that margin too (#82). Same treatment as
            // the bar/sidebars; pairs with rules.lua turning the layerrule
            // blur off for this namespace. No region when the background
            // isn't painted: blurring a transparent rect frosts bare
            // wallpaper. Per-corner radii, the bar's centre pill's pattern:
            // attached to the frame the pill squares its outward corners.
            // Published only while the pill is AT REST: Quickshell's Region
            // re-evaluates on its item's own x/y/width/height, and the dock
            // hides by offsetting an ancestor (dockMouseArea's centre offset),
            // which the pill never sees - so a hidden dock left a frosted
            // silhouette over the window where the pill rests. The frost lands
            // when the pill has arrived and lifts the instant it starts to go.
            WindowBlurRegion {
                targetWindow: dockRoot
                region: Region {
                    item: Config.options.dock.showBackground && dockMouseArea.atRest ? dockVisualBackground : null
                    topLeftRadius: dockVisualBackground.topLeftRadius
                    topRightRadius: dockVisualBackground.topRightRadius
                    bottomLeftRadius: dockVisualBackground.bottomLeftRadius
                    bottomRightRadius: dockVisualBackground.bottomRightRadius
                }
            }

            DockContextMenu {
                id: dockContextMenu
            }

            MouseArea {
                id: dockMouseArea
                // The strip fills the dock's thickness across its own axis and
                // is sized by the icons along it. Across the axis that is
                // exactly the surface, so centring is the same placement the
                // reveal anchor used to give - with a membership that never
                // changes.
                readonly property var box: DockGeometry.contentBox(
                    root.edge, dockRoot.dockThickness, implicitWidth, implicitHeight)
                width: box.width
                height: box.height

                // The reveal is one number: revealed, a sliver, or one past
                // gone. Which way it travels is the edge's business.
                readonly property var revealOffsets: DockGeometry.revealOffsets(
                    dockRoot.dockThickness, Config.options?.dock.hoverRegionHeight ?? 2)
                readonly property real revealOffset: dockRoot.reveal
                    ? revealOffsets.revealed
                    : (Config.options?.dock.hoverToReveal
                        ? revealOffsets.peeking : revealOffsets.hidden)
                // Toward the screen edge the dock is on, so it travels off the
                // screen to leave. A push the other way would slide it
                // further ONTO the screen to hide.
                readonly property real revealPush: dockMouseArea.revealOffset
                    * DockGeometry.hideDirection(root.edge)

                // The strip used to anchor to its inward side and grow that
                // margin to push itself out, which means the anchor moves to
                // another side when the dock turns. During the turn the new
                // side and the old centre anchor are both live on ONE axis,
                // and Qt answers `right` + `horizontalCenter` by WRITING the
                // item's width (2 * (right - hcenter)) - measured at 5120 on
                // a surface that was already 75 wide. That write outlives the
                // binding it clobbered, because `box` has finished changing
                // by then and never re-evaluates. Centre at every edge and
                // push with an offset instead: same placement, one membership.
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: root.vertical ? dockMouseArea.revealPush : 0
                anchors.verticalCenterOffset: root.vertical ? 0 : dockMouseArea.revealPush

                implicitWidth: dockHoverRegion.implicitWidth + Appearance.sizes.elevationMargin * 2
                implicitHeight: dockHoverRegion.implicitHeight + Appearance.sizes.elevationMargin * 2
                hoverEnabled: true

                Behavior on anchors.horizontalCenterOffset {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on anchors.verticalCenterOffset {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                // The ANIMATED offsets, not revealOffset: at rest means the
                // slide has finished, for the blur region above.
                readonly property bool atRest: anchors.horizontalCenterOffset === 0 && anchors.verticalCenterOffset === 0

                Item {
                    id: dockHoverRegion
                    anchors.fill: parent
                    implicitWidth: dockBackground.implicitWidth
                    implicitHeight: dockBackground.implicitHeight

                    Item {
                        id: dockBackground
                        // One anchor at every edge, because the turn is a
                        // change of size rather than of anchors. The body used
                        // to anchor both ends of its across axis and centre on
                        // the other, which means the SET of anchors changes
                        // when the dock turns - and Qt refuses the moment when
                        // left, right and horizontalCenter are all live rather
                        // than re-applying once the third clears. It kept both
                        // orientations' anchors and filled the surface in both
                        // axes: a full-screen pill with the icons spread over
                        // 5120px, of which a side edge shows 75.
                        anchors.centerIn: parent

                        // The dock's whole thickness across its own axis - the
                        // visual background insets the two margins out of it -
                        // and the icons plus a 5px shoulder along the strip.
                        readonly property var box: DockGeometry.contentBox(
                            root.edge, dockRoot.dockThickness,
                            dockRow.implicitWidth + 5 * 2,
                            dockRow.implicitHeight + 5 * 2)
                        implicitWidth: box.width
                        implicitHeight: box.height
                        width: box.width
                        height: box.height

                        StyledRectangularShadow {
                            target: dockVisualBackground
                            visible: false
                        }

                        // The neck (motion-split.md §2): a same-colour bridge
                        // between the pill's outward edge and the band from
                        // the seam to the pinch-off, its waist narrowing to
                        // nothing, its flanks two concave fillets hugging the
                        // band and the waist. One Shape on one path from the
                        // module, no layer; boxed, never anchored - the turn
                        // is a size, and an anchor set that changes with the
                        // edge is the trap the strip already paid for. Under
                        // the pill, so the pill's own edge is what the eye
                        // reads. Up to the seam the waist is the pill's full
                        // width: the fused outline stretching as the pill
                        // lifts, which is the reference's swell.
                        Shape {
                            id: splitNeck
                            readonly property real pillAlong: root.vertical ? dockVisualBackground.height : dockVisualBackground.width
                            readonly property real waist: DockGeometry.neckWaist(splitNeck.pillAlong, dockRoot.splitProgress, Appearance.animation.splitSeam, Appearance.animation.splitNeckReach)
                            readonly property real fillet: DockGeometry.neckFilletSize(dockRoot.splitLift, splitNeck.pillAlong, splitNeck.waist)
                            readonly property var box: DockGeometry.neckBox(root.edge,
                                { x: dockVisualBackground.x, y: dockVisualBackground.y,
                                  width: dockVisualBackground.width, height: dockVisualBackground.height },
                                dockRoot.splitLift, splitNeck.waist, splitNeck.fillet)
                            // Drawn for a split (a lift that began as the tab) and
                            // for every landing; a pill that was never fused rises
                            // without one.
                            visible: Config.options.dock.showBackground && dockRoot.splitLift > 0 && splitNeck.waist > 0
                                && (dockRoot.liftFromTab || dockRoot.splitTarget === 0)
                            x: box.x
                            y: box.y
                            width: box.width
                            height: box.height
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                strokeWidth: 0
                                fillColor: FrameGeometry.color
                                PathSvg { path: DockGeometry.neckPath(root.edge, splitNeck.waist, root.vertical ? splitNeck.width : splitNeck.height, splitNeck.fillet) }
                            }
                        }

                        Rectangle {
                            id: dockVisualBackground
                            property real margin: Appearance.sizes.elevationMargin
                            // The pill's own margins carry the lift (outward
                            // grows, inward shrinks, the sum is the thickness),
                            // so the blur region - which tracks its item's OWN
                            // geometry - rides the motion, and the frost lands
                            // with the pill rather than a beat after it.
                            readonly property var pillMargins: DockGeometry.liftedMargins(root.edge, dockRoot.dockMargins, dockRoot.splitRoom, dockRoot.splitLift)
                            anchors.fill: parent
                            anchors.topMargin:    pillMargins.top
                            anchors.bottomMargin: pillMargins.bottom
                            anchors.leftMargin:   pillMargins.left
                            anchors.rightMargin:  pillMargins.right
                            color: !Config.options.dock.showBackground ? "transparent"
                                   : dockRoot.attachedLook ? FrameGeometry.color : Appearance.colors.colLayer0
                            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                            border.width: Config.options.dock.showBackground && !dockRoot.attachedLook ? Appearance.borderWidth.standard : 0
                            Behavior on border.width { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                            border.color: Appearance.colors.colLayer0Border
                            // `large`: the tab's inward corners sit next to the
                            // fillets and the bar plate's corners in frame mode,
                            // so the pill's radius is a design value, not a sum.
                            radius: Appearance.rounding.large
                            // The outward pair rounds from the seam, where the
                            // outlines part, to rest: square while fused, a
                            // pill once apart. With no lift, over the look's
                            // own scalar.
                            readonly property var frameRadii: DockGeometry.cornerRadiiAt(root.edge, radius,
                                dockRoot.liftFromTab || dockRoot.splitTarget === 0 ? dockRoot.apart : 1,
                                dockRoot.splitTravel > 0 ? Appearance.animation.splitSeam : 0)
                            topLeftRadius:     frameRadii.topLeft
                            topRightRadius:    frameRadii.topRight
                            bottomLeftRadius:  frameRadii.bottomLeft
                            bottomRightRadius: frameRadii.bottomRight
                        }

                        // A GridLayout with a flow rather than a RowLayout, so
                        // the strip turns without the children being destroyed
                        // and rebuilt: one tree, per the spec's §9 Q2. Its id
                        // and its `padding` are reached by DYNAMIC SCOPE from
                        // DockSeparator and DockAppButton - renaming either
                        // yields undefined and NaN geometry, with no error.
                        GridLayout {
                            id: dockRow
                            flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                            // Same reasoning as the body above: the strip is
                            // centred at every edge and takes its size from
                            // the module, so no anchor has to appear or
                            // disappear when the dock turns.
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: dockRoot.liftOffset.x
                            anchors.verticalCenterOffset: dockRoot.liftOffset.y
                            readonly property var box: DockGeometry.contentBox(
                                root.edge, dockRoot.dockThickness,
                                implicitWidth, implicitHeight)
                            width: box.width
                            height: box.height
                            rowSpacing: Appearance.spacing.space50
                            columnSpacing: Appearance.spacing.space50
                            property real padding: Appearance.spacing.space100
                            property bool hasPinnedApps: (Config.options?.dock.pinnedApps?.length ?? 0) > 0

                            VerticalButtonGroup {
                                // space50 across the dock's thickness, the
                                // compositor's gap at both ends of the strip.
                                readonly property var pinMargins: DockGeometry.axisMargins(
                                    root.edge, Appearance.spacing.space50, 0,
                                    root.pinned
                                        ? Appearance.sizes.hyprlandGapsOut + 4
                                        : Appearance.sizes.hyprlandGapsOut)
                                Layout.topMargin: pinMargins.top
                                Layout.bottomMargin: pinMargins.bottom
                                Layout.leftMargin: pinMargins.left
                                Layout.rightMargin: pinMargins.right
                                // A layout item that does not fill defaults to
                                // AlignLeft, which at a vertical edge is the
                                // OUTWARD side: the pin hung half off the
                                // painted body. Everything else in the strip
                                // fills its cross axis and never showed it.
                                Layout.alignment: Qt.AlignCenter

                                GroupButton {
                                    baseWidth: 35; baseHeight: 35
                                    visible: Config.options.dock.showPinButton
                                    // The press stretches along the strip, so
                                    // the grown edge is the one the strip runs
                                    // in - at a side edge that is the width.
                                    clickedWidth: root.vertical ? baseWidth + 20 : baseWidth
                                    clickedHeight: root.vertical ? baseHeight : baseHeight + 20
                                    buttonRadius: Appearance.rounding.normal
                                    toggled: root.pinned
                                    onClicked: root.pinned = !root.pinned
                                    contentItem: MaterialSymbol {
                                        verticalAlignment: Text.AlignVCenter
                                        text: "keep"
                                        horizontalAlignment: Text.AlignHCenter
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: root.pinned
                                               ? Appearance.m3colors.m3onPrimary
                                               : Appearance.colors.colOnLayer0
                                    }
                                }
                            }

                            DockSeparator {
                                // dockMedia.visible, not the showMedia option:
                                // the tile is absent at a vertical edge and a
                                // separator that reads the option instead of
                                // the tile hides against nothing.
                                visible: Config.options.dock.showPinButton
                                    && (dockRow.hasPinnedApps
                                        || !(dockMedia.visible && dockMedia.hasTrack))
                            }

                            DragApps {
                                id: dragSlots
                                visible: dockRow.hasPinnedApps
                                // space25 across the thickness; the negative
                                // margin is a pull-in at the LEADING end of the
                                // strip, closing the gap an absent pin button
                                // leaves - so it is not the symmetric pair
                                // axisMargins() hands out.
                                readonly property var slotInset: DockGeometry.directedSides(
                                    root.edge, Appearance.spacing.space25, 0)
                                readonly property real slotPull: Config.options.dock.showPinButton
                                    ? 0 : -Appearance.spacing.space200
                                Layout.fillHeight: false
                                Layout.fillWidth: false
                                Layout.topMargin: root.vertical ? slotPull : slotInset.top
                                Layout.bottomMargin: root.vertical ? 0 : slotInset.bottom
                                Layout.leftMargin: root.vertical ? slotInset.left : slotPull
                                Layout.rightMargin: root.vertical ? slotInset.right : 0
                                pinnedApps:    Config.options?.dock.pinnedApps ?? []
                                contextMenu:   dockContextMenu
                                buttonPadding: dockRow.padding
                                btnSize:       46
                                btnSpacing:    1
                            }

                            DockSeparator {
                                visible: dockRow.hasPinnedApps
                                    && (activeAppsArea.activeUnpinned.length > 0
                                        || (dockMedia.visible && MprisController.activePlayer !== null))
                            }

                            Item {
                                id: activeAppsArea
                                Layout.fillHeight: !root.vertical
                                Layout.fillWidth: root.vertical
                                Layout.topMargin: 0
                                Layout.leftMargin: 0
                                property bool requestDockShow: false

                                property var activeUnpinned: {
                                    return TaskbarApps.apps.filter(
                                        a => !a.pinned
                                          && a.appId !== "SEPARATOR"
                                          && a.toplevels.length > 0
                                    )
                                }
                                property bool hasActiveUnpinned: activeUnpinned.length > 0 || dockMedia.visible

                                implicitWidth:  root.vertical ? parent.width : activeRow.implicitWidth
                                implicitHeight: root.vertical ? activeRow.implicitHeight : parent.height

                                Behavior on implicitWidth {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                                Behavior on implicitHeight {
                                    enabled: root.vertical
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }

                                GridLayout {
                                    id: activeRow
                                    anchors.fill: parent
                                    flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                                    rowSpacing: -Appearance.spacing.space50
                                    columnSpacing: -Appearance.spacing.space50

                                    DockMedia {
                                        id: dockMedia
                                        // A 240x60 card has no 60x240 form.
                                        // The vertical dock omits it the way
                                        // the vertical bar omits what does not
                                        // fit; a richer vertical media tile is
                                        // its own spec (§9 Q1).
                                        visible: Config.options.dock.showMedia && !root.vertical
                                        Layout.fillHeight: true
                                        Layout.topMargin: Appearance.spacing.space150
                                        Layout.bottomMargin: Appearance.spacing.space100
                                        Layout.leftMargin: 0
                                    }

                                    Repeater {
                                        model: activeAppsArea.activeUnpinned
                                        delegate: DockAppButton {
                                            required property var modelData
                                            appToplevel: modelData
                                            appListRoot: appListBridge
                                            contextMenu: dockContextMenu
                                            crossMargin: Appearance.spacing.space25
                                            insetInward:  dockRow.padding + Appearance.spacing.space100
                                            insetOutward: dockRow.padding + Appearance.spacing.space100
                                        }
                                    }
                                }

                                QtObject {
                                    id: appListBridge
                                    property Item lastHoveredButton: null
                                    property bool buttonHovered: false
                                }
                            }

                            DockSeparator {
                                visible: Config.options.dock.showAppsButton
                            }

                            DockButton {
                                crossMargin: 0
                                visible: Config.options.dock.showAppsButton
                                onClicked: GlobalStates.overviewOpen = !GlobalStates.overviewOpen
                                insetInward:  dockRow.padding + 10
                                insetOutward: dockRow.padding + 7
                                // Centred in what is PAINTED, not in the item:
                                // the insets are asymmetric (they compensate
                                // the body's elevation-vs-gap margins), so a
                                // glyph filling the whole rect sits off-centre
                                // by half their difference. Vertically nobody
                                // saw it; at a side edge it reads as a glyph
                                // pushed sideways.
                                contentItem: MaterialSymbol {
                                    anchors.fill: parent
                                    anchors.topMargin: parent.topInset
                                    anchors.bottomMargin: parent.bottomInset
                                    anchors.leftMargin: parent.leftInset
                                    anchors.rightMargin: parent.rightInset
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: Math.min(parent.width, parent.height) / 2
                                    text: "apps"
                                    color: Appearance.colors.colOnLayer0
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
