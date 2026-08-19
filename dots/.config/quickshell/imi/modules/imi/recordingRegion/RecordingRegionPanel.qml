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
 * Built from the same pieces as the region selector's own toolbar - `Toolbar`,
 * `IconToolbarButton`, `ToolbarPairedFab` - so it is the shell's M3 expressive
 * toolbar rather than a pill with icons in it: 56dp container on the surface
 * container role, full corner, its own shadow, 22dp icons in 40dp targets, and
 * the destructive action separated out as a paired FAB the way the selector
 * separates its close.
 *
 * No tooltips on these buttons, deliberately. A StyledToolTip is a Controls
 * Popup, and a Popup renders in the overlay of the window it belongs to - which
 * here is a window the exact size of the toolbar. The tooltip has nowhere to go
 * except on top of the buttons, it arrives with no delay, and while it is up it
 * takes the pointer: arrow cursor, clicks swallowed. The selector's toolbar gets
 * away with tooltips because its window is the whole screen and they have room
 * above. If these controls ever need labels, they need a surface of their own.
 *
 * The window is exactly the size of the controls and sits OUTSIDE the region.
 * gsr records whatever the compositor shows inside the rectangle, so anything
 * drawn over it would be in every frame of a clip that cannot be re-taken -
 * see recording_region.js, which refuses to place the toolbar at all rather
 * than place it inside.
 */
Scope {
    id: root

    readonly property var region: RecordingRegion.parseRegion(Persistent.states.record.region)
    readonly property bool active: ScreenRecord.recording && root.region !== null

    // The room the shadows need around the controls. The window has to include
    // it - a layer surface clips at its own bounds - and the gap to the region
    // has to clear it too, because a soft shadow bleeding over the edge of the
    // capture is as recorded as the toolbar itself would be.
    readonly property real shadowMargin: Appearance.sizes.elevationMargin

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

    // The controls' width, published by the instance inside the window.
    //
    // It cannot be measured out here: a layout that is not in a scene is never
    // polished, so its implicit size stays zero, and placing the window from
    // that would centre a zero-width toolbar. The window is therefore sized by
    // its content and POSITIONED from the size that content reports - which is
    // not circular, because the width does not depend on where the window is.
    // Until the first report the window is off-centre by half its width for a
    // frame, which is invisible: it is appearing at that moment anyway.
    property real measuredWidth: 0

    // The container height is fixed by the toolbar itself (Toolbar.qml's 56dp
    // M3 expressive height), so the only question placement needs answered
    // before the window exists - does it fit above or below - has a constant
    // answer and does not wait on a measurement.
    readonly property real controlsHeight: 56

    // Two placements, split on purpose.
    //
    // `fit` answers "is there room, and on which side" using only the fixed
    // container height, so it does NOT depend on the measured width - and the
    // window's existence depends only on `fit`. Feeding the loader from a
    // value that the loader's own content produces is a cycle, and QML said so:
    // "Binding loop detected for property spot".
    //
    // `spot` then adds the horizontal placement, which does use the measured
    // width. Nothing gates on it, so a width that arrives a frame later moves
    // the window instead of re-creating it.
    readonly property var fit: {
        if (!root.active || !root.targetScreen) return null;
        return RecordingRegion.placeToolbar(
            root.region,
            { x: root.targetScreen.x, y: root.targetScreen.y,
              width: root.targetScreen.width, height: root.targetScreen.height },
            { width: 0, height: root.controlsHeight },
            Appearance.spacing.space100 + root.shadowMargin);
    }

    readonly property var spot: {
        if (!root.fit || !root.targetScreen) return null;
        const placed = RecordingRegion.placeToolbar(
            root.region,
            { x: root.targetScreen.x, y: root.targetScreen.y,
              width: root.targetScreen.width, height: root.targetScreen.height },
            { width: root.measuredWidth, height: root.controlsHeight },
            Appearance.spacing.space100 + root.shadowMargin);
        return placed ?? root.fit;
    }

    component RecordingControls: RowLayout {
        // Wider than the toolbar's internal rhythm on purpose: the FAB is a
        // separate object paired WITH the toolbar, not another item in it, and
        // at the same spacing as the buttons inside it reads as a crowded
        // fourth button that happens to be red.
        spacing: Appearance.spacing.space150

        Toolbar {
            padding: Appearance.spacing.space100

            // Non-interactive: what the capture is doing, in the one place the
            // capture cannot show it. It breathes while running and holds
            // still when paused, so the state is readable without reading.
            Item {
                Layout.fillHeight: true
                // No extra margin: the toolbar's padding is the inset, and
                // adding to it here made the left end wider than the right.
                implicitWidth: statusIcon.implicitWidth + Appearance.spacing.space50

                MaterialSymbol {
                    id: statusIcon
                    anchors.centerIn: parent
                    text: ScreenRecord.recordPaused ? "pause_circle" : "screen_record"
                    iconSize: 22
                    color: ScreenRecord.recordPaused
                        ? Appearance.colors.colOnSurfaceVariant
                        : Appearance.colors.colError
                    animateChange: true

                    SequentialAnimation on opacity {
                        running: !ScreenRecord.recordPaused
                        loops: Animation.Infinite
                        alwaysRunToEnd: true
                        NumberAnimation {
                            to: 0.4
                            duration: Appearance.animation.scale(Appearance.animationCurves.expressiveDefaultSpatialDuration)
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                        }
                        NumberAnimation {
                            to: 1
                            duration: Appearance.animation.scale(Appearance.animationCurves.expressiveDefaultSpatialDuration)
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                        }
                    }
                }
            }

            IconToolbarButton {
                text: ScreenRecord.recordPaused ? "play_arrow" : "pause"
                toggled: ScreenRecord.recordPaused
                releaseAction: () => ScreenRecord.togglePauseRecord()
            }

            IconToolbarButton {
                // Only while the replay ring buffer is armed: this dumps the
                // last N seconds to their own clip and leaves both the buffer
                // and this recording running.
                visible: ScreenRecord.replaying
                text: "save"
                releaseAction: () => ScreenRecord.saveReplay()
            }
        }

        ToolbarPairedFab {
            // Paired off to the side, the way the selector pairs its close: it
            // ends the thing the rest of the toolbar is adjusting, so it should
            // not sit in the same row of equals. Error rather than tertiary,
            // because stopping is the one action here that cannot be undone.
            Layout.alignment: Qt.AlignVCenter
            iconText: "stop"
            baseSize: 48
            colBackground: Appearance.colors.colErrorContainer
            colBackgroundHover: Appearance.colors.colErrorContainerHover
            colRipple: Appearance.colors.colErrorContainerActive
            colOnBackground: Appearance.colors.colOnErrorContainer
            onClicked: ScreenRecord.stopRecord()
        }
    }

    LazyLoader {
        active: root.active && root.fit !== null

        PanelWindow {
            id: toolbarWindow
            visible: true
            screen: root.targetScreen
            color: "transparent"
            WlrLayershell.namespace: "quickshell:recordingRegion"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            implicitWidth: controls.implicitWidth + root.shadowMargin * 2
            implicitHeight: controls.implicitHeight + root.shadowMargin * 2
            // Anchored to the corner and pushed out by the margin, because a
            // layer surface has no coordinates of its own. The margins are
            // screen-relative and back off by the shadow inset, so the controls
            // themselves land exactly where the placement put them.
            anchors { top: true; left: true }
            margins {
                top: (root.spot?.y ?? 0) - (root.targetScreen?.y ?? 0) - root.shadowMargin
                left: (root.spot?.x ?? 0) - (root.targetScreen?.x ?? 0) - root.shadowMargin
            }

            RecordingControls {
                id: controls
                anchors.centerIn: parent
            }

            // Reported back out so the placement can centre the window on the
            // region. A Binding rather than an assignment, so the value tracks
            // a toolbar that changes width - save-clip appearing when the
            // replay buffer is armed mid-recording.
            Binding {
                target: root
                property: "measuredWidth"
                value: controls.implicitWidth
            }
        }
    }
}
