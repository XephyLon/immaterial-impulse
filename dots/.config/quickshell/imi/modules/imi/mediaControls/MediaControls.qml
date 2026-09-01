pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.plugins.designsystem.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property bool visible: false
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property var realPlayers: MprisController.players
    readonly property var meaningfulPlayers: MprisController.meaningfulPlayers
    readonly property real osdWidth: Appearance.sizes.osdWidth
    readonly property real widgetWidth: Appearance.sizes.mediaControlsWidth
    readonly property real widgetHeight: Appearance.sizes.mediaControlsHeight
    property real popupRounding: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

    readonly property string mediaPosition: {
        if (Config.options.bar.layouts.leftLayout.includes("media")) return "left"
        if (Config.options.bar.layouts.middleLayout.includes("media")) return "center"
        if (Config.options.bar.layouts.rightLayout.includes("media")) return "right"
        return "center"
    }

    readonly property bool barVertical: Config.options.bar.vertical
    readonly property string barEdge: {
        if (!barVertical) return Config.options.bar.bottom ? "bottom" : "top"
        return Config.options.bar.bottom ? "right" : "left"
    }
    readonly property real gap: Config.options.bar.cornerStyle === 3 ? Appearance.sizes.hyprlandGapsOut : 0
    readonly property bool cornerStyleReducesGap: Config.options.bar.cornerStyle === 1 || Config.options.bar.cornerStyle === 2
    readonly property real barThickness: barVertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight

    // The cava process used to live here, gated on an expression naming every
    // surface that might want bands - this popup, the right sidebar, a bar
    // layout entry, a desktop plugin - which is how a widget written against
    // CavaService could increment a reference count nothing consulted. The
    // process is CavaService's now and each of those surfaces holds its own
    // claim; this one is the media popup's.
    CavaRef {
        active: GlobalStates.mediaControlsOpen
    }

    Loader {
        id: mediaControlsLoader
        active: GlobalStates.mediaControlsOpen
        onActiveChanged: {
            if (!mediaControlsLoader.active && root.realPlayers.length === 0) {
                GlobalStates.mediaControlsOpen = false;
            }
        }

        sourceComponent: PanelWindow {
            id: panelWindow
            visible: true

            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            implicitWidth: root.widgetWidth
            implicitHeight: playerColumnLayout.implicitHeight
            color: "transparent"
            WlrLayershell.namespace: "quickshell:mediaControls"

            anchors {
                top: true
                left: true
            }
            margins {
                top: {
                    if (root.barEdge === "top") return root.barThickness + (root.cornerStyleReducesGap ? -root.gap -6 : root.gap)
                    if (root.barEdge === "bottom") return panelWindow.screen.height - root.barThickness - (root.cornerStyleReducesGap ? -root.gap : root.gap) - playerColumnLayout.implicitHeight
                    if (root.mediaPosition === "left") return 0
                    if (root.mediaPosition === "right") return panelWindow.screen.height - playerColumnLayout.implicitHeight - root.gap
                    return (panelWindow.screen.height - playerColumnLayout.implicitHeight) / 2
                }
                left: {
                    if (root.barEdge === "left") return root.barThickness + (root.cornerStyleReducesGap ? -root.gap : root.gap)
                    if (root.barEdge === "right") return panelWindow.screen.width - root.barThickness - (root.cornerStyleReducesGap ? -root.gap : root.gap) - root.widgetWidth
                    if (root.mediaPosition === "left") return 0
                    if (root.mediaPosition === "right") return panelWindow.screen.width - root.widgetWidth - root.gap
                    return (panelWindow.screen.width - root.widgetWidth) / 2
                }
            }

            mask: Region {
                item: playerColumnLayout
            }

            Component.onCompleted: {
                if (!Config.options.bar.media.alwaysVisible)
                    GlobalFocusGrab.addDismissable(panelWindow);
            }
            Component.onDestruction: {
                if (!Config.options.bar.media.alwaysVisible)
                    GlobalFocusGrab.removeDismissable(panelWindow);
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    if (!Config.options.bar.media.alwaysVisible)
                        GlobalStates.mediaControlsOpen = false;
                }
            }

            // Auto-hide integration (issue #30): while the box is open the bar
            // stays shown (see Bar.qml mustShow). When the pointer leaves the box
            // and the bar auto-hides, close the box so the bar can hide too.
            property bool mouseInPopup: mediaControlsHoverHandler.hovered
            HoverHandler {
                id: mediaControlsHoverHandler
            }
            Timer {
                id: autoHideDismissTimer
                interval: 100
                onTriggered: {
                    if (!panelWindow.mouseInPopup)
                        GlobalStates.mediaControlsOpen = false;
                }
            }
            onMouseInPopupChanged: {
                if (Config?.options.bar.autoHide.enable && Config?.options.bar.autoHide.dismissPopups && !mouseInPopup)
                    autoHideDismissTimer.restart();
                else
                    autoHideDismissTimer.stop();
            }

            ColumnLayout {
                id: playerColumnLayout
                anchors.fill: parent
                spacing: -Appearance.sizes.elevationMargin // Shadow overlap okay

                Repeater {
                    model: ScriptModel {
                        values: root.meaningfulPlayers
                    }
                    delegate: Player {
                        required property MprisPlayer modelData
                        player: modelData
                        visualizerPoints: CavaService.values
                        maxVisualizerValue: CavaService.maxValue
                        implicitWidth: root.widgetWidth
                        implicitHeight: showLyrics ? 290 : Appearance.sizes.mediaControlsHeight
                        radius: root.popupRounding
                    }
                }

                Item {
                    // No player placeholder
                    Layout.alignment: {
                        if (panelWindow.anchors.left)
                            return Qt.AlignLeft;
                        if (panelWindow.anchors.right)
                            return Qt.AlignRight;
                        return Qt.AlignHCenter;
                    }
                    Layout.leftMargin: Appearance.sizes.hyprlandGapsOut
                    Layout.rightMargin: Appearance.sizes.hyprlandGapsOut
                    visible: root.meaningfulPlayers.length === 0
                    implicitWidth: placeholderBackground.implicitWidth + Appearance.sizes.elevationMargin
                    implicitHeight: placeholderBackground.implicitHeight + Appearance.sizes.elevationMargin

                    StyledRectangularShadow {
                        target: placeholderBackground
                    }

                    Rectangle {
                        id: placeholderBackground
                        anchors.centerIn: parent
                        color: Appearance.colors.colLayer0
                        radius: root.popupRounding
                        property real padding: Appearance.spacing.space250
                        implicitWidth: placeholderLayout.implicitWidth + padding * 2
                        implicitHeight: placeholderLayout.implicitHeight + padding * 2

                        ColumnLayout {
                            id: placeholderLayout
                            anchors.centerIn: parent

                            StyledText {
                                text: Translation.tr("No active player")
                                font.pixelSize: Appearance.font.pixelSize.large
                            }
                            StyledText {
                                color: Appearance.colors.colSubtext
                                text: Translation.tr("Make sure your player has MPRIS support\nor try turning off duplicate player filtering")
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "mediaControls"

        // Through GlobalStates, never the loader: assigning loader.active
        // directly destroys its binding to mediaControlsOpen, after which
        // the shortcuts (which set the state) do nothing and CavaRef (which
        // reads it) never arms - one IPC call left the visualizer dead and
        // the keybind inert for the session.
        function toggle(): void {
            GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen;
            if (GlobalStates.mediaControlsOpen)
                Notifications.timeoutAll();
        }

        function close(): void {
            GlobalStates.mediaControlsOpen = false;
        }

        function open(): void {
            GlobalStates.mediaControlsOpen = true;
            Notifications.timeoutAll();
        }
    }

    GlobalShortcut {
        name: "mediaControlsToggle"
        description: "Toggles media controls on press"

        onPressed: {
            GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen;
        }
    }
    GlobalShortcut {
        name: "mediaControlsOpen"
        description: "Opens media controls on press"

        onPressed: {
            GlobalStates.mediaControlsOpen = true;
        }
    }
    GlobalShortcut {
        name: "mediaControlsClose"
        description: "Closes media controls on press"

        onPressed: {
            GlobalStates.mediaControlsOpen = false;
        }
    }
}
