pragma Singleton
import Quickshell
import qs.services
import qs.modules.common

Singleton {
    id: root

    function closeAllWindows() {
        HyprlandData.windowList.map(w => w.pid).forEach(pid => {
            Quickshell.execDetached(["kill", pid]);
        });
    }

    function changePassword() {
        Quickshell.execDetached(["bash", "-c", `${Config.options.apps.changePassword}`]);
    }

    function lock() {
        Quickshell.execDetached(["loginctl", "lock-session"]);
    }

    function suspend() {
        Quickshell.execDetached(["bash", "-c", "systemctl suspend || loginctl suspend"]);
    }

    function logout() {
        closeAllWindows();
        Quickshell.execDetached(["pkill", "-i", "Hyprland"]);
    }

    function launchTaskManager() {
        Quickshell.execDetached(["bash", "-c", `${Config.options.apps.taskManager}`]);
    }

    function hibernate() {
        Quickshell.execDetached(["bash", "-c", `systemctl hibernate || loginctl hibernate`]);
    }

    // Order is deliberate: issue the transition FIRST, close windows after. It
    // used to be the other way round, which meant a transition that did not
    // happen - a polkit denial, an inhibitor, or a session logind does not
    // consider "active" and therefore wants admin auth for - had already killed
    // every one of the user's applications by the time it failed. The user was
    // left on an empty desktop, still logged in, with nothing on screen
    // explaining why.
    //
    // Reversing it costs nothing. systemd's shutdown sequence SIGTERMs every
    // process anyway, so applications still get their chance to save;
    // closeAllWindows() only ever brought that forward by a fraction of a second.
    function poweroff() {
        Quickshell.execDetached(["bash", "-c", `systemctl poweroff || loginctl poweroff`]);
        closeAllWindows();
    }

    function reboot() {
        Quickshell.execDetached(["bash", "-c", `reboot || loginctl reboot`]);
        closeAllWindows();
    }

    function rebootToFirmware() {
        Quickshell.execDetached(["bash", "-c", `systemctl reboot --firmware-setup || loginctl reboot --firmware-setup`]);
        closeAllWindows();
    }
}
