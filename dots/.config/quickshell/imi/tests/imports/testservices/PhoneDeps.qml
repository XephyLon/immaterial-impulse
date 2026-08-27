pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick
import qs.services

// Logic-only double of services/PhoneDeps.qml: the flags are plain
// properties a test sets, the dependency table and the feature mapping
// between the sync markers are byte-for-byte the real service's
// (tests/test_phone_sessions_contract.py enforces it), and no probe runs.
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
    property string distro: "unknown"
    property bool adbDevice: false

    readonly property bool appModeSupported: root.scrcpy && root.scrcpyMajor >= 4

    property int probesPending: 0
    property bool probed: true
    readonly property bool ready: root.probed && root.probesPending === 0
    property int rechecks: 0

    // BEGIN phone-deps logic (synced with services/PhoneDeps.qml)
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

    function recheck(): void {
        root.rechecks++;
    }

    property int adbDeviceRefreshes: 0

    function refreshAdbDevices(): void {
        if (!root.adb) return;
        root.adbDeviceRefreshes++;
    }
}
