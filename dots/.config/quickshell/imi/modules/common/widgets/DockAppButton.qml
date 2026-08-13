import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../imi/dock/dock_geometry.js" as DockGeometry

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

    // A separator is a hairline ACROSS the strip, so which axis it collapses
    // on is the dock's business, not the button's.
    implicitWidth: root.dockVertical
        ? root.span + leftInset + rightInset
        : (root.isSeparator ? 1 : root.span)
    implicitHeight: root.dockVertical
        ? (root.isSeparator ? 1 : root.span)
        : root.span + topInset + bottomInset

    LiveDesktopEntry {
        id: liveDeskEntry
        appId: root.appToplevel.appId
    }

    Loader {
        active: isSeparator
        // dockVisualBackground and dockRow resolve by DYNAMIC SCOPE through the
        // dock's own tree - renaming or reparenting either yields undefined and
        // NaN geometry rather than an error. Read AGENT.md's note on the CPU
        // spin that follows before restructuring anything above this.
        readonly property var separatorMargins: DockGeometry.axisMargins(
            root.dockEdge,
            dockVisualBackground.margin + dockRow.padding + Appearance.rounding.normal,
            dockVisualBackground.margin + dockRow.padding + Appearance.rounding.normal,
            0)
        anchors {
            fill: parent
            topMargin: separatorMargins.top
            bottomMargin: separatorMargins.bottom
            leftMargin: separatorMargins.left
            rightMargin: separatorMargins.right
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

                Flow {
                    spacing: Appearance.spacing.space50
                    // The running dots sit between the icon and the screen
                    // edge, so they swap sides with the dock: below the icon
                    // at the bottom edge, above it at the top, and BESIDE it
                    // at either side edge - where a row under the icon points
                    // into its neighbour rather than out of the dock.
                    readonly property string dotSide: DockGeometry.outwardSide(root.dockEdge)
                    flow: root.dockVertical ? Flow.TopToBottom : Flow.LeftToRight
                    anchors {
                        top: dotSide === "bottom" ? iconImageLoader.bottom : undefined
                        bottom: dotSide === "top" ? iconImageLoader.top : undefined
                        left: dotSide === "right" ? iconImageLoader.right : undefined
                        right: dotSide === "left" ? iconImageLoader.left : undefined
                        topMargin: dotSide === "bottom" ? Appearance.spacing.space25 : 0
                        bottomMargin: dotSide === "top" ? Appearance.spacing.space25 : 0
                        leftMargin: dotSide === "right" ? Appearance.spacing.space25 : 0
                        rightMargin: dotSide === "left" ? Appearance.spacing.space25 : 0
                        horizontalCenter: root.dockVertical ? undefined : parent.horizontalCenter
                        verticalCenter: root.dockVertical ? parent.verticalCenter : undefined
                    }
                    Repeater {
                        model: Math.min(appToplevel.toplevels.length, 3)
                        delegate: Rectangle {
                            required property int index
                            // The pill runs ALONG the strip and stays thin
                            // across it, so it reads as an underline at every
                            // edge. Circles when there are too many to count.
                            readonly property real pillLength: (appToplevel.toplevels.length <= 3)
                                ? root.countDotWidth : root.countDotHeight
                            radius: Appearance.rounding.full
                            implicitWidth: root.dockVertical ? root.countDotHeight : pillLength
                            implicitHeight: root.dockVertical ? pillLength : root.countDotHeight
                            color: appIsActive ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4)
                            Behavior on implicitWidth {
                                animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                            }
                            Behavior on implicitHeight {
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