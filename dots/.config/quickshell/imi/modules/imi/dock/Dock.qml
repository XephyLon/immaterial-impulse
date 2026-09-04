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
                Appearance.sizes.elevationMargin, Appearance.sizes.hyprlandGapsOut)
            readonly property var dockMargins: DockGeometry.margins(
                root.edge, Appearance.sizes.elevationMargin, Appearance.sizes.hyprlandGapsOut)

            exclusiveZone: (root.pinned && !fullscreenOnThisMonitor)
                ? DockGeometry.exclusiveZone(
                    Config.options?.dock.height ?? 60,
                    Appearance.sizes.elevationMargin, Appearance.sizes.hyprlandGapsOut)
                : 0

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
            // wallpaper.
            WindowBlurRegion {
                targetWindow: dockRoot
                regionItem: Config.options.dock.showBackground ? dockVisualBackground : null
                regionRadius: dockVisualBackground.radius
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

                        Rectangle {
                            id: dockVisualBackground
                            property real margin: Appearance.sizes.elevationMargin
                            anchors.fill: parent
                            anchors.topMargin:    dockRoot.dockMargins.top
                            anchors.bottomMargin: dockRoot.dockMargins.bottom
                            anchors.leftMargin:   dockRoot.dockMargins.left
                            anchors.rightMargin:  dockRoot.dockMargins.right
                            color: Config.options.dock.showBackground
                                   ? Appearance.colors.colLayer0 : "transparent"
                            border.width: Config.options.dock.showBackground ? 1 : 0
                            border.color: Appearance.colors.colLayer0Border
                            radius: Appearance.rounding.normal + 6
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
