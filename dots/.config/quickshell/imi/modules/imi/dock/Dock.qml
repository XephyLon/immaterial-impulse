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
            visible: !GlobalStates.screenLocked

            property var monitor: WM.monitorFor(modelData)
            property bool fullscreenOnThisMonitor: WM.fullscreenOnMonitor(monitor?.name)

            property bool reveal: {
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
                // is sized by the icons along it.
                width: root.vertical ? parent.width : implicitWidth
                height: root.vertical ? implicitHeight : parent.height
                // The reveal is one number: revealed, a sliver, or one past
                // gone. Which margin it lands on is the edge's business.
                readonly property var revealOffsets: DockGeometry.revealOffsets(
                    dockRoot.dockThickness, Config.options?.dock.hoverRegionHeight ?? 2)
                readonly property real revealOffset: dockRoot.reveal
                    ? revealOffsets.revealed
                    : (Config.options?.dock.hoverToReveal
                        ? revealOffsets.peeking : revealOffsets.hidden)

                // The body hangs off the dock's INWARD side and the offset
                // grows from there, so it travels toward the screen edge to
                // leave. A dock anchored on its outward side would slide
                // further onto the screen to hide.
                readonly property string revealSide: DockGeometry.revealAnchorSide(root.edge)
                anchors {
                    top: dockMouseArea.revealSide === "top" ? parent.top : undefined
                    bottom: dockMouseArea.revealSide === "bottom" ? parent.bottom : undefined
                    left: dockMouseArea.revealSide === "left" ? parent.left : undefined
                    right: dockMouseArea.revealSide === "right" ? parent.right : undefined
                    topMargin: dockMouseArea.revealSide === "top" ? dockMouseArea.revealOffset : 0
                    bottomMargin: dockMouseArea.revealSide === "bottom" ? dockMouseArea.revealOffset : 0
                    leftMargin: dockMouseArea.revealSide === "left" ? dockMouseArea.revealOffset : 0
                    rightMargin: dockMouseArea.revealSide === "right" ? dockMouseArea.revealOffset : 0
                    horizontalCenter: root.vertical ? undefined : parent.horizontalCenter
                    verticalCenter: root.vertical ? parent.verticalCenter : undefined
                }
                implicitWidth: dockHoverRegion.implicitWidth + Appearance.sizes.elevationMargin * 2
                implicitHeight: dockHoverRegion.implicitHeight + Appearance.sizes.elevationMargin * 2
                hoverEnabled: true

                Behavior on anchors.topMargin {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on anchors.bottomMargin {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on anchors.leftMargin {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on anchors.rightMargin {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                Item {
                    id: dockHoverRegion
                    anchors.fill: parent
                    implicitWidth: dockBackground.implicitWidth
                    implicitHeight: dockBackground.implicitHeight

                    Item {
                        id: dockBackground
                        anchors {
                            top: root.vertical ? undefined : parent.top
                            bottom: root.vertical ? undefined : parent.bottom
                            left: root.vertical ? parent.left : undefined
                            right: root.vertical ? parent.right : undefined
                            horizontalCenter: root.vertical ? undefined : parent.horizontalCenter
                            verticalCenter: root.vertical ? parent.verticalCenter : undefined
                        }
                        // Along the strip the body is the icons' size plus a
                        // 5px shoulder; across it, the dock's thickness less
                        // the two margins the body's own anchors then apply.
                        implicitWidth: root.vertical
                            ? parent.width
                                - Appearance.sizes.elevationMargin
                                - Appearance.sizes.hyprlandGapsOut
                            : dockRow.implicitWidth + 5 * 2
                        implicitHeight: root.vertical
                            ? dockRow.implicitHeight + 5 * 2
                            : parent.height
                                - Appearance.sizes.elevationMargin
                                - Appearance.sizes.hyprlandGapsOut
                        width: implicitWidth
                        height: implicitHeight

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
                            anchors.top: root.vertical ? undefined : parent.top
                            anchors.bottom: root.vertical ? undefined : parent.bottom
                            anchors.left: root.vertical ? parent.left : undefined
                            anchors.right: root.vertical ? parent.right : undefined
                            anchors.horizontalCenter: root.vertical ? undefined : parent.horizontalCenter
                            anchors.verticalCenter: root.vertical ? parent.verticalCenter : undefined
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

                                GroupButton {
                                    baseWidth: 35; baseHeight: 35
                                    visible: Config.options.dock.showPinButton
                                    clickedWidth: baseWidth; clickedHeight: baseHeight + 20
                                    buttonRadius: Appearance.rounding.normal
                                    toggled: root.pinned
                                    onClicked: root.pinned = !root.pinned
                                    contentItem: MaterialSymbol {
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
                                        buttonPadding: dockRow.padding
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
                                contentItem: MaterialSymbol {
                                    anchors.fill: parent
                                    horizontalAlignment: Text.AlignHCenter
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
