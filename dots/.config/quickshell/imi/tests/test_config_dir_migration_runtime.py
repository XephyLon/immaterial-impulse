#!/usr/bin/env python3
"""The config-directory migration against a real, running shell.

`test_config_migration.py` drives `scripts/migrate-config-dir.sh` on its own.
It cannot see the failure this module exists for: the script used to be fired
with `Quickshell.execDetached`, which returns immediately, so it ran
concurrently with `Config`'s asynchronous `FileView` load. When `Config` got
there first it wrote a default `config.json` into the destination, the script's
guard then saw that file, and the whole directory migration was skipped - a
user arriving from upstream silently kept none of their settings.

Nothing about that is observable from the script, and "it happened to win every
probe run" is not a fix. So the interleaving is forced instead: `IMI_MIGRATE_DELAY`
holds the script open for seconds, which is long enough that a `Config` load
racing it wins every single time. `ConfigDirMigrationRuntimeTest.qml` samples
`Directories.configDirReady` at the instant `Config.ready` turns true and fails
if the migration had not already finished.

Brings its own headless weston, so it needs no display of its own - a real
`qs` process needs a compositor even with no windows on screen, and running it
on the caller's session is not worth the risk for a test that migrates config
directories. Skips when weston or qs is missing, as in CI.
"""

import json
import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "ConfigDirMigrationRuntimeTest.qml"
SHIPPED_DEFAULT = ROOT / "defaults/config.json"
SOCKET = "wayland-imi-config-dir-migration"

# Long enough that a Config load racing the script wins by seconds, short
# enough not to dominate the suite. The gate is a strict happens-before, so any
# value proves the same thing; this one just makes a regression unmissable.
MIGRATE_DELAY = "3"

# A config as it arrives from upstream: the shell's own key for a plainly
# user-set value, plus two things only the in-Config upstream-key migration
# knows how to convert. Both migrations have to happen on the same launch, in
# that order, or the second one has nothing to read.
UPSTREAM_CONFIG = json.dumps({
    "panelFamily": "ii",
    "osd": {"timeout": 1700},
    "bar": {"floatStyleShadow": True, "cornerStyle": 1},
}, indent=2)

EXPECT_MIGRATED = {
    # The directory move: a key the user set, under the new directory name.
    "osd.timeout": 1700,
    # The upstream-key migration, on the same launch: a stale value rewritten,
    # and a renamed key reconstructed from what was on screen upstream.
    "panelFamily": "imi",
    "bar.shadow": True,
    "migratedUpstreamSchema": True,
}


def _stop(proc):
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()


def _runtime_available():
    return shutil.which("qs") is not None and shutil.which("weston") is not None


@unittest.skipUnless(_runtime_available(), "needs qs and weston on PATH")
class ConfigDirMigrationRuntimeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.env = dict(os.environ)
        cls.env.setdefault("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
        cls.env["WAYLAND_DISPLAY"] = SOCKET
        cls.env.pop("DISPLAY", None)
        cls.weston = subprocess.Popen(
            ["weston", "--backend=headless", "--renderer=pixman",
             f"--socket={SOCKET}", "--width=800", "--height=600"],
            env=cls.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        socket_path = Path(cls.env["XDG_RUNTIME_DIR"]) / SOCKET
        deadline = time.monotonic() + 15
        while not socket_path.exists() and time.monotonic() < deadline:
            time.sleep(0.2)
        if not socket_path.exists():
            _stop(cls.weston)
            raise AssertionError("headless weston never came up")

        # This box's headless EGL has no driver, so force software rendering.
        cls.env["LIBGL_ALWAYS_SOFTWARE"] = "1"
        cls.env["QT_QUICK_BACKEND"] = "software"

    @classmethod
    def tearDownClass(cls):
        _stop(cls.weston)

    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-config-dir-runtime-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        self.config_home = self.home / "config"
        self.old = self.config_home / "illogical-impulse"
        self.new = self.config_home / "immaterial-impulse"

    def seed_old(self, text=UPSTREAM_CONFIG):
        self.old.mkdir(parents=True)
        (self.old / "config.json").write_text(text)
        (self.old / "actions").mkdir()
        (self.old / "actions" / "mine.json").write_text('{"a": 1}')

    def launch(self, expect=None, delay=None, mode="gated"):
        env = dict(self.env)
        env["XDG_CONFIG_HOME"] = str(self.config_home)
        env["XDG_STATE_HOME"] = str(self.home / "state")
        env["XDG_CACHE_HOME"] = str(self.home / "cache")
        # The migration archives the old config dir under here before removing
        # it; unset, the tarballs would land in the caller's real ~/.local/share.
        env["XDG_DATA_HOME"] = str(self.home / "data")
        env["CONFIGDIR_EXPECT"] = json.dumps(expect or {})
        env["CONFIGDIR_MODE"] = mode
        if delay is not None:
            env["IMI_MIGRATE_DELAY"] = delay
        proc = subprocess.run(["qs", "-p", str(HARNESS)], cwd=str(ROOT), env=env,
                              capture_output=True, text=True, timeout=240)
        output = proc.stdout + proc.stderr
        failed = [line for line in output.splitlines() if "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output}")
        self.assertIn("[ConfigDirMigration] failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")
        return output

    def stored_config(self):
        return json.loads((self.new / "config.json").read_text())

    def test_a_slow_migration_still_finishes_before_config_reads(self):
        """The race, forced. Three seconds of migration is three seconds in
        which the old code's Config load would have written its defaults into
        the destination and killed the migration outright."""
        self.seed_old()
        self.launch(expect=EXPECT_MIGRATED, delay=MIGRATE_DELAY)

        stored = self.stored_config()
        self.assertEqual(stored["osd"]["timeout"], 1700)
        self.assertEqual(stored["panelFamily"], "imi")
        self.assertTrue(stored["bar"]["shadow"])
        self.assertTrue(stored["migratedUpstreamSchema"])
        self.assertTrue((self.new / "actions" / "mine.json").is_file())
        self.assertFalse(self.old.exists(), "a clean rename should consume the old dir")

    def test_the_installers_seeded_default_does_not_block_the_migration(self):
        """The same loss with no race in it at all: seed_default_config puts
        defaults/config.json in the destination during install, so by first
        launch there is always a config.json in the way."""
        self.seed_old()
        self.new.mkdir(parents=True)
        (self.new / "installed_true").write_text("")
        shutil.copyfile(SHIPPED_DEFAULT, self.new / "config.json")

        self.launch(expect=EXPECT_MIGRATED)

        stored = self.stored_config()
        self.assertEqual(stored["osd"]["timeout"], 1700)
        self.assertEqual(stored["panelFamily"], "imi")
        self.assertTrue((self.new / "installed_true").is_file())
        # A merge archives the old dir outside XDG_CONFIG_HOME and removes it,
        # so nothing that resolves a config by absolute path can still find it.
        self.assertFalse(self.old.exists(), "a merge must not leave the old dir behind")
        backups = self.home / "data/immaterial-impulse/backups"
        self.assertTrue(sorted(backups.glob("illogical-impulse-*.tar.gz")),
                        "the old dir was removed without being archived first")

    def test_a_config_the_user_wrote_here_is_kept_and_the_refusal_is_logged(self):
        """The case the script cannot decide. Nothing may be touched, and the
        shell has to say so - silence here is what made the original bug
        invisible."""
        self.seed_old()
        self.new.mkdir(parents=True)
        (self.new / "config.json").write_text(
            json.dumps({"osd": {"timeout": 777}}, indent=2))

        output = self.launch(expect={"osd.timeout": 777})

        self.assertIn("NOT migrating", output)
        self.assertIn(str(self.old), output)
        self.assertIn("settings were not migrated", output.lower())
        self.assertEqual(json.loads((self.old / "config.json").read_text()),
                         json.loads(UPSTREAM_CONFIG))
        self.assertEqual(self.stored_config()["osd"]["timeout"], 777)

    def test_a_migration_that_never_finishes_comes_up_read_only(self):
        """A gate that can hang is a shell that never loads its settings, so
        Config gives up after 10s - but read-only, because a write into a
        half-migrated directory is the thing the gate exists to prevent. The
        config file must come back byte-identical: the shell reads it, tells
        the user, and changes nothing."""
        self.seed_old()
        self.new.mkdir(parents=True)
        # No `migratedUpstreamSchema`, so an unblocked shell would certainly
        # write this file back within the settle window.
        (self.new / "config.json").write_text(
            json.dumps({"osd": {"timeout": 777}}, indent=2))
        before = (self.new / "config.json").read_bytes()

        output = self.launch(expect={"osd.timeout": 777}, delay="14", mode="watchdog")

        self.assertIn("read-only", output)
        self.assertEqual((self.new / "config.json").read_bytes(), before,
                         "the watchdog released Config with writes still enabled")

    def test_a_launch_with_nothing_to_migrate_is_not_held_up(self):
        """The gate is on the startup path of every launch, so the common case
        - no old directory at all - has to stay cheap."""
        output = self.launch()
        migration_ms = int(output.split("migration finished after ")[1].split("ms")[0])
        self.assertLess(migration_ms, 2000,
                        f"the migration gate cost {migration_ms}ms with nothing to do")


if __name__ == "__main__":
    unittest.main()
