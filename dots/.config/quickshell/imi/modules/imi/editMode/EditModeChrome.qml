import QtQuick
import Quickshell
import qs
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
 */
Scope {
    id: root

    Variants {
        model: Quickshell.screens
        delegate: Loader {
            id: surfaceLoader
            required property var modelData
            // The mode itself, plus the tail of the exit animation: the flag
            // goes false at the first frame of the leave, and the chrome has to
            // stay on screen to travel back out with the desktop.
            active: GlobalStates.editMode || GlobalStates.editProgress > 0

            sourceComponent: EditModeChromeSurface {
                screen: surfaceLoader.modelData
            }
        }
    }

    // The per-widget context menu's window - one, not one per screen: it
    // exists only while a menu is open, on the screen the widget was
    // right-clicked on, and its own loader is that gate.
    EditWidgetMenu {}
}
