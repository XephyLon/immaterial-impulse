#!/usr/bin/env python3
"""scripts/sounds/scan-sound-themes.py reports what is on disk, and nothing else.

The resolver (services/sound_theme.js, tests/tst_sound_theme.qml) makes every
decision about a sound theme, so what has to hold here is narrow but load-bearing:
the roots come out in precedence order, a theme is reported once per root it
appears in, subdirectories are walked, paths are relative to the theme directory,
and nothing is filtered out on the scanner's own judgement.
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCANNER = os.path.join(REPO_ROOT, "scripts", "sounds", "scan-sound-themes.py")


def run(*roots, env=None):
    result = subprocess.run(
        [sys.executable, SCANNER, *roots],
        capture_output=True, text=True, check=True,
        env={**os.environ, **(env or {})},
    )
    return json.loads(result.stdout)


def write(path, content=""):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(content)


class SoundThemeScanTest(unittest.TestCase):
    def test_a_theme_is_reported_with_its_index_and_its_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = os.path.join(tmp, "sounds")
            write(os.path.join(root, "demo", "index.theme"),
                  "[Sound Theme]\nName=Demo\nDirectories=stereo\n")
            write(os.path.join(root, "demo", "stereo", "power-plug.oga"))
            scan = run(root)
            self.assertEqual(scan["roots"], [root])
            self.assertEqual(len(scan["entries"]), 1)
            entry = scan["entries"][0]
            self.assertEqual(entry["theme"], "demo")
            self.assertEqual(entry["dir"], os.path.join(root, "demo"))
            self.assertIn("Name=Demo", entry["index"])
            self.assertEqual(sorted(entry["files"]),
                             ["index.theme", os.path.join("stereo", "power-plug.oga")])

    def test_nested_context_directories_are_walked(self):
        # The Pop theme keeps every file under stereo/{alert,action,notification}
        # and nothing directly in stereo/. A non-recursive listing reports it as
        # an empty theme, which is exactly the silence this work removed.
        with tempfile.TemporaryDirectory() as tmp:
            root = os.path.join(tmp, "sounds")
            write(os.path.join(root, "Pop", "index.theme"),
                  "[Sound Theme]\nDirectories=stereo/alert stereo/notification\n")
            write(os.path.join(root, "Pop", "stereo", "alert", "alarm-clock-elapsed.oga"))
            write(os.path.join(root, "Pop", "stereo", "notification", "power-plug.oga"))
            files = run(root)["entries"][0]["files"]
            self.assertIn(os.path.join("stereo", "alert", "alarm-clock-elapsed.oga"), files)
            self.assertIn(os.path.join("stereo", "notification", "power-plug.oga"), files)

    def test_the_same_theme_in_two_roots_is_reported_once_per_root_in_order(self):
        with tempfile.TemporaryDirectory() as tmp:
            user = os.path.join(tmp, "user", "sounds")
            system = os.path.join(tmp, "system", "sounds")
            write(os.path.join(user, "ocean", "stereo", "power-plug.oga"))
            write(os.path.join(system, "ocean", "stereo", "power-unplug.oga"))
            entries = run(user, system)["entries"]
            self.assertEqual([e["dir"] for e in entries],
                             [os.path.join(user, "ocean"), os.path.join(system, "ocean")])

    def test_sidecars_and_unknown_extensions_are_reported_rather_than_judged(self):
        # ocean ships power-unplug.oga.license beside its sounds. Filtering it
        # here would move a decision out of the tested resolver; the resolver
        # ignores it by building exact <event><extension> names instead.
        with tempfile.TemporaryDirectory() as tmp:
            root = os.path.join(tmp, "sounds")
            write(os.path.join(root, "ocean", "stereo", "power-unplug.oga.license"))
            self.assertEqual(run(root)["entries"][0]["files"],
                             [os.path.join("stereo", "power-unplug.oga.license")])

    def test_a_missing_root_and_a_plain_file_are_both_skipped(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = os.path.join(tmp, "sounds")
            write(os.path.join(root, "loose.oga"))
            scan = run(os.path.join(tmp, "nope"), root)
            self.assertEqual(scan["entries"], [])
            self.assertEqual(len(scan["roots"]), 2)

    def test_the_default_roots_follow_xdg_and_put_the_user_first(self):
        env = {"XDG_DATA_HOME": "/x/data", "XDG_DATA_DIRS": "/a/share:/b/share", "HOME": "/x"}
        roots = run(env=env)["roots"]
        self.assertEqual(roots[0], "/x/data/sounds")
        self.assertIn("/a/share/sounds", roots)
        self.assertIn("/b/share/sounds", roots)
        self.assertEqual(roots[-1], "/usr/share/sounds")
        self.assertEqual(len(roots), len(set(roots)))


if __name__ == "__main__":
    unittest.main()
