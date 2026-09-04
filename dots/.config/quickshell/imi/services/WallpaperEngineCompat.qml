pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import "./we_compat.js" as WeCompat

/**
 * Wallpaper Engine compatibility verdicts - the reference app's
 * (jagrat7/linux-wallpaper-engine) bulk compatibility scanner, on this
 * shell's architecture: the scan runs in a SPAWNED `qs -p` scanner process
 * (scripts/wallpapers/we_compat_scan.qml) loading each project into a real
 * WallpaperEngineSurface, so one wallpaper that wedges or crashes the
 * renderer kills the scanner and not the shell; this service owns the queue,
 * respawns the scanner past the corpse, and records the verdicts.
 *
 * The store is its own raw-JSON file on the PluginState pattern (runtime
 * project ids, so never a JsonAdapter), and deliberately NOT the overrides
 * store: verdicts are scan-managed state, not user settings - the
 * reference's SCAN_MANAGED_KEYS split, as a file boundary.
 *
 * Decisions live in services/we_compat.js (tst_we_compat.qml drives them);
 * this file owns the disk and the process.
 */
Singleton {
    id: root

    readonly property string filePath: `${Directories.shellConfig}/wallpaper-engine-compat.json`

    // Map of project id -> { status: "ok"|"broken", error, testedAt }.
    property var results: ({})
    property bool ready: false

    property bool scanning: false
    property int scanTotal: 0
    property int scanDone: 0
    // The ids still owed a verdict this scan, and the one in flight - what
    // lets a scanner death mark its victim and the respawn skip it.
    property var pendingQueue: []
    property string inFlightId: ""
    // A scanner that dies without a "testing" line in flight died between
    // projects (or at startup); cap the respawns so a scanner that cannot
    // start at all does not loop forever.
    property int respawnsLeft: 0

    function statusFor(project) {
        return WeCompat.statusOf(project, root.results);
    }

    function startScan(projects, rescan) {
        if (root.scanning)
            return;
        const queue = WeCompat.scanQueue(projects, root.results, rescan === true);
        if (queue.length === 0)
            return;
        root.pendingQueue = queue;
        root.scanTotal = queue.length;
        root.scanDone = 0;
        root.inFlightId = "";
        root.respawnsLeft = queue.length + 2;
        root.scanning = true;
        root.spawnScanner();
    }

    function stopScan() {
        if (!root.scanning)
            return;
        root.scanning = false;
        root.pendingQueue = [];
        root.inFlightId = "";
        scanProcess.running = false;
        silenceWatchdog.stop();
    }

    function spawnScanner() {
        root.progressThisRun = false;
        scanProcess.environment = ({ WE_COMPAT_QUEUE: JSON.stringify(root.pendingQueue) });
        silenceWatchdog.restart();
        scanProcess.running = true;
    }

    function recordVerdict(verdict) {
        root.progressThisRun = true;
        root.results = WeCompat.applyVerdict(root.results, verdict, Date.now());
        root.pendingQueue = root.pendingQueue.filter(entry => entry.id !== verdict.id);
        root.inFlightId = "";
        root.scanDone = root.scanTotal - root.pendingQueue.length;
        writeTimer.restart();
    }

    // Whether the current scanner run has produced any verdict. A run that
    // dies with none, no corpse named and the queue unmoved would respawn
    // straight into the same crash - a scanner whose stderr was cut off
    // before the "testing" marker looks exactly like one that never started.
    property bool progressThisRun: false

    Process {
        id: scanProcess
        // `qs` resolves through the same wrapper that launched the shell, so
        // the scanner runs the exact renderer binary whose verdicts matter.
        command: ["qs", "-p", `${Directories.scriptPath}/wallpapers/we_compat_scan.qml`]
        // The protocol rides STDERR: qs's stdout logging is block-buffered
        // off a tty, so verdicts arrived in 4-8KB bursts and a renderer
        // crash lost every line since the last flush - including the marker
        // naming the wallpaper that crashed it.
        stderr: SplitParser {
            onRead: data => {
                // qs prefixes console output; the payload is the JSON
                // document from its first brace.
                const brace = data.indexOf("{");
                if (brace < 0)
                    return;
                silenceWatchdog.restart();
                const line = data.substring(brace);
                const verdict = WeCompat.parseLine(line);
                if (verdict) {
                    root.recordVerdict(verdict);
                    return;
                }
                // The "testing" marker is not a verdict; it names the corpse
                // if the scanner dies mid-project.
                try {
                    const marker = JSON.parse(line);
                    if (marker && marker.status === "testing" && marker.id)
                        root.inFlightId = String(marker.id);
                } catch (e) { /* a stray print; the watchdog owns silence */ }
            }
        }
        onExited: {
            silenceWatchdog.stop();
            if (!root.scanning)
                return;
            // A death mid-project is that project's verdict: the renderer
            // took the scanner down trying to load it. A death with NO
            // marker and NO progress this run is the same verdict for the
            // queue's head - the scanner starts at the head, so a crash
            // early enough to lose its own marker still names its victim by
            // position, and without this the respawn walks into the same
            // crash until the ladder is spent.
            if (root.inFlightId !== "") {
                root.recordVerdict({
                    id: root.inFlightId,
                    status: "broken",
                    error: "the renderer crashed loading this wallpaper"
                });
            } else if (!root.progressThisRun && root.pendingQueue.length > 0) {
                root.recordVerdict({
                    id: root.pendingQueue[0].id,
                    status: "broken",
                    error: "the renderer crashed loading this wallpaper"
                });
            }
            if (root.pendingQueue.length > 0 && root.respawnsLeft > 0) {
                root.respawnsLeft -= 1;
                root.spawnScanner();
                return;
            }
            root.scanning = false;
            root.pendingQueue = [];
        }
    }

    // A scanner that stops speaking - no verdict, no testing marker - past
    // the per-project deadline it enforces itself has hung somewhere the
    // deadline cannot reach; kill it and let onExited's machinery take over.
    Timer {
        id: silenceWatchdog
        interval: 40000
        onTriggered: scanProcess.running = false
    }

    Timer {
        id: reloadTimer
        interval: 100
        onTriggered: compatFile.reload()
    }

    Timer {
        id: writeTimer
        interval: 100
        onTriggered: compatFile.setText(JSON.stringify(root.results, null, 2))
    }

    FileView {
        id: compatFile
        path: Directories.configDirReady ? root.filePath : ""
        watchChanges: true
        onFileChanged: reloadTimer.restart()
        onLoaded: {
            try {
                root.results = WeCompat.sanitize(JSON.parse(compatFile.text()));
            } catch (e) {
                console.warn("[WallpaperEngineCompat] unreadable store, keeping in-memory state: " + e);
            }
            root.ready = true;
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                root.results = ({});
                root.ready = true;
            } else {
                console.warn("[WallpaperEngineCompat] failed to load: " + error);
            }
        }
    }
}
