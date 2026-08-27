import QtTest
import "../modules/imi/sidebarLeft/phone/phone_cards.js" as PhoneCards

// Everything the Phone tab's feature cards and its install guide decide: the
// five-state ladder, which title and subtitle each state asks for, the elapsed
// time on an active card's detail line, the guide's distro preselection and
// its command table lookup, and the Android Apps page's local filter.
//
// The drawn cards are not reachable from here - qmltestrunner can build
// neither a RippleButton nor a laid-out box - so the decisions live in
// phone_cards.js and this is where they are exercised.
// tests/test_phone_tab_surface_contract.py is the other half: it holds the
// call sites to the services that answer them, and every key below to a
// Translation.tr arm.
TestCase {
    name: "PhoneCardsTest"

    // ---------------------------------------------------------------------
    // The state ladder
    // ---------------------------------------------------------------------

    function test_a_feature_with_no_tooling_is_unavailable_whatever_else_is_true() {
        // Unavailable outranks everything: a machine without droidcam-cli
        // cannot have an active webcam, and a card that reported one would
        // offer a Stop button for a session that does not exist.
        compare(PhoneCards.cardState(false, true, true, true), "unavailable");
        compare(PhoneCards.cardState(false, false, false, false), "unavailable");
    }

    function test_an_active_feature_outranks_an_unreachable_phone() {
        // The phone dropping off the network does not stop the stream that is
        // already running - the watchdog does, and until it says so the card
        // is active.
        compare(PhoneCards.cardState(true, false, false, true), "active");
    }

    function test_connecting_outranks_offline_and_ready() {
        compare(PhoneCards.cardState(true, false, true, false), "connecting");
        compare(PhoneCards.cardState(true, true, true, false), "connecting");
    }

    function test_a_reachable_phone_with_nothing_running_is_ready() {
        compare(PhoneCards.cardState(true, true, false, false), "ready");
        compare(PhoneCards.cardState(true, false, false, false), "offline");
    }

    // ---------------------------------------------------------------------
    // The mirror's own ladder
    // ---------------------------------------------------------------------

    function test_the_mirror_reads_a_launch_error_as_offline() {
        // scrcpy failing to launch leaves nothing running, and the subtitle
        // already carries the error - a sixth state would say it twice.
        compare(PhoneCards.mirrorState({
            available: true, reachable: true, running: false, launching: false,
            error: "scrcpy: no device found"
        }), "offline");
        compare(PhoneCards.mirrorSubtitleKey({
            available: true, reachable: true, running: false, launching: false,
            error: "scrcpy: no device found"
        }), "error");
    }

    function test_a_running_mirror_outranks_its_last_error() {
        // lastError is not cleared by a later success on every path, so a
        // stale one must not take a live mirror out of the active state.
        compare(PhoneCards.mirrorState({
            available: true, reachable: true, running: true, error: "an old failure"
        }), "active");
        compare(PhoneCards.mirrorSubtitleKey({
            available: true, reachable: true, running: true, error: "an old failure"
        }), "running");
    }

    function test_a_phone_adb_cannot_see_is_offline_before_the_click() {
        // The machine this was found on: KDE Connect reaches the phone over
        // LAN and `adb devices` lists nothing, so scrcpy has nothing to attach
        // to - and the card said "Opens a floating window for the active
        // phone" right up until the click.
        const away = {
            available: true, reachable: true, running: false, launching: false,
            adbDevice: false, error: ""
        };
        compare(PhoneCards.mirrorState(away), "offline");
        compare(PhoneCards.mirrorSubtitleKey(away), "noDevice");
    }

    function test_a_launch_that_failed_outranks_the_precondition_it_failed_on() {
        // This assertion used to run the other way, on the reasoning that
        // "the phone is not on ADB" is what to DO about scrcpy's exit. The
        // reasoning held while `error` was PhoneScrcpy.lastError - any
        // session's failure, possibly an hour old - and it is wrong now that
        // the flag carries the mirror's OWN error, cleared by every
        // launchMirror(): a non-empty one means the click the user just made
        // failed, and "No device over ADB" is the line the card was already
        // showing before that click. Preferring it made a failed launch and
        // no launch at all the same two words, which is the silent snap back
        // the recording caught.
        const away = {
            available: true, reachable: true, running: false, launching: false,
            adbDevice: false, error: "ERROR: Could not find any ADB device"
        };
        compare(PhoneCards.mirrorState(away), "offline");
        compare(PhoneCards.mirrorSubtitleKey(away), "error");
        // A launching card still outranks both: the failure being carried
        // belongs to the launch before this one.
        compare(PhoneCards.mirrorSubtitleKey(Object.assign({}, away, { launching: true })), "launching");
        compare(PhoneCards.mirrorState(Object.assign({}, away, { launching: true })), "connecting");
    }

    function test_the_window_between_the_click_and_the_answer_is_never_running() {
        // The recorded defect: the supervisor's `started` means it SPAWNED
        // scrcpy, so the card read "scrcpy Mirror / Mirror is running - click
        // to focus its window" with a filled check on a machine adb had never
        // seen a phone on. Whatever else is true, a launching mirror draws as
        // connecting - no check mark, no detail line, no focus invitation.
        const launching = {
            available: true, reachable: true, running: false, launching: true,
            adbDevice: false, error: ""
        };
        compare(PhoneCards.mirrorState(launching), "connecting");
        compare(PhoneCards.mirrorTitleKey(launching), "connecting");
        compare(PhoneCards.mirrorSubtitleKey(launching), "launching");
    }

    function test_a_probe_that_has_not_answered_yet_is_not_a_refusal() {
        // Every PhoneDeps flag starts false, so a plain falsy test would put
        // every card on "no device" for the first frames of every session -
        // and would refuse for ever at any call site that forgot the flag.
        const unknown = { available: true, reachable: true, running: false, launching: false };
        compare(PhoneCards.mirrorState(unknown), "ready");
        compare(PhoneCards.mirrorSubtitleKey(unknown), "ready");
        compare(PhoneCards.mirrorState(Object.assign({}, unknown, { adbDevice: undefined })), "ready");
        compare(PhoneCards.mirrorState(Object.assign({}, unknown, { adbDevice: true })), "ready");
    }

    function test_a_running_mirror_outranks_adb_losing_sight_of_the_phone() {
        // The transport dropping does not stop the window that is already up;
        // the supervisor's exit event is what does.
        compare(PhoneCards.mirrorState({
            available: true, reachable: true, running: true, adbDevice: false
        }), "active");
        compare(PhoneCards.mirrorSubtitleKey({
            available: true, reachable: true, running: true, adbDevice: false
        }), "running");
    }

    function test_the_mirror_titles_follow_its_ladder() {
        compare(PhoneCards.mirrorTitleKey({ available: false }), "install");
        compare(PhoneCards.mirrorTitleKey({ available: true, running: true }), "running");
        compare(PhoneCards.mirrorTitleKey({ available: true, launching: true }), "connecting");
        compare(PhoneCards.mirrorTitleKey({ available: true }), "open");
    }

    function test_only_the_first_line_of_an_error_reaches_a_subtitle() {
        compare(PhoneCards.errorHeadline("first line\nsecond line\nthird"), "first line");
        compare(PhoneCards.errorHeadline(""), "");
        compare(PhoneCards.errorHeadline(undefined), "");
        // Whitespace only is not an error: it would take a ready card offline
        // and put a blank subtitle on it.
        compare(PhoneCards.errorHeadline("   \n  "), "");
        compare(PhoneCards.mirrorState({
            available: true, reachable: true, error: "   "
        }), "ready");
    }

    // ---------------------------------------------------------------------
    // Webcam and microphone subtitles
    // ---------------------------------------------------------------------

    function test_an_active_webcam_names_its_device_when_it_has_one() {
        compare(PhoneCards.webcamSubtitleKey({
            available: true, reachable: true, active: true, device: "/dev/video2"
        }), "device");
        // v4l2-ctl is optional, so an active stream may have no device path to
        // show. It still says it is running.
        compare(PhoneCards.webcamSubtitleKey({
            available: true, reachable: true, active: true, device: ""
        }), "running");
    }

    function test_the_webcam_ladder_is_the_cards_ladder() {
        compare(PhoneCards.webcamSubtitleKey({ available: false }), "install");
        compare(PhoneCards.webcamSubtitleKey({ available: true, reachable: false }), "offline");
        compare(PhoneCards.webcamSubtitleKey({ available: true, reachable: true, connecting: true }), "connecting");
        compare(PhoneCards.webcamSubtitleKey({ available: true, reachable: true }), "ready");
        compare(PhoneCards.webcamTitleKey(true), "webcam");
        compare(PhoneCards.webcamTitleKey(false), "install");
    }

    function test_a_muted_microphone_says_so_rather_than_saying_active() {
        compare(PhoneCards.micSubtitleKey({
            available: true, reachable: true, active: true, muted: true
        }), "muted");
        compare(PhoneCards.micSubtitleKey({
            available: true, reachable: true, active: true, muted: false
        }), "active");
        compare(PhoneCards.micSubtitleKey({ available: true, reachable: true, connecting: true }), "connecting");
        compare(PhoneCards.micSubtitleKey({ available: true, reachable: true }), "ready");
        compare(PhoneCards.micSubtitleKey({ available: false }), "install");
        compare(PhoneCards.micTitleKey(true), "mic");
        compare(PhoneCards.micTitleKey(false), "install");
    }

    function test_a_failed_launch_reaches_the_webcam_and_microphone_subtitles() {
        // Both services leave `lastError` set and go back to `ready`, and the
        // card draws lastError only while it is ACTIVE - so a webcam that
        // could not connect was a card back on "Tap to start", which is
        // exactly what "clicking it does nothing" looked like.
        compare(PhoneCards.webcamSubtitleKey({
            available: true, reachable: true, error: "DroidCam did not start"
        }), "error");
        compare(PhoneCards.micSubtitleKey({
            available: true, reachable: true, error: "Phone microphone process exited"
        }), "error");
        // Whitespace is not an error: it would replace a usable "Tap to
        // start" with a blank line.
        compare(PhoneCards.webcamSubtitleKey({
            available: true, reachable: true, error: "  \n "
        }), "ready");
        compare(PhoneCards.micSubtitleKey({ available: true, reachable: true, error: "" }), "ready");
    }

    function test_a_live_session_outranks_the_error_it_has_not_hit_yet() {
        // lastError is cleared by the next start() and by nothing else, so a
        // stale one must not take a running stream off its own state.
        compare(PhoneCards.webcamSubtitleKey({
            available: true, reachable: true, active: true, device: "/dev/video2",
            error: "an old failure"
        }), "device");
        compare(PhoneCards.micSubtitleKey({
            available: true, reachable: true, connecting: true, error: "an old failure"
        }), "connecting");
    }

    // ---------------------------------------------------------------------
    // The microphone's own ladder
    // ---------------------------------------------------------------------

    function test_the_microphone_asks_for_adb_only_on_the_backend_that_uses_it() {
        // scrcpy --audio-source=mic drives the phone over ADB; droidcam-cli
        // reaches it over Wi-Fi, so an empty `adb devices` refuses one and
        // not the other.
        const base = { available: true, reachable: true, connecting: false, active: false };
        compare(PhoneCards.micState(Object.assign({}, base,
            { needsAdbDevice: true, adbDevice: false })), "offline");
        compare(PhoneCards.micSubtitleKey(Object.assign({}, base,
            { needsAdbDevice: true, adbDevice: false })), "noDevice");
        compare(PhoneCards.micState(Object.assign({}, base,
            { needsAdbDevice: false, adbDevice: false })), "ready");
        compare(PhoneCards.micSubtitleKey(Object.assign({}, base,
            { needsAdbDevice: false, adbDevice: false })), "ready");
        compare(PhoneCards.micState(Object.assign({}, base,
            { needsAdbDevice: true, adbDevice: true })), "ready");
    }

    function test_the_microphones_ladder_is_still_the_shared_one() {
        // micState is the shared ladder with one extra term, not a second
        // ladder: everything else it answers must match cardState.
        const base = { available: true, reachable: true, needsAdbDevice: true, adbDevice: true };
        compare(PhoneCards.micState(Object.assign({}, base, { available: false, active: true })), "unavailable");
        compare(PhoneCards.micState(Object.assign({}, base, { active: true, reachable: false })), "active");
        compare(PhoneCards.micState(Object.assign({}, base, { connecting: true })), "connecting");
        compare(PhoneCards.micState(Object.assign({}, base, { reachable: false })), "offline");
        compare(PhoneCards.micState(base), "ready");
        // An unanswered probe is not a refusal here either.
        compare(PhoneCards.micState({ available: true, reachable: true, needsAdbDevice: true }), "ready");
        compare(PhoneCards.micState(undefined), "unavailable");
    }

    function test_an_active_microphone_outranks_adb_losing_sight_of_the_phone() {
        compare(PhoneCards.micState({
            available: true, reachable: true, active: true, needsAdbDevice: true, adbDevice: false
        }), "active");
    }

    // ---------------------------------------------------------------------
    // The detail line's clock
    // ---------------------------------------------------------------------

    function test_elapsed_converts_the_services_seconds_to_milliseconds() {
        // PhoneCamera/PhoneMic publish startedAt in whole UNIX SECONDS, off
        // the session script's state file. Treating it as milliseconds reads
        // as a session that started in 1970.
        compare(PhoneCards.elapsedMs(1000, 1090000), 90000);
    }

    function test_a_session_that_never_started_has_no_elapsed_time() {
        compare(PhoneCards.elapsedMs(0, 1000000000), 0);
        compare(PhoneCards.elapsedMs(undefined, 1000000000), 0);
        // A clock that stepped backwards is zero, not a negative duration.
        compare(PhoneCards.elapsedMs(1000, 900000), 0);
    }

    function test_elapsed_is_formatted_at_three_scales() {
        compare(PhoneCards.formatElapsed(42000), "42s");
        compare(PhoneCards.formatElapsed(0), "0s");
        compare(PhoneCards.formatElapsed(7 * 60000 + 5000), "7m 05s");
        compare(PhoneCards.formatElapsed(59 * 60000 + 59000), "59m 59s");
        compare(PhoneCards.formatElapsed(3600000 + 3 * 60000), "1h 03m");
    }

    function test_seconds_are_padded_so_the_line_does_not_change_width_every_tick() {
        // 1m 9s -> 1m 10s reflows a monospaced detail line without this.
        compare(PhoneCards.formatElapsed(69000).length,
                PhoneCards.formatElapsed(70000).length);
    }

    // ---------------------------------------------------------------------
    // The install guide
    // ---------------------------------------------------------------------

    function test_the_guide_opens_on_the_detected_distro() {
        compare(PhoneCards.initialDistro("fedora"), "fedora");
        compare(PhoneCards.initialDistro("debian"), "debian");
        compare(PhoneCards.initialDistro("arch"), "arch");
    }

    function test_an_unrecognised_distro_opens_on_arch_rather_than_on_nothing() {
        // PhoneDeps answers "unknown" where it recognised no marker file. A
        // guide opening on that shows no command at all, which reads as a
        // dependency with no way to install it.
        compare(PhoneCards.initialDistro("unknown"), "arch");
        compare(PhoneCards.initialDistro(""), "arch");
        compare(PhoneCards.initialDistro(undefined), "arch");
        compare(PhoneCards.initialDistro("gentoo"), "arch");
    }

    function test_the_pills_are_the_three_distros_the_table_carries() {
        const pills = PhoneCards.distroPills();
        compare(pills.length, 3);
        compare(pills.map(pill => pill.key).join(","), "arch,fedora,debian");
        compare(pills.map(pill => pill.label).join(","), "Arch,Fedora,Debian");
    }

    function test_a_dependency_with_no_command_for_this_distro_draws_no_box() {
        const dependency = { key: "scrcpy", commands: { arch: "sudo pacman -S scrcpy" } };
        compare(PhoneCards.commandFor(dependency, "arch"), "sudo pacman -S scrcpy");
        compare(PhoneCards.commandFor(dependency, "fedora"), "");
        compare(PhoneCards.commandFor(null, "arch"), "");
        compare(PhoneCards.commandFor({}, "arch"), "");
    }

    function test_the_preview_line_skips_comments_but_the_copy_takes_the_block() {
        // PhoneDeps' DroidCam and v4l2loopback rows are multi-line with `#`
        // comments; the box previews the first real command and the copy
        // button hands over the whole block.
        const block = "# Enable RPM Fusion first, then:\nsudo dnf install akmod-v4l2loopback\nsudo modprobe v4l2loopback";
        compare(PhoneCards.firstCommand(block), "sudo dnf install akmod-v4l2loopback");
        compare(PhoneCards.copyArgv(block)[2], block);
    }

    function test_a_block_that_is_only_comments_still_previews_something() {
        compare(PhoneCards.firstCommand("# see the DroidCam site"), "# see the DroidCam site");
        compare(PhoneCards.firstCommand(""), "");
    }

    function test_the_copy_is_a_constant_argv_with_the_text_as_an_argument() {
        // Never `bash -c "wl-copy '...'"`: a quoting helper is the only thing
        // between an install command and the shell, and an argv has no
        // quoting to get wrong.
        const argv = PhoneCards.copyArgv("sudo pacman -S scrcpy && echo done");
        compare(argv[0], "wl-copy");
        compare(argv[1], "--");
        compare(argv.length, 3);
        compare(argv[2], "sudo pacman -S scrcpy && echo done");
        // A command that begins with a dash would otherwise be read as a flag.
        compare(PhoneCards.copyArgv("--help")[2], "--help");
        compare(PhoneCards.copyArgv(undefined)[2], "");
    }

    // ---------------------------------------------------------------------
    // The Android Apps page's filter
    // ---------------------------------------------------------------------

    function apps() {
        return [
            { name: "Signal", package: "org.thoughtcrime.securesms" },
            { name: "Camera", package: "com.android.camera2" },
            { name: "", package: "com.example.nameless" }
        ];
    }

    function test_an_empty_query_keeps_every_app() {
        compare(PhoneCards.filterApps(this.apps(), "").length, 3);
        compare(PhoneCards.filterApps(this.apps(), "   ").length, 3);
        compare(PhoneCards.filterApps(this.apps(), undefined).length, 3);
        compare(PhoneCards.filterApps(undefined, "signal").length, 0);
    }

    function test_a_query_matches_the_name_or_the_package_case_insensitively() {
        compare(PhoneCards.filterApps(this.apps(), "sig")[0].package, "org.thoughtcrime.securesms");
        compare(PhoneCards.filterApps(this.apps(), "SIG")[0].package, "org.thoughtcrime.securesms");
        // The package is searchable on its own: an app whose name is not what
        // the user knows it by is still found by what they type into a
        // launcher.
        compare(PhoneCards.filterApps(this.apps(), "camera2").length, 1);
        compare(PhoneCards.filterApps(this.apps(), "nameless")[0].package, "com.example.nameless");
        compare(PhoneCards.filterApps(this.apps(), "zzz").length, 0);
    }

    function test_an_app_with_no_name_is_labelled_by_its_last_package_segment() {
        // The `pm list packages -3` fallback carries no names at all, so
        // every app on that path would draw a blank row.
        compare(PhoneCards.appLabel({ name: "Signal", package: "org.thoughtcrime.securesms" }), "Signal");
        compare(PhoneCards.appLabel({ name: "", package: "com.example.nameless" }), "nameless");
        compare(PhoneCards.appLabel({ package: "com.example.nameless" }), "nameless");
        compare(PhoneCards.appLabel({}), "");
    }
}
