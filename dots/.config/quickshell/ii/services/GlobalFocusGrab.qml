pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland

/**
 * Manages a HyprlandFocusGrab that's to be shared by all windows.
 * "Persistent" is for windows that should always be included but not closed on dismiss, like bar and onscreen keyboard.
 * "Dismissable" is for stuff like sidebars
 */ 
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

    function hasActive(element) {
        return element?.activeFocus || Array.from(
            element?.children ?? []
        ).some(
            (child) => hasActive(child)
        );
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
        windows: root.dismissable.every(w => !w?.focusable) || root.dismissable.some(w => hasActive(w?.contentItem)) ? [...root.dismissable, ...root.persistent] : [...root.dismissable]
        active: root.dismissable.length > 0
        onCleared: () => {
            dismissDebounce.restart();
        }
    }

}
