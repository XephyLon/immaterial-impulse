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
        PhoneScrcpy.reset()
        PhoneScrcpy.available = true
        PhoneScrcpy.appModeSupported = true
        PhoneCamera.reset()
        PhoneCamera.available = true
        Config.options.phone.scrcpy.appMode.favoritePackages = []
        Config.options.phone.scrcpy.useWireless = false
        Config.options.phone.scrcpy.autoWirelessIp = true
        Config.options.phone.scrcpy.wirelessIp = ""
        Config.options.phone.webcam.connection = "wifi"
        Config.options.phone.webcam.wifiIp = ""
        Config.options.phone.webcam.mirrorHorizontally = false
        Config.options.phone.webcam.rotateDegrees = 0
        Persistent.states.phone.scrcpy.recentPackages = []
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

    // ================================================================
    // PhoneScrcpy - the flag tables
    // ================================================================

    function test_scrcpy_mirror_args_from_the_defaults_is_the_bit_rate_alone() {
        compare(PhoneScrcpy.mirrorArgs(Config.options.phone.scrcpy), ["--video-bit-rate=8M"])
        compare(PhoneScrcpy.mirrorArgs({}), [])
        compare(PhoneScrcpy.mirrorArgs(null), [])
    }

    function test_scrcpy_mirror_args_carries_every_flag_in_the_forks_order() {
        const args = PhoneScrcpy.mirrorArgs({
            stayAwake: true, turnScreenOff: true, noPowerOn: true, noAudio: true, showTouches: true,
            fullscreen: true, alwaysOnTop: true, maxFps: 60, bitRate: "4M", maxSize: 1080, videoBuffer: 50
        })
        compare(args, ["--stay-awake", "--turn-screen-off", "--no-power-on", "--no-audio", "--show-touches",
                       "--fullscreen", "--always-on-top", "--max-fps=60", "--video-bit-rate=4M",
                       "--max-size=1080", "--video-buffer=50"])
        compare(PhoneScrcpy.mirrorArgs({ maxFps: 0, bitRate: "  ", maxSize: -1, videoBuffer: 0 }), [])
    }

    function test_scrcpy_app_mode_args_opens_a_virtual_display_when_flex_is_on() {
        compare(PhoneScrcpy.appModeArgs("org.mozilla.firefox", Config.options.phone.scrcpy.appMode),
                ["--start-app=org.mozilla.firefox", "--new-display=1280x960/160", "--flex-display", "--keep-active"])
        compare(PhoneScrcpy.appModeArgs("com.a", { flexDisplay: false }), ["--start-app=com.a"])
        compare(PhoneScrcpy.appModeArgs("com.a", { flexDisplay: true, displayWidth: 1920, displayHeight: 1080, density: 240, keepActive: false, systemDecorations: false }),
                ["--start-app=com.a", "--new-display=1920x1080/240", "--flex-display", "--no-vd-system-decorations"])
        compare(PhoneScrcpy.appModeArgs("com.a", { flexDisplay: true, displayWidth: 0 }),
                ["--start-app=com.a", "--new-display=1280x960/160", "--flex-display"])
    }

    function test_scrcpy_target_args_names_a_wireless_phone_only_when_asked() {
        compare(PhoneScrcpy.targetArgs({ useWireless: false }, phone()), [])
        compare(PhoneScrcpy.targetArgs({ useWireless: true, autoWirelessIp: true, wirelessPort: "5555" }, phone()),
                ["-s", "192.168.1.50:5555"])
        compare(PhoneScrcpy.targetArgs({ useWireless: true, autoWirelessIp: true, wirelessPort: "" }, phone({ reachableAddresses: ["", " 10.0.0.9 "] })),
                ["-s", "10.0.0.9:5555"])
        compare(PhoneScrcpy.targetArgs({ useWireless: true, autoWirelessIp: false, wirelessIp: "10.0.0.3", wirelessPort: "40001" }, phone()),
                ["-s", "10.0.0.3:40001"])
        compare(PhoneScrcpy.targetArgs({ useWireless: true, autoWirelessIp: false, wirelessIp: "10.0.0.3:41234" }, phone()),
                ["-s", "10.0.0.3:41234"])
        compare(PhoneScrcpy.targetArgs({ useWireless: true, autoWirelessIp: true }, phone({ reachableAddresses: [] })), [])
        compare(PhoneScrcpy.targetArgs({ useWireless: true, autoWirelessIp: true }, null), [])
    }

    function test_scrcpy_recents_are_mru_and_capped() {
        compare(PhoneScrcpy.pushRecent([], "a", 3), ["a"])
        compare(PhoneScrcpy.pushRecent(["a", "b"], "b", 3), ["b", "a"])
        compare(PhoneScrcpy.pushRecent(["a", "b", "c"], "d", 3), ["d", "a", "b"])
        compare(PhoneScrcpy.toggleInList(["a"], "b"), ["a", "b"])
        compare(PhoneScrcpy.toggleInList(["a", "b"], "a"), ["b"])
    }

    function test_scrcpy_backoff_doubles_from_one_second_to_a_thirty_second_cap() {
        compare(PhoneScrcpy.backoffDelay(1), 1000)
        compare(PhoneScrcpy.backoffDelay(2), 2000)
        compare(PhoneScrcpy.backoffDelay(5), 16000)
        compare(PhoneScrcpy.backoffDelay(6), 30000)
        compare(PhoneScrcpy.backoffDelay(40), 30000)
    }

    // ================================================================
    // PhoneScrcpy - the event ladder
    // ================================================================

    function test_scrcpy_started_and_exited_move_the_mirror_and_the_session_list() {
        PhoneScrcpy.mirrorLaunching = true
        PhoneScrcpy.handleLine('{"event":"started","id":"mirror","pid":4242,"title":"imi-phone-mirror-mirror"}')
        verify(PhoneScrcpy.mirrorRunning)
        verify(!PhoneScrcpy.mirrorLaunching)
        compare(PhoneScrcpy.sessionCount, 1)
        compare(PhoneScrcpy.sessions.get(0).title, "imi-phone-mirror-mirror")
        compare(PhoneScrcpy.sessions.get(0).pid, 4242)
        compare(PhoneScrcpy.sessions.get(0).package, "")
        PhoneScrcpy.handleLine('{"event":"started","id":"app:org.mozilla.firefox","pid":4300,"title":"imi-phone-app-app_org.mozilla.firefox"}')
        compare(PhoneScrcpy.sessionCount, 2)
        compare(PhoneScrcpy.sessions.get(1).package, "org.mozilla.firefox")
        verify(PhoneScrcpy.isAppRunning("org.mozilla.firefox"))
        // A repeat `started` (alreadyRunning) updates the row in place.
        PhoneScrcpy.handleLine('{"event":"started","id":"mirror","pid":4242,"title":"imi-phone-mirror-mirror","alreadyRunning":true}')
        compare(PhoneScrcpy.sessionCount, 2)
        PhoneScrcpy.handleLine('{"event":"exited","id":"mirror","code":0,"error":""}')
        verify(!PhoneScrcpy.mirrorRunning)
        compare(PhoneScrcpy.sessionCount, 1)
        compare(PhoneScrcpy.lastError, "")
        PhoneScrcpy.handleLine('{"event":"exited","id":"app:org.mozilla.firefox","code":1,"error":"ERROR: Could not find ADB device"}')
        compare(PhoneScrcpy.sessionCount, 0)
        compare(PhoneScrcpy.lastError, "ERROR: Could not find ADB device")
        compare(PhoneScrcpy.feedbackLog.length, 1)
        compare(PhoneScrcpy.feedbackLog[0].ok, false)
    }

    function test_scrcpy_an_error_event_ends_the_launch_and_names_the_cause() {
        PhoneScrcpy.mirrorLaunching = true
        PhoneScrcpy.handleLine('{"event":"error","id":"mirror","message":"Failed to launch scrcpy: [Errno 2]"}')
        verify(!PhoneScrcpy.mirrorLaunching)
        verify(!PhoneScrcpy.mirrorRunning)
        compare(PhoneScrcpy.lastError, "Failed to launch scrcpy: [Errno 2]")
    }

    function test_scrcpy_a_cached_app_list_shows_but_keeps_loading_until_the_live_one() {
        PhoneScrcpy.appsLoading = true
        PhoneScrcpy.handleLine('{"event":"apps_list","deviceId":"dev_1","apps":[{"package":"com.a","name":"A","system":false}],"cached":true}')
        compare(PhoneScrcpy.apps.length, 1)
        verify(PhoneScrcpy.appsLoading)
        PhoneScrcpy.handleLine('{"event":"apps_list","deviceId":"dev_1","apps":[{"package":"com.a","name":"A","system":false},{"package":"com.b","name":"B","system":true}]}')
        compare(PhoneScrcpy.apps.length, 2)
        verify(!PhoneScrcpy.appsLoading)
        compare(PhoneScrcpy.appsError, "")
    }

    function test_scrcpy_an_apps_error_keeps_the_list_on_screen() {
        PhoneScrcpy.apps = [{ package: "com.a", name: "A", system: false }]
        PhoneScrcpy.appsLoading = true
        PhoneScrcpy.handleLine('{"event":"apps_error","message":"Phone not reachable over ADB"}')
        verify(!PhoneScrcpy.appsLoading)
        compare(PhoneScrcpy.appsError, "Phone not reachable over ADB")
        compare(PhoneScrcpy.apps.length, 1)
    }

    function test_scrcpy_ignores_lines_that_are_not_events() {
        PhoneScrcpy.handleLine("")
        PhoneScrcpy.handleLine("not json")
        PhoneScrcpy.handleLine('{"cmd":"launch"}')
        PhoneScrcpy.handleLine('[1,2]')
        compare(PhoneScrcpy.sessionCount, 0)
        compare(PhoneScrcpy.lastError, "")
    }

    // ================================================================
    // PhoneScrcpy - the commands
    // ================================================================

    function test_scrcpy_launch_mirror_sends_the_flags_and_the_target() {
        Config.options.phone.scrcpy.useWireless = true
        PhoneScrcpy.launchMirror()
        verify(PhoneScrcpy.mirrorLaunching)
        compare(PhoneScrcpy.sentMessages.length, 1)
        const msg = PhoneScrcpy.sentMessages[0]
        compare(msg.cmd, "launch")
        compare(msg.id, "mirror")
        compare(msg.type, "mirror")
        compare(msg.target_args, ["-s", "192.168.1.50:5555"])
        compare(msg.extra_args, ["--video-bit-rate=8M"])
    }

    function test_scrcpy_launch_mirror_while_running_focuses_instead() {
        PhoneScrcpy.handleLine('{"event":"started","id":"mirror","pid":1,"title":"t"}')
        PhoneScrcpy.launchMirror()
        compare(PhoneScrcpy.sentMessages, [{ cmd: "focus", id: "mirror" }])
        PhoneScrcpy.stopMirror()
        compare(PhoneScrcpy.sentMessages[1], { cmd: "stop", id: "mirror" })
    }

    function test_scrcpy_launch_mirror_without_scrcpy_is_refused() {
        PhoneScrcpy.available = false
        PhoneScrcpy.launchMirror()
        verify(!PhoneScrcpy.mirrorLaunching)
        compare(PhoneScrcpy.sentMessages, [])
        compare(PhoneScrcpy.lastError, "scrcpy is not installed")
    }

    function test_scrcpy_refresh_apps_is_gated_on_app_mode_and_keyed_on_the_device() {
        PhoneScrcpy.appModeSupported = false
        PhoneScrcpy.refreshApps()
        compare(PhoneScrcpy.sentMessages, [])
        PhoneScrcpy.appModeSupported = true
        PhoneScrcpy.refreshApps()
        verify(PhoneScrcpy.appsLoading)
        compare(PhoneScrcpy.sentMessages, [{ cmd: "list_apps", target_args: [], deviceId: "dev_1" }])
        PhoneConnect.devices = []
        compare(PhoneScrcpy.deviceId(), "default")
    }

    function test_scrcpy_launch_app_sends_app_mode_and_records_the_recent() {
        PhoneScrcpy.launchApp("org.mozilla.firefox")
        compare(PhoneScrcpy.sentMessages.length, 1)
        const msg = PhoneScrcpy.sentMessages[0]
        compare(msg.cmd, "launch")
        compare(msg.id, "app:org.mozilla.firefox")
        compare(msg.type, "app")
        compare(msg.extra_args[0], "--start-app=org.mozilla.firefox")
        compare(msg.extra_args[1], "--new-display=1280x960/160")
        compare(Persistent.states.phone.scrcpy.recentPackages.length, 1)
        compare(String(Persistent.states.phone.scrcpy.recentPackages[0]), "org.mozilla.firefox")
        compare(String(PhoneScrcpy.recents[0]), "org.mozilla.firefox")
        // Launching a running app focuses it.
        PhoneScrcpy.handleLine('{"event":"started","id":"app:org.mozilla.firefox","pid":9,"title":"t"}')
        PhoneScrcpy.launchApp("org.mozilla.firefox")
        compare(PhoneScrcpy.sentMessages[1], { cmd: "focus", id: "app:org.mozilla.firefox" })
        PhoneScrcpy.stopApp("org.mozilla.firefox")
        compare(PhoneScrcpy.sentMessages[2], { cmd: "stop", id: "app:org.mozilla.firefox" })
        PhoneScrcpy.stopAllApps()
        compare(PhoneScrcpy.sentMessages[3], { cmd: "stop_all" })
        PhoneScrcpy.launchApp("")
        compare(PhoneScrcpy.sentMessages.length, 4)
    }

    function test_scrcpy_launch_app_needs_scrcpy_four() {
        PhoneScrcpy.appModeSupported = false
        PhoneScrcpy.launchApp("com.a")
        compare(PhoneScrcpy.sentMessages, [])
        compare(PhoneScrcpy.lastError, "scrcpy 4.0+ is required for App Mode")
        compare(PhoneScrcpy.feedbackLog.length, 1)
    }

    function test_scrcpy_favorites_live_in_config() {
        verify(!PhoneScrcpy.isFavorite("com.a"))
        PhoneScrcpy.toggleFavorite("com.a")
        verify(PhoneScrcpy.isFavorite("com.a"))
        compare(Config.options.phone.scrcpy.appMode.favoritePackages.length, 1)
        PhoneScrcpy.toggleFavorite("com.a")
        verify(!PhoneScrcpy.isFavorite("com.a"))
        compare(Config.options.phone.scrcpy.appMode.favoritePackages.length, 0)
    }

    function test_scrcpy_the_supervisor_is_wanted_while_anything_is_live_or_pending() {
        verify(!PhoneScrcpy.managerWanted())
        PhoneScrcpy.mirrorLaunching = true
        verify(PhoneScrcpy.managerWanted())
        PhoneScrcpy.mirrorLaunching = false
        PhoneScrcpy.appsLoading = true
        verify(PhoneScrcpy.managerWanted())
        PhoneScrcpy.appsLoading = false
        PhoneScrcpy.pendingMessages = [{ cmd: "focus", id: "mirror" }]
        verify(PhoneScrcpy.managerWanted())
        PhoneScrcpy.pendingMessages = []
        PhoneScrcpy.handleLine('{"event":"started","id":"mirror","pid":1,"title":"t"}')
        verify(PhoneScrcpy.managerWanted())
        PhoneScrcpy.handleLine('{"event":"exited","id":"mirror","code":0,"error":""}')
        verify(!PhoneScrcpy.managerWanted())
    }

    // ================================================================
    // PhoneCamera
    // ================================================================

    function test_camera_state_ladder() {
        compare(PhoneCamera.stateFor(false, true, true, true), "unavailable")
        compare(PhoneCamera.stateFor(true, false, false, false), "offline")
        compare(PhoneCamera.stateFor(true, true, false, false), "ready")
        compare(PhoneCamera.stateFor(true, true, true, false), "connecting")
        compare(PhoneCamera.stateFor(true, true, false, true), "active")
        compare(PhoneCamera.stateFor(true, false, false, true), "active")
        compare(PhoneCamera.state, "ready")
        PhoneCamera.available = false
        compare(PhoneCamera.state, "unavailable")
        PhoneCamera.available = true
        PhoneConnect.devices = [phone({ reachable: false })]
        compare(PhoneCamera.state, "offline")
    }

    function test_camera_finds_the_droidcam_node_in_v4l2_ctl_output() {
        // Captured on the development machine, DroidCam's own module.
        compare(PhoneCamera.parseV4l2Devices("Droidcam (platform:v4l2loopback_dc-000):\n\t/dev/video0\n"), "/dev/video0")
        const mixed = "Integrated Camera (usb-0000:00:14.0-8):\n\t/dev/video1\n\t/dev/video2\n\nDroidCam (platform:v4l2loopback-000):\n\t/dev/video10\n\t/dev/video11\n"
        compare(PhoneCamera.parseV4l2Devices(mixed), "/dev/video10")
        const loopbackOnly = "Integrated Camera (usb-0000:00:14.0-8):\n\t/dev/video1\n\nDummy video device (0x0000) (platform:v4l2loopback-000):\n\t/dev/video10\n"
        compare(PhoneCamera.parseV4l2Devices(loopbackOnly), "/dev/video10")
        compare(PhoneCamera.parseV4l2Devices("Integrated Camera (usb-0000:00:14.0-8):\n\t/dev/video1\n"), "")
        compare(PhoneCamera.parseV4l2Devices(""), "")
    }

    function test_camera_droidcam_args_single_dash_size_and_flips() {
        compare(PhoneCamera.droidcamArgs({ resolution: "1280x720" }, "usb", "", 4747),
                ["droidcam-cli", "-nocontrols", "-size=1280x720", "adb", "4747"])
        compare(PhoneCamera.droidcamArgs({ resolution: "640x480", mirrorHorizontally: true }, "wifi", "192.168.1.50", 4747),
                ["droidcam-cli", "-nocontrols", "-size=640x480", "-hflip", "192.168.1.50", "4747"])
        compare(PhoneCamera.droidcamArgs({ resolution: "", rotateDegrees: 180 }, "wifi", "10.0.0.2", 4748),
                ["droidcam-cli", "-nocontrols", "-hflip", "-vflip", "10.0.0.2", "4748"])
        compare(PhoneCamera.droidcamArgs({ mirrorHorizontally: true, rotateDegrees: 180 }, "usb", "", 4747),
                ["droidcam-cli", "-nocontrols", "-hflip", "-vflip", "adb", "4747"])
    }

    function test_camera_connection_plan_is_usb_first() {
        compare(PhoneCamera.connectionPlan({ connection: "usb" }, "", []), { mode: "usb", ip: "", port: 4747 })
        compare(PhoneCamera.connectionPlan({ connection: "wifi", wifiIp: " 10.0.0.5 ", port: 4750 }, "device", ["1.2.3.4"]),
                { mode: "wifi", ip: "10.0.0.5", port: 4750 })
        compare(PhoneCamera.connectionPlan({ connection: "wifi" }, "device\n", ["1.2.3.4"]), { mode: "usb", ip: "", port: 4747 })
        compare(PhoneCamera.connectionPlan({ connection: "wifi" }, "offline", ["", "1.2.3.4"]), { mode: "wifi", ip: "1.2.3.4", port: 4747 })
        verify(PhoneCamera.connectionPlan({ connection: "wifi" }, "", []).error.length > 0)
    }

    function test_camera_preview_falls_back_from_mpv_to_ffplay_to_vlc() {
        compare(PhoneCamera.previewCommand("/dev/video0", { mpv: true, ffplay: true, vlc: true }),
                ["mpv", "--profile=low-latency", "--no-fullscreen", "--no-osc", "--title=imi webcam preview", "av://v4l2:/dev/video0"])
        compare(PhoneCamera.previewCommand("/dev/video0", { ffplay: true, vlc: true })[0], "ffplay")
        compare(PhoneCamera.previewCommand("/dev/video0", { vlc: true }), ["vlc", "--no-video-title-show", "--no-fullscreen", "v4l2:///dev/video0"])
        compare(PhoneCamera.previewCommand("/dev/video0", {}), [])
        compare(PhoneCamera.previewCommand("", { mpv: true }), [])
    }

    function test_camera_start_probes_usb_then_launches_detached() {
        PhoneCamera.responder = argv => {
            if (argv[0] === "adb") return { text: "device\n", code: 0 }
            if (argv[2] === "launch") return { text: "31337\n", code: 0 }
            return null
        }
        PhoneCamera.start()
        verify(PhoneCamera.connecting)
        compare(PhoneCamera.state, "connecting")
        compare(argvJoined(PhoneCamera.ranCommands), [
            "adb get-state",
            "bash " + sessionScript + " launch video droidcam-cli -nocontrols -size=1280x720 adb 4747"
        ])
        compare(PhoneCamera.activeMode, "usb")
        compare(PhoneCamera.sessionPid, 31337)
        compare(PhoneCamera.connectTimersArmed, 1)
        compare(Persistent.states.phone.camera.lastMode, "usb")
        compare(Persistent.states.phone.camera.lastPort, 4747)
    }

    function test_camera_start_takes_a_configured_address_without_probing() {
        Config.options.phone.webcam.wifiIp = "10.0.0.7"
        Config.options.phone.webcam.mirrorHorizontally = true
        PhoneCamera.responder = argv => ({ text: "1\n", code: 0 })
        PhoneCamera.start()
        compare(argvJoined(PhoneCamera.ranCommands), [
            "bash " + sessionScript + " launch video droidcam-cli -nocontrols -size=1280x720 -hflip 10.0.0.7 4747"
        ])
        compare(PhoneCamera.activeIp, "10.0.0.7")
        compare(Persistent.states.phone.camera.lastIp, "10.0.0.7")
    }

    function test_camera_start_falls_back_to_kde_connects_address() {
        PhoneCamera.responder = argv => argv[0] === "adb" ? { text: "", code: 1 } : { text: "5\n", code: 0 }
        PhoneCamera.start()
        compare(PhoneCamera.activeMode, "wifi")
        compare(PhoneCamera.activeIp, "192.168.1.50")
    }

    function test_camera_start_with_nothing_to_connect_to_fails_with_a_reason() {
        PhoneConnect.devices = [phone({ reachableAddresses: [] })]
        PhoneCamera.responder = argv => ({ text: "", code: 1 })
        PhoneCamera.start()
        verify(!PhoneCamera.connecting)
        verify(PhoneCamera.lastError.indexOf("USB or Wi-Fi IP") >= 0)
        compare(PhoneCamera.ranCommands.length, 1)
    }

    function test_camera_start_is_refused_without_a_reachable_phone() {
        PhoneConnect.devices = [phone({ reachable: false })]
        PhoneCamera.start()
        verify(!PhoneCamera.connecting)
        compare(PhoneCamera.ranCommands, [])
        verify(PhoneCamera.lastError.length > 0)
        PhoneCamera.available = false
        PhoneConnect.devices = [phone()]
        PhoneCamera.start()
        compare(PhoneCamera.ranCommands, [])
    }

    function test_camera_a_live_status_makes_it_active_and_arms_the_watchdog() {
        PhoneCamera.connecting = true
        PhoneCamera.responder = argv => argv[2] === "status"
            ? { text: '{"session":"video","pid":"31337","alive":true,"started":"1787811446","port":"4747","mode":"usb","ip":"adb","device":"/dev/video0","video_running":true,"audio_running":false}\n', code: 0 }
            : null
        PhoneCamera.checkSession()
        verify(PhoneCamera.active)
        verify(!PhoneCamera.connecting)
        compare(PhoneCamera.state, "active")
        compare(PhoneCamera.device, "/dev/video0")
        compare(PhoneCamera.sessionPid, 31337)
        compare(PhoneCamera.startedAt, 1787811446)
        compare(PhoneCamera.watchdogArmed, 1)
        compare(argvJoined(PhoneCamera.ranCommands), ["bash " + sessionScript + " status video"])
    }

    function test_camera_a_dead_status_while_active_reports_the_loss() {
        PhoneCamera.active = true
        PhoneCamera.device = "/dev/video0"
        PhoneCamera.responder = argv => ({ text: '{"session":"video","pid":"","alive":false}', code: 0 })
        PhoneCamera.checkSession()
        verify(!PhoneCamera.active)
        compare(PhoneCamera.device, "")
        compare(PhoneCamera.lastError, "The webcam stream ended")
    }

    function test_camera_a_dead_status_past_the_deadline_fails_the_connect() {
        PhoneCamera.connecting = true
        PhoneCamera.responder = argv => ({ text: '{"alive":false}', code: 0 })
        PhoneCamera.checkSession()
        verify(PhoneCamera.connecting)
        PhoneCamera.deadlinePassed = true
        PhoneCamera.checkSession()
        verify(!PhoneCamera.connecting)
        verify(PhoneCamera.lastError.indexOf("9s") >= 0)
    }

    function test_camera_stop_goes_through_the_session_script() {
        PhoneCamera.active = true
        PhoneCamera.device = "/dev/video0"
        PhoneCamera.stop()
        verify(!PhoneCamera.active)
        verify(PhoneCamera.userStopped)
        compare(PhoneCamera.device, "")
        compare(argvJoined(PhoneCamera.ranCommands), ["bash " + sessionScript + " stop video"])
        PhoneCamera.stop()
        compare(PhoneCamera.ranCommands.length, 1)
    }

    function test_camera_mirror_writes_the_config_and_flips_the_live_device() {
        PhoneDeps.v4l2Ctl = true
        PhoneCamera.mirror(true)
        compare(Config.options.phone.webcam.mirrorHorizontally, true)
        compare(PhoneCamera.ranCommands, [])
        PhoneCamera.active = true
        PhoneCamera.device = "/dev/video0"
        PhoneCamera.mirror(false)
        compare(argvJoined(PhoneCamera.ranCommands), ["v4l2-ctl -d /dev/video0 --set-ctrl=horizontal_flip=0"])
        PhoneCamera.flip()
        compare(Config.options.phone.webcam.cameraFacing, "back")
        PhoneCamera.flip()
        compare(Config.options.phone.webcam.cameraFacing, "front")
    }

    function test_camera_parse_session_status_tolerates_the_scripts_strings() {
        const s = PhoneCamera.parseSessionStatus('{"session":"video","pid":"12","alive":"true","started":"7","port":"4747","mode":"wifi","ip":"1.2.3.4","device":""}')
        compare(s.alive, true)
        compare(s.pid, 12)
        compare(s.port, 4747)
        compare(s.ip, "1.2.3.4")
        compare(PhoneCamera.parseSessionStatus("not json"), null)
        compare(PhoneCamera.parseSessionStatus(""), null)
    }
}
