#!/usr/bin/env python3
"""Screen recorder pins: gpu-screen-recorder migration + instant replay.

The recorder has two cooperating halves that can only break silently:
scripts/videos/record.sh (one-shot recordings, pidfile-scoped toggle) and
services/ScreenRecord.qml (replay daemon, signals, IPC, shortcuts). These
pins hold the contract between them and the config/keybind/UI wiring.
"""
import json
import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RECORD_SH = ROOT / "scripts/videos/record.sh"
SAVED_SH = ROOT / "scripts/videos/gsr-saved.sh"
SERVICE = ROOT / "services/ScreenRecord.qml"


class RecordScriptTests(unittest.TestCase):
    def setUp(self):
        self.script = RECORD_SH.read_text()

    def test_bash_syntax(self):
        for path in (RECORD_SH, SAVED_SH):
            proc = subprocess.run(["bash", "-n", str(path)], capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_uses_gpu_screen_recorder_not_wf_recorder(self):
        self.assertIn("gpu-screen-recorder", self.script)
        self.assertNotIn("wf-recorder", self.script)

    def test_toggle_is_pidfile_scoped_not_pkill(self):
        # pkill by process name would also kill the replay daemon.
        self.assertIn("imi-screenrecord.pid", self.script)
        self.assertIn('kill -INT "$(cat "$PIDFILE")"', self.script)
        self.assertNotIn("pkill", self.script)

    def test_keeps_interface_flags(self):
        for flag in ("--sound", "--fullscreen", "--region", "--path"):
            self.assertIn(flag, self.script)

    def test_reads_config_keys_matching_adapter(self):
        adapter = (ROOT / "modules/common/Config.qml").read_text()
        for key in ("fps", "quality", "codec", "audioCodec", "showCursor",
                    "framerateMode", "recordMic", "savePath"):
            self.assertIn(f".screenRecord.{key}", self.script)
            self.assertIn(key, adapter)

    def test_converts_slurp_geometry_to_gsr(self):
        # slurp "X,Y WxH" -> gsr "WxH+X+Y"
        self.assertIn('"%dx%d+%d+%d", $3, $4, $1, $2', self.script)
        out = subprocess.run(
            ["bash", "-c",
             'awk -F\'[ ,x]\' \'{printf "%dx%d+%d+%d", $3, $4, $1, $2}\' <<< "100,200 640x480"'],
            capture_output=True, text=True).stdout
        self.assertEqual(out, "640x480+100+200")

    def test_maintains_recording_state_for_bar_indicator(self):
        self.assertIn('".record.enable = $state"', self.script)

    def test_saved_hook_wired(self):
        self.assertIn("gsr-saved.sh", self.script)
        saved = SAVED_SH.read_text()
        self.assertIn('"regular"', SERVICE.read_text() + saved) if False else None
        for t in ("replay", "regular", "screenshot"):
            self.assertIn(t, saved)

    def test_mic_merges_into_single_track(self):
        self.assertIn("default_output|default_input", self.script)


class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.service = SERVICE.read_text()

    def test_replay_daemon_args(self):
        for pin in ('"-r", `${Math.max(2, o.replay.duration)}`',
                    '"-replay-storage", o.replay.storage',
                    '"-restart-replay-on-save"',
                    '"-sc", `${Directories.scriptPath}/videos/gsr-saved.sh`'):
            self.assertIn(pin, self.service)

    def test_signals(self):
        self.assertIn("replayProc.signal(10)", self.service)  # SIGUSR1 saves
        self.assertIn("kill -USR2", self.service)             # pause via pidfile

    def test_pause_scoped_by_pidfile(self):
        self.assertIn("imi-screenrecord.pid", self.service)

    def test_replay_daemon_no_respawn_loop(self):
        # A failing daemon must disable itself, not spin.
        self.assertIn("Config.options.screenRecord.replay.enable = false", self.service)

    def test_ipc_and_shortcuts(self):
        self.assertIn('target: "record"', self.service)
        for name in ("screenRecordToggle", "screenRecordPause", "replaySave", "replayToggle"):
            self.assertIn(f'name: "{name}"', self.service)

    def test_service_anchored_in_shell(self):
        # Lazy singletons without references never register IPC/shortcuts.
        shell = (ROOT / "shell.qml").read_text()
        self.assertIn("_screenRecord: ScreenRecord", shell)


class WiringTests(unittest.TestCase):
    def test_keybinds(self):
        keybinds = (ROOT.parents[1] / "hypr/hyprland/keybinds.lua").read_text()
        self.assertIn("quickshell:screenRecordToggle", keybinds)
        self.assertIn("quickshell:replaySave", keybinds)
        self.assertIn("quickshell:replayToggle", keybinds)

    def test_region_selector_checks_pidfile_not_wf_recorder(self):
        sel = (ROOT / "modules/ii/regionSelector/RegionSelection.qml").read_text()
        self.assertNotIn("wf-recorder", sel)
        self.assertIn("imi-screenrecord.pid", sel)

    def test_bar_replay_button(self):
        bar = (ROOT / "modules/ii/bar/UtilButtons.qml").read_text()
        self.assertIn("ScreenRecord.replaying", bar)
        self.assertIn("ScreenRecord.saveReplay()", bar)

    def test_privacy_indicator_shows_shell_captures(self):
        ind = (ROOT / "modules/ii/bar/PrivacyIndicator.qml").read_text()
        self.assertIn("ScreenRecord.recording", ind)
        self.assertIn("ScreenRecord.replaying", ind)
        self.assertIn('sym: "screen_record"', ind)
        self.assertIn('sym: "replay"', ind)
        popup = (ROOT / "modules/ii/bar/PrivacyIndicatorPopup.qml").read_text()
        self.assertIn("ScreenRecord.recording", popup)
        self.assertIn("ScreenRecord.replaying", popup)

    def test_sidebar_quick_toggle_registered_in_both_styles(self):
        model = (ROOT / "modules/common/models/quickToggles/InstantReplayToggle.qml").read_text()
        self.assertIn("ScreenRecord.toggleReplay()", model)
        self.assertIn("ScreenRecord.saveReplay()", model)  # altAction saves a clip
        panel = (ROOT / "modules/ii/sidebarRight/quickToggles/AndroidQuickPanel.qml").read_text()
        self.assertIn('"instantReplay"', panel)
        chooser = (ROOT / "modules/ii/sidebarRight/quickToggles/androidStyle/AndroidToggleDelegateChooser.qml").read_text()
        self.assertIn('roleValue: "instantReplay"', chooser)
        classic = (ROOT / "modules/ii/sidebarRight/quickToggles/ClassicQuickPanel.qml").read_text()
        self.assertIn("InstantReplay {}", classic)

    def test_no_wf_recorder_left_in_shell(self):
        hits = []
        for f in ROOT.rglob("*"):
            if f.is_file() and f.suffix in (".qml", ".sh", ".py") and "/tests/" not in str(f):
                if "wf-recorder" in f.read_text(errors="ignore"):
                    hits.append(str(f.relative_to(ROOT)))
        self.assertEqual(hits, [])


class ConfigContractTests(unittest.TestCase):
    def test_defaults_match_adapter(self):
        defaults = json.loads((ROOT / "defaults/config.json").read_text())
        sr = defaults["screenRecord"]
        # savePath's Config.qml default is dynamic (per-user videos dir) and
        # must never ship as a literal.
        self.assertNotIn("savePath", sr)
        self.assertEqual(sr["quality"], "very_high")
        self.assertEqual(sr["codec"], "auto")
        self.assertEqual(sr["fps"], 60)
        self.assertEqual(sr["replay"]["duration"], 120)
        self.assertFalse(sr["replay"]["enable"])
        self.assertEqual(sr["replay"]["storage"], "ram")
        adapter = (ROOT / "modules/common/Config.qml").read_text()
        for prop in ("property int fps: 60",
                     'property string quality: "very_high"',
                     "property JsonObject replay: JsonObject {",
                     "property int duration: 120"):
            self.assertIn(prop, adapter)


if __name__ == "__main__":
    unittest.main()
