import QtQuick
import Quickshell.Io
import ".."

/**
 * The laptop lid is closed (`closed: true`, default) or open, read from
 * /proc/acpi/button/lid/<name>/state through a FileView - no subprocess for
 * a kernel file. The lid directory is found once; the file is re-read on a
 * slow safety-net tick only while the condition is armed (a lid changes
 * state a few times a day). Machines without a lid never hold.
 */
ModeCondition {
    id: root
    readonly property bool wantClosed: root.params?.closed !== false

    property string statePath: ""
    property string state: ""

    // One `sh -c` at construction to resolve the glob; everything after is
    // the FileView.
    readonly property Process locate: Process {
        running: root.armed && root.statePath.length === 0
        command: ["sh", "-c", "for f in /proc/acpi/button/lid/*/state; do [ -e \"$f\" ] && { echo \"$f\"; break; }; done"]
        stdout: StdioCollector {
            onStreamFinished: root.statePath = this.text.trim()
        }
    }

    readonly property FileView reader: FileView {
        path: root.statePath.length ? root.statePath : ""
        onLoaded: {
            const m = /:\s*(\w+)/.exec(this.text());
            root.state = m ? m[1].toLowerCase() : "";
        }
        onLoadFailed: root.state = ""
    }

    readonly property Timer poll: Timer {
        interval: 60000
        repeat: true
        running: root.armed && root.statePath.length > 0
        onTriggered: root.reader.reload()
    }

    satisfied: root.state.length > 0 && (root.state === "closed") === root.wantClosed
    reason: root.state.length ? root.state : "no lid"
}
