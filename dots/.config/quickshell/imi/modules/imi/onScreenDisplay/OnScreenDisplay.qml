import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property string protectionMessage: ""
    property var focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name)

    property string currentIndicator: "volume"
    property var indicators: [
        {
            id: "volume",
            sourceUrl: "indicators/VolumeIndicator.qml"
        },
        {
            id: "brightness",
            sourceUrl: "indicators/BrightnessIndicator.qml"
        },
        {
            id: "gamma",
            sourceUrl: "indicators/GammaIndicator.qml"
        },
        {
            id: "clightTemperature",
            sourceUrl: "indicators/ClightTemperatureIndicator.qml"
        },
        {
            id: "keyboardLayout",
            sourceUrl: "indicators/KeyboardLayoutIndicator.qml"
        },
        {
            id: "audioOutput",
            sourceUrl: "indicators/AudioOutputIndicator.qml"
        },
        {
            id: "audioInput",
            sourceUrl: "indicators/AudioInputIndicator.qml"
        },
        {
            id: "capsLock",
            sourceUrl: "indicators/CapsLockIndicator.qml"
        },
        {
            id: "numLock",
            sourceUrl: "indicators/NumLockIndicator.qml"
        },
    ]

    function triggerOsd() {
        GlobalStates.osdVolumeOpen = true;
        osdTimeout.restart();
    }

    Timer {
        id: osdTimeout
        interval: Config.options.osd.timeout
        repeat: false
        running: false
        onTriggered: {
            GlobalStates.osdVolumeOpen = false;
            root.protectionMessage = "";
        }
    }

    Connections {
        target: Brightness
        function onBrightnessChanged() {
            root.protectionMessage = "";
            root.currentIndicator = "brightness";
            root.triggerOsd();
        }
    }

    Connections {
        target: Hyprsunset
        function onGammaChangeAttempt() {
            root.protectionMessage = "";
            root.currentIndicator = "gamma";
            root.triggerOsd();
        }
    }

    Connections {
        // Clight only signals a Temp change the daemon made after its first
        // report (day/night transitions), so this cannot fire at startup.
        target: Clight
        function onTemperatureChangedByDaemon() {
            root.protectionMessage = "";
            root.currentIndicator = "clightTemperature";
            root.triggerOsd();
        }
    }

    Connections {
        // Listen to volume changes
        target: Audio.sink?.audio ?? null
        function onVolumeChanged() {
            if (!Audio.ready)
                return;
            root.currentIndicator = "volume";
            root.triggerOsd();
        }
        function onMutedChanged() {
            if (!Audio.ready)
                return;
            root.currentIndicator = "volume";
            root.triggerOsd();
        }
    }

    Connections {
        // Listen to protection triggers
        target: Audio
        function onSinkProtectionTriggered(reason) {
            root.protectionMessage = reason;
            root.currentIndicator = "volume";
            root.triggerOsd();
        }
        function onSinkChanged() {
            if (!Audio.sink) return;
            root.protectionMessage = "";
            root.currentIndicator = "audioOutput";
            root.triggerOsd();
        }
        function onSourceChanged() {
            if (!Audio.source) return;
            root.protectionMessage = "";
            root.currentIndicator = "audioInput";
            root.triggerOsd();
        }
    }

    Connections {
        // Listen to lock key toggles (ignore the initial state read on startup)
        target: KeyboardLocks
        function onCapsLockOnChanged() {
            if (!KeyboardLocks.ready) return;
            root.protectionMessage = "";
            root.currentIndicator = "capsLock";
            root.triggerOsd();
        }
        function onNumLockOnChanged() {
            if (!KeyboardLocks.ready) return;
            root.protectionMessage = "";
            root.currentIndicator = "numLock";
            root.triggerOsd();
        }
    }

    Connections {
        // Listen to keyboard layout switches
        target: HyprlandXkb
        function onCurrentLayoutNameChanged() {
            // Nothing to announce a switch to/from if there's only one layout
            if (HyprlandXkb.layoutCodes.length <= 1) return;
            root.protectionMessage = "";
            root.currentIndicator = "keyboardLayout";
            root.triggerOsd();
        }
    }

    Loader {
        id: osdLoader
        active: GlobalStates.osdVolumeOpen

        sourceComponent: PanelWindow {
            id: osdRoot
            color: "transparent"

            Connections {
                target: root
                function onFocusedScreenChanged() {
                    osdRoot.screen = root.focusedScreen;
                }
            }

            WlrLayershell.namespace: "quickshell:onScreenDisplay"
            WlrLayershell.layer: WlrLayer.Overlay
            anchors {
                top: !Config.options.bar.bottom
                bottom: Config.options.bar.bottom
            }
            mask: Region {
                item: osdValuesWrapper
            }

            // Blur only the painted indicator body. Every indicator reserves an
            // elevation margin inside this surface and the text ones draw their
            // drop shadow into it, which the catch-all whole-surface blur frosted
            // into a muddy fringe (#89, the deferred half of #82; the caps lock
            // OSD is the one apollo79 reported). Same treatment as the
            // bar/sidebars/dock; pairs with rules.lua turning the layerrule
            // blur off for this namespace. The protection message is left out:
            // its m3error fill is a flat opaque hex, so a backdrop blur behind
            // it can never show, and it keeps its row in the column even while
            // hidden by opacity alone - covering it would be a no-op that only
            // risks frosting bare wallpaper if that gate were ever wrong.
            WindowBlurRegion {
                targetWindow: osdRoot
                regionItem: osdIndicatorLoader.item?.backgroundItem ?? null
                regionRadius: osdIndicatorLoader.item?.backgroundRadius ?? 0
            }

            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            margins {
                top: Appearance.sizes.barHeight
                bottom: Appearance.sizes.barHeight
            }

            implicitWidth: columnLayout.implicitWidth
            implicitHeight: columnLayout.implicitHeight
            visible: osdLoader.active

            ColumnLayout {
                id: columnLayout
                anchors.horizontalCenter: parent.horizontalCenter

                Item {
                    id: osdValuesWrapper
                    // Extra space for shadow
                    implicitHeight: contentColumnLayout.implicitHeight
                    implicitWidth: contentColumnLayout.implicitWidth
                    clip: true

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: GlobalStates.osdVolumeOpen = false
                    }

                    Column {
                        id: contentColumnLayout
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                        }
                        spacing: 0

                        Loader {
                            id: osdIndicatorLoader
                            source: root.indicators.find(i => i.id === root.currentIndicator)?.sourceUrl
                        }

                        Item {
                            id: protectionMessageWrapper
                            anchors.horizontalCenter: parent.horizontalCenter
                            implicitHeight: protectionMessageBackground.implicitHeight
                            implicitWidth: protectionMessageBackground.implicitWidth
                            opacity: root.protectionMessage !== "" ? 1 : 0

                            StyledRectangularShadow {
                                target: protectionMessageBackground
                            }
                            Rectangle {
                                id: protectionMessageBackground
                                anchors.centerIn: parent
                                color: Appearance.m3colors.m3error
                                property real padding: Appearance.spacing.space150
                                implicitHeight: protectionMessageRowLayout.implicitHeight + padding * 2
                                implicitWidth: protectionMessageRowLayout.implicitWidth + padding * 2
                                radius: Appearance.rounding.normal

                                RowLayout {
                                    id: protectionMessageRowLayout
                                    anchors.centerIn: parent
                                    MaterialSymbol {
                                        id: protectionMessageIcon
                                        text: "dangerous"
                                        iconSize: Appearance.font.pixelSize.hugeass
                                        color: Appearance.m3colors.m3onError
                                    }
                                    StyledText {
                                        id: protectionMessageTextWidget
                                        horizontalAlignment: Text.AlignHCenter
                                        color: Appearance.m3colors.m3onError
                                        wrapMode: Text.Wrap
                                        text: root.protectionMessage
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "osdVolume"

        function trigger() {
            root.triggerOsd();
        }

        function hide() {
            GlobalStates.osdVolumeOpen = false;
        }

        function toggle() {
            GlobalStates.osdVolumeOpen = !GlobalStates.osdVolumeOpen;
        }
    }
    GlobalShortcut {
        name: "osdVolumeTrigger"
        description: "Triggers volume OSD on press"

        onPressed: {
            root.triggerOsd();
        }
    }
    GlobalShortcut {
        name: "osdVolumeHide"
        description: "Hides volume OSD on press"

        onPressed: {
            GlobalStates.osdVolumeOpen = false;
        }
    }
}
