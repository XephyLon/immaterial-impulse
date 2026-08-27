"""Contract checks for services/PhoneConnect.qml.

The QML suite (tst_phone_connect.qml) exercises the parser/normalization
logic through a logic-only double, so the double proving something means
nothing unless the real service carries the same logic. The sync check here
is what makes the double's green transfer: the region between the
`BEGIN/END phone-connect parser logic` markers must be byte-for-byte
identical in both files (the BEGIN line itself may differ - each side points
its "synced with" note at the other).

The rest pins the busctl I/O the double deliberately omits:
- every busctl invocation is an argv array; the only shell string is the
  static `command -v busctl` presence probe, with nothing interpolated;
- device ids are filtered through validDeviceId before they are spliced
  into object paths, and Valent object paths pass validValentObjectPath
  before they are called into;
- the streaming monitor's lifetime, which is the half of this feature that
  cannot be unit tested and the half CONTRIBUTING.md names outright: the
  monitor Process must carry no `running` binding, every restart must go
  through the backoff plan, and the poll must stay on (gated on
  enableService && installed) as the reconcile behind it.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "services" / "PhoneConnect.qml"
DOUBLE = ROOT / "tests" / "imports" / "testservices" / "PhoneConnect.qml"
SURFACE = ROOT / "modules" / "imi" / "sidebarRight" / "phoneConnect"
DIALOG = SURFACE / "PhoneConnectDialog.qml"

# Everything the sidebar surface may ask the service to DO. The device
# dialog is shaped after a fork whose action row carries six buttons; ours
# carries the three this model backs, and a fourth appears here or not at
# all - a button whose call the service does not answer is a fake action.
MODEL_ACTIONS = {"refresh", "ring", "ping", "sendClipboard", "acceptPairing", "cancelPairing",
                 "shareUrls", "shareText", "shareClipboard", "pickAndSendFiles",
                 "browseFiles", "selectDevice"}

BEGIN = "// BEGIN phone-connect parser logic"
END = "    // END phone-connect parser logic"


def _synced_region(path: Path) -> str:
    text = path.read_text()
    assert text.count(BEGIN) == 1, f"{path}: expected exactly one BEGIN marker"
    assert text.count(END) == 1, f"{path}: expected exactly one END marker"
    start = text.index("\n", text.index(BEGIN)) + 1
    return text[start:text.index(END)]


def test_parser_region_is_byte_identical_between_service_and_double():
    service_region = _synced_region(SERVICE)
    double_region = _synced_region(DOUBLE)
    assert service_region, "synced region is empty"
    assert service_region == double_region, (
        "services/PhoneConnect.qml and tests/imports/testservices/PhoneConnect.qml "
        "have drifted between the phone-connect parser logic markers; edit both "
        "sides identically"
    )


def test_the_derived_pairing_request_list_matches_the_double():
    """`pairingRequests` sits outside the marked region like applyDevices does
    (it is a binding on `devices`, not parser logic), and the QML suite drives
    the double's copy - so the two spellings are held to each other."""
    pattern = r"    readonly property var pairingRequests:.*\n"
    service_line = re.search(pattern, SERVICE.read_text())
    double_line = re.search(pattern, DOUBLE.read_text())
    assert service_line and double_line, "pairingRequests missing on one side"
    assert service_line.group(0) == double_line.group(0), "pairingRequests drifted"


def test_the_kdeconnect_sweep_reads_the_connectivity_report_at_its_own_leaf():
    """The report is a child object (`<device>/connectivity_report`), and the
    path matters more than it reads: measured against the live daemon, a
    GetAll that names the report's interface on the DEVICE path does not fail
    - Qt's adaptor answers it with every property of the device - which
    parses as a report carrying no cellular fields and reads as "unknown" for
    ever, with nothing in any log."""
    source = SERVICE.read_text()
    calls = [line for line in source.splitlines()
             if "org.kde.kdeconnect.device.connectivity_report" in line and "GetAll" in line]
    assert len(calls) == 1, f"expected one connectivity_report GetAll, got {calls}"
    assert 'devicePath + "/connectivity_report"' in calls[0], (
        f"the report must be read at its own leaf path: {calls[0].strip()}"
    )


def test_pairing_is_answered_on_the_device_path_with_the_daemon_s_two_methods():
    """Slice 3's whole transport: acceptPairing/cancelPairing are methods of
    org.kde.kdeconnect.device on the device path itself (introspected live),
    not of a plugin leaf, and the id reaches the path as an argument the
    validator has already passed - never through a shell string."""
    source = SERVICE.read_text()
    for name in ("acceptPairing", "cancelPairing"):
        body = re.search(rf"function {name}\(.*?\n    \}}\n", source, re.S)
        assert body, f"{name}() missing"
        text = body.group(0)
        assert "root.runAction(root.busctlCall(" in text, f"{name}() does not go through runAction"
        assert f'"org.kde.kdeconnect.device", "{name}", []' in text, (
            f"{name}() does not call the device interface's {name} method"
        )
        assert "`/modules/kdeconnect/devices/${d.id}`" in text, (
            f"{name}() is aimed at something other than the device path"
        )
        # An answer is to a request the peer made. Defaulting to the active
        # device - the paired phone, which never asked - is the one shape a
        # copy of ring() would carry here.
        assert "!d.hasPairingRequest" in text, f"{name}() answers a device that never asked"
        assert "root.activeDevice" not in text, f"{name}() falls back to the active device"


def test_the_active_device_rule_matches_the_double_and_reads_the_persisted_choice():
    """Slice 6: activeDevice prefers the persisted device while it is paired
    and reachable, else the old rule. The rule is preferredActiveDevice in
    the synced region; the binding that calls it is outside it and the QML
    suite drives the double's, so both bindings are held to each other. The
    service reads the persisted id off Persistent; the double carries it as
    a plain property the suite can set."""
    pattern = r"    readonly property var activeDevice:.*\n"
    service_line = re.search(pattern, SERVICE.read_text())
    double_line = re.search(pattern, DOUBLE.read_text())
    assert service_line and double_line, "activeDevice missing on one side"
    assert service_line.group(0) == double_line.group(0), "activeDevice drifted"
    assert "root.preferredActiveDevice(root.devices, root.persistedActiveDeviceId)" in service_line.group(0)
    assert re.search(r"readonly property string persistedActiveDeviceId: Persistent\.states\?\.phone\?\.activeDeviceId \?\? \"\"",
                     SERVICE.read_text()), "the service does not read the persisted id off Persistent.states.phone"
    assert re.search(r"^    property string persistedActiveDeviceId: \"\"$", DOUBLE.read_text(), re.M), (
        "the double does not carry persistedActiveDeviceId as a settable property"
    )


def test_select_device_writes_the_persisted_id_and_the_recent_list():
    source = SERVICE.read_text()
    body = re.search(r"function selectDevice\(.*?\n    \}\n", source, re.S)
    assert body, "selectDevice() missing"
    text = body.group(0)
    assert "root.validDeviceId(id)" in text, "selectDevice persists an unvalidated id"
    assert "Persistent.states.phone.activeDeviceId = id" in text, "selectDevice does not persist the choice"
    assert "Persistent.states.phone.recentDeviceIds = root.recentDeviceIdsAfterSelect(" in text, (
        "selectDevice does not maintain the MRU list through the synced rule"
    )
    persistent = (ROOT / "modules" / "common" / "Persistent.qml").read_text()
    block = re.search(r"property JsonObject phone: JsonObject \{(.*?)\n            \}", persistent, re.S)
    assert block, "Persistent.states has no phone JsonObject"
    assert re.search(r'property string activeDeviceId: ""', block.group(1)), "phone.activeDeviceId missing"
    assert re.search(r"property list<string> recentDeviceIds: \[\]", block.group(1)), "phone.recentDeviceIds missing"


def test_state_application_helpers_match_the_double():
    # applyBackend/applyDevices sit outside the marked region (the double's
    # versions are what the QML suite drives), but their semantics are part
    # of the tested contract too - keep the bodies identical.
    for name in ("applyBackend", "applyDevices"):
        pattern = rf"    function {name}\(.*?\n    \}}\n"
        service_fn = re.search(pattern, SERVICE.read_text(), re.S)
        double_fn = re.search(pattern, DOUBLE.read_text(), re.S)
        assert service_fn and double_fn, f"{name} missing on one side"
        assert service_fn.group(0) == double_fn.group(0), f"{name} drifted"


def test_only_shell_string_is_the_static_presence_probe():
    source = SERVICE.read_text()
    shell_commands = re.findall(r'\["sh",\s*"-c",\s*(.*?)\]', source)
    assert shell_commands == ['"command -v busctl"'], (
        f"unexpected shell strings in PhoneConnect.qml: {shell_commands}"
    )
    for line in source.splitlines():
        if '"sh"' in line and "${" in line:
            raise AssertionError(f"interpolation into a shell command: {line.strip()}")


def test_busctl_calls_are_argv_arrays_via_busctl_call():
    source = SERVICE.read_text()
    for name in ("busctlCall", "busctlMonitor"):
        builder = re.search(
            rf'function {name}\(.*?\{{\n(.*?)\n    \}}', source, re.S
        )
        assert builder, f"{name} builder missing"
        assert '["busctl", "--user", "--json=short"' in builder.group(1), (
            f"{name} does not build a --json=short argv array"
        )
    # Every exec goes through the queue, the action process or the monitor,
    # all fed by those two argv builders - no other busctl literal exists.
    busctl_literals = [
        line.strip() for line in source.splitlines()
        if '"busctl"' in line
        and not line.strip().startswith('return ["busctl"')
        and "command -v" not in line
    ]
    assert busctl_literals == [], f"busctl invoked outside the argv builders: {busctl_literals}"


def test_the_match_rule_is_one_argv_element_and_never_a_shell_string():
    """The D-Bus match grammar puts single quotes inside the rule
    (`sender='org.kde.kdeconnect.daemon'`), which is exactly the string a
    shell would re-interpret. It is one argv element, appended to
    `--match=`, and the presence probe stays the only shell in the file
    (pinned separately above)."""
    source = SERVICE.read_text()
    builder = re.search(r'function busctlMonitor\(.*?\{\n(.*?)\n    \}', source, re.S)
    assert builder, "busctlMonitor builder missing"
    body = builder.group(1)
    assert '`--match=${matchRule}`' in body, (
        f"the match rule must be one argv element: {body}"
    )
    assert '"monitor"' in body, "the monitor argv must name the monitor verb"


def test_device_ids_are_validated_before_path_splicing():
    source = SERVICE.read_text()
    assert ".filter(id => root.validDeviceId(id))" in source, (
        "kdeconnect device ids must be filtered through validDeviceId before "
        "being spliced into object paths"
    )
    assert ".filter(d => root.validValentObjectPath(d.objectPath))" in source, (
        "valent object paths must be validated before DescribeAll is called on them"
    )
    # Actions build paths from ids/paths too - each must re-check.
    for action in ("ring", "ping", "sendClipboard", "acceptPairing", "cancelPairing",
                   "shareUrls", "shareText"):
        body = re.search(rf"function {action}\(.*?\n    \}}\n", source, re.S)
        assert body, f"{action}() missing"
        assert "validDeviceId" in body.group(0) or "validValentObjectPath" in body.group(0), (
            f"{action}() splices without validating"
        )


def _process_block(source: str, process_id: str) -> str:
    """The `Process { ... }` block declaring `id: <process_id>`.

    Brace-counted rather than regexed to a fixed indent: a check that bakes
    in indentation passes vacuously after any reformat, and this one has to
    be able to say a `running:` binding is absent.
    """
    for match in re.finditer(r"\bProcess\s*\{", source):
        depth, index = 1, match.end()
        while index < len(source) and depth:
            if source[index] == "{":
                depth += 1
            elif source[index] == "}":
                depth -= 1
            index += 1
        block = source[match.start():index]
        if re.search(rf"\bid:\s*{process_id}\b", block):
            return block
    raise AssertionError(f"Process block for id {process_id} not found")


def test_the_monitor_process_has_no_running_binding():
    """The rule CONTRIBUTING.md states outright. `busctl monitor` handed a
    match rule the bus rejects exits in milliseconds, so a `running:`
    binding keeping it alive is a tight respawn loop that starves
    Quickshell. It is started imperatively and the only assignment to
    `running` is the deliberate stop."""
    block = _process_block(SERVICE.read_text(), "monitorProc")
    bindings = re.findall(r"^\s*running\s*:", block, re.M)
    assert bindings == [], f"monitorProc declares a running binding: {bindings}"
    assert "monitorProc.exec(" in SERVICE.read_text(), (
        "the monitor must be started imperatively through exec()"
    )
    assert "process-lifecycle: restart-safe" in block, (
        "the monitor block must carry the restart-safe marker the plugin "
        "lifecycle lint recognises"
    )


def test_every_monitor_restart_goes_through_the_backoff_plan():
    """No path may restart the monitor without a delay: the exit handler
    consults monitorExitPlan, honours its refusal, and arms the restart
    timer with the delay it returned."""
    source = SERVICE.read_text()
    block = _process_block(source, "monitorProc")
    assert "root.monitorExitPlan(" in block, "the exit handler does not consult the plan"
    assert "monitorRestart.interval = plan.delay" in block, (
        "the restart timer is armed with something other than the plan's delay"
    )
    assert re.search(r"if\s*\(!plan\.retry\)", block), (
        "the exit handler does not honour the plan's refusal"
    )
    # startMonitor is the only other way in, and it is reached either from a
    # backend change or from that timer.
    starts = [line.strip() for line in source.splitlines()
              if "startMonitor()" in line and "function startMonitor" not in line]
    assert starts, "nothing starts the monitor"
    for line in starts:
        assert ("root.startMonitor()" in line), f"unexpected monitor start path: {line}"


def test_the_ceiling_is_declared_and_the_stream_falls_back_to_polling():
    """A ceiling that is never reached is not a ceiling; a ceiling with no
    fallback is a feature that silently stops working. Both halves."""
    source = SERVICE.read_text()
    assert re.search(r"readonly property int monitorAttemptCeiling:\s*\d+", source), (
        "no declared retry ceiling"
    )
    assert re.search(r"readonly property int monitorHealthyMs:\s*\d+", source), (
        "no declared healthy-run threshold"
    )
    assert 'root.monitorState = "failed"' in source, (
        "the ceiling never lands the monitor in a terminal state"
    )
    assert 'root.monitorState !== "failed"' in source, (
        "monitorWanted() does not read the terminal state, so the ceiling is "
        "reachable again immediately"
    )


def test_the_monitor_gate_is_a_function_not_a_binding():
    """AGENT.md's change-handler rule, paid for here. onBackendChanged is
    what arms the stream, and nothing orders a handler against the
    re-evaluation of a binding derived from the same property - written as a
    `readonly property bool` this answered with the PREVIOUS backend, read
    false on the one transition that matters, and the monitor never started
    while the model kept updating from the poll."""
    source = SERVICE.read_text()
    assert re.search(r"function monitorWanted\(\): bool \{", source), (
        "the monitor's gate must be a function"
    )
    assert not re.search(r"property bool (wantMonitor|monitorWanted)", source), (
        "the monitor's gate is a binding on the property its own handler hangs off"
    )
    handler = re.search(r"onBackendChanged: \{(.*?)\n    \}", source, re.S)
    assert handler, "onBackendChanged missing"
    assert "root.startMonitor()" in handler.group(1)


def test_valent_keeps_the_poll_because_its_signals_are_unverified():
    """A signal path that only works for one backend is a regression in the
    other. Valent gets no match rule, so nothing ever spawns a monitor for
    it, and its updates stay on the timer."""
    source = SERVICE.read_text()
    rule = re.search(r"function monitorMatchRule\(.*?\{\n(.*?)\n    \}", source, re.S)
    assert rule, "monitorMatchRule missing"
    body = rule.group(1)
    assert "kdeconnect" in body
    assert "andyholmes" not in body and "Valent" not in body, (
        f"an unverified Valent rule has been added: {body}"
    )


def test_the_poll_survives_as_the_reconcile_and_stays_gated():
    """The stream is not allowed to replace the poll. Nothing announces a
    daemon appearing (there is no monitor to hear it on), and a daemon that
    dies without a signal would leave the model frozen - so the timer stays
    on, gated exactly as before, and only slows down while the stream is
    live."""
    source = SERVICE.read_text()
    timers = re.findall(r"Timer \{(.*?)\n    \}", source, re.S)
    poll = [body for body in timers if "root.refresh()" in body and "repeat: true" in body]
    assert len(poll) == 1, f"expected exactly one poll Timer, found {len(poll)}"
    body = poll[0]
    assert "running: root.enableService && root.installed" in body
    assert "triggeredOnStart: true" in body
    assert "root.monitorLive ? root.reconcileInterval : root.pollInterval" in body, (
        "the poll does not slow down behind a live stream"
    )


def test_signal_bursts_are_coalesced_and_never_dropped():
    """One device going out of range emitted seven signals within a
    millisecond on a live daemon, and each re-read is a chain of busctl
    spawns - so they coalesce. The half that is easy to get wrong: refresh()
    declines while a sweep is in flight, so the settle timer has to re-arm
    rather than drop the change that asked for it."""
    source = SERVICE.read_text()
    settle = re.search(r"Timer \{\n\s*id: signalSettle(.*?)\n    \}", source, re.S)
    assert settle, "signalSettle timer missing"
    body = settle.group(1)
    assert "root.callQueue.length > 0" in body and "signalSettle.restart()" in body, (
        f"a signal arriving mid-sweep is dropped: {body}"
    )
    assert "signalSettle.restart()" in re.search(
        r"function handleMonitorLine\(.*?\n    \}", source, re.S).group(0), (
        "monitor lines do not go through the settle timer"
    )


def test_actions_queue_behind_one_another_instead_of_killing_the_one_in_flight():
    """`Process.exec` on a Process that is still running terminates it first
    (measured under headless weston: a 2s command followed 500ms later by a
    second exec exited with code 15, status 1, and no output). One
    `actionProc` fed straight from runAction therefore drops every action but
    the last of a burst - and a multi-file share IS a burst. runAction pushes
    onto a queue that the process's own exit pumps."""
    source = SERVICE.read_text()
    body = re.search(r"function runAction\(.*?\n    \}\n", source, re.S)
    assert body, "runAction() missing"
    assert "actionProc.exec(" not in body.group(0), "runAction execs straight onto a Process that may be busy"
    assert "root.actionQueue.push(" in body.group(0), "runAction does not queue"
    pump = re.search(r"function pumpActions\(.*?\n    \}\n", source, re.S)
    assert pump, "pumpActions() missing"
    assert "actionProc.running" in pump.group(0), "the pump does not check whether the process is busy"
    assert "actionProc.exec(" in pump.group(0), "the pump is not what starts the process"
    block = _process_block(source, "actionProc")
    assert "root.pumpActions()" in block, "the action process's exit does not pump the queue"


def test_feedback_is_one_signal_and_one_error_string_and_a_failed_action_reaches_both():
    """The tab's toast is fed by `actionFeedback(message, ok)` and its inline
    error by `lastActionError`; every failure the service can see reports
    through both, and a busctl action exiting non-zero is the one every
    action shares."""
    source = SERVICE.read_text()
    assert re.search(r"^    signal actionFeedback\(string message, bool ok\)$", source, re.M), (
        "actionFeedback(message, ok) is not declared with that exact signature"
    )
    assert re.search(r"^    property string lastActionError: \"\"$", source, re.M), (
        "lastActionError is not a string property defaulting to empty"
    )
    helper = re.search(r"function reportFailure\(message: string\): void \{\n(.*?)\n    \}", source, re.S)
    assert helper, "reportFailure(message) missing - the one spelling of a failure"
    assert "root.lastActionError = message" in helper.group(1), "reportFailure does not set lastActionError"
    assert "root.actionFeedback(message, false)" in helper.group(1), (
        "reportFailure does not raise actionFeedback(message, false)"
    )
    block = _process_block(source, "actionProc")
    assert "root.reportFailure(" in block, "a failed busctl action does not report through reportFailure"


def test_share_goes_through_the_share_plugin_one_url_per_call():
    """Slice 4's transport: `org.kde.kdeconnect.device.share.shareUrl` /
    `shareText` on the device's /share leaf, one string argument each
    (busctl signature "s"), serialized through runAction. shareUrls takes
    whatever list it is handed and keeps only file:// and http(s):// entries
    through the synced shareableUrls filter, so a stray path or an empty
    line never reaches the daemon as a URL."""
    source = SERVICE.read_text()
    assert re.search(r'readonly property bool canShare: root\.backend === "kdeconnect"', source), (
        "canShare is not declared as kdeconnect-only"
    )
    urls = re.search(r"function shareUrls\(.*?\n    \}\n", source, re.S)
    assert urls, "shareUrls() missing"
    assert "root.shareableUrls(" in urls.group(0), "shareUrls does not filter through shareableUrls"
    assert 'root.runAction(root.busctlCall("org.kde.kdeconnect.daemon", `/modules/kdeconnect/devices/${d.id}/share`, "org.kde.kdeconnect.device.share", "shareUrl", ["s", url]))' in urls.group(0), (
        "shareUrls does not call share.shareUrl on the share leaf with one string argument"
    )
    text = re.search(r"function shareText\(.*?\n    \}\n", source, re.S)
    assert text, "shareText() missing"
    assert '"org.kde.kdeconnect.device.share", "shareText", ["s", text]' in text.group(0), (
        "shareText does not call share.shareText with one string argument"
    )
    assert "root.runAction(" in text.group(0)
    for body in (urls, text):
        assert 'root.backend !== "kdeconnect"' in body.group(0), "a share action runs on a backend that has no share plugin"


def test_share_clipboard_reads_wl_paste_as_a_constant_argv_and_decides_through_the_synced_rule():
    """The clipboard is read with `wl-paste --no-newline` - a constant argv,
    never a shell string with anything interpolated - and what to do with
    the text is the synced clipboardShareTarget decision, so the QML suite
    pins the URL heuristic. An empty clipboard is a reported failure
    ("Clipboard is empty"), not a share of nothing."""
    source = SERVICE.read_text()
    block = _process_block(source, "clipboardProc")
    assert re.search(r'command:\s*\["wl-paste", "--no-newline"\]', block), (
        "the clipboard read is not the constant argv [wl-paste, --no-newline]"
    )
    assert "${" not in block and '"sh"' not in block and '"bash"' not in block
    assert "root.clipboardShareTarget(" in block, "the clipboard text is not classified through clipboardShareTarget"
    assert 'root.reportFailure(Translation.tr("Clipboard is empty"))' in block, (
        "an empty clipboard is not reported as one"
    )
    assert "root.shareUrls(" in block and "root.shareText(" in block, (
        "the clipboard does not reach both share actions"
    )
    body = re.search(r"function shareClipboard\(.*?\n    \}\n", source, re.S)
    assert body, "shareClipboard() missing"
    assert "clipboardProc.running" in body.group(0), "shareClipboard does not start the read (or guard a read in flight)"
    assert "root.validDeviceId(d.id)" in body.group(0), "shareClipboard aims at an unvalidated device"


def test_the_file_picker_is_kdialog_as_a_constant_argv_and_its_lines_become_file_urls():
    """The house picker (`kdialog --getopenfilename $HOME --multiple`, the
    pattern at SidebarRightContent.qml:113) as a constant argv: the only
    non-literal element is the start directory, read from the environment
    and never interpolated into a shell string. Its stdout is one path per
    line, turned into file:// URLs by the synced pickedFileUrls and handed
    to shareUrls - so the picker never talks to the daemon itself."""
    source = SERVICE.read_text()
    block = _process_block(source, "filePickerProc")
    command = re.search(r'command:\s*\["kdialog", "--getopenfilename", ([^\]]*)\]', block)
    assert command, "the picker is not the constant argv [kdialog, --getopenfilename, <home>, --multiple]"
    assert command.group(1).endswith('"--multiple"'), f"the picker does not ask for several files: {command.group(0)}"
    assert "${" not in block and '"sh"' not in block and '"bash"' not in block
    assert "root.pickedFileUrls(" in block, "the picker's lines are not turned into URLs by pickedFileUrls"
    assert "root.shareUrls(" in block, "the picker does not hand its files to shareUrls"
    body = re.search(r"function pickAndSendFiles\(.*?\n    \}\n", source, re.S)
    assert body, "pickAndSendFiles() missing"
    assert "filePickerProc.running" in body.group(0), "pickAndSendFiles does not start the picker (or guard one already open)"
    assert "root.validDeviceId(d.id)" in body.group(0), "pickAndSendFiles aims at an unvalidated device"


def test_browse_files_mounts_then_reads_the_mount_point_and_opens_it_as_argv():
    """Slice 5's transport: sftp.mount on the device's /sftp leaf through
    runAction; then, on the read queue, sftp.isMounted until it answers
    true (bounded - a mount that never comes up is a reported failure, not
    a timer that polls for ever) and sftp.mountPoint, the daemon's own
    answer for where it put the phone. `<mount>/storage/emulated/0` is
    preferred when that directory exists (the fork's 3a7f653b4: the mount
    root is not the user's storage), decided by the synced sftpBrowseTarget
    from a `test -d` argv, and opened with an xdg-open argv. sftpMounted
    tracks the isMounted answer."""
    source = SERVICE.read_text()
    assert re.search(r"^    property bool sftpMounted: false$", source, re.M), "sftpMounted missing"
    assert re.search(r"readonly property int sftpMountAttemptCeiling:\s*\d+", source), (
        "the wait for the mount has no declared ceiling"
    )
    body = re.search(r"function browseFiles\(.*?\n    \}\n", source, re.S)
    assert body, "browseFiles() missing"
    assert "root.validDeviceId(d.id)" in body.group(0)
    assert 'root.runAction(root.busctlCall("org.kde.kdeconnect.daemon", `/modules/kdeconnect/devices/${d.id}/sftp`, "org.kde.kdeconnect.device.sftp", "mount", []))' in body.group(0), (
        "browseFiles does not call sftp.mount on the sftp leaf"
    )
    poll = re.search(r"function pollSftpMount\(.*?\n    \}\n", source, re.S)
    assert poll, "pollSftpMount() missing"
    for member in ("isMounted", "mountPoint"):
        assert f'"org.kde.kdeconnect.device.sftp", "{member}", []' in poll.group(0), (
            f"the mount wait does not read sftp.{member}"
        )
    assert "root.sftpMounted = " in poll.group(0), "the isMounted answer does not land on sftpMounted"
    assert "root.enqueue(" in poll.group(0) and "root.runAction(" not in poll.group(0), (
        "reads belong on the serialized read queue, not the action process"
    )
    assert "root.reportFailure(" in poll.group(0), "a mount that never comes up is not reported"
    probe = _process_block(source, "storageProbe")
    assert 'storageProbe.exec(["test", "-d"' in source, "the storage directory is not probed with a test -d argv"
    assert "root.sftpBrowseTarget(" in probe, "the directory to open is not decided by sftpBrowseTarget"
    assert 'Quickshell.execDetached(["xdg-open", ' in probe, "the mount is not opened with an xdg-open argv"


def test_low_battery_is_observed_on_the_active_device_and_reported_with_notify_send_argv():
    """Slice 6's battery half: the model is observed (onActiveDeviceChanged
    fires on every sweep, since the model is rebuilt), the crossing is
    decided by the synced batteryNoticeTransition the QML suite pins the
    thresholds of, and each notice is one notify-send argv - the fork's
    exact lines: `-i phone -u normal "Low battery: <name>" "Charge is at
    <n>%."` and `-i phone -u low "Battery recovered: <name>" "Charge is
    back to <n>%."` - never a shell string."""
    source = SERVICE.read_text()
    assert re.search(r"^    onActiveDeviceChanged: root\.observeBattery\(\)$", source, re.M), (
        "the battery is not observed from onActiveDeviceChanged"
    )
    body = re.search(r"function observeBattery\(.*?\n    \}\n", source, re.S)
    assert body, "observeBattery() missing"
    text = body.group(0)
    assert "root.batteryNoticeTransition(" in text, "the crossing is not decided by batteryNoticeTransition"
    assert '"notify-send", "-i", "phone", "-u", "normal"' in text, "the low notice is not the fork's notify-send argv"
    assert '"notify-send", "-i", "phone", "-u", "low"' in text, "the recovery notice is not the fork's notify-send argv"
    assert 'Translation.tr("Low battery: %1")' in text and 'Translation.tr("Charge is at %1%.")' in text
    assert 'Translation.tr("Battery recovered: %1")' in text and 'Translation.tr("Charge is back to %1%.")' in text
    assert '"sh"' not in text and '"bash"' not in text and "${" not in text
    # A different active device starts from a clean latch.
    assert "root.batteryNoticeDeviceId" in text, "the latch is not per device"


# ---- the sidebar surface ----------------------------------------------------


def test_the_surface_calls_only_actions_the_model_exposes():
    called = set()
    for path in sorted(SURFACE.glob("*.qml")):
        called |= set(re.findall(r"\bPhoneConnect\.(\w+)\(", path.read_text()))
    assert called, "the surface calls nothing on the service"
    assert called <= MODEL_ACTIONS, f"the surface invents actions: {sorted(called - MODEL_ACTIONS)}"
    declared = set(re.findall(r"^    function (\w+)\(", SERVICE.read_text(), re.M))
    assert called <= declared, f"the surface calls what the service does not declare: {sorted(called - declared)}"


def test_the_dialog_has_one_action_row_of_the_three_model_actions():
    """ONE row of round action buttons, each a model action, in the fork's
    order (ring, ping, clipboard) minus the three it backs with scrcpy, a
    picker and SFTP."""
    dialog = DIALOG.read_text()
    assert dialog.count("id: actionRow") == 1, "the dialog must carry exactly one action row"
    buttons = re.findall(r"PhoneConnectActionButton \{(.*?)\n(?:\s{12}|\s{8})\}", dialog, re.S)
    assert len(buttons) == 3, f"expected three action buttons, found {len(buttons)}"
    called = [re.search(r"PhoneConnect\.(\w+)\(", body).group(1) for body in buttons]
    assert called == ["ring", "ping", "sendClipboard"], called


def test_the_pairing_card_answers_through_the_two_device_methods_in_a_button_row():
    """Accept and Decline are the model's two pairing calls, and they sit in a
    WindowDialogButtonRow so the filled-confirm / outlined-dismiss rule is
    derived by the row rather than spelled at the card (the polkit contract
    refuses an `outlined:` outside the widgets directory for that reason)."""
    card = (SURFACE / "PhoneConnectPairingCard.qml").read_text()
    assert "PhoneConnect.acceptPairing(" in card and "PhoneConnect.cancelPairing(" in card
    assert "WindowDialogButtonRow {" in card, "the two answers must sit in a WindowDialogButtonRow"
    assert "outlined:" not in card, "the card spells the outline rule for itself"


def test_the_notification_area_owns_the_remaining_height():
    """The area is the one child of the dialog's column that fills, so every
    other row keeps its own height and the empty state takes what is left -
    nothing floats in empty space, and nothing else competes for it."""
    dialog = DIALOG.read_text()
    fills = [line.strip() for line in dialog.splitlines() if "Layout.fillHeight: true" in line]
    assert len(fills) == 1, f"expected exactly one fillHeight in the dialog, found {fills}"
    area = re.search(r"PhoneConnectNotificationArea \{(.*?)\n    \}", dialog, re.S)
    assert area, "the dialog does not declare a PhoneConnectNotificationArea"
    assert "Layout.fillHeight: true" in area.group(1), "the notification area does not fill"


if __name__ == "__main__":
    import sys
    from contract_runner import run
    sys.exit(run(globals()))
