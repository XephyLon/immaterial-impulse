import qs.modules.common
import qs.modules.common.plugins
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import qs
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

Scope {
    id: root

    readonly property string pluginId: "drop_shelf"
    readonly property bool shakeToSummon: PluginState.option(pluginId, "shakeToSummon", false)
    readonly property real shakeSensitivity: PluginState.option(pluginId, "shakeSensitivity", 100) / 100
    readonly property bool blurBackground: PluginState.option(pluginId, "blurBackground", true)
    readonly property real backgroundOpacity: PluginState.option(pluginId, "backgroundOpacity", 0.5)

    // Dropover-style mid-drag summon: press the bound key while dragging files
    // and the shelf materializes under the cursor to receive the drop.
    GlobalShortcut {
        name: "dropShelfSummon"
        description: "Summons the drop shelf at the cursor"
        onPressed: {
            if (GlobalStates.dropShelfOpen) GlobalStates.dropShelfOpen = false
            else DropShelf.summonAtCursor()
        }
    }

    IpcHandler {
        target: "dropShelf"

        function toggle(): void {
            if (GlobalStates.dropShelfOpen) GlobalStates.dropShelfOpen = false
            else DropShelf.summonAtCursor()
        }

        function open(): void {
            DropShelf.summonAtCursor()
        }

        function close(): void {
            GlobalStates.dropShelfOpen = false
        }
    }

    // Shake-to-summon: a helper polls the Hyprland socket for the cursor and
    // reports shakes. Wayland offers no global "drag in progress" signal, so
    // this is armed whenever enabled - the strict gesture plus auto-dismiss
    // keeps false positives harmless. Paused while locked or fullscreen.
    Process {
        id: shakeProc
        running: root.shakeToSummon
            && !GlobalStates.screenLocked
            && !HyprlandData.focusedMonitorHasFullscreen
        command: ["python3", `${Directories.scriptPath}/dropshelf/shake_detector.py`,
            "--sensitivity", `${root.shakeSensitivity}`]
        stdout: SplitParser {
            onRead: line => {
                if (!line.startsWith("SHAKE ")) return
                const parts = line.trim().split(/\s+/)
                if (parts.length < 3) return
                if (!GlobalStates.dropShelfOpen) {
                    DropShelf.openAtGlobal(parseFloat(parts[1]), parseFloat(parts[2]))
                    DropShelf.armAutoDismiss()
                }
            }
        }
        stderr: SplitParser {
            onRead: line => console.warn("[DropShelf] shake detector:", line)
        }
        onExited: (exitCode, exitStatus) => {
            // One-shot on purpose (no respawn loop; see docs/PLUGINS.md process
            // lifecycle). A clean toggle restarts it via the running binding.
            if (root.shakeToSummon)
                console.warn("[DropShelf] shake detector exited:", exitCode)
        }
    }

    LazyLoader {
        active: GlobalStates.dropShelfOpen

        component: PanelWindow {
            id: shelfWindow
            visible: true
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:dropshelf"
            color: "transparent"

            anchors { top: true; left: true }
            margins {
                left: Math.max(20, GlobalStates.dropShelfX - implicitWidth / 2)
                top: GlobalStates.dropShelfAnchorBelow
                    ? GlobalStates.dropShelfY + 10
                    : Math.max(20, GlobalStates.dropShelfY - implicitHeight - 30)
            }

            implicitWidth: 360
            implicitHeight: contentColumn.implicitHeight + 24

            DropArea {
                id: shelfDropArea
                anchors.fill: parent
                keys: ["text/uri-list"]

                onEntered: (drag) => {
                    drag.accepted = drag.hasUrls
                }

                onDropped: (drop) => {
                    if (!drop.hasUrls) {
                        drop.accepted = false
                        return
                    }
                    DropShelf.addItems(drop.urls)
                    drop.accept()
                }
            }

            // A summoned shelf auto-dismisses unless the user engages with it.
            Binding {
                target: DropShelf
                property: "autoDismissHeld"
                value: shelfDropArea.containsDrag || shelfHoverHandler.hovered
            }
            Component.onDestruction: DropShelf.autoDismissHeld = false

            StyledRectangularShadow {
                target: shelfBg
            }

            Rectangle {
                id: shelfBg
                anchors.fill: parent

                HoverHandler {
                    id: shelfHoverHandler
                }
                radius: Appearance.rounding.large
                // Translucent when frosted: the compositor blurs behind every
                // quickshell:* layer (hyprland rules.lua), so lowering the tint's
                // opacity is all "blur" takes here.
                color: root.blurBackground
                    ? ColorUtils.transparentize(Appearance.colors.colLayer0, 1 - root.backgroundOpacity)
                    : Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border

                ColumnLayout {
                    id: contentColumn
                    anchors.fill: parent
                    anchors.margins: Appearance.spacing.space150
                    spacing: Appearance.spacing.space100

                    Carousel {
                        id: shelfCarousel
                        Layout.fillWidth: true
                        Layout.preferredHeight: 140
                        showCurrentIndicator: false
                        model: DropShelf.items
                        largeItemWidthRatio: 0.42
                        mediumItemWidthRatio: 0.28
                        smallItemWidthRatio: 0.12

                        delegate: Loader {
                            id: shelfItemLoader
                            property string entryPath: modelData
                            property real fixedWidth
                            property real fixedHeight
                            sourceComponent: /\.(png|jpe?g|webp|bmp|gif)$/i.test(shelfItemLoader.entryPath)
                                ? imageDelegate
                                : fileDelegate

                            Component {
                                id: imageDelegate
                                Item {
                                    anchors.fill: parent
                                    StyledImage {
                                        id: shelfImg
                                        anchors.fill: parent
                                        source: "file://" + shelfItemLoader.entryPath
                                        fillMode: Image.PreserveAspectCrop
                                        cache: true
                                        asynchronous: true

                                        Drag.active: dragArea.drag.active
                                        Drag.dragType: Drag.Automatic
                                        Drag.mimeData: { "text/uri-list": "file://" + shelfItemLoader.entryPath }
                                        Drag.supportedActions: Qt.CopyAction

                                        MouseArea {
                                            id: dragArea
                                            anchors.fill: parent
                                            drag.target: parent
                                            cursorShape: Qt.OpenHandCursor
                                            onPressed: parent.grabToImage(() => {})
                                            onReleased: {
                                                if (parent.Drag.active) {
                                                    parent.Drag.drop()
                                                }
                                                parent.x = 0
                                                parent.y = 0
                                            }
                                        }
                                    }
                                }
                            }

                            Component {
                                id: fileDelegate
                                Item {
                                    anchors.fill: parent
                                    Rectangle {
                                        id: fileBg
                                        anchors.fill: parent
                                        color: Appearance.colors.colSurfaceContainerHighest

                                        Drag.active: fileDragArea.drag.active
                                        Drag.dragType: Drag.Automatic
                                        Drag.mimeData: { "text/uri-list": "file://" + shelfItemLoader.entryPath }
                                        Drag.supportedActions: Qt.CopyAction

                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: Appearance.spacing.space50
                                            MaterialSymbol {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: shelfItemLoader.entryPath.endsWith("/") ? "folder" : "draft"
                                                iconSize: 32
                                                color: Appearance.colors.colOnLayer1
                                            }
                                            StyledText {
                                                Layout.alignment: Qt.AlignHCenter
                                                Layout.maximumWidth: 90
                                                elide: Text.ElideMiddle
                                                text: shelfItemLoader.entryPath.split("/").pop()
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: Appearance.colors.colOnLayer1
                                            }
                                        }

                                        MouseArea {
                                            id: fileDragArea
                                            anchors.fill: parent
                                            drag.target: parent
                                            cursorShape: Qt.OpenHandCursor
                                            onReleased: {
                                                if (parent.Drag.active) {
                                                    parent.Drag.drop()
                                                }
                                                parent.x = 0
                                                parent.y = 0
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("%1 elements").arg(DropShelf.items.length)
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer0
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Appearance.spacing.space50
                        spacing: Appearance.spacing.space100

                        RippleButton {
                            Layout.fillWidth: true
                            implicitHeight: 40
                            buttonRadius: height / 2
                            colBackground: Appearance.colors.colSecondaryContainer
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                            onClicked: DropShelf.copyAll()
                            contentItem: RowLayout {
                                anchors.fill: parent
                                spacing: Appearance.spacing.space75
                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: Translation.tr("Copy")
                                    color: Appearance.colors.colOnSecondaryContainer
                                }
                            }
                        }

                        RippleButton {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignRight
                            implicitHeight: 40
                            buttonRadius: height / 2
                            colBackground: Appearance.colors.colLayer1
                            colBackgroundHover: Appearance.colors.colLayer1Hover
                            onClicked: DropShelf.clear()
                            contentItem: RowLayout {
                                anchors.fill: parent
                                spacing: Appearance.spacing.space75
                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: Translation.tr("Clear")
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                        }
                        RippleButton {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignRight
                            implicitHeight: 40
                            buttonRadius: height / 2
                            colBackground: Appearance.colors.colLayer1
                            colBackgroundHover: Appearance.colors.colLayer1Hover
                            onClicked: DropShelf.hide()
                            contentItem: RowLayout {
                                anchors.fill: parent
                                spacing: Appearance.spacing.space75
                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: Translation.tr("Close")
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
