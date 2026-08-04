pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs

/**
 * Selective EFI reboot: enumerate the firmware boot menu (efibootmgr) and
 * reboot into a chosen entry by setting BootNext - firmware-level, so it
 * works with any bootloader (GRUB, systemd-boot, Windows Boot Manager).
 *
 * Reading the entries needs no privileges; setting BootNext does, so the
 * write goes through pkexec (the shell's polkit agent shows the prompt) and
 * the reboot only follows a successful authentication.
 */
Singleton {
    id: root

    // [{ num: "0000", label: "Windows Boot Manager", current: bool }]
    property var entries: []
    property string pendingNum: ""
    property string pendingLabel: ""

    // Pure parser, unit-tested against real efibootmgr output.
    // Transient media entries ("UEFI:USB...", BBS fallbacks) are firmware
    // noise in an OS picker and are dropped; "UEFI OS" (no colon) survives.
    function parseEntries(text) {
        const lines = text.split("\n")
        let current = ""
        let order = []
        let found = []
        for (const line of lines) {
            const currentMatch = line.match(/^BootCurrent:\s*([0-9A-Fa-f]{4})/)
            if (currentMatch) { current = currentMatch[1]; continue }
            const orderMatch = line.match(/^BootOrder:\s*(.*)/)
            if (orderMatch) { order = orderMatch[1].split(",").map(s => s.trim()); continue }
            const entryMatch = line.match(/^Boot([0-9A-Fa-f]{4})(\*?)\s+(.*)$/)
            if (!entryMatch || entryMatch[2] !== "*") continue // inactive entries can't boot
            let label = entryMatch[3]
            // Label ends at the tab-separated device path; some firmwares glue
            // the path right on, so also cut at known device-path openers.
            label = label.split("\t")[0]
            label = label.replace(/(HD\(|PciRoot\(|BBS\(|VenMsg\(|Fv\().*$/, "").trim()
            if (label === "" || label.startsWith("UEFI:")) continue
            found.push({ num: entryMatch[1], label: label, current: entryMatch[1] === current })
        }
        // Firmware boot-order position is the natural presentation order.
        found.sort((a, b) => {
            const ai = order.indexOf(a.num), bi = order.indexOf(b.num)
            return (ai < 0 ? 999 : ai) - (bi < 0 ? 999 : bi)
        })
        return found
    }

    function refresh() {
        listProc.running = true
    }

    function rebootInto(num, label) {
        root.pendingNum = num
        root.pendingLabel = label
        setNextProc.running = true
    }

    Process {
        id: listProc
        command: ["efibootmgr"]
        stdout: StdioCollector {
            id: listCollector
            onStreamFinished: root.entries = root.parseEntries(listCollector.text)
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) root.entries = [] // non-EFI system or efibootmgr missing
        }
    }

    function notify(title, body) {
        Quickshell.execDetached(["notify-send", title, body, "-a", "Session"])
    }

    Process {
        id: setNextProc
        command: ["pkexec", "efibootmgr", "-n", root.pendingNum]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                // BootNext is now armed in firmware. From here every exit path
                // must either reboot or clear it again - see rebootProc.
                rebootProc.running = true
            } else if (exitCode !== 126 && exitCode !== 127) {
                // 126/127 = polkit dismissal/authorization failure: user's call,
                // stay quiet. Anything else is a real failure worth surfacing.
                root.notify("Reboot cancelled",
                    `efibootmgr failed to set BootNext (${exitCode})`)
            }
        }
    }

    // Deliberately a Process rather than Session.reboot(). Session.reboot() is
    // execDetached, which reports nothing back - and once BootNext is armed,
    // "the reboot silently did not happen" is precisely the state that must not
    // go unnoticed, because it leaves the machine set to boot another OS at some
    // unrelated future restart. An exit code is the whole point.
    //
    // Nothing tears down the UI first. The session screen has already hidden
    // itself before rebootInto() is called, and a reboot that fails must leave
    // the user's session exactly as it was.
    Process {
        id: rebootProc
        command: ["bash", "-c", "reboot || loginctl reboot"]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) return // system is going down; nothing left to do
            // The reboot definitively failed, so the armed BootNext is now a
            // trap: the next restart, for whatever unrelated reason days later,
            // would boot the other OS. Clear it. This needs privilege again and
            // therefore a second polkit prompt - unavoidable, but it only
            // happens on a path where something has already gone wrong.
            disarmProc.running = true
        }
    }

    Process {
        id: disarmProc
        command: ["pkexec", "efibootmgr", "-N"]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.notify("Reboot failed",
                    `Could not reboot into ${root.pendingLabel}. BootNext was cleared, so this machine still boots as usual.`)
            } else {
                // Worst case: armed, could not reboot, could not disarm. The
                // user has to know the exact command, because nothing on screen
                // will hint that the next restart boots a different OS.
                root.notify("Reboot failed - BootNext still set",
                    `Could not reboot into ${root.pendingLabel}, and clearing BootNext failed (${exitCode}). The next restart will boot ${root.pendingLabel}. Run: sudo efibootmgr -N`)
            }
        }
    }
}
