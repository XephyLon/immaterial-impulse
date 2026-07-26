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


def test_default_config_ships_disabled():
    cfg = json.loads(DEFAULT_CONFIG.read_text())
    assert cfg["appearance"]["openrgb"] == {"enable": False}


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
    # The only bash -c in the file is the constant availability probe.
    bash_commands = re.findall(r'"bash", "-c", (.+?)\]', source)
    assert bash_commands == ['"command -v openrgb"'], (
        "bash -c must only carry the constant availability probe, never values"
    )


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


if __name__ == "__main__":
    import sys
    from contract_runner import run
    sys.exit(run(globals()))
