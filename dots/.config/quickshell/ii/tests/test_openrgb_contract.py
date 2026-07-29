"""Contract checks for services/OpenRgb.qml (port of dots-hyprland PR #3415).

OpenRgb is Process wiring around the openrgb CLI - there is no callable pure
logic to unit-test, so this pins the structure that must survive refactors:
the feature is off by default, palette changes are debounced rather than
applied per animation frame, the color reaches openrgb as its own argv
element (never spliced into a shell string), a missing binary degrades to a
silent no-op, and the lazily-loaded singleton is actually instantiated at
startup.
"""

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "services" / "OpenRgb.qml"
CONFIG = ROOT / "modules" / "common" / "Config.qml"
SHELL = ROOT / "shell.qml"
QUICK_CONFIG = ROOT / "modules" / "ii" / "settings" / "pages" / "QuickConfig.qml"
DEFAULT_CONFIG = ROOT / "defaults" / "config.json"


def _source() -> str:
    return SERVICE.read_text()


def test_config_schema_defaults_off():
    config = CONFIG.read_text()
    block = re.search(r"property JsonObject openrgb: JsonObject \{(.*?)\}", config, re.S)
    assert block, "no appearance.openrgb JsonObject in Config.qml"
    assert "property bool enable: false" in block.group(1), "openrgb must default to disabled"
    assert "property list<string> excludedDevices: []" in block.group(1), (
        "openrgb must ship with no devices excluded"
    )


def test_default_config_ships_disabled():
    cfg = json.loads(DEFAULT_CONFIG.read_text())
    assert cfg["appearance"]["openrgb"] == {
        "enable": False,
        "excludedDevices": [],
        "colorSource": "accent",
        "monitorFullscreenOnly": True,
        "monitorPollInterval": 200,
        "monitorColorDelta": 12,
        "monitorSmooth": True,
    }


def test_palette_changes_are_debounced():
    source = _source()
    assert "function onM3primaryChanged()" in source, "no palette-change trigger"
    assert re.search(r"Timer\s*\{\s*id:\s*debounceTimer", source), "no debounce timer"
    # The trigger path must restart the timer, not apply directly.
    assert "debounceTimer.restart()" in source
    assert "onTriggered: root.requestApply()" in source


def test_color_is_argv_not_shell_spliced():
    source = _source()
    assert re.search(
        r'applyProc\.command = \["openrgb", "--mode", "static", "--color", hex\]',
        source,
    ), "openrgb must be invoked as an argv array with the color as its own element"
    # The per-device (exclusion) path builds argv the same way.
    assert (
        'cmd.push("--device", String(dev.index), "--mode", "static", "--color", hex)'
        in source
    ), "per-device apply must keep color and index as their own argv elements"
    # The only bash -c uses in the file are the two constant availability
    # probes (openrgb for the accent path, grim for the ambient sampler).
    bash_commands = re.findall(r'"bash", "-c", (.+?)\]', source)
    assert bash_commands == ['"command -v openrgb"', '"command -v grim"'], (
        "bash -c must only carry the constant availability probes, never values"
    )


def _function_block(source: str, name: str) -> str:
    """Extracts a brace-balanced `function <name>(...) { ... }` block."""
    start = source.index(f"function {name}")
    depth = 0
    for pos in range(start, len(source)):
        if source[pos] == "{":
            depth += 1
        elif source[pos] == "}":
            depth -= 1
            if depth == 0:
                return source[start : pos + 1]
    raise AssertionError(f"unbalanced braces in function {name}")


def test_logic_double_is_in_sync():
    double = (ROOT / "tests" / "imports" / "testservices" / "OpenRgb.qml").read_text()
    source = _source()
    for name in ("parseDeviceList", "buildDeviceCommand", "colorDelta", "mixHex"):
        assert _function_block(source, name) == _function_block(double, name), (
            f"{name} drifted between services/OpenRgb.qml and its test double"
        )


def test_exclusions_are_name_keyed_and_rescan_before_apply():
    source = _source()
    assert (
        "readonly property list<string> excludedDevices: "
        "Config.options.appearance.openrgb.excludedDevices ?? []" in source
    ), "exclusions must come from config with an empty-list fallback"
    # Indices shift when devices (dis)connect - the exclusion path must
    # re-enumerate before every apply instead of trusting a cached scan.
    assert re.search(
        r"if \(root\.excludedDevices\.length > 0\) \{[\s\S]*?"
        r"root\.applyAfterScan = true;\s*\n\s*root\.rescanDevices\(\);",
        source,
    ), "exclusion apply must scan first (applyAfterScan + rescanDevices)"
    assert "excluded.includes(dev.name)" in source, "exclusion must match by device name"
    # Toggling exclusions must force a fresh (debounced) apply.
    assert "function onExcludedDevicesChanged()" in source


def test_settings_ui_replaces_the_list_wholesale():
    page = QUICK_CONFIG.read_text()
    # JsonAdapter lists only persist on whole-list assignment.
    assert "Config.options.appearance.openrgb.excludedDevices = excluded" in page, (
        "device toggles must write the exclusion list by replacement"
    )
    assert "OpenRgb.rescanDevices()" in page, "settings page must be able to trigger a scan"


def test_missing_binary_is_a_noop():
    source = _source()
    exited = re.search(r"availabilityProc[\s\S]*?onExited:([\s\S]*?)\n    \}", source)
    assert exited, "availability probe has no onExited handler"
    body = exited.group(1)
    assert "root.available = exitCode === 0" in body
    assert re.search(r"if \(root\.available\)\s*\n\s*root\.startPendingApply\(\);", body)
    assert 'root.pendingColor = ""' in body, "unavailable openrgb must drop the pending apply"


def test_apply_is_gated_on_config():
    source = _source()
    assert "readonly property bool enabled: Config.options.appearance.openrgb.enable" in source
    assert re.search(r"if \(!Config\.ready \|\| !root\.enabled\)\s*\n\s*return;", source)


def test_singleton_is_loaded_at_startup():
    assert "OpenRgb.load()" in SHELL.read_text(), (
        "lazily-loaded singleton never instantiates without a shell.qml reference"
    )


def test_settings_toggle_binds_the_option():
    page = QUICK_CONFIG.read_text()
    assert "Config.options.appearance.openrgb.enable" in page, (
        "no settings toggle for appearance.openrgb.enable"
    )
    assert "Config.options.appearance.openrgb.colorSource" in page, (
        "no settings selector for appearance.openrgb.colorSource"
    )


def test_ambient_schema_defaults_to_accent():
    config = CONFIG.read_text()
    block = re.search(r"property JsonObject openrgb: JsonObject \{(.*?)\}", config, re.S)
    assert block, "no appearance.openrgb JsonObject in Config.qml"
    body = block.group(1)
    assert 'property string colorSource: "accent"' in body, (
        "ambient sync must default to the accent source"
    )
    assert "property bool monitorFullscreenOnly: true" in body, (
        "monitor sampling must default to fullscreen-only"
    )


def test_ambient_loop_is_gated():
    source = _source()
    # The sampling clock only runs while ambient mode is active AND grim is
    # known to exist - never for accent-only users.
    assert re.search(
        r"Timer \{\s*\n\s*id: ambientTimer\s*\n\s*"
        r"running: root\.ambientActive && root\.grimAvailable",
        source,
    ), "the ambient Timer must be gated on ambientActive && grimAvailable"
    # ambientActive itself derives from monitor mode, the lockscreen, and the
    # fullscreen-only option against HyprlandData's derived flag.
    assert "readonly property bool monitorMode: root.enabled && root.colorSource === \"monitor\"" in source
    assert "HyprlandData.focusedMonitorHasFullscreen" in source
    assert re.search(
        r"readonly property bool ambientActive: root\.monitorMode\s*\n\s*"
        r"&& !GlobalStates\.screenLocked",
        source,
    ), "ambientActive must require monitor mode and an unlocked session"
    # While ambient drives the hardware the accent path must stand down.
    assert re.search(
        r"if \(root\.ambientActive\)\s*\n\s*return;", source
    ), "requestApply must not fight the ambient loop"


def test_grim_is_argv_not_shell_spliced():
    source = _source()
    assert (
        'grimProc.command = ["grim", "-o", name, "-s", "0.125", "-t", "jpeg", "-q", "80", root.ambientFramePath]'
        in source
    ), "grim must be invoked as an argv array with monitor name and path as own elements"
    # The monitor name comes from HyprlandData's monitor list, nowhere else.
    assert "HyprlandData.monitors.find(m => m.focused)?.name" in source


def test_ambient_exit_snaps_back_to_accent():
    source = _source()
    changed = re.search(r"onAmbientActiveChanged: \{([\s\S]*?)\n    \}", source)
    assert changed, "no onAmbientActiveChanged handler"
    body = changed.group(1)
    assert 'root.lastAppliedColor = ""' in body, (
        "leaving ambient mode must clear the dedup color"
    )
    assert "root.scheduleApply()" in body, (
        "leaving ambient mode must schedule an accent re-apply"
    )


def test_fullscreen_flag_lives_in_hyprland_data():
    hypr = (ROOT / "services" / "HyprlandData.qml").read_text()
    assert "readonly property bool focusedMonitorHasFullscreen" in hypr
    assert "w.fullscreen >= 2" in hypr, (
        "fullscreen detection must use Hyprland's int state (>= 2 = real fullscreen)"
    )


if __name__ == "__main__":
    import sys
    from contract_runner import run
    sys.exit(run(globals()))
