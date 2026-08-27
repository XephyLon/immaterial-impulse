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
 * constant `command -v` at construction (tests/lint_capability_probe_gating.py
 * is why every probe starts itself), and `missingFor(feature)` turns the
 * flags into the install guide's rows - one per missing dependency, with
 * the sibling fork's per-distro commands verbatim. `recheck()` re-runs
 * every probe, which is what the guide's Re-check button and a finished
 * install script call.
 *
 * The dependency table and the feature -> dependency mapping between the
 * sync markers are kept byte-for-byte in sync with the logic-only double
 * (tests/imports/testservices/PhoneDeps.qml);
 * tests/test_phone_sessions_contract.py enforces it.
 */
Singleton {
    id: root

    property bool scrcpy: false
    property bool adb: false
    property bool droidcamCli: false
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

    readonly property bool appModeSupported: root.scrcpy && root.scrcpyMajor >= 4

    // Probes still in flight. `ready` is false until the first sweep has
    // answered, so a card reads "checking" rather than "install" while the
    // probes run.
    property int probesPending: 0
    property bool probed: false
    readonly property bool ready: root.probed && root.probesPending === 0

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

    // Which dependencies a feature is missing, given the presence flags.
    // "mirror" is scrcpy + adb; "webcam" is DroidCam + the loopback module
    // (loaded or merely installed), with v4l-utils and mpv recommended;
    // "microphone" is pactl + either audio backend.
    function missingDeps(feature: string, flags: var): var {
        const f = flags ?? {};
        const missing = [];
        const need = (key, present) => { if (!present) missing.push(root.dependency(key)); };
        if (feature === "mirror") {
            need("scrcpy", f.scrcpy === true);
            need("android-tools", f.adb === true);
        } else if (feature === "webcam") {
            need("droidcam-cli", f.droidcamCli === true);
            need("v4l2loopback", f.v4l2loopbackLoaded === true || f.v4l2loopbackInstalled === true);
            need("v4l-utils", f.v4l2Ctl === true);
            need("mpv", f.mpv === true);
        } else if (feature === "microphone") {
            need("pactl", f.pactl === true);
            need("audio-backend", f.scrcpy === true || f.droidcamCli === true);
        }
        return missing;
    }
    // END phone-deps logic

    function flags(): var {
        return {
            scrcpy: root.scrcpy, adb: root.adb, droidcamCli: root.droidcamCli,
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
            root.scrcpy = exitCode === 0;
            if (root.scrcpy) {
                root.startProbe(versionProbe);
            } else {
                root.scrcpyVersion = "";
                root.scrcpyMajor = 0;
                root.scrcpyMinor = 0;
            }
        }
    }

    Process {
        id: versionProbe
        command: ["scrcpy", "--version"]
        stdout: StdioCollector { id: versionOut }
        onRunningChanged: if (!running) root.probeAnswered()
        onExited: (exitCode, exitStatus) => {
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
        onExited: (exitCode, exitStatus) => { root.adb = exitCode === 0; }
    }

    Process {
        id: droidcamProbe
        command: ["sh", "-c", "command -v droidcam-cli"]
        Component.onCompleted: root.startProbe(this)
        onRunningChanged: if (!running) root.probeAnswered()
        onExited: (exitCode, exitStatus) => { root.droidcamCli = exitCode === 0; }
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
