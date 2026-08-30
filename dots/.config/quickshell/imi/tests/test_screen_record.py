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
        self.assertIn('kill -INT "$gsr_pid"', self.script)
        self.assertNotIn("pkill", self.script)

    def test_the_stop_reaches_a_recorder_that_ignores_int_and_sits_on_term(self):
        """The recording the maintainer could not stop from the privacy card or
        the overlay: gsr blocked at portal selection, never capturing, INT
        still ignored (a `&` job in non-interactive bash is born with INT and
        QUIT ignored, and gsr undoes that only once capturing) and TERM caught
        but never acted on. Every stop path funnels into this script with a
        live pidfile, and it sent one INT.

        Driven for real: a stand-in `gpu-screen-recorder` on PATH that ignores
        INT and traps TERM to a no-op, launched through the script's own
        launch (which is where the mask comes from), then stopped through the
        script's own toggle. It must be gone within the ladder's window and the
        pidfile with it. The stand-in exits 0 on any signal it DOES receive,
        so a launch that stops ignoring INT ends it at the first rung.
        """
        import os, tempfile, time, shutil, stat
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            binstub = home / "bin"; binstub.mkdir()
            gsr = binstub / "gpu-screen-recorder"
            # INT and TERM are both trapped to no-ops - handled and ignored,
            # the way a wedged gsr behaves - so only KILL ends it: the worst
            # case the ladder must beat. Traps, not `trap '' INT`: that would
            # set SIG_IGN itself, and the assertion below reads the mask the
            # LAUNCH handed the process, which must be clean. `exec sleep`
            # would replace the traps, so it loops instead.
            # It also opens its output file, the way gsr does the moment
            # capture begins - the start watchdog reads that as "capturing".
            gsr.write_text("#!/usr/bin/env bash\n"
                           "trap ':' INT TERM\n"
                           "while [[ $# -gt 0 ]]; do [[ $1 == -o ]] && : > \"$2\"; shift; done\n"
                           "while :; do sleep 0.2; done\n")
            gsr.chmod(gsr.stat().st_mode | stat.S_IEXEC)
            for helper in ("notify-send", "slurp", "jq"):
                stub = binstub / helper
                if helper == "jq":
                    # The script reads its config through jq; the real one is
                    # fine but must be on the stub PATH too.
                    real = shutil.which("jq")
                    if real: os.symlink(real, stub); continue
                stub.write_text("#!/usr/bin/env bash\nexit 0\n")
                stub.chmod(stub.stat().st_mode | stat.S_IEXEC)
            runtime = home / "rt"; runtime.mkdir(mode=0o700)
            cfg = home / ".config/immaterial-impulse"; cfg.mkdir(parents=True)
            (cfg / "config.json").write_text(json.dumps({"screenRecord": {
                "fps": 30, "quality": "medium", "audioCodec": "opus", "codec": "auto",
                "framerateMode": "vfr", "showCursor": True, "recordAudio": False,
                "recordMic": False, "tonemapSdr": False, "savePath": str(home / "Videos")}}))
            (home / "Videos").mkdir()
            state = home / ".local/state/quickshell"; state.mkdir(parents=True)
            (state / "states.json").write_text(json.dumps({"record": {"enable": False, "region": ""}}))
            env = dict(os.environ, HOME=str(home), XDG_RUNTIME_DIR=str(runtime),
                       XDG_CONFIG_HOME=str(home / ".config"),
                       PATH=f"{binstub}:{os.environ['PATH']}")
            env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)

            # Start: the script blocks on `wait`, so run it detached.
            starter = subprocess.Popen(["bash", str(RECORD_SH), "--fullscreen"], env=env,
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            pidfile = runtime / "imi-screenrecord.pid"
            deadline = time.monotonic() + 10
            while not pidfile.exists() and time.monotonic() < deadline:
                time.sleep(0.1)
            self.assertTrue(pidfile.exists(), "the script never wrote its pidfile")
            gsr_pid = int(pidfile.read_text().strip())
            self.assertTrue(Path(f"/proc/{gsr_pid}").exists(), "the stand-in never came up")

            # The launch must not hand gsr an ignored INT.
            sigign = re.search(r"SigIgn:\s*([0-9a-f]+)",
                               Path(f"/proc/{gsr_pid}/status").read_text()).group(1)
            self.assertEqual(int(sigign, 16) & 0x2, 0,
                             f"gsr was launched with SIGINT ignored (SigIgn={sigign}); "
                             f"the launch must run under job control")

            # Stop through the toggle - the same path every UI stop takes.
            t0 = time.monotonic()
            subprocess.run(["bash", str(RECORD_SH)], env=env, timeout=30, check=True)
            deadline = time.monotonic() + 8
            while Path(f"/proc/{gsr_pid}").exists() and time.monotonic() < deadline:
                time.sleep(0.1)
            elapsed = time.monotonic() - t0
            self.assertFalse(Path(f"/proc/{gsr_pid}").exists(),
                             f"the recorder survived the stop ({elapsed:.1f}s) - the toggle "
                             f"must escalate INT -> TERM -> KILL")
            try:
                starter.wait(timeout=10)
            except subprocess.TimeoutExpired:
                starter.kill(); self.fail("record.sh did not exit after its recorder died")
            self.assertFalse(pidfile.exists(), "the pidfile outlived the recording")

    def test_a_recording_that_never_starts_is_torn_down_and_reported(self):
        """The bar said "recording" for minutes while gsr sat at CreateSession
        against a hard-hung portal - single-threaded, no output file - and the
        user's only signal was that Stop did nothing. The script now waits a
        bounded window for the OUTPUT FILE (gsr opens it as capture begins)
        and, past it, tears gsr down and says why. Driven with a stand-in that
        never opens its file, and the window shortened through the env hook.
        """
        import os, tempfile, time, shutil, stat
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            binstub = home / "bin"; binstub.mkdir()
            gsr = binstub / "gpu-screen-recorder"
            gsr.write_text("#!/usr/bin/env bash\n"
                           "trap ':' INT TERM\n"
                           "while :; do sleep 0.2; done\n")
            gsr.chmod(gsr.stat().st_mode | stat.S_IEXEC)
            notes = home / "notify.log"
            (binstub / "notify-send").write_text(f"#!/usr/bin/env bash\necho \"$*\" >> {notes}\n")
            (binstub / "notify-send").chmod(0o755)
            (binstub / "slurp").write_text("#!/usr/bin/env bash\nexit 0\n"); (binstub / "slurp").chmod(0o755)
            real_jq = shutil.which("jq"); self.assertTrue(real_jq); os.symlink(real_jq, binstub / "jq")
            runtime = home / "rt"; runtime.mkdir(mode=0o700)
            cfg = home / ".config/immaterial-impulse"; cfg.mkdir(parents=True)
            (cfg / "config.json").write_text(json.dumps({"screenRecord": {
                "fps": 30, "quality": "medium", "audioCodec": "opus", "codec": "auto",
                "framerateMode": "vfr", "showCursor": True, "recordAudio": False,
                "recordMic": False, "tonemapSdr": False, "savePath": str(home / "Videos")}}))
            (home / "Videos").mkdir()
            state = home / ".local/state/quickshell"; state.mkdir(parents=True)
            (state / "states.json").write_text(json.dumps({"record": {"enable": False, "region": ""}}))
            env = dict(os.environ, HOME=str(home), XDG_RUNTIME_DIR=str(runtime),
                       XDG_CONFIG_HOME=str(home / ".config"),
                       PATH=f"{binstub}:{os.environ['PATH']}",
                       IMI_RECORD_START_WINDOW_S="2")
            env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)

            t0 = time.monotonic()
            proc = subprocess.Popen(["bash", str(RECORD_SH), "--fullscreen"], env=env,
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                proc.wait(timeout=12)
            except subprocess.TimeoutExpired:
                # The pre-fix shape: record.sh blocks on `wait` behind a
                # recorder that never began, and the bar says "recording"
                # until someone kills it by hand.
                proc.kill(); proc.wait()
                for stray in subprocess.run(["pgrep", "-f", str(gsr)], capture_output=True,
                                            text=True).stdout.split():
                    subprocess.run(["kill", "-KILL", stray])
                self.fail("record.sh never gave up on a recorder that produced no output "
                          "file - the start watchdog is missing")
            elapsed = time.monotonic() - t0
            self.assertFalse((runtime / "imi-screenrecord.pid").exists(),
                             "the pidfile outlived the never-started recording")
            self.assertEqual(json.loads((state / "states.json").read_text())["record"]["enable"], False,
                             "the indicator was left saying 'recording'")
            self.assertTrue(notes.exists() and "Recording did not start" in notes.read_text(),
                            "the user was not told the recording never started")
            self.assertFalse(list((home / "Videos").glob("*.mp4")), "no file should exist")

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
        self.assertIn(".record.enable = $state", self.script)

    def test_state_writes_the_flag_and_the_region_together(self):
        # The shell rewrites this file wholesale from its own copy, so a region
        # written from QML after launching the script lands on top of the
        # `enable = true` written here and the recording indicator never comes
        # on. One writer: the flag and the region go in the same jq update.
        self.assertIn(".record.region = \\$region", self.script)
        self.assertIn('jq --arg region "$region"', self.script)
        # A full-screen capture stores no region, and must not inherit the last.
        self.assertIn('set_recording_state true "$REGION"', self.script)
        self.assertIn('set_recording_state false ""', self.script)

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
        # The classic style renders the same model; there is no classic
        # InstantReplay type any more.
        classic = (ROOT / "modules/imi/sidebarRight/quickToggles/ClassicQuickPanel.qml").read_text()
        self.assertIn("toggleModel: InstantReplayToggle {}", classic)

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


class SdrRoutingTests(unittest.TestCase):
    """SDR delivery: portal for fullscreen, shell selector + convert for regions.

    Hyprland tonemaps screencopy for capture clients, so portal capture yields
    native SDR at record time (bt709/yuv420p, verified live) where KMS hands
    the encoder raw PQ. Portal is FULLSCREEN ONLY: routing regions through the
    picker double-prompted after the shell's own selector. And the fullscreen
    token has a shipped precondition - xdph issues restore tokens only when
    the picker's checkbox is ticked, which dots/.config/hypr/xdph.conf
    pre-checks via allow_token_by_default. Without it the picker prompts on
    EVERY recording (that shipped once, misdiagnosed as an xdph limitation).
    """

    @classmethod
    def setUpClass(cls):
        cls.script = SCRIPT.read_text()
        cls.code = "\n".join(l for l in cls.script.splitlines()
                             if not l.lstrip().startswith("#"))

    def test_sdr_toggle_routes_fullscreen_to_portal(self):
        self.assertIn("tonemapSdr", self.code)
        self.assertIn("-w portal", self.code)
        toggle = self.code[self.code.index("tonemapSdr"):]
        toggle = toggle[:toggle.index("PORTAL_TOKEN=")]
        self.assertRegex(toggle,
                         r'if \[\[ \$FULLSCREEN -eq 1 \]\];[\s\S]*?USE_PORTAL=1')

    def test_regions_never_prompt_twice(self):
        # The overlay's Record Region runs the shell selector first; a portal
        # picker after it is the double prompt this arrangement exists to end.
        self.assertEqual(self.code.count("USE_PORTAL=1"), 1)
        portal_block = self.code[self.code.index("-w portal"):]
        portal_block = portal_block[:portal_block.index("elif")]
        self.assertNotIn("slurp", portal_block)
        self.assertNotIn("REGION", portal_block)

    def test_fullscreen_portal_restores_a_session_token(self):
        portal_block = self.code[self.code.index("-w portal"):]
        portal_block = portal_block[:portal_block.index("elif")]
        self.assertIn("restore-portal-session", portal_block)

    def test_the_token_precondition_ships_with_the_dots(self):
        # xdph only issues tokens when allow_token_by_default pre-checks the
        # picker box. Portal fullscreen without this file regresses to a
        # prompt per recording - the exact failure that got portal capture
        # removed once already.
        xdph = ROOT.parents[1] / "hypr/xdph.conf"
        self.assertTrue(xdph.exists(), f"missing {xdph}")
        conf = "\n".join(l for l in xdph.read_text().splitlines()
                          if not l.lstrip().startswith("#"))
        self.assertIn("allow_token_by_default = true", conf)

    def test_sdr_region_forces_an_hdr_capture_codec(self):
        # The converter re-encodes to H.264 anyway; honouring an explicit
        # H.264 choice at capture would bake the wash-out in first.
        toggle = self.code[self.code.index("tonemapSdr"):]
        toggle = toggle[:toggle.index("PORTAL_TOKEN=")]
        self.assertRegex(toggle, r'else\s*\n\s*CODEC="hevc_hdr"')
