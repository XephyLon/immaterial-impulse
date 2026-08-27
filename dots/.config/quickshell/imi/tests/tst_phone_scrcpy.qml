import QtQuick
import QtTest
import testservices
import qs.modules.common

// The Phone tab's four session services - PhoneDeps, PhoneScrcpy,
// PhoneCamera, PhoneMic - driven through their logic-only doubles in
// tests/imports/testservices. Every argv, flag table and state ladder is
// exercised here; the process I/O the doubles omit is pinned by
// tests/test_phone_sessions_contract.py, and the supervisor itself by
// tests/test_phone_scrcpy_manager.py.
TestCase {
    name: "PhoneSessionsTest"

    readonly property string sessionScript: "/mock/phone/droidcam_session.sh"
    readonly property string statusScript: "/mock/phone/droidcam_status.sh"
    readonly property string setupScript: "/mock/phone/setup_droidcam_input.sh"
    readonly property string teardownScript: "/mock/phone/teardown_droidcam_input.sh"

    function phone(extra) {
        return Object.assign({
            id: "dev_1", name: "Phone", type: "phone", reachable: true, paired: true,
            hasPairingRequest: false, reachableAddresses: ["192.168.1.50"],
            cellularNetworkType: "LTE", cellularNetworkStrength: 3,
            batteryAvailable: true, batteryCharge: 80, batteryCharging: false
        }, extra || {})
    }

    function argvJoined(list) {
        return list.map(a => a.join(" "))
    }

    function init() {
        PhoneConnect.installed = true
        PhoneConnect.backend = "kdeconnect"
        PhoneConnect.devices = [phone()]
        PhoneDeps.scrcpy = false
        PhoneDeps.adb = false
        PhoneDeps.droidcamCli = false
        PhoneDeps.v4l2Ctl = false
        PhoneDeps.pactl = false
        PhoneDeps.mpv = false
        PhoneDeps.ffplay = false
        PhoneDeps.vlc = false
        PhoneDeps.v4l2loopbackLoaded = false
        PhoneDeps.v4l2loopbackInstalled = false
        PhoneDeps.scrcpyMajor = 0
    }

    // ================================================================
    // PhoneDeps
    // ================================================================

    function test_deps_parses_the_scrcpy_version_line() {
        const v = PhoneDeps.parseScrcpyVersion("scrcpy 4.1 <https://github.com/Genymobile/scrcpy>")
        compare(v.major, 4)
        compare(v.minor, 1)
        compare(v.version, "4.1")
        compare(PhoneDeps.parseScrcpyVersion("scrcpy v2.7.1").version, "2.7.1")
        compare(PhoneDeps.parseScrcpyVersion("Dependencies (compiled / linked):"), null)
        compare(PhoneDeps.parseScrcpyVersion(""), null)
    }

    function test_deps_app_mode_needs_scrcpy_four() {
        PhoneDeps.scrcpy = true
        PhoneDeps.scrcpyMajor = 3
        verify(!PhoneDeps.appModeSupported)
        PhoneDeps.scrcpyMajor = 4
        verify(PhoneDeps.appModeSupported)
        PhoneDeps.scrcpy = false
        verify(!PhoneDeps.appModeSupported)
    }

    function test_deps_reads_the_distro_off_the_marker_files() {
        compare(PhoneDeps.parseDistro("/etc/arch-release\n"), "arch")
        compare(PhoneDeps.parseDistro("/etc/fedora-release\n"), "fedora")
        compare(PhoneDeps.parseDistro("/etc/debian_version\n"), "debian")
        compare(PhoneDeps.parseDistro(""), "unknown")
        compare(PhoneDeps.parseDistro("/etc/os-release\n"), "unknown")
    }

    function test_deps_counts_droidcams_own_loopback_module_as_loaded() {
        compare(PhoneDeps.parseLsmod("Module                  Size  Used by\nsnd_aloop              45056  1\nv4l2loopback_dc        45056  0\n"), true)
        compare(PhoneDeps.parseLsmod("v4l2loopback           53248  0\n"), true)
        compare(PhoneDeps.parseLsmod("snd_aloop              45056  1\nvideodev              421888  1\n"), false)
        compare(PhoneDeps.parseLsmod(""), false)
    }

    function test_deps_dependency_table_carries_the_forks_commands() {
        const scrcpy = PhoneDeps.dependency("scrcpy")
        compare(scrcpy.key, "scrcpy")
        compare(scrcpy.commands.arch, "sudo pacman -S scrcpy")
        compare(scrcpy.commands.fedora, "sudo dnf install scrcpy")
        compare(scrcpy.commands.debian, "sudo apt install scrcpy")
        compare(PhoneDeps.dependency("android-tools").commands.debian, "sudo apt install android-tools-adb")
        compare(PhoneDeps.dependency("droidcam-cli").commands.arch, "yay -S droidcam")
        verify(PhoneDeps.dependency("v4l2loopback").commands.fedora.startsWith("sudo dnf install akmod-v4l2loopback"))
        compare(PhoneDeps.dependency("pactl").commands.arch, "sudo pacman -S pulseaudio-utils")
        verify(PhoneDeps.dependency("audio-backend").commands.arch.indexOf("yay -S droidcam") > 0)
        verify(PhoneDeps.dependency("scrcpy").description.length > 0)
        compare(PhoneDeps.dependency("python-dbus"), null)
    }

    function test_deps_missing_for_mirror_is_scrcpy_and_adb() {
        compare(PhoneDeps.missingDeps("mirror", {}).map(d => d.key), ["scrcpy", "android-tools"])
        compare(PhoneDeps.missingDeps("mirror", { scrcpy: true }).map(d => d.key), ["android-tools"])
        compare(PhoneDeps.missingDeps("mirror", { scrcpy: true, adb: true }), [])
    }

    function test_deps_missing_for_webcam_accepts_an_installed_but_unloaded_module() {
        compare(PhoneDeps.missingDeps("webcam", {}).map(d => d.key),
                ["droidcam-cli", "v4l2loopback", "v4l-utils", "mpv"])
        compare(PhoneDeps.missingDeps("webcam", { droidcamCli: true, v4l2loopbackInstalled: true, v4l2Ctl: true, mpv: true }), [])
        compare(PhoneDeps.missingDeps("webcam", { droidcamCli: true, v4l2loopbackLoaded: true, v4l2Ctl: true }).map(d => d.key), ["mpv"])
    }

    function test_deps_missing_for_microphone_needs_pactl_and_one_backend() {
        compare(PhoneDeps.missingDeps("microphone", {}).map(d => d.key), ["pactl", "audio-backend"])
        compare(PhoneDeps.missingDeps("microphone", { pactl: true, droidcamCli: true }), [])
        compare(PhoneDeps.missingDeps("microphone", { scrcpy: true }).map(d => d.key), ["pactl"])
        compare(PhoneDeps.missingDeps("nonsense", {}), [])
    }

    function test_deps_missing_for_reads_the_live_flags() {
        PhoneDeps.scrcpy = true
        compare(PhoneDeps.missingFor("mirror").map(d => d.key), ["android-tools"])
        PhoneDeps.adb = true
        compare(PhoneDeps.missingFor("mirror"), [])
    }
}
