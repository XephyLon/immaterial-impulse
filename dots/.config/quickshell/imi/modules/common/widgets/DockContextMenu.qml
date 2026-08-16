import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "../../imi/dock/dock_geometry.js" as DockGeometry

/**
 * Right-click context menu for dock app icons (ported from upstream
 * end-4/dots-hyprland PR #3045, adapted to this shell's conventions).
 *
 * Offers desktop-entry actions, "Open new instance", "Move to workspace",
 * pin/unpin and close-window(s). One instance is shared by the whole dock
 * (pinned and running apps); callers hand it the clicked button and the
 * TaskbarApps entry via open().
 */
Item {
    id: root

    readonly property string dockEdge: DockGeometry.normalizedEdge(
        Config.options?.dock.edge ?? "bottom")
    readonly property bool dockVertical: DockGeometry.isVertical(root.dockEdge)

    property var appToplevel: null
    // Authoritative app id for pin/launch actions. For pinned apps this is the
    // exact string stored in Config.options.dock.pinnedApps (TaskbarApps entry
    // ids are lowercased, so the entry's own id can't be used to unpin).
    property string menuAppId: ""
    property Item targetButton: null
    property alias isOpen: menuLoader.active

    readonly property var desktopEntry: liveDeskEntry.entry
    readonly property bool hasWindows: (appToplevel?.toplevels?.length ?? 0) > 0
    readonly property bool hasDesktopActions: (desktopEntry?.actions?.length ?? 0) > 0
    readonly property bool menuAppPinned: (Config.options?.dock.pinnedApps ?? [])
        .some(id => id.toLowerCase() === root.menuAppId.toLowerCase())

    // Same workspace-group math as the overview: show the current group's
    // workspaces rather than a hardcoded 1-10.
    readonly property int workspacesShown: Math.min(
        (Config.options?.overview.rows ?? 2) * (Config.options?.overview.columns ?? 5), 10)
    readonly property int workspaceGroup: Math.floor(
        ((Hyprland.focusedMonitor?.activeWorkspace?.id ?? 1) - 1) / workspacesShown)

    LiveDesktopEntry {
        id: liveDeskEntry
        appId: root.menuAppId
    }

    function open(button, appToplevelData, appId) {
        if (menuLoader.active)
            menuLoader.active = false
        targetButton = button
        appToplevel = appToplevelData
        menuAppId = appId ?? (appToplevelData?.appId ?? "")
        menuLoader.active = true
    }

    function close() {
        menuLoader.active = false
    }

    Loader {
        id: menuLoader
        active: false
        sourceComponent: PopupWindow {
            id: contextPopup
            visible: true

            // Away from the edge the dock is on: a menu that opens upward
            // from a top dock is drawn off the screen, and one that opens
            // upward from a side dock runs off the top of a tall strip.
            readonly property string openSide: DockGeometry.popupGravity(root.dockEdge)
            readonly property int openFlag: contextPopup.openSide === "top" ? Edges.Top
                : contextPopup.openSide === "bottom" ? Edges.Bottom
                : contextPopup.openSide === "left" ? Edges.Left : Edges.Right
            anchor {
                item: root.targetButton
                gravity: contextPopup.openFlag
                edges: contextPopup.openFlag
                // Slide along the screen edge the menu is running out of, not
                // along the one it opened away from.
                adjustment: root.dockVertical ? PopupAdjustment.SlideY : PopupAdjustment.SlideX
            }

            color: "transparent"
            implicitWidth: menuBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
            implicitHeight: menuBackground.implicitHeight + Appearance.sizes.elevationMargin * 2

            HyprlandFocusGrab {
                active: true
                windows: [contextPopup]
                onCleared: root.close()
            }

            StyledRectangularShadow {
                target: menuBackground
            }

            Rectangle {
                id: menuBackground
                property real contentPadding: Appearance.spacing.space50

                // The surface is the card plus an elevation margin on every
                // side, so centring IS the old "hug the side facing the dock
                // and push off it by the elevation margin" - it lands on the
                // same pixel at all four edges, and it does so without an
                // anchor that has to move to another side when the dock turns
                // (see Dock.qml's strip for what that costs).
                anchors.centerIn: parent
                color: Appearance.m3colors.m3surfaceContainer
                radius: Appearance.rounding.normal
                implicitWidth: menuColumn.implicitWidth + contentPadding * 2
                implicitHeight: menuColumn.implicitHeight + contentPadding * 2

                ColumnLayout {
                    id: menuColumn
                    anchors {
                        fill: parent
                        margins: menuBackground.contentPadding
                    }
                    spacing: 0

                    // Desktop entry actions (e.g. "New Window", "New Incognito Window")
                    Repeater {
                        model: root.hasDesktopActions ? root.desktopEntry.actions : []
                        delegate: ContextMenuItem {
                            required property var modelData
                            Layout.fillWidth: true
                            iconName: Icons.getDesktopActionMaterialSymbol(modelData.icon ?? "")
                            label: modelData.name
                            onClicked: {
                                DockLaunchTracker.markLaunching(root.menuAppId)
                                AppUsage.recordLaunch(root.desktopEntry?.id)
                                modelData.execute()
                                root.close()
                            }
                        }
                    }

                    Loader {
                        active: root.hasDesktopActions
                        visible: active
                        Layout.fillWidth: true
                        sourceComponent: ContextMenuSeparator {}
                    }

                    ContextMenuItem {
                        Layout.fillWidth: true
                        iconName: "open_in_new"
                        label: Translation.tr("Open new instance")
                        enabled: root.desktopEntry !== null
                        onClicked: {
                            DockLaunchTracker.markLaunching(root.menuAppId)
                            AppUsage.recordLaunch(root.desktopEntry?.id)
                            root.desktopEntry?.execute()
                            root.close()
                        }
                    }

                    ContextMenuSeparator {
                        Layout.fillWidth: true
                    }

                    // Move all of the app's windows to a workspace
                    Loader {
                        active: root.hasWindows
                        visible: active
                        Layout.fillWidth: true
                        sourceComponent: ColumnLayout {
                            spacing: 0

                            ContextMenuItem {
                                Layout.fillWidth: true
                                iconName: "move_item"
                                label: Translation.tr("Move to workspace")
                                enabled: false
                                pointingHandCursor: false
                            }

                            RowLayout {
                                Layout.leftMargin: Appearance.spacing.space100
                                Layout.rightMargin: Appearance.spacing.space100
                                Layout.bottomMargin: Appearance.spacing.space50
                                spacing: Appearance.spacing.space25

                                Repeater {
                                    model: root.workspacesShown
                                    delegate: RippleButton {
                                        id: wsButton
                                        required property int index
                                        readonly property int workspaceValue:
                                            root.workspaceGroup * root.workspacesShown + index + 1
                                        implicitWidth: 28
                                        implicitHeight: 28
                                        buttonRadius: Appearance.rounding.small
                                        contentItem: StyledText {
                                            anchors.centerIn: parent
                                            text: String(wsButton.workspaceValue)
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            horizontalAlignment: Text.AlignHCenter
                                            color: Appearance.m3colors.m3onSurface
                                        }
                                        onClicked: {
                                            for (const toplevel of root.appToplevel.toplevels) {
                                                const addr = toplevel.HyprlandToplevel?.address
                                                if (!addr)
                                                    continue
                                                Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${wsButton.workspaceValue}, follow = false, window = "address:0x${addr}" })`)
                                            }
                                            root.close()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    ContextMenuItem {
                        Layout.fillWidth: true
                        iconName: root.menuAppPinned ? "keep_off" : "keep"
                        label: root.menuAppPinned
                            ? Translation.tr("Unpin")
                            : Translation.tr("Pin to dock")
                        onClicked: {
                            TaskbarApps.togglePin(root.menuAppId)
                            root.close()
                        }
                    }

                    Loader {
                        active: root.hasWindows
                        visible: active
                        Layout.fillWidth: true
                        sourceComponent: ContextMenuSeparator {}
                    }

                    Loader {
                        active: root.hasWindows
                        visible: active
                        Layout.fillWidth: true
                        sourceComponent: ContextMenuItem {
                            iconName: "close"
                            label: (root.appToplevel?.toplevels?.length ?? 0) > 1
                                ? Translation.tr("Close all windows")
                                : Translation.tr("Close window")
                            onClicked: {
                                for (const toplevel of root.appToplevel.toplevels) {
                                    toplevel.close()
                                }
                                root.close()
                            }
                        }
                    }
                }
            }
        }
    }

    component ContextMenuItem: RippleButton {
        id: menuItemRoot
        property string iconName
        property string label
        implicitHeight: 36
        implicitWidth: Math.max(itemRow.implicitWidth + Appearance.spacing.space250, 180)
        buttonRadius: Appearance.rounding.small

        contentItem: RowLayout {
            id: itemRow
            anchors {
                fill: parent
                leftMargin: Appearance.spacing.space125
                rightMargin: Appearance.spacing.space175
            }
            spacing: Appearance.spacing.space100

            MaterialSymbol {
                visible: menuItemRoot.iconName !== ""
                text: menuItemRoot.iconName
                iconSize: Appearance.font.pixelSize.normal
                color: menuItemRoot.enabled
                    ? Appearance.m3colors.m3onSurface
                    : Appearance.m3colors.m3outline
                Layout.alignment: Qt.AlignVCenter
            }

            StyledText {
                Layout.fillWidth: true
                text: menuItemRoot.label
                horizontalAlignment: Text.AlignLeft
                font.pixelSize: Appearance.font.pixelSize.small
                color: menuItemRoot.enabled
                    ? Appearance.m3colors.m3onSurface
                    : Appearance.m3colors.m3outline
                elide: Text.ElideRight
            }
        }
    }

    component ContextMenuSeparator: Item {
        implicitHeight: Appearance.spacing.space100

        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: Appearance.spacing.space125
                rightMargin: Appearance.spacing.space125
            }
            implicitHeight: 1
            color: ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.7)
        }
    }
}
