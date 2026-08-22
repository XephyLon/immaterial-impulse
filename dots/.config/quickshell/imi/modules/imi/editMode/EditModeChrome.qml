import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common

/**
 * Edit Mode's chrome, one surface per screen.
 *
 * The mode is global (`GlobalStates.editMode`) because the layouts it will edit
 * are, so every monitor's desktop shrinks and every monitor gets its own
 * toolbar and tab bar - the chrome frames the desktop it is drawn beside, and a
 * single-screen chrome would frame one of them and float over the others.
 *
 * The surfaces exist only while the mode is on the way in, on, or on the way
 * out. That is the first of the two gates the chrome stands down through, and
 * it is the one that matters when the mode is OFF: a full-screen `Overlay`
 * surface left mapped with a stale mask eats clicks on a desktop nobody is
 * editing, and that is the state nobody looks at.
 *
 * ---- and a third gate: something is covering the desktop ------------------
 *
 * The mode's two halves sit on opposite sides of the window stack. The desktop
 * being edited is `quickshell:background` on `WlrLayer.Bottom` - BELOW every
 * window - and this chrome is `quickshell:editMode` on `WlrLayer.Overlay`,
 * ABOVE every window. Anything that covers the screen therefore lands between
 * them: it hides the desktop and is itself painted over by the toolbar, the tab
 * bar and the drawer. The mode is not merely untidy in that state, it is
 * unusable - the widgets being arranged cannot be seen at all.
 *
 * So the chrome joins the desktop under the window rather than standing down.
 * `Bottom` is the only layer below a window, and being "as invisible as the
 * desktop" there is not the objection it first looks like - it is the entire
 * point. Under the window both halves are occluded together, blurred and dimmed
 * together by the compositor, and nothing snaps: the first attempt at this
 * destroyed the surface instead, and a mode popping out of existence while its
 * surroundings dim is uglier than the overlap it fixed.
 *
 * `Bar.qml:96` switches its own layer on the same pair of conditions, which is
 * the precedent for doing it this way rather than with visibility.
 *
 * Gated on the SPECIAL workspace rather than on "anything covering", because a
 * special workspace is the one surface that is deliberately summoned over
 * whatever is already there - it is shown ON TOP of the active workspace rather
 * than instead of it, which is exactly the case a mode about the desktop must
 * yield to. `Visualizer.qml:42-46` reads the same field the same way, and reads
 * it per monitor because a scratchpad is per monitor.
 */
Scope {
    id: root

    Variants {
        model: Quickshell.screens
        delegate: Loader {
            id: surfaceLoader
            required property var modelData
            // This screen's Hyprland record, for the special-workspace gate.
            // Found by name rather than by index: `Quickshell.screens` and
            // `HyprlandData.monitors` are two lists that agree today and are
            // not promised to stay in the same order.
            readonly property var thisMonitorData: HyprlandData.monitors.find(monitor =>
                monitor.name === surfaceLoader.modelData?.name)
            // A scratchpad is summoned OVER the desktop, so while one is up on
            // this screen the desktop is not visible and its chrome must not be
            // either. Empty name is the "none shown" value the field carries.
            readonly property bool specialShown:
                (surfaceLoader.thisMonitorData?.specialWorkspace?.name ?? "") !== ""

            // The mode itself, plus the tail of the exit animation: the flag
            // goes false at the first frame of the leave, and the chrome has to
            // stay on screen to travel back out with the desktop.
            active: GlobalStates.editMode || GlobalStates.editProgress > 0

            sourceComponent: EditModeChromeSurface {
                screen: surfaceLoader.modelData
                // Not a visibility gate. Standing the chrome down made it pop
                // out of existence while everything around it was being blurred
                // and dimmed by the compositor; going UNDER the window instead
                // means it takes that treatment with the desktop it frames.
                underneath: surfaceLoader.specialShown
            }
        }
    }

    // The per-widget context menu's window - one, not one per screen: it
    // exists only while a menu is open, on the screen the widget was
    // right-clicked on, and its own loader is that gate.
    EditWidgetMenu {}
}
