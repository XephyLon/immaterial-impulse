import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "recording_region.js" as RecordingRegion

/**
 * Controls for a region recording, parked against the rectangle being captured.
 *
 * A region recording gives no sign of itself inside the frame - which is the
 * point, but it leaves stopping the capture as a trip to the bar. This puts
 * stop, pause and (while the replay buffer is armed) save-clip beside the
 * region, for as long as the recording runs.
 *
 * The window is exactly the size of the toolbar and sits OUTSIDE the region.
 * gsr records whatever the compositor shows inside the rectangle, so anything
 * drawn over it would be in every frame of a clip that cannot be re-taken -
 * see recording_region.js, which refuses to place the toolbar at all rather
 * than place it inside.
 */
Scope {
    id: root

    readonly property var region: RecordingRegion.parseRegion(Persistent.states.record.region)
    readonly property bool active: ScreenRecord.recording && root.region !== null

    // The screen the region is on, by its top-left corner: a region dragged
    // across a monitor boundary belongs to the monitor it started on, which is
    // also the one gsr attributed the capture to.
    readonly property var targetScreen: {
        if (!root.region) return null;
        for (const screen of Quickshell.screens) {
            if (root.region.x >= screen.x && root.region.x < screen.x + screen.width
                && root.region.y >= screen.y && root.region.y < screen.y + screen.height)
                return screen;
        }
        return Quickshell.screens[0] ?? null;
    }

    readonly property real toolbarWidth: toolbarMetrics.implicitWidth
    readonly property real toolbarHeight: toolbarMetrics.implicitHeight

    readonly property var spot: {
        if (!root.active || !root.targetScreen) return null;
        return RecordingRegion.placeToolbar(
            root.region,
            { x: root.targetScreen.x, y: root.targetScreen.y,
              width: root.targetScreen.width, height: root.targetScreen.height },
            { width: root.toolbarWidth, height: root.toolbarHeight },
            Appearance.spacing.space100);
    }

    // Measured off-window so the placement has a size to work with before the
    // window exists - the toolbar's own width decides where the window goes,
    // and a window cannot be positioned by something it contains.
    Item {
        id: toolbarMetrics
        visible: false
        implicitWidth: Appearance.spacing.space100 * 2
            + 36 * (2 + (ScreenRecord.replaying ? 1 : 0))
            + Appearance.spacing.space50 * (1 + (ScreenRecord.replaying ? 1 : 0))
        implicitHeight: 44
    }

    LazyLoader {
        active: root.active && root.spot !== null

        PanelWindow {
            id: toolbarWindow
            visible: true
            screen: root.targetScreen
            color: "transparent"
            WlrLayershell.namespace: "quickshell:recordingRegion"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            implicitWidth: root.toolbarWidth
            implicitHeight: root.toolbarHeight
            // Anchored to the corner and pushed out by the margin, because a
            // layer surface has no coordinates of its own. The margins are
            // screen-relative; the placement is in global coordinates.
            anchors { top: true; left: true }
            margins {
                top: (root.spot?.y ?? 0) - (root.targetScreen?.y ?? 0)
                left: (root.spot?.x ?? 0) - (root.targetScreen?.x ?? 0)
            }

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer0
                border.width: Appearance.borderWidth.standard
                border.color: Appearance.colors.colLayer0Border

                RowLayout {
                    anchors.centerIn: parent
                    spacing: Appearance.spacing.space50

                    // Says which of the two states the capture is in, in a
                    // place where the recording itself cannot show it.
                    MaterialSymbol {
                        Layout.leftMargin: Appearance.spacing.space50
                        text: ScreenRecord.recordPaused ? "pause_circle" : "screen_record"
                        iconSize: Appearance.font.pixelSize.large
                        color: ScreenRecord.recordPaused
                            ? Appearance.colors.colOnSurfaceVariant
                            : Appearance.colors.colError
                    }

                    RippleButton {
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        releaseAction: () => ScreenRecord.togglePauseRecord()
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: ScreenRecord.recordPaused ? "play_arrow" : "pause"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }

                    RippleButton {
                        // Stop keeps the file - record.sh writes it out on
                        // stop, so there is no separate save for a recording.
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        releaseAction: () => ScreenRecord.stopRecord()
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "stop"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colError
                        }
                    }

                    RippleButton {
                        // Only while the replay ring buffer is armed: this
                        // dumps the last N seconds to their own clip and
                        // leaves both the buffer and this recording running.
                        visible: ScreenRecord.replaying
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        releaseAction: () => ScreenRecord.saveReplay()
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "save"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }
        }
    }
}
