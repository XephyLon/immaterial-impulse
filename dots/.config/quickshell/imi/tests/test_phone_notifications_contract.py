"""Contract checks for services/PhoneNotifications.qml.

The QML suite (tst_phone_notifications.qml) drives a logic-only double, so
its green transfers to the real service only while the region between the
`BEGIN/END phone-notifications parser logic` markers is byte-for-byte
identical in both files (the BEGIN line may differ - each side points its
"synced with" note at the other), and while the three derived properties
the tab reads are spelled the same.

The rest pins the busctl I/O the double omits, and the two decisions the
spec (docs/superpowers/specs/2026-08-27-phone-tab-design.md, W2) names
outright:
- every busctl invocation is an argv array built by PhoneConnect.busctlCall;
  the service carries no busctl literal and no shell string at all;
- dismiss is the LEAF's notification.dismiss on <device>/notifications/<id>,
  never the device-level sendAction("cancel") the fork once used;
- the reply refetch delay is a declared constant the timer reads;
- there is no monitor here (one stream: PhoneConnect's), the refetch hangs
  off PhoneConnect.deviceChangeSettled, and no Process carries a running
  binding;
- ids are validated before they are spliced into a path;
- services/Notifications.qml drops the daemon's copy behind the mirror gate,
  before it tracks the notification, and the gate reads the tab's switch
  through an optional chain (the key is declared by another workstream);
- Persistent declares the cache key the service writes.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "services" / "PhoneNotifications.qml"
DOUBLE = ROOT / "tests" / "imports" / "testservices" / "PhoneNotifications.qml"
PHONE_CONNECT = ROOT / "services" / "PhoneConnect.qml"
NOTIFICATIONS = ROOT / "services" / "Notifications.qml"
PERSISTENT = ROOT / "modules" / "common" / "Persistent.qml"

COMMENT = re.compile(r"/\*.*?\*/|//[^\n]*", re.S)

BEGIN = "// BEGIN phone-notifications parser logic"
END = "    // END phone-notifications parser logic"

LEAF_IFACE = "org.kde.kdeconnect.device.notifications.notification"
DEVICE_IFACE = "org.kde.kdeconnect.device.notifications"


def _synced_region(path: Path) -> str:
    text = path.read_text()
    assert text.count(BEGIN) == 1, f"{path}: expected exactly one BEGIN marker"
    assert text.count(END) == 1, f"{path}: expected exactly one END marker"
    start = text.index("\n", text.index(BEGIN)) + 1
    return text[start:text.index(END)]


def _code(path: Path) -> str:
    """The file with its comments stripped: the header records the cancel
    action and the monitor it does NOT use, and a check that reads prose
    as code reddens on the explanation."""
    return COMMENT.sub("", path.read_text())


def _function(source: str, name: str) -> str:
    body = re.search(rf"    function {name}\(.*?\n    \}}\n", source, re.S)
    assert body, f"{name}() missing"
    return body.group(0)


def _process_blocks(source: str):
    for match in re.finditer(r"\bProcess\s*\{", source):
        depth, index = 1, match.end()
        while index < len(source) and depth:
            if source[index] == "{":
                depth += 1
            elif source[index] == "}":
                depth -= 1
            index += 1
        yield source[match.start():index]


def test_parser_region_is_byte_identical_between_service_and_double():
    service_region = _synced_region(SERVICE)
    double_region = _synced_region(DOUBLE)
    assert service_region, "synced region is empty"
    assert service_region == double_region, (
        "services/PhoneNotifications.qml and tests/imports/testservices/PhoneNotifications.qml "
        "have drifted between the phone-notifications parser logic markers; edit both "
        "sides identically"
    )


def test_the_derived_properties_the_tab_reads_match_the_double():
    """count, groupsByAppName and appNameList sit outside the region (they
    are bindings on `notifications`), and the QML suite drives the double's
    copies - so the spellings are held to each other."""
    for name in ("count", "groupsByAppName", "appNameList"):
        pattern = rf"    readonly property [\w<>]+ {name}:.*\n"
        service_line = re.search(pattern, SERVICE.read_text())
        double_line = re.search(pattern, DOUBLE.read_text())
        assert service_line and double_line, f"{name} missing on one side"
        assert service_line.group(0) == double_line.group(0), f"{name} drifted"


def test_every_busctl_call_is_an_argv_array_from_phone_connects_builder():
    source = SERVICE.read_text()
    assert '"busctl"' not in source, "the service spells a busctl argv of its own"
    assert '"sh"' not in source and '"bash"' not in source, "the service reaches a shell"
    execs = [line.strip() for line in source.splitlines() if ".exec(" in line]
    assert execs == ["busProc.exec(next.argv);"], f"a Process is started outside the queue: {execs}"
    calls = [line.strip() for line in source.splitlines() if "root.enqueue(" in line or "root.runAction(" in line]
    started = [line for line in calls if "PhoneConnect.busctlCall(" in line]
    forwarded = [line for line in calls if line.startswith("root.enqueue(argv")]
    assert started and len(started) + len(forwarded) == len(calls), (
        f"a call that is not PhoneConnect.busctlCall's argv: {calls}"
    )


def test_dismiss_is_the_leafs_own_method_and_never_a_cancel_action():
    """The fork's first version called the device-level sendAction with
    "cancel" as the action - which invokes a named Android action button, and
    "cancel" is not one, so the phone kept showing what the sidebar had
    dropped. The leaf object has a dismiss() of its own; it is the only
    dismiss there is."""
    source = SERVICE.read_text()
    body = _function(source, "dismiss")
    assert f'"{LEAF_IFACE}", "dismiss", []' in body, "dismiss() does not call the leaf's dismiss method"
    assert "`${root.notificationsPath(deviceId)}/${publicId}`" in body, "dismiss() is not aimed at the leaf path"
    assert '"cancel"' not in _code(SERVICE), "a cancel action has crept back in"
    all_body = _function(source, "dismissAll")
    assert "root.dismiss(" in all_body, "dismissAll() does not go through dismiss()"
    for name in ("sendReply", "sendAction"):
        assert f'"{DEVICE_IFACE}", "{name}", ["ss"' in source, f"{name} is not the device-level two-string call"


def test_the_reply_refetch_delay_is_a_declared_constant_the_timer_reads():
    source = SERVICE.read_text()
    assert re.search(r"readonly property int replyRefetchDelay:\s*800\b", source), (
        "the reply refetch delay must be declared as replyRefetchDelay: 800"
    )
    timer = re.search(r"Timer \{\n\s*id: replyRefetch(.*?)\n    \}", source, re.S)
    assert timer, "replyRefetch timer missing"
    assert "interval: root.replyRefetchDelay" in timer.group(1), "the timer does not read the constant"
    assert "replyRefetch.restart()" in _function(source, "reply"), "reply() does not arm the refetch"
    for name in ("reconcileInterval", "cacheSaveDelay"):
        assert re.search(rf"readonly property int {name}:\s*\d+", source), f"{name} not declared"
        assert f"interval: root.{name}" in source, f"no timer reads {name}"


def test_one_stream_the_refetch_hangs_off_phone_connects_settled_signal():
    source = SERVICE.read_text()
    assert "monitor" not in _code(SERVICE).lower(), "the service runs a monitor of its own"
    assert "function onDeviceChangeSettled()" in source, "no refetch on PhoneConnect.deviceChangeSettled"
    assert "signal deviceChangeSettled()" in PHONE_CONNECT.read_text(), "PhoneConnect does not declare the signal"
    settle = re.search(r"Timer \{\n\s*id: signalSettle(.*?)\n    \}", PHONE_CONNECT.read_text(), re.S)
    assert settle and "root.deviceChangeSettled()" in settle.group(1), "PhoneConnect's settle does not raise it"
    allow = _function(PHONE_CONNECT.read_text(), "signalChangesDevices")
    for member in ("notificationPosted", "notificationUpdated", "notificationRemoved", "allNotificationsRemoved"):
        assert member in allow, f"{member} is not on PhoneConnect's allowlist"
    for block in _process_blocks(source):
        assert not re.search(r"^\s*running\s*:", block, re.M), f"a Process carries a running binding: {block[:80]}"


def test_ids_are_validated_before_they_are_spliced_into_a_path():
    source = SERVICE.read_text()
    assert ".filter(id => root.validPublicId(id))" in source, "public ids are not filtered before the leaf reads"
    for name in ("dismiss", "reply", "sendAction", "sweep"):
        body = _function(source, name)
        assert "PhoneConnect.validDeviceId(deviceId)" in body, f"{name}() splices a device id without validating"
    assert "root.validPublicId(publicId)" in _function(source, "dismiss")


def test_the_mirror_gate_reads_the_tabs_switch_through_an_optional_chain():
    source = SERVICE.read_text()
    assert "Config.options.sidebar?.phone?.enable ?? true" in source, (
        "the tab switch is declared by another workstream; read it through ?. with a default"
    )
    assert re.search(r"readonly property bool mirrorActive: root\.tabEnabled && \(PhoneConnect\.activeDevice\?\.reachable \?\? false\)", source), (
        "mirrorActive is not tabEnabled && the active device's reachability"
    )


def test_the_desktop_server_drops_the_daemons_copy_before_tracking_it():
    """The dedupe belongs at ingestion: an untracked notification is
    discarded by the server, a tracked one is on the list and the popup."""
    source = NOTIFICATIONS.read_text()
    handler = re.search(r"onNotification: \(notification\) => \{(.*?)\n        \}", source, re.S)
    assert handler, "onNotification handler missing"
    body = handler.group(1)
    gate = body.find("PhoneNotifications.mirrorsDesktopNotification(notification.appName)")
    assert gate != -1, "the server does not ask PhoneNotifications before accepting a notification"
    assert gate < body.find("notification.tracked = true"), "the gate sits after the notification is tracked"
    assert "return;" in body[gate:body.find("notification.tracked = true")], "the gate does not drop"
    wrapper = _function(SERVICE.read_text(), "mirrorsDesktopNotification")
    assert "root.mirrorActive" in wrapper and "d.paired" in wrapper, (
        "the wrapper must gate on mirrorActive and compare against PAIRED devices' names"
    )


def test_persistent_declares_the_cache_key_the_service_writes():
    persistent = PERSISTENT.read_text()
    block = re.search(r"property JsonObject phone: JsonObject \{(.*?)\n            \}", persistent, re.S)
    assert block, "Persistent has no phone JsonObject"
    assert 'property string cachedNotificationsJson: ""' in block.group(1)
    source = SERVICE.read_text()
    assert "Persistent.states.phone.cachedNotificationsJson = root.cacheWith(" in source, "the cache is not written through cacheWith"
    assert "Persistent.ready" in _function(source, "restoreCache"), "restoreCache does not wait for Persistent"


if __name__ == "__main__":
    import sys
    from contract_runner import run
    sys.exit(run(globals()))
