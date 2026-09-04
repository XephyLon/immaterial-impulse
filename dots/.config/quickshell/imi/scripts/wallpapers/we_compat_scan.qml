import QtQuick
import Quickshell
import Quickshell.WallpaperEngine

// The Wallpaper Engine compatibility scanner, run BY the shell as its own
// `qs -p` process (services/WallpaperEngineCompat.qml spawns it): it loads
// each queued project into a real WallpaperEngineSurface and reports one
// JSON verdict line per project on stdout. A separate process on purpose -
// a project that wedges the renderer inside WE's setup() (which the surface
// answers by DETACHING the thread and leaking it) or that crashes the
// engine outright takes the scanner down, not the shell; the service
// respawns it for the rest of the queue.
//
// Standalone config: only binary modules (Quickshell, WallpaperEngine) are
// importable here, no qs.* singletons. The queue arrives as JSON in the
// WE_COMPAT_QUEUE environment variable: [{id, path}, ...].
//
// The window is small and titled rather than hidden, deliberately: a
// surface that is not rendered never produces a frame, so `rendered` -
// the scan's whole instrument - needs a mapped window. What a small
// window cannot judge is resolution-dependent VRAM exhaustion; the scan's
// verdicts are about STRUCTURAL breakage (a project.json the engine
// refuses, missing assets, a codec it cannot start), which is what stays
// true at every size.
ShellRoot {
    id: scanRoot

    property var queue: {
        try {
            const parsed = JSON.parse(Quickshell.env("WE_COMPAT_QUEUE") || "[]");
            return Array.isArray(parsed) ? parsed : [];
        } catch (e) {
            return [];
        }
    }
    property int index: -1

    function emitLine(payload) {
        // One JSON document per line, on STDERR (console.warn), not stdout.
        // qs's stdout logging is block-buffered when it is not a tty, so
        // verdicts sat in a 4-8KB buffer and arrived at the service in
        // bursts - and a renderer crash lost every line since the last
        // flush, including the "testing" marker that names the corpse, so
        // the service could not mark the crashing wallpaper and respawned
        // into the same crash. stderr is unbuffered, so every line lands as
        // it is written. The service strips the log prefix before parsing.
        console.warn(JSON.stringify(payload));
    }

    function next() {
        scanRoot.index += 1;
        if (scanRoot.index >= scanRoot.queue.length) {
            Qt.quit();
            return;
        }
        const entry = scanRoot.queue[scanRoot.index];
        scanRoot.emitLine({ id: entry.id, status: "testing" });
        deadline.restart();
        surface.projectPath = entry.path;
    }

    function verdict(status, error) {
        deadline.stop();
        const entry = scanRoot.queue[scanRoot.index];
        scanRoot.emitLine({ id: entry.id, status: status, error: error ?? "" });
    }

    FloatingWindow {
        id: window
        title: "Wallpaper compatibility scan"
        implicitWidth: 384
        implicitHeight: 216
        color: "#111111"

        WallpaperEngineSurface {
            id: surface
            anchors.fill: parent
            live: true

            onRenderedChanged: {
                if (!rendered || scanRoot.index < 0) return;
                scanRoot.verdict("ok");
                scanRoot.next();
            }
            onFailedChanged: {
                if (!failed || scanRoot.index < 0) return;
                scanRoot.verdict("broken", "the renderer could not start this wallpaper");
                scanRoot.next();
            }
        }

        // A project that neither renders nor fails inside the deadline is
        // reported broken and ends THIS scanner: switching away from a
        // wedged load leans on the surface's bounded-join/detach machinery,
        // and a leaked renderer thread in the scanner would sit under every
        // later verdict. Exiting is cheap - the service respawns with the
        // rest of the queue.
        Timer {
            id: deadline
            interval: 25000
            onTriggered: {
                scanRoot.verdict("broken", "timed out loading");
                Qt.quit();
            }
        }

        Component.onCompleted: scanRoot.next()
    }
}
