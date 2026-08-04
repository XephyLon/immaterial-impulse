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
import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/wallpapers/we_still.sh"
SERVICE = ROOT / "services/WallpaperEngine.qml"
CONFIG = ROOT / "modules/common/Config.qml"


class StillScriptTests(unittest.TestCase):
    def setUp(self):
        self.script = SCRIPT.read_text()

    def test_exists_and_is_executable(self):
        self.assertTrue(SCRIPT.exists())
        self.assertTrue(SCRIPT.stat().st_mode & 0o111, "not executable")

    def test_bash_syntax(self):
        proc = subprocess.run(["bash", "-n", str(SCRIPT)], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_renders_silently(self):
        # This runs on every scene switch. Without --silent the wallpaper's
        # audio plays for the few seconds the renderer is up, every time.
        #
        # Comments are stripped first: the flag is explained in a comment right
        # above the call, so asserting on the raw text passes even when the flag
        # itself is deleted. Mutation testing caught exactly that.
        code = "\n".join(l for l in self.script.splitlines()
                         if not l.lstrip().startswith("#"))
        self.assertIn("--silent", code)

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
