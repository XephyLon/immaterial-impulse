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
- no `busctl monitor`: updates are bounded polling (a persistent streaming
  Process needs backoff and a retry ceiling per CONTRIBUTING.md), and the
  poll timer is gated on enableService && installed.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "services" / "PhoneConnect.qml"
DOUBLE = ROOT / "tests" / "imports" / "testservices" / "PhoneConnect.qml"

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
    builder = re.search(
        r'function busctlCall\(.*?\{\n(.*?)\n    \}', source, re.S
    )
    assert builder, "busctlCall builder missing"
    assert '["busctl", "--user", "--json=short"' in builder.group(1)
    # Every exec goes through the queue or the action process, both fed by
    # busctlCall argv arrays - no other busctl literal should exist.
    busctl_literals = [
        line.strip() for line in source.splitlines()
        if '"busctl"' in line
        and not line.strip().startswith('return ["busctl"')
        and "command -v" not in line
    ]
    assert busctl_literals == [], f"busctl invoked outside busctlCall: {busctl_literals}"


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
    for action in ("ring", "ping", "sendClipboard"):
        body = re.search(rf"function {action}\(.*?\n    \}}\n", source, re.S)
        assert body, f"{action}() missing"
        assert "validDeviceId" in body.group(0) or "validValentObjectPath" in body.group(0), (
            f"{action}() splices without validating"
        )


def test_no_streaming_monitor_and_poll_timer_is_gated():
    source = SERVICE.read_text()
    assert '"monitor"' not in source, (
        "busctl monitor is a persistent streaming Process; bounded polling was "
        "the reviewed decision (see the service header comment)"
    )
    timer = re.search(r"Timer \{(.*?)\n    \}", source, re.S)
    assert timer, "poll Timer missing"
    assert "running: root.enableService && root.installed" in timer.group(1)
    assert "repeat: true" in timer.group(1)


if __name__ == "__main__":
    import sys
    from contract_runner import run
    sys.exit(run(globals()))
