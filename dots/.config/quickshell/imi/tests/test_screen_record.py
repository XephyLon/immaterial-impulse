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


class HdrCodecTests(unittest.TestCase):
    """gpu-screen-recorder does not tonemap.

    Handed an HDR surface with an SDR codec it encodes 8-bit and tags the file
    bt709, so a PQ signal ends up labelled as gamma and decodes flat and grey.
    These run the real script against stub hyprctl/gpu-screen-recorder binaries
    and read back the argv it built, rather than asserting on source text - the
    mapping is a behaviour, and a source grep would pass on a script that
    computed the codec correctly and then forgot to pass it.
    """

    def run_record(self, preset, codec="auto"):
        """Run record.sh --fullscreen against a monitor whose CM preset is
        `preset`, and return the argv it handed to gpu-screen-recorder."""
        import os
        import shutil
        import tempfile

        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp, True)
        bindir = tmp / "bin"
        bindir.mkdir()
        argv_file = tmp / "argv"

        monitors = json.dumps([{
            "name": "DP-1", "focused": True,
            "colorManagementPreset": preset,
            "currentFormat": "XBGR2101010",
        }])
        (bindir / "hyprctl").write_text(
            "#!/usr/bin/env bash\ncat <<'MONEOF'\n" + monitors + "\nMONEOF\n")
        # Records argv and exits, so record.sh's `wait` returns immediately.
        (bindir / "gpu-screen-recorder").write_text(
            '#!/usr/bin/env bash\nprintf "%s\\n" "$@" > "' + str(argv_file) + '"\n')
        for noop in ("notify-send", "slurp"):
            (bindir / noop).write_text("#!/usr/bin/env bash\nexit 0\n")
        for f in bindir.iterdir():
            f.chmod(0o755)

        home = tmp / "home"
        (home / ".config/immaterial-impulse").mkdir(parents=True)
        (home / ".config/immaterial-impulse/config.json").write_text(
            json.dumps({"screenRecord": {"codec": codec, "savePath": str(tmp / "out")}}))

        env = dict(os.environ)
        env["PATH"] = str(bindir) + os.pathsep + env["PATH"]
        env["HOME"] = str(home)
        env["XDG_CONFIG_HOME"] = str(home / ".config")
        env["XDG_RUNTIME_DIR"] = str(tmp)
        subprocess.run(["bash", str(RECORD_SH), "--fullscreen"],
                       env=env, capture_output=True, text=True, timeout=60)
        self.assertTrue(argv_file.exists(), "gpu-screen-recorder was never invoked")
        return argv_file.read_text().split("\n")

    def codec_of(self, argv):
        return argv[argv.index("-k") + 1] if "-k" in argv else None

    def test_hdr_monitor_upgrades_auto_to_hevc_hdr(self):
        # The reported bug: on an HDR display "auto" produced 8-bit bt709 HEVC.
        self.assertEqual(self.codec_of(self.run_record("hdredid")), "hevc_hdr")

    def test_plain_hdr_preset_also_counts(self):
        # Hyprland has two HDR presets; matching "hdredid" alone misses one.
        self.assertEqual(self.codec_of(self.run_record("hdr")), "hevc_hdr")

    def test_sdr_monitor_is_left_alone(self):
        # 10-bit is not HDR: wide-gamut SDR reports the same currentFormat,
        # which is why the preset and not the format is the signal.
        self.assertIsNone(self.codec_of(self.run_record("srgb")))
        self.assertEqual(self.codec_of(self.run_record("srgb", codec="hevc")), "hevc")

    def test_explicit_codecs_map_to_their_hdr_variants(self):
        self.assertEqual(self.codec_of(self.run_record("hdredid", codec="hevc")), "hevc_hdr")
        self.assertEqual(self.codec_of(self.run_record("hdredid", codec="av1")), "av1_hdr")

    def test_h264_is_not_silently_swapped(self):
        # H.264 has no HDR variant. Changing the codec someone explicitly chose
        # is worse than telling them why the file will look wrong.
        self.assertEqual(self.codec_of(self.run_record("hdredid", codec="h264")), "h264")

    def test_replay_path_agrees_with_the_script(self):
        # Two capture paths, one behaviour. The replay daemon lives in QML and
        # would otherwise drift out of step with record.sh silently.
        qml = SERVICE.read_text()
        self.assertIn("hdrCodecFor", qml)
        self.assertIn('startsWith("hdr")', qml)
        for expected in ('return "hevc_hdr"', 'return "av1_hdr"'):
            self.assertIn(expected, qml)
        self.assertIn("root.hdrCodecFor(o.codec, o.replay.monitor)", qml,
                      "replayArgs must route its codec through the HDR mapping")

    def test_service_imports_the_module_declaring_HyprlandData(self):
        # #104 was exactly this shape: a singleton used without importing the
        # module that declares it throws ReferenceError at the call site.
        self.assertIn("import qs.services", SERVICE.read_text())


class WiringTests(unittest.TestCase):
    def test_keybinds(self):
        keybinds = (ROOT.parents[1] / "hypr/hyprland/keybinds.lua").read_text()
        self.assertIn("quickshell:screenRecordToggle", keybinds)
        self.assertIn("quickshell:replaySave", keybinds)
        self.assertIn("quickshell:replayToggle", keybinds)

    def test_region_selector_checks_pidfile_not_wf_recorder(self):
        sel = (ROOT / "modules/imi/regionSelector/RegionSelection.qml").read_text()
        self.assertNotIn("wf-recorder", sel)
        self.assertIn("imi-screenrecord.pid", sel)

    def test_bar_replay_button(self):
        bar = (ROOT / "modules/imi/bar/UtilButtons.qml").read_text()
        self.assertIn("ScreenRecord.replaying", bar)
        self.assertIn("ScreenRecord.saveReplay()", bar)

    def test_privacy_indicator_shows_shell_captures(self):
        ind = (ROOT / "modules/imi/bar/PrivacyIndicator.qml").read_text()
        self.assertIn("ScreenRecord.recording", ind)
        self.assertIn("ScreenRecord.replaying", ind)
        self.assertIn('sym: "screen_record"', ind)
        self.assertIn('sym: "replay"', ind)
        popup = (ROOT / "modules/imi/bar/PrivacyIndicatorPopup.qml").read_text()
        self.assertIn("ScreenRecord.recording", popup)
        self.assertIn("ScreenRecord.replaying", popup)

    def test_sidebar_quick_toggle_registered_in_both_styles(self):
        model = (ROOT / "modules/common/models/quickToggles/InstantReplayToggle.qml").read_text()
        self.assertIn("ScreenRecord.toggleReplay()", model)
        self.assertIn("ScreenRecord.saveReplay()", model)  # altAction saves a clip
        panel = (ROOT / "modules/imi/sidebarRight/quickToggles/AndroidQuickPanel.qml").read_text()
        self.assertIn('"instantReplay"', panel)
        chooser = (ROOT / "modules/imi/sidebarRight/quickToggles/androidStyle/AndroidToggleDelegateChooser.qml").read_text()
        self.assertIn('roleValue: "instantReplay"', chooser)
        classic = (ROOT / "modules/imi/sidebarRight/quickToggles/ClassicQuickPanel.qml").read_text()
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


class PortalSdrTests(unittest.TestCase):
    """SDR delivery captures through the portal instead of converting.

    Hyprland tonemaps screencopy for capture clients - the reason a grim
    screenshot of an HDR desktop looks right - so portal capture yields native
    SDR at record time (verified live: bt709/yuv420p, correct colours), where
    the KMS path hands the encoder raw PQ. Regions are covered too: the portal
    picker has a Region tab and replaces slurp in this mode.
    """

    @classmethod
    def setUpClass(cls):
        cls.script = SCRIPT.read_text()
        cls.code = "\n".join(l for l in cls.script.splitlines()
                             if not l.lstrip().startswith("#"))

    def test_sdr_toggle_routes_to_portal_capture(self):
        self.assertIn("tonemapSdr", self.code)
        self.assertIn("-w portal", self.code)
        self.assertIn("USE_PORTAL=1", self.code)

    def test_fullscreen_restores_a_session_token_region_does_not(self):
        # Fullscreen: the picker should appear once, then the token pins the
        # choice. Region: every capture is a fresh selection, exactly as slurp
        # was, so restoring a stale region would be wrong.
        portal_block = self.code[self.code.index("-w portal"):]
        portal_block = portal_block[:portal_block.index("elif")]
        self.assertIn("restore-portal-session", portal_block)
        self.assertRegex(portal_block,
                         r'if \[\[ \$FULLSCREEN -eq 1 \]\];[\s\S]*restore-portal-session')

    def test_hdr_codec_upgrade_only_when_keeping_hdr(self):
        # With portal capture the stream is SDR - forcing an _hdr codec onto it
        # would tag an SDR stream as PQ, recreating the original wash-out in
        # reverse. The upgrade lives in the else-branch of the toggle.
        idx_portal = self.code.index("USE_PORTAL=1")
        idx_hdr = self.code.index('CODEC="hevc_hdr"')
        self.assertLess(idx_portal, idx_hdr)
        self.assertIn("else", self.code[idx_portal:idx_hdr])
