import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Screenshot result popup: preview + save/edit/discard. One instance, shown
 * on the focused monitor. Owns the notified file while visible: discard (and
 * timeout, for scratch files only) deletes it; save copies it to Pictures.
 */
Scope {
    id: root

    property string currentPath: ""
    property bool fileIsScratch: currentPath.startsWith(Directories.screenshotTemp)
        || currentPath.startsWith("/tmp/")
    property string editorBinary: ""

    Connections {
        target: ScreenshotEvents
        function onScreenshotTaken(path) {
            if (!(Config.options.screenshotResult?.enable ?? true)) return;
            // Replacing an existing popup discards the old file (same rules
            // as timeout).
            if (root.currentPath !== "" && root.currentPath !== path)
                root.releaseCurrent();
            root.currentPath = path;
            dismissTimer.restart();
        }
    }

    // Discard, timeout and replacement all use the same rule: scratch files
    // are deleted, user-saved files (CTRL+Print target) are always kept.
    function releaseCurrent() {
        if (root.currentPath === "") return;
        if (root.fileIsScratch)
            Quickshell.execDetached(["rm", "-f", "--", root.currentPath]);
        root.currentPath = "";
    }

    function saveCurrent() {
        if (root.currentPath === "") return;
        // Path rides as $2, the scratch flag as $3; the script text is a
        // fixed string. Scratch cleanup runs INSIDE the same script, strictly
        // after a successful copy - a separately spawned detached rm would
        // race the cp and could unlink the source before it is even opened.
        Quickshell.execDetached(["bash", "-c",
            'd="$1/Screenshots"; mkdir -p "$d"; ' +
            'n="$d/Screenshot_$(date +%Y-%m-%d_%H.%M.%S).png"; ' +
            'while [ -e "$n" ]; do n="${n%.png}_$RANDOM.png"; done; ' +
            'cp -n -- "$2" "$n" && [ "$3" = "1" ] && rm -f -- "$2"',
            "_", FileUtils.trimFileProtocol(Directories.pictures), root.currentPath,
            root.fileIsScratch ? "1" : "0"]);
        // Deletion (when due) is the script's job - just close.
        root.currentPath = "";
    }

    function editCurrent() {
        const custom = Config.options.screenshotResult?.editorCommand ?? [];
        if (root.currentPath === "" || (root.editorBinary === "" && custom.length === 0)) return;
        // A configured custom editor wins and needs no probed binary.
        const args = custom.length > 0
            ? custom.concat([root.currentPath])
            : (root.editorBinary.endsWith("satty")
                ? [root.editorBinary, "--filename", root.currentPath]
                : [root.editorBinary, "-f", root.currentPath]);
        Quickshell.execDetached(args);
        // The editor needs the file - close without deleting.
        root.currentPath = "";
    }

    // Resolve the annotation tool once: config override, else swappy, else satty.
    Process {
        id: editorProbe
        running: true
        command: ["bash", "-c", "command -v swappy satty 2>/dev/null | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: root.editorBinary = text.trim()
        }
    }

    Timer {
        id: dismissTimer
        interval: Config.options.screenshotResult?.timeoutMs ?? 6000
        onTriggered: {
            if (panelLoader.item?.hovered) { dismissTimer.restart(); return; }
            root.releaseCurrent();
        }
    }

    LazyLoader {
        id: panelLoader
        active: root.currentPath !== ""

        PanelWindow {
            id: popupWindow
            readonly property bool hovered: hoverHandler.hovered
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
            anchors { bottom: true; left: true }
            margins {
                bottom: Appearance.sizes.hyprlandGapsOut + Appearance.spacing.space200
                left: Appearance.spacing.space200
            }
            implicitWidth: content.implicitWidth
            implicitHeight: content.implicitHeight
            color: "transparent"
            WlrLayershell.namespace: "quickshell:screenshotResult"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusiveZone: 0

            Item {
                anchors.fill: parent

                HoverHandler { id: hoverHandler }

                // Re-run the entrance motion when a new screenshot replaces
                // the one on display (the window itself is not recreated).
                Connections {
                    target: root
                    function onCurrentPathChanged() {
                        if (root.currentPath !== "") enterAnimation.restart();
                    }
                }

                ColumnLayout {
                    id: content
                    anchors.centerIn: parent
                    spacing: Appearance.spacing.space100

                    Component.onCompleted: enterAnimation.restart()

                    // Entrance motion: tokens only (durations/easings come
                    // from Appearance.animation, never raw literals).
                    ParallelAnimation {
                        id: enterAnimation
                        NumberAnimation {
                            target: content; property: "opacity"; from: 0; to: 1
                            duration: Appearance.animation.elementMoveEnter.duration
                            easing.type: Appearance.animation.elementMoveEnter.type
                            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                        }
                        NumberAnimation {
                            target: content; property: "scale"; from: 0.92; to: 1
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: previewImage.paintedWidth + Appearance.spacing.space100 * 2
                        Layout.preferredHeight: previewImage.paintedHeight + Appearance.spacing.space100 * 2
                        radius: Appearance.rounding.large
                        color: Appearance.colors.colLayer0
                        border.width: Appearance.borderWidth.emphasis
                        border.color: Appearance.colors.colLayer0Border

                        Image {
                            id: previewImage
                            anchors.centerIn: parent
                            source: root.currentPath !== "" ? "file://" + root.currentPath : ""
                            sourceSize.width: 340
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            // Nested corner: container radius minus the inset so the
                            // image's rounding visually matches the card's.
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: previewImage.paintedWidth
                                    height: previewImage.paintedHeight
                                    radius: Appearance.rounding.large - Appearance.spacing.space100
                                }
                            }
                        }
                    }

                    // Action bar sits on its own translucent card so the
                    // compositor's quickshell:.* layer rule can frost it.
                    Rectangle {
                        Layout.alignment: Qt.AlignLeft
                        implicitWidth: actionRow.implicitWidth + Appearance.spacing.space100 * 2
                        implicitHeight: actionRow.implicitHeight + Appearance.spacing.space100 * 2
                        radius: Appearance.rounding.large
                        color: Appearance.colors.colLayer0
                        border.width: Appearance.borderWidth.standard
                        border.color: Appearance.colors.colLayer0Border

                        RowLayout {
                            id: actionRow
                            anchors.centerIn: parent
                            spacing: Appearance.spacing.space100

                            // Filled (secondary-container) primary actions; Discard
                            // below stays background-less per the design.
                            RippleButton {
                                buttonRadius: Appearance.rounding.normal
                                // 44: square action-button dimension (no Appearance.sizes
                                // token exists for this; matches DiscordVoicePopup's 44).
                                implicitWidth: 44; implicitHeight: 44
                                colBackground: Appearance.colors.colSecondaryContainer
                                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                                colRipple: Appearance.colors.colSecondaryContainerActive
                                onClicked: root.saveCurrent()
                                MaterialSymbol { anchors.centerIn: parent; text: "save"; iconSize: 22; color: Appearance.colors.colOnSecondaryContainer }
                                StyledToolTip { text: Translation.tr("Save to Pictures") }
                            }
                            RippleButton {
                                visible: root.editorBinary !== ""
                                    || (Config.options.screenshotResult?.editorCommand ?? []).length > 0
                                buttonRadius: Appearance.rounding.normal
                                implicitWidth: 44; implicitHeight: 44
                                colBackground: Appearance.colors.colSecondaryContainer
                                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                                colRipple: Appearance.colors.colSecondaryContainerActive
                                onClicked: root.editCurrent()
                                MaterialSymbol { anchors.centerIn: parent; text: "edit"; iconSize: 22; color: Appearance.colors.colOnSecondaryContainer }
                                StyledToolTip { text: Translation.tr("Annotate") }
                            }
                            RippleButton {
                                buttonRadius: Appearance.rounding.normal
                                implicitWidth: 44; implicitHeight: 44
                                colBackgroundHover: Appearance.colors.colErrorContainerHover
                                colRipple: Appearance.colors.colErrorContainerActive
                                onClicked: root.releaseCurrent()
                                MaterialSymbol { anchors.centerIn: parent; text: "delete"; iconSize: 22; color: Appearance.colors.colError }
                                StyledToolTip { text: Translation.tr("Discard") }
                            }
                    }
                    }
                }
            }
        }
    }
}
