"""Contract checks for the Phone tab's four session services:
services/PhoneDeps.qml, PhoneScrcpy.qml, PhoneCamera.qml, PhoneMic.qml.

The QML suite (tst_phone_scrcpy.qml) drives logic-only doubles under
tests/imports/testservices, so the doubles proving something transfers to
the real services only while the regions between the `BEGIN/END <name>
logic` markers are byte-for-byte identical - the first check here. The
rest pins the process I/O the doubles deliberately omit, which is the half
CONTRIBUTING.md names outright:

- every command is an argv array. The only shell strings are PhoneDeps'
  constant probes (`command -v <tool>` and the distro marker walk), with
  nothing interpolated into any of them;
- no Process in any of the four files carries a `running:` binding. The
  scrcpy supervisor is started imperatively, carries the restart-safe
  marker, and every restart goes through the backoff ladder; the
  capability probes start themselves from Component.onCompleted (the
  capability-probe lint's rule) and again from recheck();
- the supervisor's idle timer is declared at its ten seconds and consults
  managerWanted() before stopping anything;
- the DroidCam sessions are launched detached through droidcam_session.sh
  rather than held by a Process, and the microphone's default-sink swap is
  both persisted and undone on every exit path.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVICES = ROOT / "services"
DOUBLES = ROOT / "tests" / "imports" / "testservices"

SYNCED = {
    "PhoneDeps": "phone-deps",
    "PhoneScrcpy": "phone-scrcpy",
    "PhoneCamera": "phone-camera",
    "PhoneMic": "phone-mic",
}


def _source(name: str) -> str:
    return (SERVICES / f"{name}.qml").read_text()


def _synced_region(path: Path, tag: str) -> str:
    text = path.read_text()
    begin = f"    // BEGIN {tag} logic"
    end = f"    // END {tag} logic"
    assert text.count(begin) == 1, f"{path}: expected exactly one BEGIN marker"
    assert text.count(end) == 1, f"{path}: expected exactly one END marker"
    start = text.index("\n", text.index(begin)) + 1
    return text[start:text.index(end)]


def _named_block(source: str, object_id: str) -> str:
    """The body of the `Process`/`Timer` block carrying `id: <object_id>`.

    Brace-counted forward from the brace that opened it, which is found by
    walking back from the id - these blocks are located by what they are
    called rather than by where they sit in the file.
    """
    marker = source.index("id: " + object_id + "\n")
    start = source.rindex("{", 0, marker)
    depth, index = 1, start + 1
    while index < len(source) and depth:
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
        index += 1
    return source[start:index]


def _process_blocks(source: str):
    """Every `Process { ... }` block, brace-counted with string literals
    skipped, so a `}` inside a shell string cannot end a block early."""
    for match in re.finditer(r"\bProcess\s*\{", source):
        depth, index, quote = 1, match.end(), None
        while index < len(source) and depth:
            char = source[index]
            if quote:
                if char == "\\":
                    index += 1
                elif char == quote:
                    quote = None
            elif char in "\"'`":
                quote = char
            elif char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
            index += 1
        yield source[match.start():index]


def _process_block(source: str, process_id: str) -> str:
    for block in _process_blocks(source):
        if re.search(rf"\bid:\s*{process_id}\b", block):
            return block
    raise AssertionError(f"Process block for id {process_id} not found")


def _shell_strings(source: str):
    """Every `["sh"|"bash", "-c", <expr>]` literal's third element, up to the
    closing bracket of the argv - a JS string literal is read whole, so a
    `]` inside it (the distro probe's `[ -f "$f" ]`) does not end it."""
    out = []
    for match in re.finditer(r'\["(?:sh|bash)",\s*"-c",\s*', source):
        index, depth, quote = match.end(), 0, None
        while index < len(source):
            char = source[index]
            if quote:
                if char == "\\":
                    index += 1
                elif char == quote:
                    quote = None
            elif char in "\"'`":
                quote = char
            elif char == "[":
                depth += 1
            elif char == "]":
                if depth == 0:
                    break
                depth -= 1
            index += 1
        out.append(source[match.end():index].strip())
    return out


# ---- the doubles -------------------------------------------------------------


def test_every_synced_region_is_byte_identical_between_service_and_double():
    for name, tag in SYNCED.items():
        service_region = _synced_region(SERVICES / f"{name}.qml", tag)
        double_region = _synced_region(DOUBLES / f"{name}.qml", tag)
        assert service_region.strip(), f"{name}: synced region is empty"
        assert service_region == double_region, (
            f"services/{name}.qml and tests/imports/testservices/{name}.qml have "
            f"drifted between the {tag} logic markers; edit both sides identically"
        )


def test_the_doubles_are_registered_for_the_qml_suite():
    qmldir = (DOUBLES / "qmldir").read_text().splitlines()
    for name in SYNCED:
        assert f"singleton {name} {name}.qml" in qmldir, f"{name} is not in testservices/qmldir"


def test_the_doubles_hold_no_process():
    for name in SYNCED:
        text = (DOUBLES / f"{name}.qml").read_text()
        assert not re.search(r"\bProcess\s*\{", text), f"the {name} double declares a Process"
        assert "Quickshell.Io" not in text, f"the {name} double imports Quickshell.Io"


# ---- argv only ---------------------------------------------------------------


def test_the_only_shell_strings_are_phone_deps_constant_probes():
    for name in ("PhoneScrcpy", "PhoneCamera", "PhoneMic"):
        assert _shell_strings(_source(name)) == [], (
            f"{name}.qml carries a shell string: {_shell_strings(_source(name))}"
        )
    deps = _shell_strings(_source("PhoneDeps"))
    probes = [s for s in deps if s.startswith('"command -v ')]
    assert len(probes) == 10, f"expected ten `command -v` probes, found {probes}"
    for string in deps:
        assert string.startswith('"') and string.endswith('"'), f"not a plain literal: {string}"
        assert "${" not in string and "+" not in string, f"interpolation into a shell string: {string}"
    others = [s for s in deps if s not in probes]
    assert len(others) == 1 and "/etc/arch-release /etc/fedora-release /etc/debian_version" in others[0], (
        f"unexpected shell strings beside the probes: {others}"
    )


def test_no_service_interpolates_into_a_shell_command_line():
    for name in SYNCED:
        for line in _source(name).splitlines():
            if re.search(r'"(?:sh|bash)",\s*"-c"', line) and "${" in line:
                raise AssertionError(f"{name}.qml interpolates into a shell command: {line.strip()}")


def _run_argvs(source: str):
    """The first argument of every `root.run(` call, bracket-balanced."""
    out = []
    for match in re.finditer(r"root\.run\(", source):
        index, depth, quote = match.end(), 0, None
        while index < len(source):
            char = source[index]
            if quote:
                if char == "\\":
                    index += 1
                elif char == quote:
                    quote = None
            elif char in "\"'`":
                quote = char
            elif char in "([{":
                depth += 1
            elif char in ")]}":
                if depth == 0:
                    break
                depth -= 1
            elif char == "," and depth == 0:
                break
            index += 1
        out.append(source[match.end():index].strip())
    return out


def test_every_exec_and_run_takes_an_argv_array():
    """The one-shot queue only ever sees a literal array or an array a
    builder returned - never a joined string."""
    for name in ("PhoneCamera", "PhoneMic"):
        source = _source(name)
        argvs = _run_argvs(source)
        assert len(argvs) > 5, f"{name}.qml never runs a command"
        for argv in argvs:
            # A local named `argv` is fine while it is declared as an array.
            local = argv == "argv" and "const argv = [" in source
            assert local or argv.startswith("[") or argv.startswith("root.") or argv.startswith("PhoneScrcpy."), (
                f"{name}.qml runs something that is not an argv array: {argv[:80]}"
            )
        assert "cmdProc.exec(next.argv)" in source, f"{name}.qml's queue does not exec the argv"


def test_droidcam_sessions_are_launched_detached_through_the_session_script():
    """No Process here holds a droidcam-cli or a scrcpy mic stream: both go
    through droidcam_session.sh launch, whose pidfile is the binary's, so
    the stream outlives the shell and is re-adopted at boot."""
    camera = _source("PhoneCamera")
    mic = _source("PhoneMic")
    assert '"launch", "video"' in camera, "the webcam is not launched through the session script"
    assert '"launch", "scrcpy-mic"' in mic and '"launch", "audio"' in mic, (
        "a microphone backend is not launched through the session script"
    )
    for name, source in (("PhoneCamera", camera), ("PhoneMic", mic)):
        for block in _process_blocks(source):
            assert "droidcam-cli" not in block and "scrcpy" not in block.replace("PhoneScrcpy", ""), (
                f"{name}.qml holds a stream in a Process block"
            )
        assert 'root.checkSession()' in source or 'root.reconcile()' in source
        assert "Component.onCompleted" in source, f"{name}.qml never re-adopts a session at boot"


# ---- process lifetimes -------------------------------------------------------


def test_no_process_in_the_four_services_has_a_running_binding():
    for name in SYNCED:
        for block in _process_blocks(_source(name)):
            bindings = re.findall(r"^\s*running\s*:", block, re.M)
            assert bindings == [], f"{name}.qml declares a running binding in {block[:120]!r}"


def test_the_supervisor_carries_the_marker_and_restarts_on_the_ladder():
    source = _source("PhoneScrcpy")
    block = _process_block(source, "manager")
    assert "process-lifecycle: restart-safe" in block, "the supervisor lacks the restart-safe marker"
    assert "stdinEnabled: true" in block, "the supervisor is not written to over stdin"
    assert "scrcpy_session_manager.py" in block, "the supervisor is not the session manager script"
    assert "root.restartAttempts >= root.maxRestartAttempts" in block, "no ceiling in the exit handler"
    assert "restartTimer.interval = root.backoffDelay(root.restartAttempts)" in block, (
        "the restart timer is armed with something other than the ladder's delay"
    )
    assert re.search(r"readonly property int maxRestartAttempts:\s*5", source), "no declared ceiling"
    assert "manager.running = true" in source and "manager.running = false" in source, (
        "the supervisor must be started and stopped imperatively"
    )
    starts = [line.strip() for line in source.splitlines()
              if "startManager(" in line and "function startManager" not in line]
    assert starts and all("root.startManager(" in line for line in starts), starts


def test_the_supervisor_idle_timer_is_ten_seconds_and_asks_before_stopping():
    source = _source("PhoneScrcpy")
    timer = re.search(r"Timer \{\n\s*id: managerIdleTimer(.*?)\n    \}", source, re.S)
    assert timer, "managerIdleTimer missing"
    body = timer.group(1)
    assert re.search(r"interval:\s*10000", body), "the idle timer is not ten seconds"
    assert "root.managerWanted()" in body and "root.stopManager()" in body, (
        "the idle timer stops the supervisor without asking managerWanted()"
    )
    assert "managerIdleTimer.restart()" in re.search(r"function send\(.*?\n    \}", source, re.S).group(0), (
        "a command does not re-arm the idle timer"
    )
    for handler in ("onSessionCountChanged", "onAppsLoadingChanged", "onMirrorLaunchingChanged"):
        assert f"{handler}: managerIdleTimer.restart()" in source, f"{handler} does not re-arm the idle timer"


def test_the_capability_probes_start_themselves_and_again_from_recheck():
    source = _source("PhoneDeps")
    probes = [block for block in _process_blocks(source) if '"command -v ' in block]
    assert len(probes) == 10, f"expected ten probes, found {len(probes)}"
    for block in probes:
        assert "Component.onCompleted: root.startProbe(this)" in block, f"a probe does not start itself: {block[:80]}"
        assert "onRunningChanged: if (!running) root.probeAnswered()" in block, (
            "a probe's accounting hangs off exited, which a missing binary never emits"
        )
    recheck = re.search(r"function recheck\(\): void \{(.*?)\n    \}", source, re.S)
    assert recheck, "recheck() missing"
    for probe_id in ("scrcpyProbe", "adbProbe", "droidcamProbe", "v4l2CtlProbe", "pactlProbe",
                     "mpvProbe", "ffplayProbe", "vlcProbe", "kdialogProbe", "wlPasteProbe",
                     "lsmodProbe", "modinfoProbe", "distroProbe"):
        assert probe_id in recheck.group(1), f"recheck() does not restart {probe_id}"
    assert '["scrcpy", "--version"]' in source, "the version probe is not the argv scrcpy --version"


def test_the_three_spawned_tools_are_asked_whether_they_run_not_only_whether_they_exist():
    """`command -v` answers presence; a package linked against a library the
    system has moved past is present and dies before main. The three binaries
    the tab spawns are therefore started as well, each from its own presence
    probe rather than from a feature's activation, and each under a kill guard
    so a tool that blocks cannot leave a probe outstanding for the session."""
    source = _source("PhoneDeps")
    assert '["adb", "--version"]' in source, "adb is never actually started"
    assert '["droidcam-cli"]' in source, "droidcam-cli is never actually started"
    assert '["scrcpy", "--version"]' in source, "scrcpy is never actually started"
    for probe, presence in (("adbRunProbe", "adbProbe"),
                            ("droidcamRunProbe", "droidcamProbe"),
                            ("versionProbe", "scrcpyProbe")):
        block = _named_block(source, presence)
        assert "root.startProbe(%s)" % probe in block, (
            f"{probe} is not started by {presence}, so it answers only once a feature asks"
        )
    for guard, probe in (("adbRunGuard", "adbRunProbe"),
                         ("droidcamRunGuard", "droidcamRunProbe"),
                         ("scrcpyRunGuard", "versionProbe")):
        assert f"{guard}.restart()" in source and f"{probe}.signal(15)" in source, (
            f"{probe} has no kill guard: a tool that blocks would hang its probe"
        )
    # Both halves, or a tool that merely quotes the phrase - or any non-zero
    # exit at all - would be reported as unable to run.
    parse = re.search(r"function parseLoaderFailure\(.*?\n    \}", source, re.S).group(0)
    assert "exitCode !== 127" in parse, "the classifier does not require exit 127"
    assert "error while loading shared libraries" in parse, "the classifier does not read the loader"


def test_the_microphone_swap_is_persisted_and_undone_on_every_exit_path():
    source = _source("PhoneMic")
    remember = re.search(r"function rememberSwap\(.*?\n    \}", source, re.S).group(0)
    assert "Persistent.states.phone.mic.originalDefaultSink = original" in remember
    restore = re.search(r"function restoreDefaultSink\(.*?\n    \}", source, re.S).group(0)
    assert 'Persistent.states.phone.mic.originalDefaultSink = ""' in restore
    assert '["pactl", "set-default-sink", original]' in restore
    for fn in ("fail", "stop", "becomeActive"):
        body = re.search(rf"function {fn}\(.*?\n    \}}", source, re.S).group(0)
        assert "root.restoreDefaultSink()" in body, f"{fn}() leaves the default sink swapped"
    reconcile = re.search(r"function reconcile\(.*?\n    \}", source, re.S).group(0)
    assert "root.restorePlan(" in reconcile, "boot reconciliation does not consult restorePlan"
    assert "Component.onCompleted: root.reconcile()" in source, "reconciliation does not run at boot"
    swap = re.search(r"Timer \{\n\s*id: swapTimer(.*?)\n    \}", source, re.S)
    assert swap and "root.restoreDefaultSink()" in swap.group(1), "the swap poll has no ceiling restore"


def test_the_config_and_persistent_blocks_carry_every_key_the_services_read():
    config = (ROOT / "modules" / "common" / "Config.qml").read_text()
    persistent = (ROOT / "modules" / "common" / "Persistent.qml").read_text()
    phone = config[config.index("property JsonObject phone: JsonObject {"):]
    for key in ("showPeripheralCards", "stayAwake", "turnScreenOff", "noPowerOn", "noAudio", "showTouches",
                "fullscreen", "alwaysOnTop", "maxFps", "bitRate", "maxSize", "videoBuffer", "useWireless",
                "autoWirelessIp", "wirelessIp", "wirelessPort", "flexDisplay", "displayWidth", "displayHeight",
                "density", "keepActive", "systemDecorations", "favoritePackages", "cameraFacing", "resolution",
                "mirrorHorizontally", "rotateDegrees", "connection", "wifiIp", "micGain", "setAsDefault",
                "favoriteIds", "sortBy", "hideUnnamed"):
        assert re.search(rf"property \S+ {key}:", phone), f"Config.options.phone lacks {key}"
    assert config.rstrip().endswith("}\n        }\n    }\n}") or config.rstrip().endswith("}"), "Config.qml shape"
    sidebar = re.search(r"property JsonObject sidebar: JsonObject \{(.*?)\n            \}", config, re.S)
    assert sidebar, "Config.options.sidebar not found"
    tab_key = re.search(r"property JsonObject phone: JsonObject \{(.*?)\n                \}", sidebar.group(1), re.S)
    assert tab_key, "sidebar.phone.enable is not declared beside sidebar.media"
    enabled = re.search(r"property bool enable: (true|false)", tab_key.group(1))
    assert enabled, "sidebar.phone lacks an enable property"
    # The key gates more than a tab: PhoneNotifications reads it as
    # mirrorActive, and that is what drops kdeconnectd's desktop copy of a
    # phone notification. True before a list exists to read them in and the
    # phone's notifications stop arriving anywhere at all - so the default
    # follows the tab into the tree, and this releases itself when W5 lands.
    tab_exists = (ROOT / "modules/imi/sidebarLeft/phone").is_dir()
    if not tab_exists:
        assert enabled.group(1) == "false", (
            "sidebar.phone.enable is true but modules/imi/sidebarLeft/phone does not exist: "
            "the notification dedupe would drop the phone's notifications with nothing drawing them"
        )
    states = persistent[persistent.index("property JsonObject phone: JsonObject {"):]
    for key in ("activeDeviceId", "recentDeviceIds", "cachedNotificationsJson", "recentPackages",
                "originalDefaultSink", "lastBackend", "lastMode", "lastIp", "lastPort"):
        assert re.search(rf"property \S+ {key}:", states), f"Persistent.states.phone lacks {key}"


def test_the_supervisor_script_writes_the_titles_and_the_cache_the_service_expects():
    script = (ROOT / "scripts" / "phone" / "scrcpy_session_manager.py").read_text()
    assert 'TITLE_PREFIX = "imi-phone-"' in script
    assert '"immaterial-impulse" / "phone" / "apps"' in script
    assert 'self.stop_all()' in re.search(r"def run\(self\):.*?\n\n", script, re.S).group(0), (
        "stdin closing does not stop every session"
    )
    session = (ROOT / "scripts" / "phone" / "droidcam_session.sh").read_text()
    assert "quickshell/imi/phone" in session, "the session state dir is not the shell's"
    for name in ("droidcam_session.sh", "droidcam_status.sh"):
        text = (ROOT / "scripts" / "phone" / name).read_text()
        assert "pgrep -" + "f" not in text, f"{name} matches its own caller"


if __name__ == "__main__":
    import sys
    from contract_runner import run
    sys.exit(run(globals()))
