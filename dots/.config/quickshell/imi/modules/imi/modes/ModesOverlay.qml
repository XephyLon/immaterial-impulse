import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

/**
 * The Modes & Routines manager, on Super+Y.
 *
 * Same shape as the usage overlay: one centred surface on the overlay layer,
 * held open by a focus grab and dismissed by anything that takes focus away.
 * The window is torn down on close, so the editor costs nothing while shut.
 * The IPC target `modes` lives in the engine; this only answers the
 * GlobalShortcuts and GlobalStates.modesOpen.
 */
Scope {
    id: root

    // The surface's lifetime: raised when the manager is asked for, dropped
    // by the exit animation's own onFinished - never by a Timer.
    property bool reallyOpen: false
    // Written back by the content as it is used, read once per opening.
    property string pendingTab: "modes"

    function resolveView() {
        root.pendingTab = Config.options.modes.lastTab || "modes";
    }

    Connections {
        target: GlobalStates

        function onModesOpenChanged() {
            if (GlobalStates.modesOpen && !root.reallyOpen) {
                root.requestOpen();
            } else if (!GlobalStates.modesOpen && root.reallyOpen) {
                root.requestClose();
            }
        }
    }

    function requestOpen() {
        root.resolveView();
        root.reallyOpen = true;
        GlobalStates.modesOpen = true;
    }

    // The window stays until dialogWrap's exit animation finishes.
    function requestClose() {
        GlobalStates.modesOpen = false;
    }

    function requestToggle() {
        if (GlobalStates.modesOpen) {
            root.requestClose();
        } else {
            root.requestOpen();
        }
    }

    Loader {
        id: modesLoader
        active: root.reallyOpen

        sourceComponent: PanelWindow {
            id: modesRoot

            visible: modesLoader.active
            color: "transparent"
            exclusiveZone: 0
            implicitWidth: modesBackground.width + Appearance.sizes.elevationMargin * 2
            implicitHeight: modesBackground.height + Appearance.sizes.elevationMargin * 2

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            WlrLayershell.namespace: "quickshell:modes"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: GlobalStates.modesOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            // Clicks outside the panel belong to whatever is underneath, and
            // once the manager is dismissed the whole surface passes input
            // through while it fades (OverlayLifecycle: the mask follows the
            // FLAG, so a leaving surface never eats a click).
            mask: Region {
                item: GlobalStates.modesOpen ? modesInputMask : null
            }

            // Blur only the card; the surface is screen-sized and transparent
            // everywhere else (rules.lua: blur = false for this namespace).
            WindowBlurRegion {
                targetWindow: modesRoot
                regionItem: modesBackground
                regionRadius: modesBackground.radius
            }

            function hide() {
                root.requestClose();
            }

            // Registering the grab immediately would catch the keypress that
            // opened the overlay and close it again.
            Timer {
                id: registerGrabTimer
                interval: 150
                onTriggered: GlobalFocusGrab.addDismissable(modesRoot)
            }

            Component.onCompleted: registerGrabTimer.start()

            Component.onDestruction: {
                registerGrabTimer.stop();
                GlobalFocusGrab.removeDismissable(modesRoot);
            }

            Connections {
                target: GlobalFocusGrab

                function onDismissed() {
                    modesRoot.hide();
                }
            }

            onVisibleChanged: {
                if (visible)
                    initialFocusTimer.restart();
            }

            Timer {
                id: initialFocusTimer
                interval: 50
                onTriggered: modesBackground.forceActiveFocus()
            }

            Item {
                id: modesInputMask
                anchors.centerIn: parent
                width: modesBackground.width
                height: modesBackground.height
            }

            Item {
                id: dialogWrap
                anchors.fill: parent
                transformOrigin: Item.Center
                // One scalar, one tier per direction: scale and opacity both
                // derive from `appear`, the enter tier brings it up when the
                // window is built, the exit tier takes it down and owns the
                // window's lifetime (M3_GUIDELINES, "Component Entrance and Exit").
                property real appear: 0
                scale: 0.94 + 0.06 * appear
                opacity: appear

                NumberAnimation {
                    id: enterAnim
                    target: dialogWrap
                    property: "appear"
                    to: 1
                    duration: Appearance.animation.elementMoveEnter.duration
                    easing.type: Appearance.animation.elementMoveEnter.type
                    easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                }
                NumberAnimation {
                    id: exitAnim
                    target: dialogWrap
                    property: "appear"
                    to: 0
                    // The fast tier, not elementMoveExit: an opacity transition
                    // with a scale nudge, not a departure across the screen
                    // (the overview's exit says why).
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    // The window's lifetime IS this animation's.
                    onFinished: root.reallyOpen = false
                }
                Component.onCompleted: enterAnim.start()
                Connections {
                    target: GlobalStates
                    function onModesOpenChanged() {
                        if (GlobalStates.modesOpen) { exitAnim.stop(); enterAnim.start(); }
                        else { enterAnim.stop(); exitAnim.start(); }
                    }
                }

                StyledRectangularShadow {
                    target: modesBackground
                }

                Rectangle {
                    id: modesBackground

                    property real padding: Appearance.spacing.space250
                    readonly property real maxBgWidth: modesRoot.screen ? modesRoot.screen.width * 0.95 : 1900
                    readonly property real maxBgHeight: modesRoot.screen ? modesRoot.screen.height * 0.80 : 1000

                    anchors.centerIn: parent
                    color: Appearance.colors.colLayer0
                    border.width: Appearance.borderWidth.standard
                    border.color: Appearance.colors.colLayer0Border
                    radius: Appearance.rounding.windowRounding
                    implicitWidth: Math.min(maxBgWidth, modesContent.implicitWidth + padding * 2)
                    implicitHeight: Math.min(maxBgHeight, modesContent.implicitHeight + padding * 2)

                    // Escape belongs to the window unless a picker is open and
                    // wants it first; everything else is the content's.
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            if (modesContent.handleEscape()) {
                                event.accepted = true;
                                return;
                            }
                            modesRoot.hide();
                            event.accepted = true;
                            return;
                        }
                        event.accepted = modesContent.handleKey(event.key, event.modifiers);
                    }

                    RippleButton {
                        id: closeButton

                        implicitWidth: 40
                        implicitHeight: 40
                        buttonRadius: Appearance.rounding.full
                        z: 2
                        onClicked: modesRoot.hide()

                        anchors {
                            top: parent.top
                            right: parent.right
                            topMargin: Appearance.spacing.space250
                            rightMargin: Appearance.spacing.space250
                        }

                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.pixelSize: Appearance.font.pixelSize.title
                            text: "close"
                            rotation: closeButton.hovered ? 90 : 0

                            Behavior on rotation {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                        }
                    }

                    ModesContent {
                        id: modesContent

                        readonly property real calculatedWidth: modesRoot.screen ? modesRoot.screen.width * 0.92 : 1700
                        readonly property real calculatedHeight: modesRoot.screen ? modesRoot.screen.height * 0.62 : 650

                        anchors.centerIn: parent
                        width: Math.min(1500, Math.max(900, calculatedWidth), parent.width - parent.padding * 2)
                        height: Math.min(700, Math.max(460, calculatedHeight), parent.height - parent.padding * 2)
                        initialTab: root.pendingTab
                        onRequestClose: modesRoot.hide()
                    }
                }
            }
        }
    }

    GlobalShortcut {
        name: "modesToggle"
        description: "Toggles the Modes & Routines overlay on press"
        onPressed: root.requestToggle()
    }

    GlobalShortcut {
        name: "modesOpen"
        description: "Opens the Modes & Routines overlay on press"
        onPressed: root.requestOpen()
    }

    GlobalShortcut {
        name: "modesClose"
        description: "Closes the Modes & Routines overlay on press"
        onPressed: root.requestClose()
    }
}
