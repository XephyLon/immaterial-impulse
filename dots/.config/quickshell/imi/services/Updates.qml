pragma Singleton
import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import "updates_outcome.js" as UpdatesOutcome

/*
 * System updates service. Currently only supports Arch.
 */
Singleton {
    id: root

    property bool available: false
    property alias checking: checkUpdatesProc.running
    property int count: 0
    
    readonly property bool updateAdvised: available && count > Config.options.updates.adviseUpdateThreshold
    readonly property bool updateStronglyAdvised: available && count > Config.options.updates.stronglyAdviseUpdateThreshold

    function load() {}
    function refresh() {
        if (!available) return;
        print("[Updates] Checking for system updates")
        checkUpdatesProc.running = true;
    }

    // The bar widget's two gestures, moved here so the widget is a view:
    // a manual check with a notification, and the upgrade run in a terminal
    // followed by the outcome notification 5 s after it exits (the count
    // needs that long to be re-read).
    function checkNow() {
        root.refresh();
        Quickshell.execDetached(["notify-send", Translation.tr("Updates"), Translation.tr("Checking for updates..."), "-a", "Shell"]);
    }
    function runUpgrade() {
        if (upgradeProc.running) return;
        upgradeProc.running = true;
    }
    // The outcome notification for the count read after an upgrade run:
    // decided by updates_outcome.js (tests/tst_updates_outcome.qml drives
    // it), worded here. The two commands are the bar widget's old ones
    // byte for byte: "up to date" carried no urgency flag, "cancelled"
    // carried `-u normal`.
    function outcomeCommand(countAfter) {
        const body = UpdatesOutcome.outcome(countAfter).upToDate
            ? Translation.tr("System up to date")
            : Translation.tr("Update cancelled — %1 updates still pending").arg(countAfter);
        return UpdatesOutcome.command(countAfter, Translation.tr("Updates"), body);
    }

    Process {
        id: upgradeProc
        command: ["kitty", "--hold", "fish", "-i", "-l", "-c", "yay -Syu --combinedupgrade=false"]
        onExited: (exitCode, exitStatus) => {
            root.refresh();
            outcomeTimer.restart();
        }
    }
    Timer {
        id: outcomeTimer
        interval: 5000
        repeat: false
        onTriggered: Quickshell.execDetached(root.outcomeCommand(root.count))
    }

    Timer {
        interval: Config.options.updates.checkInterval * 60 * 1000
        repeat: true
        running: Config.ready && Config.options.updates.enableCheck
        onTriggered: {
            print("[Updates] Periodic update check due")
            root.refresh();
        }
    }

    Process {
        id: checkAvailabilityProc
        running: Config.ready && Config.options.updates.enableCheck
        command: ["which", "checkupdates"]
        onExited: (exitCode, exitStatus) => {
            root.available = (exitCode === 0);
            root.refresh();
        }
    }

    Process {
        id: checkUpdatesProc
        command: ["bash", "-c", "pacman=$(checkupdates 2>/dev/null | wc -l); aur=$(yay -Qua 2>/dev/null | wc -l || paru -Qua 2>/dev/null | wc -l || echo 0); echo $((pacman + aur))"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.count = parseInt(text.trim())
            }
        }
    }
}
