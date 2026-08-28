pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

/**
 * What the Phone tab's optional tooling looks like on this machine
 * (docs/superpowers/specs/2026-08-27-phone-tab-design.md, W3).
 *
 * Nothing here is an installer dependency: scrcpy, adb, DroidCam, the
 * v4l2loopback module, pactl and the preview players are all probed with a
 * constant `command -v` at construction
 * (tests/lint_capability_probe_gating.py is why every probe starts itself),
 * and `missingFor(feature)` turns the flags into the install guide's rows -
 * one per missing dependency, with the sibling fork's per-distro commands
 * verbatim. `recheck()` re-runs every probe, which is what the guide's
 * Re-check button and a finished install script call.
 *
 * A tool has THREE states here, not two. `command -v` answers presence; the
 * three binaries the tab spawns - scrcpy, adb and droidcam-cli - are then
 * actually STARTED, because a package linked against a library the system has
 * moved past is on PATH and dies before main, and a flag that says "present"
 * for it is a card that reads `ready` and does nothing when clicked. See
 * `parseLoaderFailure` for the measurement.
 *
 * The dependency table and the feature -> dependency mapping between the
 * sync markers are kept byte-for-byte in sync with the logic-only double
 * (tests/imports/testservices/PhoneDeps.qml);
 * tests/test_phone_sessions_contract.py enforces it.
 */
Singleton {
    id: root

    // PRESENCE is `command -v`. USABILITY is presence plus the binary
    // actually starting, and the three tools this tab SPAWNS are asked both
    // questions - see the run-probe block below for the machine that made
    // that difference matter. The plain names stay the ones every consumer
    // reads, because "can I use this tool" is the question they were all
    // really asking.
    property bool scrcpyPresent: false
    property bool adbPresent: false
    property bool droidcamCliPresent: false

    // The soname the dynamic loader could not find when one of those three is
    // on PATH and cannot start; "" for a binary that starts.
    property string scrcpyRunError: ""
    property string adbRunError: ""
    property string droidcamCliRunError: ""

    readonly property bool scrcpy: root.scrcpyPresent && root.scrcpyRunError.length === 0
    readonly property bool adb: root.adbPresent && root.adbRunError.length === 0
    readonly property bool droidcamCli: root.droidcamCliPresent && root.droidcamCliRunError.length === 0

    property bool v4l2Ctl: false
    property bool pactl: false
    property bool mpv: false
    property bool ffplay: false
    property bool vlc: false
    property bool kdialog: false
    property bool wlPaste: false
    property bool v4l2loopbackLoaded: false
    property bool v4l2loopbackInstalled: false
    property string scrcpyVersion: ""
    property int scrcpyMajor: 0
    property int scrcpyMinor: 0
    property string distro: "unknown" // arch | fedora | debian | unknown

    // Whether `adb devices` currently lists a phone in the `device` state.
    // The one thing here that is LIVE rather than a fact about what is
    // installed: a phone is plugged in and unplugged while the shell runs, so
    // `refreshAdbDevices()` exists and the card stack calls it while it is on
    // screen and has seen nothing. It lives beside the tooling because the
    // question a card asks before its click is the same shape - "can this
    // feature start at all" - and `unavailable` already answers the other
    // half of it.
    property bool adbDevice: false

    readonly property bool appModeSupported: root.scrcpy && root.scrcpyMajor >= 4

    // Probes still in flight. `ready` is false until the first sweep has
    // answered, so a card reads "checking" rather than "install" while the
    // probes run.
    property int probesPending: 0
    property bool probed: false
    readonly property bool ready: root.probed && root.probesPending === 0

    // How long a run probe may take before it is killed. Generous, because
    // the only thing a short one buys is a wrong answer.
    readonly property int runProbeTimeoutMs: 5000

    // BEGIN phone-deps logic (synced with tests/imports/testservices/PhoneDeps.qml)
    // `scrcpy --version` prints "scrcpy 4.1 <url>" on its first line.
    function parseScrcpyVersion(line: string): var {
        const match = /^scrcpy\s+v?(\d+)\.(\d+)(?:\.(\d+))?/.exec((line ?? "").trim());
        if (!match) return null;
        return {
            major: parseInt(match[1]),
            minor: parseInt(match[2]),
            version: match[1] + "." + match[2] + (match[3] ? "." + match[3] : "")
        };
    }

    // The distro probe prints every marker file that exists, one per line;
    // the first one names the distro.
    function parseDistro(text: string): string {
        for (const line of (text ?? "").split("\n")) {
            const file = line.trim();
            if (file === "/etc/arch-release") return "arch";
            if (file === "/etc/fedora-release") return "fedora";
            if (file === "/etc/debian_version") return "debian";
        }
        return "unknown";
    }

    // `lsmod` lists one module per line, name first. DroidCam's own build of
    // the module is `v4l2loopback_dc`, which counts.
    function parseLsmod(text: string): bool {
        return (text ?? "").split("\n").some(line => /^v4l2loopback(\b|_)/.test(line.trim()));
    }

    // `adb devices` prints a header line and then one `<serial>\t<state>` row
    // per transport. Only a row in the `device` state is a phone the tools can
    // drive: `unauthorized` is a phone that has not answered the RSA prompt
    // and `offline` a transport that has dropped, and either is a launch that
    // fails a second later with nothing on screen having said so. WHICH
    // transport is not answered here - the scrcpy supervisor resolves that
    // for itself on every launch, and a second answer to it would be a second
    // answer that can disagree.
    function parseAdbDevices(text: string): bool {
        for (const raw of (text ?? "").split("\n")) {
            const line = raw.trim();
            if (line.length === 0) continue;
            if (line.indexOf("List of devices") === 0) continue;
            const parts = line.split(/\s+/);
            if (parts.length >= 2 && parts[1] === "device") return true;
        }
        return false;
    }

    // Three states, not two, and the third is what `command -v` cannot see.
    // Measured on this machine: `droidcam-cli` was on PATH and died before
    // main with `error while loading shared libraries: libswscale.so.9:
    // cannot open shared object file` - the package built against ffmpeg 8 on
    // a system that had moved to ffmpeg 9's libswscale.so.10 - so the webcam
    // card read `ready`, the click did nothing, and the message the user was
    // given sent them to look at their phone.
    //
    // A dynamic-loader failure is distinctive and is NOT the same as a tool
    // that runs and exits non-zero: the loader writes that sentence to stderr
    // and the process comes back **127**, where `droidcam-cli` with no
    // arguments prints its usage and exits 1. Both halves are required, so a
    // tool that merely quotes the phrase is not classified by it, and 127
    // cannot be a shell's "command not found" here because every probe is a
    // constant argv with no shell on the path. Returns the soname the loader
    // could not find, or "" for a binary that started.
    function parseLoaderFailure(exitCode: int, stderrText: string): string {
        if (exitCode !== 127) return "";
        const match = /error while loading shared libraries:\s*([^\s:]+)/.exec(String(stderrText ?? ""));
        return match ? match[1] : "";
    }

    // The install guide's rows: the sibling fork's table, verbatim.
    function dependency(key: string): var {
        const table = {
            "scrcpy": {
                name: Translation.tr("scrcpy"),
                description: Translation.tr("Mirrors your phone screen in a floating SDL window. The main binary for screen mirroring."),
                commands: {
                    arch: "sudo pacman -S scrcpy",
                    fedora: "sudo dnf install scrcpy",
                    debian: "sudo apt install scrcpy"
                }
            },
            "android-tools": {
                name: Translation.tr("android-tools (adb)"),
                description: Translation.tr("Required for USB connection, quick actions (screenshot, power button) and opening apps from notifications."),
                commands: {
                    arch: "sudo pacman -S android-tools",
                    fedora: "sudo dnf install android-tools",
                    debian: "sudo apt install android-tools-adb"
                }
            },
            "droidcam-cli": {
                name: Translation.tr("DroidCam CLI"),
                description: Translation.tr("Connects to the DroidCam app on your phone and streams video to /dev/videoN"),
                commands: {
                    arch: "yay -S droidcam",
                    fedora: "# Enable RPM Fusion first, then:\nsudo dnf install android-tools\n# Download from https://www.dev47apps.com/droidcam/linux/",
                    debian: "# Download from https://www.dev47apps.com/droidcam/linux/\n# Or: sudo apt install droidcam"
                }
            },
            "v4l2loopback": {
                name: Translation.tr("v4l2loopback kernel module"),
                description: Translation.tr("Creates virtual /dev/videoN devices that DroidCam writes to. Without it, droidcam-cli has nowhere to stream."),
                commands: {
                    arch: "yay -S v4l2loopback-dkms\nsudo modprobe v4l2loopback\necho v4l2loopback | sudo tee /etc/modules-load.d/v4l2loopback.conf",
                    fedora: "sudo dnf install akmod-v4l2loopback\nsudo modprobe v4l2loopback\necho v4l2loopback | sudo tee /etc/modules-load.d/v4l2loopback.conf",
                    debian: "sudo apt install v4l2loopback-dkms\nsudo modprobe v4l2loopback\necho v4l2loopback | sudo tee /etc/modules-load.d/v4l2loopback.conf"
                }
            },
            "v4l-utils": {
                name: Translation.tr("v4l-utils (v4l2-ctl)"),
                description: Translation.tr("Recommended for device detection and live mirror/flip controls"),
                commands: {
                    arch: "sudo pacman -S v4l-utils",
                    fedora: "sudo dnf install v4l-utils",
                    debian: "sudo apt install v4l-utils"
                }
            },
            "mpv": {
                name: Translation.tr("mpv (optional)"),
                description: Translation.tr("Recommended for the webcam preview window. Falls back to ffplay/vlc if absent."),
                commands: {
                    arch: "sudo pacman -S mpv",
                    fedora: "sudo dnf install mpv",
                    debian: "sudo apt install mpv"
                }
            },
            "pactl": {
                name: Translation.tr("pactl (PulseAudio/PipeWire CLI)"),
                description: Translation.tr("Required for audio routing — creates a virtual null-sink that turns the phone mic stream into a recordable source."),
                commands: {
                    arch: "sudo pacman -S pulseaudio-utils",
                    fedora: "sudo dnf install pulseaudio-utils",
                    debian: "sudo apt install pulseaudio-utils"
                }
            },
            "audio-backend": {
                name: Translation.tr("scrcpy or DroidCam CLI"),
                description: Translation.tr("At least one audio backend is needed. scrcpy is preferred (no extra app on phone). DroidCam CLI is the fallback."),
                commands: {
                    arch: "# Option 1 (preferred):\nsudo pacman -S scrcpy\n# Option 2:\nyay -S droidcam",
                    fedora: "# Option 1 (preferred):\nsudo dnf install scrcpy\n# Option 2: install from https://www.dev47apps.com/droidcam/linux/",
                    debian: "# Option 1 (preferred):\nsudo apt install scrcpy\n# Option 2:\nsudo apt install droidcam"
                }
            }
        };
        const entry = table[key];
        if (!entry) return null;
        return { key: key, name: entry.name, description: entry.description, commands: entry.commands };
    }

    // A dependency row for a tool that IS installed and cannot start. The
    // install commands stay on it - reinstalling is the repair for a package
    // linked against a library the system has moved past, and on Arch
    // `yay -S droidcam` rebuilds it - but the description says what the
    // problem actually is, because "install DroidCam CLI" is a lie told to
    // somebody who has. An empty library name returns the row untouched, so
    // an absent tool reads exactly as it did before.
    function brokenDependency(entry: var, missingLibrary: string): var {
        const library = String(missingLibrary ?? "");
        if (!entry || library.length === 0) return entry;
        return {
            key: entry.key,
            name: entry.name,
            commands: entry.commands,
            broken: true,
            missingLibrary: library,
            description: Translation.tr("Installed, but it cannot start: the dynamic loader cannot find %1. This package was built against an older library than the system now ships, so it needs rebuilding or reinstalling rather than installing.").arg(library)
        };
    }

    // Which dependencies a feature is missing, given the presence flags.
    // "mirror" is scrcpy + adb; "webcam" is DroidCam + the loopback module
    // (loaded or merely installed), with v4l-utils and mpv recommended;
    // "microphone" is pactl + either audio backend.
    //
    // A tool that is present and cannot start counts as missing here - the
    // click does nothing either way, which is the whole complaint - and its
    // row carries `broken` and the loader's own missing library.
    function missingDeps(feature: string, flags: var): var {
        const f = flags ?? {};
        const missing = [];
        const need = (key, present, brokenBy) => {
            if (present) return;
            missing.push(root.brokenDependency(root.dependency(key), brokenBy));
        };
        const scrcpyBroken = String(f.scrcpyRunError ?? "");
        const adbBroken = String(f.adbRunError ?? "");
        const droidcamBroken = String(f.droidcamCliRunError ?? "");
        if (feature === "mirror") {
            need("scrcpy", f.scrcpy === true, scrcpyBroken);
            need("android-tools", f.adb === true, adbBroken);
        } else if (feature === "webcam") {
            need("droidcam-cli", f.droidcamCli === true, droidcamBroken);
            need("v4l2loopback", f.v4l2loopbackLoaded === true || f.v4l2loopbackInstalled === true, "");
            need("v4l-utils", f.v4l2Ctl === true, "");
            need("mpv", f.mpv === true, "");
        } else if (feature === "microphone") {
            need("pactl", f.pactl === true, "");
            need("audio-backend", f.scrcpy === true || f.droidcamCli === true,
                 scrcpyBroken.length > 0 ? scrcpyBroken : droidcamBroken);
        }
        return missing;
    }

    // END phone-deps logic

    function flags(): var {
        return {
            scrcpy: root.scrcpy, adb: root.adb, droidcamCli: root.droidcamCli,
            scrcpyRunError: root.scrcpyRunError, adbRunError: root.adbRunError,
            droidcamCliRunError: root.droidcamCliRunError,
            v4l2Ctl: root.v4l2Ctl, pactl: root.pactl, mpv: root.mpv, ffplay: root.ffplay,
            vlc: root.vlc, kdialog: root.kdialog, wlPaste: root.wlPaste,
            v4l2loopbackLoaded: root.v4l2loopbackLoaded,
            v4l2loopbackInstalled: root.v4l2loopbackInstalled
        };
    }

    function missingFor(feature: string): var {
        return root.missingDeps(feature, root.flags());
    }

    // Starts one probe and counts it; ready() waits for the count to return
    // to zero. Accounting hangs off `running` rather than `exited`, because a
    // binary that is not there fails to start without ever exiting.
    function startProbe(probe: var): void {
        if (probe.running) return;
        root.probesPending++;
        probe.running = true;
    }

    function recheck(): void {
        for (const probe of [scrcpyProbe, adbProbe, droidcamProbe, v4l2CtlProbe, pactlProbe,
                             mpvProbe, ffplayProbe, vlcProbe, kdialogProbe, wlPasteProbe,
                             lsmodProbe, modinfoProbe, distroProbe])
            root.startProbe(probe);
    }

    // Live state, so it is re-asked rather than answered once. Refused while
    // adb is not USABLE - a Process whose binary is not on PATH never emits
    // `exited`, so the flag would keep whatever it had while the probe count
    // still moved, and one that cannot start answers 127 to every question
    // there is.
    function refreshAdbDevices(): void {
        if (!root.adb) return;
        root.startProbe(adbDevicesProbe);
    }

    function probeAnswered(): void {
        root.probesPending = Math.max(0, root.probesPending - 1);
    }

    Component.onCompleted: root.probed = true

    // One constant `command -v` per tool. Each starts itself at construction
    // (the capability-probe lint's rule) and again from recheck(). The flag
    // is written from onExited; the pending count from onRunningChanged.
    Process {
        id: scrcpyProbe
        command: ["sh", "-c", "command -v scrcpy"]
        Component.onCompleted: root.startProbe(this)
        onRunningChanged: if (!running) root.probeAnswered()
        onExited: (exitCode, exitStatus) => {
            root.scrcpyPresent = exitCode === 0;
            if (root.scrcpyPresent) {
                root.startProbe(versionProbe);
            } else {
                root.scrcpyRunError = "";
                root.scrcpyVersion = "";
                root.scrcpyMajor = 0;
                root.scrcpyMinor = 0;
            }
        }
    }

    // scrcpy's run probe and its version probe are the same run: it is the
    // one of the three that already had to be started to be asked something.
    Process {
        id: versionProbe
        command: ["scrcpy", "--version"]
        stdout: StdioCollector { id: versionOut }
        stderr: StdioCollector { id: versionErr }
        onRunningChanged: {
            if (running) scrcpyRunGuard.restart();
            else { scrcpyRunGuard.stop(); root.probeAnswered(); }
        }
        onExited: (exitCode, exitStatus) => {
            root.scrcpyRunError = root.parseLoaderFailure(exitCode, versionErr.text);
            const parsed = root.parseScrcpyVersion(versionOut.text.split("\n")[0] ?? "");
            root.scrcpyVersion = parsed?.version ?? "";
            root.scrcpyMajor = parsed?.major ?? 0;
            root.scrcpyMinor = parsed?.minor ?? 0;
        }
    }

    Process {
        id: adbProbe
        command: ["sh", "-c", "command -v adb"]
        Component.onCompleted: root.startProbe(this)
        onRunningChanged: if (!running) root.probeAnswered()
        onExited: (exitCode, exitStatus) => {
            root.adbPresent = exitCode === 0;
            if (root.adbPresent) {
                root.startProbe(adbRunProbe);
            } else {
                root.adbRunError = "";
                root.adbDevice = false;
            }
        }
    }

    // `adb --version` prints the client's banner and starts no server -
    // measured, it answers instantly on a machine with no adb server running.
    // Started by the presence probe's own exit rather than from anything a
    // feature does, which is the capability-probe gating rule
    // (tests/lint_capability_probe_gating.py) followed one hop along.
    Process {
        id: adbRunProbe
        command: ["adb", "--version"]
        stdout: StdioCollector {}
        stderr: StdioCollector { id: adbRunErr }
        onRunningChanged: {
            if (running) adbRunGuard.restart();
            else { adbRunGuard.stop(); root.probeAnswered(); }
        }
        onExited: (exitCode, exitStatus) => {
            root.adbRunError = root.parseLoaderFailure(exitCode, adbRunErr.text);
            if (root.adb) root.startProbe(adbDevicesProbe);
            else root.adbDevice = false;
        }
    }

    // Not started from Component.onCompleted and not in recheck()'s list: it
    // is started by the presence probe above, which recheck() does restart, so
    // a machine without adb never spawns it at all.
    Process {
        id: adbDevicesProbe
        command: ["adb", "devices"]
        stdout: StdioCollector { id: adbDevicesOut }
        stderr: StdioCollector {}
        onRunningChanged: if (!running) root.probeAnswered()
        onExited: (exitCode, exitStatus) => {
            root.adbDevice = exitCode === 0 && root.parseAdbDevices(adbDevicesOut.text);
        }
    }

    Process {
        id: droidcamProbe
        command: ["sh", "-c", "command -v droidcam-cli"]
        Component.onCompleted: root.startProbe(this)
        onRunningChanged: if (!running) root.probeAnswered()
        onExited: (exitCode, exitStatus) => {
            root.droidcamCliPresent = exitCode === 0;
            if (root.droidcamCliPresent) root.startProbe(droidcamRunProbe);
            else root.droidcamCliRunError = "";
        }
    }

    // Bare, because nothing droidcam-cli accepts exits zero: with no
    // arguments it prints its usage to stderr and exits 1, which is a tool
    // that RAN. The loader failure this exists for happens before main, so
    // the arguments are beside the point - what matters is that the command
    // returns promptly, which a usage message does.
    Process {
        id: droidcamRunProbe
        command: ["droidcam-cli"]
        stdout: StdioCollector {}
        stderr: StdioCollector { id: droidcamRunErr }
        onRunningChanged: {
            if (running) droidcamRunGuard.restart();
            else { droidcamRunGuard.stop(); root.probeAnswered(); }
        }
        onExited: (exitCode, exitStatus) => {
            root.droidcamCliRunError = root.parseLoaderFailure(exitCode, droidcamRunErr.text);
        }
    }

    // A tool that BLOCKS is neither of the two states this file can report,
    // and it must not become a probe that never answers: the guard kills it
    // and lets its own exit classify it, which lands on "it runs" because a
    // killed process is not a loader failure. Erring that way is deliberate -
    // claiming a tool is broken on the strength of it being slow is a worse
    // lie than the one this whole block replaced.
    Timer {
        id: scrcpyRunGuard
        interval: root.runProbeTimeoutMs
        onTriggered: if (versionProbe.running) versionProbe.signal(15)
    }

    Timer {
        id: adbRunGuard
        interval: root.runProbeTimeoutMs
        onTriggered: if (adbRunProbe.running) adbRunProbe.signal(15)
    }

    Timer {
        id: droidcamRunGuard
        interval: root.runProbeTimeoutMs
        onTriggered: if (droidcamRunProbe.running) droidcamRunProbe.signal(15)
    }

    Process {
        id: v4l2CtlProbe
        command: ["sh", "-c", "command -v v4l2-ctl"]
        Component.onCompleted: root.startProbe(this)
        onRunningChanged: if (!running) root.probeAnswered()
        onExited: (exitCode, exitStatus) => { root.v4l2Ctl = exitCode === 0; }
    }

    Process {
        id: pactlProbe
        command: ["sh", "-c", "command -v pactl"]
        Component.onCompleted: root.startProbe(this)
        onRunningChanged: if (!running) root.probeAnswered()
        onExited: (exitCode, exitStatus) => { root.pactl = exitCode === 0; }
    }

    Process {
        id: mpvProbe
        command: ["sh", "-c", "command -v mpv"]
        Component.onCompleted: root.startProbe(this)
        onRunningChanged: if (!running) root.probeAnswered()
        onExited: (exitCode, exitStatus) => { root.mpv = exitCode === 0; }
    }

    Process {
        id: ffplayProbe
        command: ["sh", "-c", "command -v ffplay"]
        Component.onCompleted: root.startProbe(this)
        onRunningChanged: if (!running) root.probeAnswered()
        onExited: (exitCode, exitStatus) => { root.ffplay = exitCode === 0; }
    }

    Process {
        id: vlcProbe
        command: ["sh", "-c", "command -v vlc"]
        Component.onCompleted: root.startProbe(this)
        onRunningChanged: if (!running) root.probeAnswered()
        onExited: (exitCode, exitStatus) => { root.vlc = exitCode === 0; }
    }

    Process {
        id: kdialogProbe
        command: ["sh", "-c", "command -v kdialog"]
        Component.onCompleted: root.startProbe(this)
        onRunningChanged: if (!running) root.probeAnswered()
        onExited: (exitCode, exitStatus) => { root.kdialog = exitCode === 0; }
    }

    Process {
        id: wlPasteProbe
        command: ["sh", "-c", "command -v wl-paste"]
        Component.onCompleted: root.startProbe(this)
        onRunningChanged: if (!running) root.probeAnswered()
        onExited: (exitCode, exitStatus) => { root.wlPaste = exitCode === 0; }
    }

    Process {
        id: lsmodProbe
        command: ["lsmod"]
        stdout: StdioCollector { id: lsmodOut }
        Component.onCompleted: root.startProbe(this)
        onRunningChanged: if (!running) root.probeAnswered()
        onExited: (exitCode, exitStatus) => {
            root.v4l2loopbackLoaded = exitCode === 0 && root.parseLsmod(lsmodOut.text);
        }
    }

    Process {
        id: modinfoProbe
        command: ["modinfo", "v4l2loopback"]
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        Component.onCompleted: root.startProbe(this)
        onRunningChanged: if (!running) root.probeAnswered()
        onExited: (exitCode, exitStatus) => {
            root.v4l2loopbackInstalled = exitCode === 0;
        }
    }

    Process {
        id: distroProbe
        command: ["sh", "-c", "for f in /etc/arch-release /etc/fedora-release /etc/debian_version; do [ -f \"$f\" ] && echo \"$f\"; done; true"]
        stdout: StdioCollector { id: distroOut }
        Component.onCompleted: root.startProbe(this)
        onRunningChanged: if (!running) root.probeAnswered()
        onExited: (exitCode, exitStatus) => {
            root.distro = root.parseDistro(distroOut.text);
        }
    }
}
