#!/usr/bin/env python3
import os, subprocess, tempfile, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATE = ROOT / "scripts/migrate-config-dir.sh"


class ConfigMigrationTests(unittest.TestCase):
    def _run(self, home):
        # Override XDG_CONFIG_HOME too: the script prefers it over $HOME/.config,
        # and CI runners export it (pointing at the runner's real home), which
        # silently no-ops the migration outside the sandbox.
        subprocess.run(["bash", str(MIGRATE)],
                       env=dict(os.environ, HOME=str(home),
                                XDG_CONFIG_HOME=str(home / ".config")),
                       check=True)

    def test_moves_old_dir_when_new_absent(self):
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            old = home / ".config/illogical-impulse"
            old.mkdir(parents=True)
            (old / "config.json").write_text('{"marker": 1}')
            self._run(home)
            new = home / ".config/immaterial-impulse"
            self.assertTrue(new.is_dir())
            self.assertEqual((new / "config.json").read_text(), '{"marker": 1}')
            self.assertFalse(old.exists())

    def test_noop_when_new_has_real_config(self):
        # New dir already has a genuine config.json -> never clobber it.
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            old = home / ".config/illogical-impulse"
            old.mkdir(parents=True)
            (old / "config.json").write_text('{"old": 1}')
            new = home / ".config/immaterial-impulse"
            new.mkdir(parents=True)
            (new / "config.json").write_text('{"keep": 1}')
            self._run(home)
            self.assertEqual((new / "config.json").read_text(), '{"keep": 1}')
            self.assertTrue(old.exists())

    def test_migrates_into_precreated_new_dir(self):
        # The installer pre-creates ~/.config/immaterial-impulse (installed_true
        # etc.) but no config.json yet, while the user's real settings are still
        # under illogical-impulse. Migrate the user data in, keep installer files,
        # leave the old dir as a backup. (Regression: this used to be skipped and
        # the user got a default config.)
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            old = home / ".config/illogical-impulse"
            (old / "actions").mkdir(parents=True)
            (old / "config.json").write_text('{"bar": "mine"}')
            (old / "actions" / "a.json").write_text("{}")
            new = home / ".config/immaterial-impulse"
            new.mkdir(parents=True)
            (new / "installed_true").write_text("")
            self._run(home)
            self.assertEqual((new / "config.json").read_text(), '{"bar": "mine"}')
            self.assertTrue((new / "actions" / "a.json").is_file())
            self.assertTrue((new / "installed_true").is_file())  # installer file kept
            self.assertTrue(old.exists())                        # old kept as backup

    def test_noop_when_nothing_to_migrate(self):
        with tempfile.TemporaryDirectory() as d:
            self._run(Path(d))  # must exit 0, create nothing


if __name__ == "__main__":
    unittest.main()
