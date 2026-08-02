#!/usr/bin/env python3
"""The config-directory migration, one on-disk state per test.

`tests/test_config_dir_migration_runtime.py` covers the other half of this -
that the shell actually waits for the script before reading the directory. Here
the script is driven on its own, because its whole job is to decide what to do
from what is on disk and nothing else.
"""
import os, shutil, subprocess, tempfile, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATE = ROOT / "scripts/migrate-config-dir.sh"
SHIPPED_DEFAULT = ROOT / "defaults/config.json"

# The script's "I refused to touch anything, tell the user" status. Kept in
# step with DECLINED in the script and with the exit code Directories.qml
# translates into its warning.
DECLINED = 3


class ConfigMigrationTests(unittest.TestCase):
    def _run(self, home, expect=0):
        # Override XDG_CONFIG_HOME too: the script prefers it over $HOME/.config,
        # and CI runners export it (pointing at the runner's real home), which
        # silently no-ops the migration outside the sandbox.
        proc = subprocess.run(["bash", str(MIGRATE)],
                              env=dict(os.environ, HOME=str(home),
                                       XDG_CONFIG_HOME=str(home / ".config")),
                              capture_output=True, text=True)
        self.assertEqual(proc.returncode, expect,
                         f"unexpected exit {proc.returncode}\n{proc.stderr}")
        return proc

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

    def test_declines_loudly_when_new_has_a_real_config(self):
        # Both directories hold a config the user could plausibly have written.
        # Nothing may be touched - and the script has to say so, because the
        # silence is what let a whole settings directory go missing unnoticed.
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            old = home / ".config/illogical-impulse"
            old.mkdir(parents=True)
            (old / "config.json").write_text('{"old": 1}')
            new = home / ".config/immaterial-impulse"
            new.mkdir(parents=True)
            (new / "config.json").write_text('{"keep": 1}')
            proc = self._run(home, expect=DECLINED)
            self.assertEqual((new / "config.json").read_text(), '{"keep": 1}')
            self.assertTrue(old.exists())
            self.assertIn("NOT migrating", proc.stderr)
            self.assertIn(str(old), proc.stderr)

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

    # --- the seeded default, which is what actually blocked this in the field ---

    def test_the_installers_seeded_default_does_not_block_the_migration(self):
        # seed_default_config (sdata/subcmd-install/3.files.sh) copies
        # defaults/config.json in verbatim on any install that finds no
        # config.json - which is every arriving upstream user, because theirs is
        # still under the old name. A guard that only asks "does a config.json
        # exist" therefore skipped the migration for exactly the population it
        # was written for, with no race needed.
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            old = home / ".config/illogical-impulse"
            (old / "presets").mkdir(parents=True)
            (old / "config.json").write_text('{"osd": {"timeout": 4321}}')
            (old / "presets" / "p.json").write_text("{}")
            new = home / ".config/immaterial-impulse"
            new.mkdir(parents=True)
            (new / "installed_true").write_text("")
            shutil.copyfile(SHIPPED_DEFAULT, new / "config.json")
            self._run(home)
            self.assertEqual((new / "config.json").read_text(),
                             '{"osd": {"timeout": 4321}}')
            self.assertTrue((new / "presets" / "p.json").is_file())
            self.assertTrue((new / "installed_true").is_file())
            self.assertTrue(old.exists())

    def test_a_seeded_default_with_one_edit_is_the_users_and_is_kept(self):
        # The whole point of comparing bytes rather than shape: one changed
        # setting makes it the user's file, and this must fall on the "don't
        # touch it" side of the line.
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            old = home / ".config/illogical-impulse"
            old.mkdir(parents=True)
            (old / "config.json").write_text('{"old": 1}')
            new = home / ".config/immaterial-impulse"
            new.mkdir(parents=True)
            edited = SHIPPED_DEFAULT.read_text().replace(
                '"panelFamily": "imi"', '"panelFamily": "custom"', 1)
            self.assertNotEqual(edited, SHIPPED_DEFAULT.read_text(),
                                "the edit this test relies on did not apply")
            (new / "config.json").write_text(edited)
            self._run(home, expect=DECLINED)
            self.assertEqual((new / "config.json").read_text(), edited)

    def test_declines_when_the_shipped_defaults_are_missing(self):
        # No baseline to compare against means no way to tell a seeded default
        # from the user's own file. Do nothing and say so, rather than guess.
        with tempfile.TemporaryDirectory() as d, tempfile.TemporaryDirectory() as shell:
            home = Path(d)
            old = home / ".config/illogical-impulse"
            old.mkdir(parents=True)
            (old / "config.json").write_text('{"old": 1}')
            new = home / ".config/immaterial-impulse"
            new.mkdir(parents=True)
            (new / "config.json").write_text('{"whatever": 1}')

            # A copy of the script with no defaults/ next to it.
            detached = Path(shell) / "scripts"
            detached.mkdir()
            shutil.copyfile(MIGRATE, detached / "migrate-config-dir.sh")
            proc = subprocess.run(
                ["bash", str(detached / "migrate-config-dir.sh")],
                env=dict(os.environ, HOME=str(home),
                         XDG_CONFIG_HOME=str(home / ".config")),
                capture_output=True, text=True)
            self.assertEqual(proc.returncode, DECLINED, proc.stderr)
            self.assertIn("shipped defaults", proc.stderr)
            self.assertEqual((new / "config.json").read_text(), '{"whatever": 1}')

    # --- idempotency, now that a merge leaves both directories in place ---

    def test_a_second_run_after_a_merge_is_a_silent_noop(self):
        # A merge deliberately keeps the old directory as a backup, so the next
        # launch sees "both dirs, both with a config.json" - the exact shape
        # that has to be declined. Without a record of the merge it would nag
        # forever, or re-copy files the user deleted in between.
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            old = home / ".config/illogical-impulse"
            old.mkdir(parents=True)
            (old / "config.json").write_text('{"mine": 1}')
            (old / "gone.json").write_text("{}")
            new = home / ".config/immaterial-impulse"
            new.mkdir(parents=True)
            shutil.copyfile(SHIPPED_DEFAULT, new / "config.json")
            self._run(home)
            self.assertEqual((new / "config.json").read_text(), '{"mine": 1}')

            (new / "config.json").write_text('{"mine": 2}')   # the user edits it
            (new / "gone.json").unlink()                       # and deletes a file
            proc = self._run(home)
            self.assertEqual((new / "config.json").read_text(), '{"mine": 2}')
            self.assertFalse((new / "gone.json").exists())
            self.assertEqual(proc.stderr, "")

    def test_a_new_dir_appearing_mid_rename_does_not_nest_the_old_one(self):
        # Other singletons create files under the new directory at startup, so
        # the rename can lose to a mkdir. `mv old new` would then move the old
        # directory *inside* the new one; `mv -T` refuses and the merge path
        # takes over.
        with tempfile.TemporaryDirectory() as d:
            home = Path(d)
            old = home / ".config/illogical-impulse"
            old.mkdir(parents=True)
            (old / "config.json").write_text('{"mine": 1}')
            new = home / ".config/immaterial-impulse"
            new.mkdir(parents=True)
            (new / "plugin-state.json").write_text("{}")
            self._run(home)
            self.assertFalse((new / "illogical-impulse").exists())
            self.assertEqual((new / "config.json").read_text(), '{"mine": 1}')
            self.assertTrue((new / "plugin-state.json").is_file())


if __name__ == "__main__":
    unittest.main()
