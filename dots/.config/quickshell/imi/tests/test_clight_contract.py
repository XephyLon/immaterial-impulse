"""Contract checks for the Clight integration.

The integration spans four files whose cooperation is invisible to the QML
unit tests (Process/DBus wiring, a Variants-backed monitor list, settings
pages): services/Clight.qml, the deferral in services/Brightness.qml, the OSD
value-indicator extension, and the Services settings section. The moving
parts that a display-less check can pin are pinned here; the end-to-end
behaviour against fake busctl/brightnessctl binaries lives in
test_clight_integration_runtime.py.

The one deliberate absence is also pinned: Hyprsunset.qml must not know
Clight exists. Night-light ownership stays with the shell (its restore
semantics are pinned by test_nightlight_state_runtime.py); a detected daemon
must not silently change what night light does.
"""

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CLIGHT = ROOT / "services" / "Clight.qml"
BRIGHTNESS = ROOT / "services" / "Brightness.qml"
HYPRSUNSET = ROOT / "services" / "Hyprsunset.qml"
OSD_VALUE = ROOT / "modules" / "imi" / "onScreenDisplay" / "OsdValueIndicator.qml"
OSD_DISPLAY = ROOT / "modules" / "imi" / "onScreenDisplay" / "OnScreenDisplay.qml"
OSD_TEMP = ROOT / "modules" / "imi" / "onScreenDisplay" / "indicators" / "ClightTemperatureIndicator.qml"
CONFIG = ROOT / "modules" / "common" / "Config.qml"
SERVICES_PAGE = ROOT / "modules" / "imi" / "settings" / "pages" / "ServicesConfig.qml"


# --------------------------------------------------------------------- Clight

def test_clight_commands_are_argv_arrays_not_shell():
    source = CLIGHT.read_text()
    # The only shell invocation allowed is the static presence probe.
    shell_calls = re.findall(r'\["(?:ba)?sh",\s*"-c",\s*(.*?)\]', source)
    assert shell_calls == ['"command -v clight"'], shell_calls
    # Every busctl invocation is an argv array starting with the binary name.
    assert 'cmdProc.exec(["busctl", "--user", "call"' in source
    assert 'root.queuePropertyWrite(["busctl", "--user", "set-property"' in source


def test_clight_polling_is_gated_on_detection():
    source = CLIGHT.read_text()
    # Machines without Clight must never spawn a busctl: the poll timer needs
    # both the config gate and the one-shot binary detection.
    assert re.search(
        r"Timer \{[^}]*running: root\.enableService && root\.installed", source, re.S
    ), "poll timer is not gated on enableService && installed"
    body = re.search(r"function refresh\(\): void \{(.*?)\n    \}", source, re.S)
    assert body, "refresh() missing"
    assert "if (!root.enableService || !root.installed)" in body.group(1)


def test_clight_relative_moves_track_the_commanded_value():
    source = CLIGHT.read_text()
    body = re.search(r"function setBacklight\(target: real\): void \{(.*?)\n    \}", source, re.S)
    assert body, "setBacklight missing"
    # Absolute targets become deltas against the last commanded value, with
    # the same never-fully-black floor Brightness.qml's own writers keep.
    assert "Math.max(0.01, Math.min(1, target))" in body.group(1)
    assert "target - root.commandedBacklight" in body.group(1)
    drain = re.search(r"function drainBacklightQueue\(\): void \{(.*?)\n    \}", source, re.S)
    assert drain, "drainBacklightQueue missing"
    assert "Math.abs(root.pendingDelta) < 0.005" in drain.group(1), (
        "no epsilon: the external-sync loop would echo forever")


def test_clight_serializes_backlight_commands():
    source = CLIGHT.read_text()
    # Process.exec on a running process kills it and drops that command's
    # delta, so only one busctl may be in flight and queued deltas follow on
    # exit - and property writes must not share the backlight command process.
    drain = re.search(r"function drainBacklightQueue\(\): void \{(.*?)\n    \}", source, re.S)
    assert drain and "if (root.commandInFlight" in drain.group(1)
    exited = re.search(r"id: cmdProc\s*\n\s*onExited: \(exitCode, exitStatus\) => \{(.*?)\n        \}", source, re.S)
    assert exited, "cmdProc exit handler missing"
    assert "root.commandInFlight = false;" in exited.group(1)
    assert "root.drainBacklightQueue();" in exited.group(1)
    for setter in ("setAutoCalibration", "setDayTemperature", "setNightTemperature"):
        body = re.search(r"function " + setter + r"\([^)]*\): void \{(.*?)\n    \}", source, re.S)
        assert body and "root.queuePropertyWrite(" in body.group(1), setter
    prop_exited = re.search(r"id: propProc\s*\n\s*onExited: \(exitCode, exitStatus\) => \{(.*?)\n        \}", source, re.S)
    assert prop_exited, "propProc exit handler missing"
    assert "root.propInFlight = false;" in prop_exited.group(1)
    assert "root.drainPropertyQueue();" in prop_exited.group(1)


def test_clight_temperature_signal_skips_the_first_report():
    source = CLIGHT.read_text()
    body = re.search(r"function applyState\(text: string\): void \{(.*?)\n    \}", source, re.S)
    assert body, "applyState missing"
    assert "const firstReport = !root.ready;" in body.group(1)
    assert re.search(
        r"if \(!firstReport && previous !== values\.Temp\)\s*\n\s*root\.temperatureChangedByDaemon\(\)",
        body.group(1),
    ), "startup report would announce a temperature 'change'"


# ----------------------------------------------------------------- Brightness

def test_brightness_defers_to_clight_before_its_own_writers():
    source = BRIGHTNESS.read_text()
    body = re.search(r"function syncBrightness\(\) \{(.*?)\n        \}", source, re.S)
    assert body, "syncBrightness missing"
    guard = body.group(1).find("if (Clight.managesBacklight)")
    ddc = body.group(1).find('setProc.exec(["ddcutil"')
    backlight = body.group(1).find('setProc.exec(["brightnessctl"')
    assert guard != -1, "syncBrightness never defers to Clight"
    assert ddc != -1 and backlight != -1, "stock writers must survive for the degraded path"
    assert guard < ddc and guard < backlight, "deferral must come before the direct writers"
    assert "Clight.setBacklight(brightnessValue)" in body.group(1)


def test_brightness_external_sync_does_not_pop_the_osd():
    source = BRIGHTNESS.read_text()
    # Daemon recalibrations flow in through updateFromExternal, which must
    # suppress the brightnessChanged signal the OSD listens for.
    assert re.search(
        r"onBrightnessChanged: \{\s*\n\s*if \(!monitor\.ready \|\| monitor\.externalSync\) return;",
        source,
    ), "externalSync no longer suppresses the OSD trigger"
    body = re.search(r"function updateFromExternal\(value: real\): void \{(.*?)\n        \}", source, re.S)
    assert body, "updateFromExternal missing"
    assert "monitor.externalSync = true;" in body.group(1)
    assert "monitor.externalSync = false;" in body.group(1)


# ----------------------------------------------------------------- Night light

def test_night_light_ownership_is_untouched_by_clight():
    # The conservative decision, as code: hyprsunset restore/schedule/toggles
    # know nothing about Clight, so a detected daemon cannot silently change
    # night-light behaviour. The settings page warns instead.
    assert "Clight" not in HYPRSUNSET.read_text()
    assert "Hyprsunset" not in CLIGHT.read_text()


# ------------------------------------------------------------------------ OSD

def test_osd_value_indicator_display_text_is_optional():
    source = OSD_VALUE.read_text()
    assert 'property string displayText: ""' in source
    assert re.search(
        r'text: root\.displayText !== "" \? root\.displayText : Math\.round\(root\.value \* 100\)',
        source,
    ), "displayText must replace the percentage only when set"


def test_osd_registers_the_clight_temperature_indicator():
    source = OSD_DISPLAY.read_text()
    assert '"clightTemperature"' in source
    assert 'sourceUrl: "indicators/ClightTemperatureIndicator.qml"' in source
    assert re.search(
        r"target: Clight\s*\n\s*function onTemperatureChangedByDaemon\(\)", source
    ), "no OSD trigger for daemon temperature changes"
    temp = OSD_TEMP.read_text()
    assert "displayText: `${Clight.temperature}K`" in temp


# --------------------------------------------------------------------- Config

def test_clight_enable_setting_has_both_halves():
    config = CONFIG.read_text()
    clight_block = re.search(r"property JsonObject clight: JsonObject \{(.*?)\n\s*\}", config, re.S)
    assert clight_block, "light.clight schema missing from Config.qml"
    assert "property bool enable: true" in clight_block.group(1)

    page = SERVICES_PAGE.read_text()
    assert "checked: Config.options.light.clight.enable" in page
    assert ("onToggleRequested: Config.options.light.clight.enable = "
            "!Config.options.light.clight.enable" in page)


def test_settings_temperature_spinboxes_write_from_value_modified():
    page = SERVICES_PAGE.read_text()
    for setter in ("setDayTemperature", "setNightTemperature"):
        assert re.search(
            r"onValueModified: \{\s*\n\s*Clight\." + setter + r"\(newValue\);", page
        ), f"{setter} must be driven from onValueModified(newValue)"
    # The daemon-state switch must not echo poll refreshes back at the daemon.
    # It used to need an `if (checked !== Clight.autoCalibration)` guard for
    # that, because the write came back through the binding and re-fired the
    # handler. A ConfigSwitch click is an intent now (#158) - it fires once per
    # click and never on a state change - so the guard has nothing to suppress
    # and is gone. What has to hold instead: the daemon call reads the daemon's
    # own state rather than the widget's, and hangs off the intent.
    assert re.search(
        r"onToggleRequested: Clight\.setAutoCalibration\(!Clight\.autoCalibration\)", page
    ), "auto-calibration must ask the daemon for the opposite of what it reports"
    assert "onCheckedChanged" not in page, (
        "a ConfigSwitch write-back on onCheckedChanged is a dead switch now - "
        "`checked` no longer moves on a click"
    )


if __name__ == "__main__":
    import sys
    from contract_runner import run
    sys.exit(run(globals()))
