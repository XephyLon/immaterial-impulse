import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import Quickshell
import Quickshell.Io
import "warp_status.js" as WarpStatus

QuickToggleModel {
    id: root
    name: Translation.tr("Cloudflare WARP")

    toggled: false
    icon: "cloud_lock"
    
    mainAction: () => {
        if (toggled) {
            root.toggled = false
            Quickshell.execDetached(["warp-cli", "disconnect"])
        } else {
            root.toggled = true
            Quickshell.execDetached(["warp-cli", "connect"])
        }
    }

    Process {
        id: connectProc
        command: ["warp-cli", "connect"]
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                Quickshell.execDetached(["notify-send", 
                    Translation.tr("Cloudflare WARP"), 
                    Translation.tr("Connection failed. Please inspect manually with the <tt>warp-cli</tt> command")
                    , "-a", "Shell"
                ])
            }
        }
    }

    Process {
        id: registrationProc
        command: ["warp-cli", "registration", "new"]
        onExited: (exitCode, exitStatus) => {
            console.log("Warp registration exited with code and status:", exitCode, exitStatus)
            if (exitCode === 0) {
                connectProc.running = true
            } else {
                Quickshell.execDetached(["notify-send", 
                    Translation.tr("Cloudflare WARP"), 
                    Translation.tr("Registration failed. Please inspect manually with the <tt>warp-cli</tt> command"),
                    "-a", "Shell"
                ])
            }
        }
    }

    Process {
        id: fetchActiveState
        running: true
        command: ["bash", "-c", "warp-cli status"]
        stdout: StdioCollector {
            id: warpStatusCollector
            onStreamFinished: {
                // The reading lives in warp_status.js (tests/tst_warp_status.qml).
                const status = WarpStatus.parse(warpStatusCollector.text)
                if (status.available) root.available = true
                if (status.state === "unregistered") registrationProc.running = true
                else if (status.state === "connected") root.toggled = true
                else if (status.state === "disconnected") root.toggled = false
            }
        }
    }
    tooltipText: Translation.tr("Cloudflare WARP (1.1.1.1)")
}
