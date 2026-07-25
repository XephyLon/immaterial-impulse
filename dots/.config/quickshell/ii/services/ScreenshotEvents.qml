pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Central "a screenshot was taken" event source. The region selector emits
 * directly; Hyprland keybinds reach it over IPC:
 *   qs -c ii ipc call screenshot notify /path/to/shot.png
 * notify() validates before emitting: the file must exist and look like an
 * image. Validation is sanity (IPC is same-user), not a security boundary -
 * but consumers must still never splice the path into a shell string.
 */
Singleton {
    id: root

    signal screenshotTaken(string path)

    function emitIfValid(path) {
        const p = (path ?? "").trim();
        if (!p.startsWith("/")) {
            console.warn("[ScreenshotEvents] ignoring non-absolute path:", p);
            return;
        }
        if (!/\.(png|jpe?g|webp)$/i.test(p)) {
            console.warn("[ScreenshotEvents] ignoring non-image path:", p);
            return;
        }
        existenceProbe.probePath = p;
        existenceProbe.running = true;
    }

    // `test -e` with the path as an argument (never interpolated).
    Process {
        id: existenceProbe
        property string probePath: ""
        command: ["test", "-f", probePath]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0)
                root.screenshotTaken(existenceProbe.probePath);
            else
                console.warn("[ScreenshotEvents] ignoring missing file:", existenceProbe.probePath);
        }
    }

    IpcHandler {
        target: "screenshot"
        function notify(path: string): void {
            root.emitIfValid(path);
        }
    }
}
