pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs

Singleton {
    id: root
    property var items: []
    property int maxItems: 30

    function addItems(urls) {
        let arr = [...items]
        for (const url of urls) {
            const path = FileUtils.trimFileProtocol(decodeURIComponent(url.toString()))
            if (!arr.includes(path) && arr.length < root.maxItems) {
                arr.push(path)
            }
        }
        root.items = arr
    }

    function show(urls, x, y) {
        root.addItems(urls)
        GlobalStates.dropShelfX = x
        GlobalStates.dropShelfY = y
        GlobalStates.dropShelfAnchorBelow = false
        GlobalStates.dropShelfOpen = true
    }

    // Open the (empty or not) shelf at a global layout coordinate, converted
    // to the coordinates of the monitor containing the point.
    function openAtGlobal(globalX, globalY) {
        const mon = HyprlandData.monitors.find(m =>
            globalX >= m.x && globalX < m.x + m.width / (m.scale || 1) &&
            globalY >= m.y && globalY < m.y + m.height / (m.scale || 1))
        GlobalStates.dropShelfX = globalX - (mon?.x ?? 0)
        GlobalStates.dropShelfY = globalY - (mon?.y ?? 0)
        GlobalStates.dropShelfAnchorBelow = false
        GlobalStates.dropShelfOpen = true
    }

    // Summon the shelf under the cursor (global shortcut / shake gesture).
    // An untouched summoned shelf auto-dismisses so accidental triggers cost nothing.
    function summonAtCursor() {
        cursorPosProc.running = true
    }

    // Held true by the panel while the pointer or a drag is over the shelf.
    property bool autoDismissHeld: false
    readonly property int autoDismissSeconds: Config.options.dropShelf.autoDismissSeconds
    function armAutoDismiss() {
        if (root.autoDismissSeconds > 0)
            autoDismissTimer.restart()
    }

    Timer {
        id: autoDismissTimer
        interval: root.autoDismissSeconds * 1000
        onTriggered: {
            if (!root.autoDismissHeld && root.items.length === 0)
                GlobalStates.dropShelfOpen = false
        }
    }

    Process {
        id: cursorPosProc
        command: ["hyprctl", "-j", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const pos = JSON.parse(text)
                    root.openAtGlobal(pos.x, pos.y)
                    root.armAutoDismiss()
                } catch (e) {
                    console.log("[DropShelf] cursorpos parse failed:", e)
                }
            }
        }
    }

    function copyAll() {
        if (root.items.length === 0) return
        const uriList = root.items.map(p => "file://" + p).join("\n")
        copyProc.payload = uriList
        copyProc.running = true
    }

    function clear() {
        root.items = []
        GlobalStates.dropShelfOpen = false
    }

    function hide() {
        GlobalStates.dropShelfOpen = false
    }

    Process {
        id: copyProc
        property string payload: ""
        command: ["bash", "-c", `printf '%s' '${StringUtils.shellSingleQuoteEscape(copyProc.payload)}' | wl-copy --type text/uri-list`]
    }
}