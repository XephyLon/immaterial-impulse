#!/usr/bin/env python3
import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCANNER = ROOT / "scripts/wallpapers/wallpaper_engine.py"


def load_scanner():
    spec = importlib.util.spec_from_file_location("wallpaper_engine_scanner", SCANNER)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader
    spec.loader.exec_module(module)
    return module


class WallpaperEngineTests(unittest.TestCase):
    def test_scanner_reads_metadata_and_skips_malformed_projects(self):
        scanner = load_scanner()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            valid = root / "123"
            valid.mkdir()
            (valid / "preview.jpg").write_bytes(b"preview")
            (valid / "project.json").write_text(json.dumps({
                "title": "A live wallpaper",
                "type": "scene",
                "preview": "preview.jpg",
                "tags": ["Relaxing"],
            }))
            invalid = root / "456"
            invalid.mkdir()
            (invalid / "project.json").write_text("not json")

            projects = scanner.scan(str(root))

            self.assertEqual(len(projects), 1)
            self.assertEqual(projects[0]["id"], "123")
            self.assertEqual(projects[0]["title"], "A live wallpaper")
            self.assertEqual(projects[0]["preview"], str(valid / "preview.jpg"))

    def test_scanner_confines_preview_to_the_project_directory(self):
        scanner = load_scanner()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            secret = root / "secret.jpg"
            secret.write_bytes(b"not for the picker")
            project = root / "789"
            project.mkdir()
            # An absolute path and a "../" escape must both be rejected: only a
            # preview inside the project directory is trusted.
            (project / "project.json").write_text(json.dumps({
                "title": "Escapes its directory",
                "preview": "../secret.jpg",
            }))

            projects = scanner.scan(str(root))

            self.assertEqual(len(projects), 1)
            self.assertEqual(projects[0]["preview"], "")

    def test_runner_checks_for_its_runtime_dependencies(self):
        runner = (ROOT / "scripts/wallpapers/wallpaper-engine.sh").read_text()
        self.assertIn("for tool in linux-wallpaperengine hyprctl jq", runner)

    def test_runner_uses_one_bounded_runtime_for_all_monitors(self):
        runner = (ROOT / "scripts/wallpapers/wallpaper-engine.sh").read_text()
        self.assertIn('mapfile -t monitors', runner)
        self.assertIn('args+=(--screen-root "$monitor" --scaling "$scaling")', runner)
        self.assertEqual(runner.count('setsid linux-wallpaperengine'), 1)
        self.assertIn("pkill -f '(^|/)[l]inux-wallpaperengine( |$)'", runner)
        self.assertNotIn("eval ", runner)

    def test_runner_builds_a_single_multi_monitor_command(self):
        runner = ROOT / "scripts/wallpapers/wallpaper-engine.sh"
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            bin_dir = temp / "bin"
            project = temp / "project"
            bin_dir.mkdir()
            project.mkdir()
            (bin_dir / "hyprctl").write_text("#!/bin/sh\nprintf '[{\"name\":\"DP-1\"},{\"name\":\"HDMI-A-1\"}]\\n'\n")
            (bin_dir / "jq").write_text("#!/bin/sh\nprintf 'DP-1\\nHDMI-A-1\\n'\n")
            (bin_dir / "pkill").write_text("#!/bin/sh\nexit 0\n")
            (bin_dir / "linux-wallpaperengine").write_text("#!/bin/sh\nexit 0\n")
            (bin_dir / "setsid").write_text(
                "#!/bin/sh\nprintf '%s\\n' \"$*\" > \"$TEST_COMMAND_FILE\"\n"
            )
            for executable in bin_dir.iterdir():
                executable.chmod(0o755)
            command_file = temp / "command"
            environment = os.environ | {
                "PATH": f"{bin_dir}:{os.environ['PATH']}",
                "XDG_STATE_HOME": str(temp / "state"),
                "XDG_CONFIG_HOME": str(temp / "config"),
                "TEST_COMMAND_FILE": str(command_file),
            }
            subprocess.run(
                [str(runner), "apply", str(project), "60", "fit", "true"],
                check=True,
                env=environment,
            )
            command = command_file.read_text()
            self.assertEqual(command.count("--screen-root"), 2)
            self.assertIn("--fps 60", command)
            self.assertIn("--silent", command)
            self.assertIn(str(project), command)

    def test_selector_exposes_engine_source_and_managed_controls(self):
        selector = (ROOT / "modules/ii/wallpaperSelector/WallpaperSelectorContent.qml").read_text()
        service = (ROOT / "services/WallpaperEngine.qml").read_text()
        self.assertIn('value: "wallpaperEngine"', selector)
        self.assertIn("WallpaperEngineGrid", selector)
        self.assertIn("WallpaperEngine.refresh()", selector)
        self.assertIn("WallpaperEngine.stop()", selector)
        self.assertIn("Wallpapers.applyColorsOnly(project.preview", service)
        self.assertIn("Config.options.wallpaperSelector.wallpaperEngine.activeProject", service)


if __name__ == "__main__":
    unittest.main()
