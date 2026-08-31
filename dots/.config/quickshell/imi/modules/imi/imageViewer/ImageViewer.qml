import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick

/**
 * The fullscreen image viewer: a path in GlobalStates.aiImageViewerSource
 * opens it centered over everything; Esc or a click outside closes it and
 * the wheel zooms about the center.
 */
Scope {
    id: root

    LazyLoader {
        active: GlobalStates.aiImageViewerSource.length > 0

        component: PanelWindow {
            id: viewerWindow
            // The focused monitor, the OSD's grammar - without a screen the
            // compositor picks whichever output was focused at creation and
            // the surface contract rightly refuses the ambiguity (#297).
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name)
                ?? Quickshell.screens[0]
            visible: true
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:imageViewer"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "transparent"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            function close(): void {
                GlobalStates.aiImageViewerSource = "";
            }

            Rectangle {
                anchors.fill: parent
                color: ColorUtils.transparentize(Appearance.m3colors.m3scrim ?? "#000000", 0.28)
                focus: true
                Keys.onEscapePressed: viewerWindow.close()

                MouseArea {
                    anchors.fill: parent
                    onClicked: viewerWindow.close()
                }

                WheelHandler {
                    property real zoom: 1
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => {
                        zoom = Math.max(0.2, Math.min(8,
                            zoom * Math.pow(1.15, event.angleDelta.y / 120)));
                        viewerImage.scale = zoom;
                    }
                }

                StyledImage {
                    id: viewerImage
                    anchors.centerIn: parent
                    width: Math.min(parent.width * 0.9, implicitWidth)
                    height: Math.min(parent.height * 0.9, implicitHeight)
                    fillMode: Image.PreserveAspectFit
                    source: GlobalStates.aiImageViewerSource.length > 0
                        ? Qt.resolvedUrl("file://" + GlobalStates.aiImageViewerSource) : ""
                    scale: 1
                    Behavior on scale {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    // Clicking the image itself must not close the viewer.
                    MouseArea { anchors.fill: parent; onClicked: {} }

                    // Panning: drag moves the centered image by its anchor
                    // offsets, accumulating across gestures; closing the
                    // viewer unloads everything, so pan and zoom reset for
                    // the next open.
                    DragHandler {
                        id: dragPan
                        target: null
                        property real baseX: 0
                        property real baseY: 0
                        onActiveChanged: {
                            if (active) {
                                baseX = viewerImage.anchors.horizontalCenterOffset;
                                baseY = viewerImage.anchors.verticalCenterOffset;
                            }
                        }
                        onActiveTranslationChanged: {
                            viewerImage.anchors.horizontalCenterOffset = dragPan.baseX + activeTranslation.x;
                            viewerImage.anchors.verticalCenterOffset = dragPan.baseY + activeTranslation.y;
                        }
                    }
                }
            }
        }
    }
}
