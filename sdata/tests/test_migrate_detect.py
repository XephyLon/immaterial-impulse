#!/usr/bin/env python3
import subprocess, tempfile, unittest
from pathlib import Path

LIB = Path(__file__).resolve().parents[1] / "lib/migrate-existing.sh"


def run(installed_list):
    fake = f"printf '%s\\n' {installed_list}"
    return subprocess.run(
        ["bash", "-c", f'IMI_PKG_QUERY_CMD="{fake}" source "{LIB}"; has_legacy_packages && echo YES || echo NO'],
        capture_output=True, text=True,
    ).stdout.strip()


def run_config(config_dir):
    return subprocess.run(
        ["bash", "-c", f'IMI_LEGACY_CONFIG_DIR="{config_dir}" source "{LIB}"; has_legacy_config && echo YES || echo NO'],
        capture_output=True, text=True,
    ).stdout.strip()


class MigrateDetectTests(unittest.TestCase):
    def test_detects_legacy(self):
        self.assertEqual(run("illogical-impulse-basic illogical-impulse-audio foo"), "YES")

    def test_no_legacy(self):
        self.assertEqual(run("immaterial-impulse-basic bar"), "NO")

    def test_detects_legacy_config(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(run_config(d), "YES")

    def test_no_legacy_config(self):
        self.assertEqual(run_config("/nonexistent/illogical-impulse-xyzzy"), "NO")


if __name__ == "__main__":
    unittest.main()
