pragma Singleton
import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

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
    property alias upgrading: upgradeProc.running
    function runUpgrade() {
        if (upgradeProc.running) return;
        upgradeProc.running = true;
    }
    // The outcome, as a notification body and urgency, for the count read
    // after an upgrade run. Pure, so tests/test_updates_contract.py can pin it.
    function outcomeFor(countAfter) {
        return countAfter === 0
            ? { "body": Translation.tr("System up to date"), "urgency": "low" }
            : { "body": Translation.tr("Update cancelled — %1 updates still pending").arg(countAfter), "urgency": "normal" };
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
        onTriggered: {
            const outcome = root.outcomeFor(root.count);
            Quickshell.execDetached(["notify-send", Translation.tr("Updates"), outcome.body, "-a", "Shell", "-u", outcome.urgency]);
        }
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
