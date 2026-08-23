pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services

/**
 * Manages a HyprlandFocusGrab that's to be shared by all windows.
 * "Persistent" is for windows that should always be included but not closed on dismiss, like bar and onscreen keyboard.
 * "Dismissable" is for stuff like sidebars.
 **/
 
Singleton {
    id: root

    signal dismissed()

    property list<var> persistent: []
    property list<var> dismissable: []

    function dismiss() {
        root.dismissable = [];
        root.dismissed();
    }

    Component.onCompleted: {
        console.log("[GlobalFocusGrab] Initialized");
    }

    function addPersistent(window) {
        if (root.persistent.indexOf(window) === -1) {
            root.persistent.push(window);
        }
    }

    function removePersistent(window) {
        var index = root.persistent.indexOf(window);
        if (index !== -1) {
            root.persistent.splice(index, 1);
        }
    }

    function addDismissable(window) {
        if (root.dismissable.indexOf(window) === -1) {
            root.dismissable.push(window);
        }
    }

    function removeDismissable(window) {
        var index = root.dismissable.indexOf(window);
        if (index !== -1) {
            root.dismissable.splice(index, 1);
        }
    }

    // Debounce transient clears. When a sidebar opens, Hyprland sends a
    // ToplevelHandle activation update ~20ms later for the previously-focused
    // window; HyprlandFocusGrab reads that as "a non-panel toplevel became
    // active" and fires onCleared, which used to dismiss() the just-opened panel
    // (sidebars "blinked" open then shut). The grab re-activates within a frame
    // or two, so we defer the dismiss briefly and skip it if the grab came back.
    // A genuine click-outside leaves the grab inactive, so it still dismisses.
    // See issue #25.
    Timer {
        id: dismissDebounce
        interval: 100
        onTriggered: {
            if (!grab.active) root.dismiss();
        }
    }

    HyprlandFocusGrab {
        id: grab
        // Persistent windows first, dismissables LAST - the order is load-
        // bearing. When the grab activates, Hyprland moves keyboard focus to
        // a whitelisted surface, and it picks from the END of this list.
        // Measured on the persistent sidebars (which never re-map, so the
        // grab is the only thing that can hand them the keyboard): with the
        // dismissable first and the bar/OSK after it, opening the left
        // sidebar never activated its window - keys went to a persistent
        // surface and every keypress was lost until the pointer happened to
        // enter the panel. Same build, same open, with the dismissable moved
        // to the end: Window.active flipped true immediately and typing
        // landed in the AI chat's field with the cursor half a screen away.
        //
        // The old conditional (`every(!focusable) || some(hasActive(...))`)
        // tried to solve the same problem by dropping the persistent windows
        // from the list entirely in some states - which worked only by
        // leaving nothing else for Hyprland to pick, and cost the protection
        // those windows are listed for (a bar click would clear the grab and
        // dismiss the panel). Ordering keeps both: the panel gets the
        // keyboard, and clicking the bar or typing on the OSK stays inside
        // the grab.
        windows: [...root.persistent, ...root.dismissable]
        active: root.dismissable.length > 0
        onCleared: () => {
            dismissDebounce.restart();
        }
    }
}