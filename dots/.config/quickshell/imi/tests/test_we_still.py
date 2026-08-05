#!/usr/bin/env python3
"""Full-resolution Wallpaper Engine stills.

The SDDM greeter cannot run Wallpaper Engine, so it needs a static image of the
active project. The only image a project ships is the Steam Workshop preview - a
thumbnail, often square and around 1000px - which on a wide display was cropped
to a narrow band and upscaled several times over (#113; measured at 910x910 on
5120x1440).

scripts/wallpapers/we_still.sh renders the project at the display's own size.
These pin the parts that fail silently: the audio flag, the process-group
teardown, and the recompression's output extension.
"""
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/wallpapers/we_still.sh"
SERVICE = ROOT / "services/WallpaperEngine.qml"
CONFIG = ROOT / "modules/common/Config.qml"


class StillScriptTests(unittest.TestCase):
    def setUp(self):
        self.script = SCRIPT.read_text()
        # Comments are stripped for anything asserting a flag is *used*: every
        # flag here is explained in a comment right above the call, so matching
        # the raw text passes even when the flag itself is deleted. Mutation
        # testing caught exactly that on --silent.
        self.code = "\n".join(l for l in self.script.splitlines()
                              if not l.lstrip().startswith("#"))

    def test_exists_and_is_executable(self):
        self.assertTrue(SCRIPT.exists())
        self.assertTrue(SCRIPT.stat().st_mode & 0o111, "not executable")

    def test_bash_syntax(self):
        proc = subprocess.run(["bash", "-n", str(SCRIPT)], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_renders_silently(self):
        # Nothing is visible on screen while this runs, so a burst of the
        # wallpaper's audio would be the only sign it happened at all.
        self.assertIn("--silent", self.code)

    def test_renders_beneath_the_shell_rather_than_in_a_window(self):
        # --window opens an ordinary floating window: it takes focus and covers
        # the screen for the seconds the render takes. --screen-root binds a
        # layer-shell surface and --layer background puts it under the shell's
        # own (opaque) wallpaper, so the render is not visible and does not
        # touch focus. Losing either flag puts the window back.
        self.assertIn("--screen-root", self.code)
        self.assertIn("--layer background", self.code)

    def test_does_not_pause_behind_a_fullscreen_window(self):
        # A background pauses by default while a fullscreen window is active.
        # Paused, it never reaches the screenshot frame - so a render started
        # over a fullscreen app would sit until the timeout and produce
        # nothing. Only matters in layer-shell mode, which is now the default.
        self.assertIn("--no-fullscreen-pause", self.code)

    def test_window_mode_survives_as_a_fallback(self):
        # Not every caller has a named output: a non-Hyprland compositor, or an
        # explicit geometry argument asking for a size that is not a monitor's.
        self.assertIn("--window", self.code)

    def test_kills_the_process_group_not_the_pid(self):
        # --screenshot does not exit once it has written the file, so the caller
        # has to stop it - and the renderer spawns children, so a bare `kill`
        # leaves them holding the GPU.
        self.assertIn("setsid", self.script)
        self.assertRegex(self.script, r'kill -TERM -"\$pgid"')
        self.assertRegex(self.script, r'kill -KILL -"\$pgid"')

    def test_waits_for_the_file_rather_than_a_fixed_sleep(self):
        self.assertRegex(self.script, r'\[\[ -s "\$raw" \]\] && break')

    def test_recompression_target_keeps_a_jpg_extension(self):
        # ffmpeg picks its encoder from the output extension. A bare ".tmp"
        # makes it fail, and stderr is discarded - so the uncompressed ~8 MiB
        # frame is left in place and the script still reports success. This was
        # a real bug in the first version of this script, found only by
        # measuring the output size.
        m = re.search(r'tmp_out="([^"]+)"', self.script)
        self.assertIsNotNone(m, "no tmp_out assignment found")
        self.assertTrue(m.group(1).endswith(".jpg"),
                        f"recompression target {m.group(1)!r} must end in .jpg")

    def test_rejects_a_non_numeric_project_id(self):
        # The id is interpolated into a command line.
        proc = subprocess.run(["bash", str(SCRIPT), "../../etc/passwd", "/tmp/x.jpg"],
                              capture_output=True, text=True)
        self.assertEqual(proc.returncode, 2, proc.stdout + proc.stderr)

    def test_missing_renderer_is_a_distinct_exit_code(self):
        # A machine without the Wallpaper Engine extra is the common case, not
        # an error: the service logs it and the greeter keeps the preview.
        self.assertIn("exit 3", self.script)


def _make_jpeg(path, width, height):
    """A real JPEG of a known size - the cache check reads the file's geometry."""
    subprocess.run(
        ["ffmpeg", "-y", "-f", "lavfi", "-i", f"color=c=red:s={width}x{height}",
         "-frames:v", "1", str(path)],
        capture_output=True, check=True)


@unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"),
                     "ffmpeg/ffprobe required to build and measure the fixture")
class StillCacheTests(unittest.TestCase):
    """A cached still is reused instead of re-rendered.

    Every one of these runs the real script. They reach the cache branch and
    return before the renderer is ever consulted, so they pass on a machine
    with no linux-wallpaperengine - which is what CI is.
    """

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.out = Path(self.tmp) / "3097818836.jpg"

        # A stub renderer shadowing the real one. Whether it ran is the actual
        # question these tests ask - "is linux-wallpaperengine installed" is
        # not, and answering it by emptying PATH silently fails on a developer
        # machine where the real binary sits in /usr/bin and gets found anyway.
        # It renders nothing, so a cache miss ends in the no-frame path.
        self.stub_dir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.stub_dir, True)
        self.marker = Path(self.stub_dir) / "ran"
        stub = Path(self.stub_dir) / "linux-wallpaperengine"
        stub.write_text(f'#!/usr/bin/env bash\ntouch {self.marker}\nexit 0\n')
        stub.chmod(0o755)

    def run_script(self, geometry="800x600", env=None):
        return subprocess.run(
            ["bash", str(SCRIPT), "3097818836", str(self.out), geometry],
            capture_output=True, text=True,
            # A miss waits for a frame the stub never writes, so cap the wait.
            env={**os.environ, **(env or {}),
                 "PATH": f"{self.stub_dir}:{os.environ['PATH']}",
                 "WE_STILL_TIMEOUT": "1"})

    def rendered(self):
        return self.marker.exists()

    def test_a_matching_still_is_reused(self):
        # The whole point: switching back to a scene seen a minute ago must not
        # spend several seconds of GPU reproducing a file already on disk.
        _make_jpeg(self.out, 800, 600)
        before = self.out.stat().st_mtime_ns
        proc = self.run_script()
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertFalse(self.rendered(), "renderer ran despite a usable cache")
        self.assertEqual(self.out.stat().st_mtime_ns, before, "still was rewritten")
        self.assertEqual(proc.stdout.strip(), str(self.out))

    def test_reuse_does_not_need_the_renderer_installed(self):
        # The cache check sits ahead of the availability guard on purpose: a
        # good still on disk must not be thrown away by a machine that has
        # since dropped the Wallpaper Engine extra.
        #
        # Asserted as an ordering rather than by running with the renderer
        # removed: it lives in /usr/bin, so any PATH narrow enough to hide it
        # also hides bash and ffprobe, and the test then passes or fails for
        # reasons that have nothing to do with the branch under test.
        script = SCRIPT.read_text()
        self.assertLess(script.index("WE_STILL_FORCE"),
                        script.index("linux-wallpaperengine not installed"),
                        "availability guard runs before the cache check")

    def test_a_still_at_the_wrong_size_is_not_reused(self):
        # A still cached at the old resolution is precisely the upscaled
        # thumbnail this script exists to avoid, so a monitor change has to
        # invalidate it.
        _make_jpeg(self.out, 640, 480)
        self.run_script(geometry="800x600")
        self.assertTrue(self.rendered(), "stale-size still was accepted")

    def test_force_bypasses_the_cache(self):
        # For a project whose content was updated in the Workshop, where the
        # size still matches but the render no longer does.
        _make_jpeg(self.out, 800, 600)
        self.run_script(env={"WE_STILL_FORCE": "1"})
        self.assertTrue(self.rendered(), "WE_STILL_FORCE did not force a render")

    def test_an_empty_still_is_not_reused(self):
        # A truncated write must not be mistaken for a cache hit.
        self.out.write_bytes(b"")
        self.run_script()
        self.assertTrue(self.rendered(), "empty still was accepted as a cache hit")


class ServiceWiringTests(unittest.TestCase):
    def setUp(self):
        self.service = SERVICE.read_text()

    def test_only_scenes_are_rendered(self):
        # A video is a plain file the greeter can play or sample, and web falls
        # back to the static wallpaper - neither needs a multi-second render.
        self.assertRegex(self.service, r'\(project\.type \?\? ""\) !== "scene"')

    def test_renders_are_queued_not_concurrent(self):
        # The renderer holds a GPU context; two at once on a wallpaper spam is
        # the failure this avoids.
        self.assertIn("stillProcess.pendingProject = project", self.service)

    def test_still_is_recorded_only_on_success(self):
        body = self.service[self.service.index("id: stillProcess"):]
        self.assertIn("if (exitCode === 0", body)
        self.assertIn("activeStill = stillProcess.target", body)

    def test_stop_clears_the_still(self):
        # A still naming a project that is no longer active is exactly the
        # stale-field failure #103 was about.
        stop = self.service[self.service.index("function stop()"):]
        stop = stop[:stop.index("\n    }")]
        self.assertIn("activeStill = \"\"", stop)

    def test_config_declares_the_field(self):
        self.assertIn("property string activeStill:", CONFIG.read_text())


if __name__ == "__main__":
    unittest.main()
