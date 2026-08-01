import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

DockButton {
    id: root
    property var appToplevel
    property var appListRoot
    // Shared DockContextMenu instance (provided by the dock window); falls back
    // to plain pin-toggling on right click when absent.
    property var contextMenu: null
    property int lastFocused: -1
    property real iconSize: 33
    property real countDotWidth: 10
    property real countDotHeight: 4
    property bool appIsActive: appToplevel.toplevels.find(t => (t.activated == true)) !== undefined

    readonly property bool isSeparator: appToplevel.appId === "SEPARATOR"
    property var desktopEntry: liveDeskEntry.entry
    enabled: !isSeparator
    hoverEnabled: true
    implicitWidth: isSeparator ? 1 : implicitHeight - topInset - bottomInset

    LiveDesktopEntry {
        id: liveDeskEntry
        appId: root.appToplevel.appId
    }

    Loader {
        active: isSeparator
        anchors {
            fill: parent
            topMargin: dockVisualBackground.margin + dockRow.padding + Appearance.rounding.normal
            bottomMargin: dockVisualBackground.margin + dockRow.padding + Appearance.rounding.normal
        }
        sourceComponent: DockSeparator {}
    }

    Loader {
        anchors.fill: parent
        active: appToplevel.toplevels.length > 0
        sourceComponent: MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onEntered: {
                appListRoot.lastHoveredButton = root
                appListRoot.buttonHovered = true
                lastFocused = appToplevel.toplevels.length - 1
            }
            onExited: {
                if (appListRoot.lastHoveredButton === root) {
                    appListRoot.buttonHovered = false
                }
            }
        }
    }

    onClicked: {
        if (appToplevel.toplevels.length === 0) {
            DockLaunchTracker.markLaunching(appToplevel.appId);
            root.desktopEntry?.execute();
            return;
        }
        lastFocused = (lastFocused + 1) % appToplevel.toplevels.length
        appToplevel.toplevels[lastFocused].activate()
    }

    middleClickAction: () => {
        DockLaunchTracker.markLaunching(appToplevel.appId);
        root.desktopEntry?.execute();
    }

    altAction: () => {
        if (root.contextMenu) {
            root.contextMenu.open(root, root.appToplevel);
        } else {
            TaskbarApps.togglePin(appToplevel.appId);
        }
    }

    contentItem: Loader {
        active: !isSeparator
        sourceComponent: DockIconMotion {
            id: iconMotion
            anchors.fill: parent
            hovered: root.hovered
            pressed: root.down
            launching: DockLaunchTracker.isLaunching(root.appToplevel.appId)

            Component.onCompleted: {
                if (DockLaunchTracker.firstAppearance(root.appToplevel.appId))
                    playAppear();
            }

            Item {
                anchors.centerIn: parent
                width: root.iconSize
                height: root.iconSize

                Loader {
                    id: iconImageLoader
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    active: !root.isSeparator
                    sourceComponent: IconImage {
                        source: Quickshell.iconPath(AppSearch.guessIcon(appToplevel.appId), "image-missing")
                        implicitSize: root.iconSize
                    }
                }

                Loader {
                    active: Config.options.dock.monochromeIcons
                    anchors.fill: iconImageLoader
                    sourceComponent: Item {
                        Desaturate {
                            id: desaturatedIcon
                            visible: false // There's already color overlay
                            anchors.fill: parent
                            source: iconImageLoader
                            desaturation: 0.8
                        }
                        ColorOverlay {
                            anchors.fill: desaturatedIcon
                            source: desaturatedIcon
                            color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.9)
                        }
                    }
                }

                RowLayout {
                    spacing: Appearance.spacing.space50
                    anchors {
                        top: iconImageLoader.bottom
                        topMargin: Appearance.spacing.space25
                        horizontalCenter: parent.horizontalCenter
                    }
                    Repeater {
                        model: Math.min(appToplevel.toplevels.length, 3)
                        delegate: Rectangle {
                            required property int index
                            radius: Appearance.rounding.full
                            implicitWidth: (appToplevel.toplevels.length <= 3) ?
                                root.countDotWidth : root.countDotHeight // Circles when too many
                            implicitHeight: root.countDotHeight
                            color: appIsActive ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4)
                            Behavior on implicitWidth {
                                animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                            }
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                    }
                }
            }
        }
    }
}