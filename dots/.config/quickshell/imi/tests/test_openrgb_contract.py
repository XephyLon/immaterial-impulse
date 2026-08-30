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
QUICK_CONFIG = ROOT / "modules" / "imi" / "settings" / "pages" / "QuickConfig.qml"
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
        "monitorExcludedTypes": ["GPU"],
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
        r'applyProc\.command = root\.sdkCommand\(\["openrgb", "--mode", root\.pendingMode, "--color", hex\]\)',
        source,
    ), "openrgb must be invoked as an argv array with the color as its own element"
    # The mode is one of two internal constants, never user input.
    assert re.findall(r'root\.pendingMode = "(\w+)"', source) == ["static", "direct"], (
        "pendingMode must only ever be the static (accent) or direct (ambient) constant"
    )
    # The per-device (exclusion) path builds argv the same way.
    assert (
        'cmd.push("--device", String(dev.index), "--mode", mode, "--color", hex)'
        in source
    ), "per-device apply must keep color and index as their own argv elements"
    # The only bash -c uses in the file are the constant probes: the two
    # binary availability checks and the SDK-server port check.
    bash_commands = re.findall(r'"bash", "-c", (.+?)\]', source)
    assert bash_commands == [
        '"command -v openrgb"',
        '"command -v grim"',
        '"exec 3<>/dev/tcp/127.0.0.1/6742"',
    ], "bash -c must only carry the constant probes, never values"


def test_every_write_goes_through_the_sdk_server():
    """The CLI does not talk to a running server on its own. Without
    `--client` each call is a hardware detection pass that resets every
    device to its default colour - the lights blinked white once per
    debounce and once per ambient sample. So: a server is wanted whenever
    the sync is on (not only in ambient mode), writes wait for it, and every
    openrgb argv - the apply, the per-device apply, the device scan - is
    routed through `sdkCommand`, which splices the client flag in."""
    source = _source()
    assert 'readonly property list<string> sdkClientArgs: ["--client", "127.0.0.1:6742"]' in source
    assert "return [argv[0]].concat(root.sdkClientArgs, argv.slice(1));" in source
    assert "applyProc.command = root.sdkCommand(cmd);" in source, (
        "the per-device apply bypasses the server"
    )
    assert 'command: root.sdkCommand(["openrgb", "--list-devices"])' in source, (
        "the device scan bypasses the server - a detecting scan blinks the lights too"
    )
    assert "running: root.enabled && root.available && !root.serverReady" in source, (
        "the server is only sought in ambient mode; the accent path blinks"
    )
    assert re.search(r"if \(root\.serverStarting\)\s*\n\s*return;", source), (
        "a write does not wait for the server we are starting"
    )
    assert re.search(r"onServerReadyChanged:\s*\{\s*if \(root\.serverReady\)\s*root\.startPendingApply\(\);", source), (
        "nothing re-dispatches the held write once the server answers"
    )
    debounce = re.search(r"id: debounceTimer.*?interval: (\d+)", source, re.S)
    assert debounce and int(debounce.group(1)) <= 250, (
        "the debounce is back to hiding a blink rather than coalescing animation steps"
    )


def test_colours_stream_through_one_open_client():
    """The Effects plugin's model: connect once, Direct mode once, then
    frames. The streamer is a Process kept open with stdin; both the accent
    path and the ambient loop hand their colour to `pushColor` first and
    fall through to the CLI only while no streamer is ready."""
    source = _source()
    assert "readonly property string streamScript: `${Directories.scriptPath}/rgb/openrgb_stream.py`" in source
    assert (ROOT / "scripts/rgb/openrgb_stream.py").is_file()
    proc = re.search(r"Process\s*\{\s*id: streamProc(.*?)\n    \}", source, re.S)
    assert proc, "no streamProc"
    assert "stdinEnabled: true" in proc.group(1)
    assert "running: root.streamWanted" in proc.group(1)
    assert 'data.startsWith("ready")' in proc.group(1), "the streamer's ready line gates the writes"
    assert 'streamProc.write(hex + "\\n");' in source
    assert 'args.push("--exclude-name", name);' in source, "name exclusions must be their own argv elements"
    assert 'args.push("--exclude-type", type);' in source
    # Both paths try the stream before the CLI.
    assert source.count("if (root.pushColor(hex))\n            return;") == 2, (
        "the accent path and the ambient loop must both hand the colour to the streamer first"
    )


def test_the_ambient_sample_is_a_screencopy_not_a_grim_spawn():
    """The loop reads the compositor's frame through a ScreencopyView: no
    process spawn, no JPEG encode. The view lives in a one-pixel
    transparent input-masked bottom-layer window because `grabToImage`
    refuses an item whose window is not visible (measured in
    ScreenSampleProbe.qml), the sample lands on tmpfs, and grim survives
    only as the fallback behind `samplerBroken`."""
    source = _source()
    start = source.find("id: samplerWindow")
    end = source.find("id: ambientTimer")
    assert 0 < start < end, "no sampler window ahead of the ambient timer"
    body = source[start:end]
    for line in ("implicitWidth: 1", "implicitHeight: 1", 'color: "transparent"',
                 "WlrLayershell.layer: WlrLayer.Bottom", "mask: Region {}",
                 "exclusionMode: ExclusionMode.Ignore"):
        assert line in body, f"sampler window lost `{line}` - it must stay one invisible, input-free pixel"
    assert "live: false" in body, "a live view captures every frame; the loop samples on its own clock"
    assert "paintCursor: false" in body
    assert "XDG_RUNTIME_DIR" in source, "the sample belongs on tmpfs, not the cache"
    assert "if (!root.samplerBroken && samplerLoader.item !== null)" in source, (
        "captureAmbientFrame no longer prefers the screencopy sampler"
    )
    assert re.search(r"running: root\.ambientActive && root\.serverReady\s*\n\s*"
                     r"&& \(!root\.samplerBroken \|\| root\.grimAvailable\)", source), (
        "the loop must run without grim installed unless the sampler broke"
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
    # enumerate before applying instead of trusting a stale scan (the
    # ambient loop's one-scan-per-activation reuse is the sole exception,
    # pinned separately).
    assert re.search(
        r"if \(root\.excludedDevices\.length > 0 \|\| typeFiltered\) \{[\s\S]*?"
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
    # The sampling clock only runs while ambient mode is active AND an
    # OpenRGB SDK server answers - serverless CLI writes do a full
    # detection pass per call, which resets devices to their default
    # (white) and takes seconds. grim left the gate when the screencopy
    # sampler arrived: it is only required once the sampler has broken.
    assert re.search(
        r"Timer \{\s*\n\s*id: ambientTimer\s*\n\s*"
        r"running: root\.ambientActive && root\.serverReady\s*\n\s*"
        r"&& \(!root\.samplerBroken \|\| root\.grimAvailable\)",
        source,
    ), "the ambient Timer must be gated on ambientActive, serverReady, and grim only as the broken-sampler fallback"
    # The managed server is a constant argv and only spawned once per
    # activation (no crash-loop respawns from the poll timer), and the spawn
    # goes through the detector sync so an excluded device is never even
    # claimed by the server.
    assert 'command: ["openrgb", "--server"]' in source
    assert "root.serverSpawnAttempted = false" in source
    assert re.search(
        r"if \(!root\.serverSpawnAttempted && !serverProc\.running && !detectorSyncProc\.running\) \{\s*\n\s*"
        r"root\.serverSpawnAttempted = true;[\s\S]*?"
        r"detectorSyncProc\.thenStartServer = true;",
        source,
    ), "the server spawn must run the detector sync first, at most once per activation"


def test_ambient_skips_gpu_writes_and_caches_the_scan():
    source = _source()
    config = CONFIG.read_text()
    # GPU RGB rides the graphics i2c bus; streaming to it stalls games. The
    # ambient loop must exclude it by default, and only the ambient loop -
    # the accent path passes no type filter.
    assert 'property list<string> monitorExcludedTypes: ["GPU"]' in config
    assert re.search(
        r'root\.pendingMode === "direct" \? root\.ambientTypeExclusions : \[\]',
        source,
    ), "type exclusions must only apply to ambient (direct) writes"
    assert "excludedTypes.includes(dev.type)" in source
    # One device scan per ambient activation: per-write scans double the bus
    # traffic. The cache invalidates on activation and on exclusion changes
    # (a detector-sync restart re-enumerates).
    assert re.search(
        r'if \(root\.pendingMode === "direct" && root\.ambientScanDone && root\.devices\.length > 0\) \{\s*\n\s*'
        r"root\.startExclusionApply\(\);",
        source,
    ), "ambient applies must reuse the per-activation scan"
    assert source.count("root.ambientScanDone = false") >= 2, (
        "the scan cache must reset on activation and on exclusion changes"
    )


def test_detector_sync_is_argv_and_covers_exclusion_changes():
    source = _source()
    # Excluded device names reach the sync script as their own argv elements.
    assert (
        'command: ["python3", root.detectorSyncScript, root.detectorStatePath]'
        ".concat(root.excludedDevices)" in source
    ), "detector sync must pass excluded names as argv elements, never spliced"
    # Toggling exclusions in monitor mode re-syncs detectors, and a reported
    # change restarts our managed server so it takes effect.
    assert re.search(
        r"function onExcludedDevicesChanged\(\)[\s\S]*?detectorSyncProc\.running = true;",
        source,
    ), "exclusion changes must trigger a detector re-sync"
    assert re.search(
        r"else if \(changed && serverProc\.running\) \{\s*\n\s*"
        r"serverProc\.running = false;\s*\n\s*serverProc\.running = true;",
        source,
    ), "a detector change must restart the managed server"
    assert (ROOT / "scripts" / "rgb" / "sync_openrgb_detectors.py").exists()
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


def test_privacy_indicator_filters_ambient_capture_pulses():
    # The ambient sampler grims a frame per tick; without a filter the bar's
    # screencast dot blinks once a second for the shell's own capture. The
    # filter is opt-out (config default true) and only debounces while the
    # sampler runs, so real casts still show (after the pulse window).
    config = CONFIG.read_text()
    assert "property bool ignoreAmbientCapture: true" in config
    capture = (ROOT / "services" / "MediaCapture.qml").read_text()
    assert "root.ignoreAmbientCapture && OpenRgb.ambientActive" in capture
    assert re.search(
        r"id: ambientPulseFilter[\s\S]*?onTriggered: root\.screencastActive = true",
        capture,
    ), "a held cast must still surface through the pulse filter"


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
