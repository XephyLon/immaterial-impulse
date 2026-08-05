#!/usr/bin/env python3
"""SDR delivery for HDR recordings: opt-in, probe-gated, atomic.

record.sh stores real HDR10 on an HDR display - correct in HDR-aware players,
washed out in everything that does not tonemap (VLC defaults, Discord,
browsers). tonemap-sdr.sh is the delivery half: invoked by gsr-saved.sh when a
save lands, it acts only when the user opted in AND the file is actually HDR,
and replaces the file only by renaming a fully-written temporary.

Behavioural tests drive the real script against a real (tiny) HDR10 clip with
a sandboxed XDG_CONFIG_HOME; the failure-path test stubs ffmpeg/ffprobe via
PATH. notify-send is stubbed throughout.
"""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/videos/tonemap-sdr.sh"
SAVED_HOOK = (ROOT / "scripts/videos/gsr-saved.sh").read_text()

HAVE_FFMPEG = bool(shutil.which("ffmpeg") and shutil.which("ffprobe"))


def encoders():
    if not HAVE_FFMPEG:
        return ""
    return subprocess.run(["ffmpeg", "-hide_banner", "-encoders"],
                          capture_output=True, text=True).stdout


def make_clip(path, hdr):
    # x265 writes the VUI from its own params and ignores ffmpeg's -color_*
    # flags, so the HDR tagging must go through -x265-params or the fixture
    # probes as "unknown" - which it did on this test's first run.
    color = (["-pix_fmt", "yuv420p10le", "-x265-params",
              "colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc"]
             if hdr else ["-pix_fmt", "yuv420p"])
    codec = "libx265" if hdr else "libx264"
    subprocess.run(
        ["ffmpeg", "-y", "-v", "error", "-f", "lavfi",
         "-i", "testsrc2=s=64x64:d=0.3:r=10", "-c:v", codec, *color, str(path)],
        capture_output=True, check=True)


def transfer_of(path):
    return subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=color_transfer", "-of", "csv=p=0", str(path)],
        capture_output=True, text=True).stdout.strip()


class SandboxedRun:
    def __init__(self, enabled, stub_dir=None):
        self.tmp = Path(tempfile.mkdtemp())
        conf = self.tmp / "config/immaterial-impulse"
        conf.mkdir(parents=True)
        (conf / "config.json").write_text(
            '{"screenRecord": {"tonemapSdr": %s}}' % ("true" if enabled else "false"))
        stubs = self.tmp / "bin"
        stubs.mkdir()
        (stubs / "notify-send").write_text("#!/usr/bin/env bash\nexit 0\n")
        (stubs / "notify-send").chmod(0o755)
        path = f"{stubs}:{os.environ['PATH']}"
        if stub_dir:
            path = f"{stub_dir}:{path}"
        self.env = {**os.environ, "XDG_CONFIG_HOME": str(self.tmp / "config"),
                    "PATH": path}

    def run(self, target):
        return subprocess.run(["bash", str(SCRIPT), str(target)],
                              env=self.env, capture_output=True, text=True)


@unittest.skipUnless(HAVE_FFMPEG and "libx265" in encoders(),
                     "ffmpeg with libx265 required to build the HDR fixture")
class TonemapBehaviourTests(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir, True)
        self.clip = self.dir / "rec.mp4"

    def test_hdr_clip_becomes_bt709_when_enabled(self):
        make_clip(self.clip, hdr=True)
        self.assertEqual(transfer_of(self.clip), "smpte2084", "fixture is not HDR")
        proc = SandboxedRun(enabled=True).run(self.clip)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(transfer_of(self.clip), "bt709",
                         "file was not tonemapped to SDR")

    def test_toggle_off_leaves_the_file_alone(self):
        make_clip(self.clip, hdr=True)
        before = self.clip.stat().st_mtime_ns
        SandboxedRun(enabled=False).run(self.clip)
        self.assertEqual(self.clip.stat().st_mtime_ns, before,
                         "acted despite the toggle being off")

    def test_sdr_input_is_never_reencoded(self):
        # Double-tonemapping an SDR file darkens it; the probe is the guard.
        make_clip(self.clip, hdr=False)
        before = self.clip.stat().st_mtime_ns
        proc = SandboxedRun(enabled=True).run(self.clip)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(self.clip.stat().st_mtime_ns, before,
                         "re-encoded an already-SDR file")

    def test_a_failed_encode_keeps_the_hdr_original(self):
        # Losing the only copy of a recording to a failed conversion is the
        # one outcome strictly worse than a washed-out embed. Stub ffprobe to
        # claim HDR and ffmpeg to fail; the original must survive, and the
        # temporary must not linger.
        make_clip(self.clip, hdr=True)
        original = self.clip.read_bytes()
        stubs = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, stubs, True)
        # The trailing comma reproduces what a real gpu-screen-recorder file's
        # side data does to CSV probing - the shape that made the first version
        # of the script silently classify every real HDR recording as SDR. If
        # parsing regresses to a strict match, this stub makes the script skip,
        # ffmpeg never runs, and the "failed encode" assertions below fail.
        (stubs / "ffprobe").write_text("#!/usr/bin/env bash\necho 'smpte2084,'\n")
        (stubs / "ffmpeg").write_text("#!/usr/bin/env bash\nexit 1\n")
        for s in ("ffprobe", "ffmpeg"):
            (stubs / s).chmod(0o755)
        proc = SandboxedRun(enabled=True, stub_dir=stubs).run(self.clip)
        self.assertNotEqual(proc.returncode, 0)
        self.assertEqual(self.clip.read_bytes(), original, "original was damaged")
        self.assertEqual(list(self.dir.glob("*sdr-tmp*")), [], "temporary left behind")

    def test_a_missing_file_is_a_quiet_noop(self):
        proc = SandboxedRun(enabled=True).run(self.dir / "gone.mp4")
        self.assertEqual(proc.returncode, 0)


class HookWiringTests(unittest.TestCase):
    def test_saves_and_replays_trigger_it_screenshots_do_not(self):
        # Replays never pass through record.sh, which is why the delivery hangs
        # off the saved-hook: a save landing is the observed event.
        hook = "\n".join(l for l in SAVED_HOOK.splitlines()
                         if not l.lstrip().startswith("#"))
        self.assertIn("regular|replay", hook)
        self.assertIn("tonemap-sdr.sh", hook)

    def test_the_hook_detaches_the_reencode(self):
        # The hook runs inside gsr's process context; a re-encode that blocks
        # or dies with it loses the conversion on every recorder exit.
        self.assertRegex(SAVED_HOOK, r"setsid -f .*tonemap-sdr\.sh")

    def test_libplacebo_detection_survives_pipefail(self):
        # `ffmpeg -filters | grep -q` under `set -o pipefail` reads as failed:
        # grep -q exits at the first match, ffmpeg takes SIGPIPE, and the
        # pipeline's status is ffmpeg's 141 - so libplacebo silently never got
        # selected and every tonemap ran on the CPU. 13s instead of 5 on the
        # same clip, with nothing logged. The detection must consume the whole
        # stream (capture to a variable), never early-exit it.
        script = SCRIPT.read_text()
        self.assertNotIn("| grep -q libplacebo", script)
        self.assertIn('filters="$(', script)

    def test_the_encoder_ladder_is_width_aware(self):
        # NVENC's H.264 tops out at 4096px and rejects wider frames with a
        # misleading "No capable devices found" - at 5120x1440 the h264 rung
        # can never succeed, so wider clips go straight to HEVC.
        script = SCRIPT.read_text()
        self.assertIn("width > 4096", script)
        self.assertRegex(script, r"LADDER=\(hevc_nvenc")
        self.assertRegex(script, r"LADDER=\(h264_nvenc")

    def test_the_temporary_keeps_a_video_extension(self):
        # ffmpeg infers the muxer from the output extension; a bare ".tmp"
        # fails. Same trap that shipped in we_still.sh once already.
        script = SCRIPT.read_text()
        import re
        m = re.search(r'tmp="\$\{FILE%\.mp4\}([^"]+)"', script)
        self.assertIsNotNone(m, "no temporary assignment found")
        self.assertTrue(m.group(1).endswith(".mp4"),
                        f"temporary {m.group(1)!r} must end in .mp4")


if __name__ == "__main__":
    unittest.main()
