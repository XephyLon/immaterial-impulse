"""Contract checks for services/PhoneContacts.qml.

The QML suite (tst_phone_contacts.qml) drives the contacts list's decisions
through a logic-only double, so the double proving something transfers to
the shell only while the real service carries the same logic: the region
between the `BEGIN/END phone-contacts logic` markers must be byte-for-byte
identical in both files (the BEGIN line may differ - each side points its
"synced with" note at the other), and so must the `filtered` binding that
composes those functions.

The rest pins what the double deliberately omits:
- every adb and python invocation is an argv array built by the synced
  builders; the only shell strings are the two static `command -v` probes,
  with nothing interpolated, and both start themselves;
- the monitor Process carries no `running` binding and the restart-safe
  marker, is started through exec(), and every exit consults the one
  backoff ladder (PhoneConnect.monitorExitPlan) - the rule CONTRIBUTING.md
  states outright for a streaming process;
- the dialer and SMS intents are refused with lastError when adb is absent
  or no device is in the `device` state, and go through `adb devices`
  first because the wireless-debugging port moves;
- the Config keys W3 declares are read with optional chaining and defaults,
  and a favorite is written only when the key exists;
- the device followed is PhoneConnect.activeDevice, and the script the
  service names is the one in the tree.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "services" / "PhoneContacts.qml"
DOUBLE = ROOT / "tests" / "imports" / "testservices" / "PhoneContacts.qml"
SCRIPT = ROOT / "scripts" / "phone" / "contacts_monitor.py"

BEGIN = "// BEGIN phone-contacts logic"
END = "    // END phone-contacts logic"


def _synced_region(path: Path) -> str:
    text = path.read_text()
    assert text.count(BEGIN) == 1, f"{path}: expected exactly one BEGIN marker"
    assert text.count(END) == 1, f"{path}: expected exactly one END marker"
    start = text.index("\n", text.index(BEGIN)) + 1
    return text[start:text.index(END)]


def _process_block(source: str, process_id: str) -> str:
    """The `Process { ... }` block declaring `id: <process_id>`, brace-counted
    rather than regexed to an indent, so it can say a binding is absent."""
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


def _function(source: str, name: str) -> str:
    body = re.search(rf"    function {name}\(.*?\n    \}}\n", source, re.S)
    assert body, f"{name}() missing"
    return body.group(0)


# ---- the double ------------------------------------------------------------


def test_the_logic_region_is_byte_identical_between_service_and_double():
    service_region = _synced_region(SERVICE)
    double_region = _synced_region(DOUBLE)
    assert service_region, "synced region is empty"
    assert service_region == double_region, (
        "services/PhoneContacts.qml and tests/imports/testservices/PhoneContacts.qml "
        "have drifted between the phone-contacts logic markers; edit both sides identically"
    )


def test_the_region_carries_every_decision_the_qml_suite_drives():
    region = _synced_region(DOUBLE)
    for name in ("normalizeQuery", "contactMatches", "isFavorite", "isHidden", "sortKey",
                 "sortContacts", "filterContacts", "toggledFavorites", "adbSerialFromDevices",
                 "intentUri", "intentArgv", "monitorArgv", "parseMonitorEvent"):
        assert f"function {name}(" in region, f"{name} is outside the synced region"


def test_the_filtered_binding_matches_the_double():
    pattern = r"    readonly property var filtered:.*\n"
    service_line = re.search(pattern, SERVICE.read_text())
    double_line = re.search(pattern, DOUBLE.read_text())
    assert service_line and double_line, "filtered binding missing on one side"
    assert service_line.group(0) == double_line.group(0), "the filtered binding drifted"
    assert "root.filterContacts(root.contacts, root.query, root.hideUnnamed, root.favorites, root.sortBy)" in service_line.group(0)


# ---- argv only -------------------------------------------------------------


def test_only_shell_strings_are_the_two_static_presence_probes():
    source = SERVICE.read_text()
    shell_commands = re.findall(r'\["sh",\s*"-c",\s*(.*?)\]', source)
    assert sorted(shell_commands) == ['"command -v adb"', '"command -v gio"'], (
        f"unexpected shell strings in PhoneContacts.qml: {shell_commands}"
    )
    for line in source.splitlines():
        if '"sh"' in line and "${" in line:
            raise AssertionError(f"interpolation into a shell command: {line.strip()}")
    assert "execDetached" not in source, "an intent must be a Process whose exit is read, not fire-and-forget"


def test_the_presence_probes_start_themselves():
    source = SERVICE.read_text()
    for probe in ("gioProbe", "adbProbe"):
        block = _process_block(source, probe)
        assert re.search(r"^\s*running:\s*true", block, re.M), f"{probe} does not start itself"


def test_adb_is_invoked_only_through_the_argv_builder_and_devices():
    source = SERVICE.read_text()
    region = _synced_region(SERVICE)
    assert 'return ["adb", ...target, "shell", "am", "start", "-a", action, "-d", uri];' in region
    outside = source.replace(region, "")
    adb_literals = [line.strip() for line in outside.splitlines()
                    if '"adb"' in line and "command -v" not in line]
    assert adb_literals == ['if (!adbDevicesProc.running) adbDevicesProc.exec(["adb", "devices"]);'], (
        f"adb invoked outside the builders: {adb_literals}"
    )
    assert "intentProc.exec(root.intentArgv(serial, intent.action, intent.uri))" in source


def test_the_monitor_is_spawned_from_the_argv_builder_at_the_script_in_the_tree():
    source = SERVICE.read_text()
    assert SCRIPT.exists(), "scripts/phone/contacts_monitor.py is missing"
    assert "/phone/contacts_monitor.py`" in source, "the service names a different script"
    assert "monitorProc.exec(root.monitorArgv(root.monitorScript, root.deviceId))" in source
    assert 'return ["python3", script, ...device];' in _synced_region(SERVICE)


# ---- the monitor's lifetime ---------------------------------------------------


def test_the_monitor_process_has_no_running_binding_and_carries_the_marker():
    block = _process_block(SERVICE.read_text(), "monitorProc")
    bindings = re.findall(r"^\s*running\s*:", block, re.M)
    assert bindings == [], f"monitorProc declares a running binding: {bindings}"
    assert "process-lifecycle: restart-safe" in block, (
        "the monitor block must carry the restart-safe marker the plugin lifecycle lint recognises"
    )


def test_every_monitor_exit_consults_the_one_backoff_ladder():
    """No second spelling of the ladder: the exit handler asks
    PhoneConnect.monitorExitPlan, honours its refusal, and arms the timer
    with the delay it returned. The one restart outside it is the
    deliberate one, gated on the flag restartMonitor() sets while it stops
    the process, and it is what a device change goes through."""
    source = SERVICE.read_text()
    block = _process_block(source, "monitorProc")
    assert "PhoneConnect.monitorExitPlan(" in block, "the exit handler does not consult the plan"
    assert "monitorRestart.interval = plan.delay" in block, (
        "the restart timer is armed with something other than the plan's delay"
    )
    assert re.search(r"if\s*\(!plan\.retry\)", block), "the exit handler does not honour the plan's refusal"
    assert "if (root.monitorRestartWanted)" in block
    assert not re.search(r"function monitorExitPlan|function monitorBackoffDelay|Math\.pow\(2", source), (
        "a second copy of the backoff ladder"
    )
    code = re.sub(r"//[^\n]*", "", source)
    starts = [line.strip() for line in code.splitlines()
              if re.search(r"\bstartMonitor\(\)", line) and "function startMonitor" not in line]
    assert starts, "nothing starts the monitor"
    for line in starts:
        assert "root.startMonitor()" in line, f"unexpected monitor start path: {line}"


def test_the_ceiling_is_declared_and_reachable_and_the_gate_is_a_function():
    source = SERVICE.read_text()
    assert re.search(r"readonly property int monitorAttemptCeiling:\s*\d+", source)
    assert re.search(r"readonly property int monitorHealthyMs:\s*\d+", source)
    assert 'root.monitorState = "failed"' in source
    assert re.search(r"function monitorWanted\(\): bool \{", source), "the monitor's gate must be a function"
    assert not re.search(r"property bool (wantMonitor|monitorWanted)", source), (
        "the monitor's gate is a binding on the property its own handler hangs off"
    )
    assert 'root.monitorState !== "failed"' in _function(source, "monitorWanted")


def test_a_device_change_restarts_the_monitor_from_the_top_of_the_ladder():
    source = SERVICE.read_text()
    assert "readonly property string deviceId: PhoneConnect.activeDevice?.id ?? \"\"" in source
    handler = re.search(r"onDeviceIdChanged: \{(.*?)\n    \}", source, re.S)
    assert handler and "root.restartMonitor()" in handler.group(1)
    restart = _function(source, "restartMonitor")
    assert "root.monitorAttempts = 0" in restart
    assert "root.monitorRestartWanted = true" in restart and "monitorProc.running = false" in restart


# ---- the intents -------------------------------------------------------------


def test_dialer_and_sms_are_the_two_android_intents_over_a_resolved_serial():
    source = SERVICE.read_text()
    assert 'root.startIntent("android.intent.action.DIAL", "tel", number)' in _function(source, "openDialer")
    assert 'root.startIntent("android.intent.action.SENDTO", "sms", number)' in _function(source, "composeSms")
    start = _function(source, "startIntent")
    assert "if (!root.adbAvailable)" in start and "root.refuse(" in start, (
        "an intent with no adb must be refused with lastError, not spawned"
    )
    devices = _process_block(source, "adbDevicesProc")
    assert "root.adbSerialFromDevices(adbDevicesOut.text)" in devices
    assert 'if (serial === "")' in devices and "root.refuse(" in devices, (
        "no device in the `device` state must be refused with lastError"
    )
    refuse = _function(source, "refuse")
    assert 'root.lastError = "";' in refuse and "root.lastError = message;" in refuse, (
        "a repeated refusal must still raise lastErrorChanged"
    )


# ---- the config keys ----------------------------------------------------------


def test_config_reads_are_optional_and_defaulted_and_a_favorite_is_written_only_when_declared():
    source = SERVICE.read_text()
    expected = {
        "enabled": 'Config.options.phone?.contacts?.enabled ?? true',
        "hideUnnamed": 'Config.options.phone?.contacts?.hideUnnamed ?? true',
        "sortBy": 'Config.options.phone?.contacts?.sortBy ?? "first"',
        "favorites": 'Config.options.phone?.contacts?.favoriteIds ?? []',
    }
    for name, expression in expected.items():
        assert f"property {'string' if name == 'sortBy' else 'bool' if name != 'favorites' else 'var'} {name}: {expression}" in source, (
            f"{name} does not read its Config key with optional chaining and a default"
        )
    for line in source.splitlines():
        if "Config.options.phone." in line:
            raise AssertionError(f"a Config read without optional chaining: {line.strip()}")
    toggle = _function(source, "toggleFavorite")
    assert "store.favoriteIds === undefined" in toggle, "toggleFavorite writes into an undeclared key"
    assert "store.favoriteIds = root.toggledFavorites(store.favoriteIds, uid)" in toggle
    writes = [line.strip() for line in source.splitlines() if re.search(r"favoriteIds\s*=[^=]", line)]
    assert writes == ["store.favoriteIds = root.toggledFavorites(store.favoriteIds, uid);"], writes


if __name__ == "__main__":
    import sys
    from contract_runner import run
    sys.exit(run(globals()))
