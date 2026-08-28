import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common

/**
 * The webcam preview player's LIFETIME, scored as a process that is either
 * still there or reaped.
 *
 * The defect: `openPreview()` spawned the player with
 * `Quickshell.execDetached`, which returns no handle - so ending the session
 * stopped the stream and left the player's window on screen, frozen on the
 * last frame the loopback device produced, with nothing in the shell able to
 * close it. Every check below is `kill -0 <pid>` against the pid the player
 * itself wrote, because "the flag went false" is exactly what the broken
 * version would also have reported.
 *
 * Five ways a session can end are driven, each one to the pid:
 *
 *   1. the user presses stop;
 *   2. the stream dies on its own and the service's own 5s watchdog finds
 *      the pidfile's process gone;
 *   3. the user closes the player's window, after which a later stop must
 *      reap nothing - a control process the harness started is asked;
 *   4. the phone disappears from the daemon;
 *   5. the shell goes away, which is the driver's half: the harness exits
 *      with a preview deliberately still up and
 *      tests/test_phone_preview_lifetime_runtime.py asks the kernel
 *      afterwards.
 *
 * The fakes are the load-bearing part. `droidcam-cli` on the maintainer's
 * machine cannot run at all (built against ffmpeg 8 on a system with 9), so
 * the stream is a stub of that name which prints the `Video: /dev/videoN`
 * line the session script greps for and then sits still until it is signalled
 * - and the REAL scripts/phone/droidcam_session.sh launches it, so the
 * pidfile, the status verb and the stop verb are the shell's own. The player
 * is a stub `mpv` which records its pid and then sits still likewise. Neither
 * can reach anything of the maintainer's: every XDG directory, the compositor
 * and the session bus belong to the driver.
 *
 * Driven by tests/test_phone_preview_lifetime_runtime.py.
 *
 *   PATH=<dir with the stubs>:$PATH qs -p PhonePreviewLifetimeRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int checksRun: 0
    property int elapsed: 0

    // Where the stub player writes its own pid, and the marker the fake
    // daemon reads to decide whether the phone is still on the network.
    readonly property string previewPidFile: Quickshell.env("PREVIEW_PIDFILE") ?? ""
    readonly property string absentMarker: Quickshell.env("PHONE_ABSENT_MARKER") ?? ""

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[PhonePreviewLifetime] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function finish() {
        console.log(`[PhonePreviewLifetime] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }

    // ---- asking the kernel about a pid ------------------------------------
    //
    // A property flipping is not evidence a process died: the whole defect
    // was a player nothing held, so the only honest instrument is `kill -0`
    // against a real pid. It is argv, never a shell string, for the same
    // reason the services are.

    property int watchedPid: 0
    property string watchedState: "unknown" // unknown | alive | gone

    function watchPid(pid) {
        harness.watchedState = "unknown";
        harness.watchedPid = pid;
    }

    Process {
        id: aliveProc
        onExited: (exitCode, exitStatus) => {
            harness.watchedState = exitCode === 0 ? "alive" : "gone";
        }
    }

    Timer {
        interval: 200
        repeat: true
        running: harness.watchedPid > 0
        onTriggered: if (!aliveProc.running) aliveProc.exec(["kill", "-0", String(harness.watchedPid)])
    }

    // The pid the stub player wrote for itself. Read back rather than taken
    // off the Process handle, so nothing about this measurement depends on a
    // property the service would have to grow for a test.
    property int playerPid: 0

    Process {
        id: readPid
        stdout: StdioCollector { id: readPidOut }
        onExited: (exitCode, exitStatus) => {
            harness.playerPid = exitCode === 0 ? (parseInt(readPidOut.text.trim()) || 0) : 0;
        }
    }

    function refreshPlayerPid() {
        if (!readPid.running)
            readPid.exec(["cat", harness.previewPidFile]);
    }

    // One-shot commands the harness itself issues (killing the stub stream,
    // planting the daemon's marker). Serialized behind one Process, because a
    // second exec on a running one terminates the first (AGENT.md).
    property var pending: []

    Process {
        id: cmdProc
        onExited: (exitCode, exitStatus) => harness.pump()
    }

    function runCmd(argv) {
        harness.pending = harness.pending.concat([argv]);
        harness.pump();
    }

    function pump() {
        if (cmdProc.running || harness.pending.length === 0)
            return;
        const next = harness.pending[0];
        harness.pending = harness.pending.slice(1);
        cmdProc.exec(next);
    }

    // The control for "a stop reaps only what it started": an unrelated
    // process, alive throughout, asked after the stop that follows a player
    // the user closed by hand. Without it, "nothing else died" is a claim
    // about a machine nobody looked at.
    Process { id: sentinel }

    // ---- the step runner ---------------------------------------------------

    property var waitPredicate: null
    property string waitLabel: ""
    property int waitElapsed: 0
    readonly property int waitTimeoutMs: 30000

    function waitUntil(label, predicate) {
        harness.waitLabel = label;
        harness.waitPredicate = predicate;
        harness.waitElapsed = 0;
    }

    function waitForPlayerGone() {
        harness.watchPid(harness.playerPid);
        harness.waitUntil("the player is reaped", () => harness.watchedState === "gone");
    }

    function waitForPlayerUp() {
        harness.waitUntil("the player starts and writes its pid", () => {
            if (!PhoneCamera.previewRunning)
                return false;
            harness.refreshPlayerPid();
            return harness.playerPid > 0;
        });
    }

    // The pidfile is emptied before every open, and the wait is on it being
    // gone: a round that read the file too early would find the PREVIOUS
    // round's pid sitting in it, which is dead, and would then score a
    // perfectly good player as never having started.
    function waitPidfileCleared() {
        harness.runCmd(["rm", "-f", harness.previewPidFile]);
        harness.waitUntil("the player's pidfile is cleared", () => {
            harness.refreshPlayerPid();
            return harness.playerPid === 0;
        });
    }

    Component.onCompleted: {
        // A singleton is constructed on first use; this read starts the
        // presence probes and the daemon sweep.
        console.log(`[PhonePreviewLifetime] services constructed, installed=${PhoneConnect.installed}`);
    }

    Timer {
        id: waitForReady
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            harness.elapsed += waitForReady.interval;
            const ready = Config.ready && PhoneConnect.installed
                && PhoneConnect.devices.length === 1 && PhoneDeps.ready
                && PhoneCamera.available;
            if (!ready) {
                if (harness.elapsed >= 40000) {
                    harness.check(`the fake daemon answered and the probes settled`
                                  + ` (devices ${PhoneConnect.devices.length},`
                                  + ` deps ready ${PhoneDeps.ready},`
                                  + ` camera available ${PhoneCamera.available})`, false);
                    harness.finish();
                }
                return;
            }
            waitForReady.running = false;
            steps.running = true;
        }
    }

    property var stepList: [
        () => sentinel.exec(["sleep", "600"]),

        // ---- 1. the user presses stop --------------------------------------
        () => PhoneCamera.start(),
        () => harness.waitUntil("the stream comes up",
                                () => PhoneCamera.active && PhoneCamera.device.length > 0),
        () => harness.check(`the stub stream is live on ${PhoneCamera.device}`
                            + ` at pid ${PhoneCamera.sessionPid}`,
                            PhoneCamera.active && PhoneCamera.sessionPid > 0),
        () => harness.waitPidfileCleared(),
        () => PhoneCamera.openPreview(),
        () => harness.waitForPlayerUp(),
        () => harness.watchPid(harness.playerPid),
        () => harness.waitUntil("the player is alive", () => harness.watchedState === "alive"),
        () => harness.check(`the player is running at pid ${harness.playerPid}`,
                            PhoneCamera.previewRunning && harness.watchedState === "alive"),
        () => PhoneCamera.stop(),
        () => harness.waitForPlayerGone(),
        () => harness.check(`the stop button reaps the player, pid ${harness.playerPid}`
                            + ` is ${harness.watchedState}`,
                            harness.watchedState === "gone" && !PhoneCamera.previewRunning),

        // ---- 2. the stream dies on its own, the watchdog finds it ----------
        () => PhoneCamera.start(),
        () => harness.waitUntil("the stream comes up again",
                                () => PhoneCamera.active && PhoneCamera.device.length > 0),
        () => harness.check(`the stub stream is live again at pid ${PhoneCamera.sessionPid}`,
                            PhoneCamera.active && PhoneCamera.sessionPid > 0),
        () => harness.waitPidfileCleared(),
        () => PhoneCamera.openPreview(),
        () => harness.waitForPlayerUp(),
        () => harness.watchPid(harness.playerPid),
        () => harness.waitUntil("the player is alive", () => harness.watchedState === "alive"),
        () => harness.check(`the player is running at pid ${harness.playerPid}`,
                            PhoneCamera.previewRunning && harness.watchedState === "alive"),
        // Nothing in the shell asks for this: the stream is killed under it,
        // the way droidcam-cli exits when the phone leaves the network.
        () => harness.runCmd(["kill", String(PhoneCamera.sessionPid)]),
        () => harness.waitUntil("the watchdog notices the stream has gone",
                                () => !PhoneCamera.active),
        () => harness.check(`the watchdog ended the session by itself,`
                            + ` lastError "${PhoneCamera.lastError}"`,
                            !PhoneCamera.active && PhoneCamera.lastError.length > 0),
        () => harness.waitForPlayerGone(),
        () => harness.check(`...and the player went with it, pid ${harness.playerPid}`
                            + ` is ${harness.watchedState}`,
                            harness.watchedState === "gone" && !PhoneCamera.previewRunning),

        // ---- 3. the user closes the player's window ------------------------
        () => PhoneCamera.start(),
        () => harness.waitUntil("the stream comes up a third time",
                                () => PhoneCamera.active && PhoneCamera.device.length > 0),
        () => harness.check(`the stub stream is live a third time at pid ${PhoneCamera.sessionPid}`,
                            PhoneCamera.active && PhoneCamera.sessionPid > 0),
        () => harness.waitPidfileCleared(),
        () => PhoneCamera.openPreview(),
        () => harness.waitForPlayerUp(),
        () => harness.watchPid(harness.playerPid),
        () => harness.waitUntil("the player is alive", () => harness.watchedState === "alive"),
        () => harness.check(`the player is running at pid ${harness.playerPid}`,
                            PhoneCamera.previewRunning && harness.watchedState === "alive"),
        () => harness.runCmd(["kill", String(harness.playerPid)]),
        () => harness.waitUntil("the service hears the player exit",
                                () => !PhoneCamera.previewRunning),
        () => harness.check(`closing the window clears the handle, previewRunning`
                            + ` ${PhoneCamera.previewRunning}`,
                            !PhoneCamera.previewRunning),
        // The pid the player held is now free for the kernel to reissue. A
        // service tracking that number would spend the stop below on
        // whatever holds it; a Process handle has nothing left to address.
        () => PhoneCamera.stop(),
        () => harness.waitUntil("the session ends", () => !PhoneCamera.active),
        () => harness.watchPid(parseInt(String(sentinel.processId)) || 0),
        () => harness.waitUntil("the control process answers",
                                () => harness.watchedState !== "unknown"),
        () => harness.check(`a stop after the player has gone reaps nothing else,`
                            + ` the control at pid ${harness.watchedPid} is ${harness.watchedState}`,
                            harness.watchedPid > 0 && harness.watchedState === "alive"),

        // ---- 4. the phone disappears from the daemon ----------------------
        () => PhoneCamera.start(),
        () => harness.waitUntil("the stream comes up a fourth time",
                                () => PhoneCamera.active && PhoneCamera.device.length > 0),
        () => harness.check(`the stub stream is live a fourth time at pid ${PhoneCamera.sessionPid}`,
                            PhoneCamera.active && PhoneCamera.sessionPid > 0),
        () => harness.waitPidfileCleared(),
        () => PhoneCamera.openPreview(),
        () => harness.waitForPlayerUp(),
        () => harness.watchPid(harness.playerPid),
        () => harness.waitUntil("the player is alive", () => harness.watchedState === "alive"),
        () => harness.check(`the player is running at pid ${harness.playerPid}`,
                            PhoneCamera.previewRunning && harness.watchedState === "alive"),
        // The daemon stops listing the phone, and the shell's own sweep is
        // what notices - never a write to the model from here.
        () => harness.runCmd(["touch", harness.absentMarker]),
        () => PhoneConnect.refresh(),
        () => harness.waitUntil("the daemon stops reporting the phone",
                                () => PhoneConnect.devices.length === 0),
        () => harness.check(`the phone is gone from the daemon's list,`
                            + ` activeDevice ${PhoneConnect.activeDevice === null}`,
                            PhoneConnect.devices.length === 0 && !PhoneCamera.deviceReachable),
        () => harness.waitUntil("the session ends with the device", () => !PhoneCamera.active),
        () => harness.check(`the session ended with the device`, !PhoneCamera.active),
        () => harness.waitForPlayerGone(),
        () => harness.check(`...and the player went with it, pid ${harness.playerPid}`
                            + ` is ${harness.watchedState}`,
                            harness.watchedState === "gone" && !PhoneCamera.previewRunning),

        // ---- 5. the shell goes away, with a preview deliberately up --------
        () => harness.runCmd(["rm", "-f", harness.absentMarker]),
        () => PhoneConnect.refresh(),
        () => harness.waitUntil("the phone comes back", () => PhoneConnect.devices.length === 1),
        () => harness.check(`the phone is back on the daemon's list`,
                            PhoneConnect.devices.length === 1 && PhoneCamera.deviceReachable),
        () => PhoneCamera.start(),
        () => harness.waitUntil("the stream comes up a fifth time",
                                () => PhoneCamera.active && PhoneCamera.device.length > 0),
        () => harness.waitPidfileCleared(),
        () => PhoneCamera.openPreview(),
        () => harness.waitForPlayerUp(),
        () => harness.watchPid(harness.playerPid),
        () => harness.waitUntil("the player is alive", () => harness.watchedState === "alive"),
        () => {
            // The before half of the driver's after: it reads this pid back
            // out of the same file once this process is gone, and a check
            // that only ran afterwards would pass on a player that never
            // started.
            console.log(`[PhonePreviewLifetime] player pid at exit: ${harness.playerPid}`);
            harness.check(`the player is up as the shell exits, pid ${harness.playerPid}`
                          + ` is ${harness.watchedState}`,
                          PhoneCamera.previewRunning && harness.watchedState === "alive");
        },

        () => harness.finish()
    ]

    property int stepIndex: 0
    Timer {
        id: steps
        interval: 250
        repeat: true
        onTriggered: {
            if (harness.waitPredicate !== null) {
                if (harness.waitPredicate()) {
                    harness.waitPredicate = null;
                    return;
                }
                harness.waitElapsed += steps.interval;
                if (harness.waitElapsed < harness.waitTimeoutMs)
                    return;
                harness.check(`${harness.waitLabel} (gave up after ${harness.waitElapsed}ms)`, false);
                harness.waitPredicate = null;
                harness.finish();
                return;
            }
            if (harness.stepIndex >= harness.stepList.length)
                return;
            harness.stepList[harness.stepIndex++]();
        }
    }
}
