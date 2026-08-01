#!/usr/bin/env python3
"""Hermetic tests for the installer's destructive file-sync helpers.

Targets sdata/subcmd-install/3.files.sh:
  - rsync_dir__sync / rsync_dir__sync_exclude / rsync_dir__sync_exclude_from
    (rsync -a --delete): files copied, extraneous dest files deleted ONLY
    inside the target dir, excludes honored, canaries outside dest survive.
  - auto_backup_configs: clashing dirs/files are backed up into BACKUP_DIR,
    non-clashing ones are not; a pre-existing BACKUP_DIR skips the backup
    (ask=false path).
  - install_file__auto_backup: firstrun moves the clashing file to <t>.old and
    installs; non-firstrun keeps <t> and writes <t>.new.
  - seed_default_config: seeds defaults/config.json on a fresh install only,
    never overwrites an existing config.json.

3.files.sh is meant to be *sourced* by ./setup and has a procedural install
body after its function definitions (submodule update, sourcing
3.files-legacy.sh, hyprctl reload, ...). The tests therefore extract only the
function-definition prelude (everything before the first full-width #####
separator) and source it in a bash harness together with the real shared
helpers (sdata/lib/environment-variables.sh + functions.sh), with HOME and all
XDG_* dirs pointed into a per-test sandbox tempdir. ask=false so v()/x() never
prompt; on failure x() aborts because stdin is not a tty.
"""
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

# 3.files.sh lives at <repo>/sdata/subcmd-install/3.files.sh
ROOT = Path(__file__).resolve()
while not (ROOT / "sdata").exists():
    ROOT = ROOT.parent
FILES_SH = ROOT / "sdata/subcmd-install/3.files.sh"
ENV_SH = ROOT / "sdata/lib/environment-variables.sh"
FUNCS_SH = ROOT / "sdata/lib/functions.sh"

FILES_TEXT = FILES_SH.read_text(encoding="utf-8")
HAVE_RSYNC = shutil.which("rsync") is not None


def function_prelude() -> str:
    """Everything in 3.files.sh before the first '#####...' separator line.

    That is exactly the function-definition block; the procedural install body
    (mkdir loop, submodule update, sourcing 3.files-legacy.sh, hyprctl reload)
    starts right after it and must never run in tests.
    """
    out = []
    for line in FILES_TEXT.splitlines(keepends=True):
        if re.match(r"^#{5,}\s*$", line):
            break
        out.append(line)
    text = "".join(out)
    # Pin the extraction: all functions under test present, no procedural body.
    for fn in ("auto_backup_configs", "seed_default_config",
               "rsync_dir__sync", "rsync_dir__sync_exclude",
               "install_file__auto_backup"):
        assert fn in text, f"prelude extraction lost {fn}()"
    assert "hyprctl" not in text, "prelude extraction leaked the install body"
    assert "auto_update_git_submodule\nv auto_update" not in text
    return text


class InstallerFileSyncTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.sandbox = Path(self._tmp.name)
        self.home = self.sandbox / "home"
        self.cfg = self.home / ".config"
        self.data = self.home / ".local/share"
        self.cfg.mkdir(parents=True)
        self.data.mkdir(parents=True)
        self.backup = self.home / "ii-original-dots-backup"
        self.listfile = self.cfg / "immaterial-impulse/installed_listfile"
        self.prelude = self.sandbox / "prelude.sh"
        self.prelude.write_text(function_prelude())

    def tearDown(self):
        self._tmp.cleanup()

    def run_harness(self, snippet, cwd=None, extra_env=None):
        env = dict(
            os.environ,
            HOME=str(self.home),
            XDG_CONFIG_HOME=str(self.cfg),
            XDG_DATA_HOME=str(self.data),
            XDG_CACHE_HOME=str(self.home / ".cache"),
            XDG_STATE_HOME=str(self.home / ".local/state"),
            XDG_BIN_HOME=str(self.home / ".local/bin"),
            BACKUP_DIR=str(self.backup),
        )
        if extra_env:
            env.update(extra_env)
        script = "\n".join([
            "ask=false",
            'INSTALL_FIRSTRUN="${INSTALL_FIRSTRUN:-true}"',
            f'source "{ENV_SH}"',
            f'source "{FUNCS_SH}"',
            f'source "{self.prelude}"',
            snippet,
        ])
        return subprocess.run(["bash", "-c", script],
                              cwd=str(cwd or self.sandbox), env=env,
                              capture_output=True, text=True)

    def assert_ok(self, r):
        self.assertEqual(r.returncode, 0,
                         f"harness failed\nstdout:\n{r.stdout}\nstderr:\n{r.stderr}")

    def plant_canaries(self):
        """Files just OUTSIDE the sync destination; --delete must never eat them."""
        canaries = {
            self.cfg / "canary.txt": "canary-in-config-root",
            self.cfg / "other-app/settings.conf": "canary-sibling-dir",
            self.home / "canary-home.txt": "canary-in-home",
        }
        for p, content in canaries.items():
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(content)
        return canaries

    def assert_canaries(self, canaries):
        for p, content in canaries.items():
            self.assertTrue(p.is_file(), f"canary outside dest was deleted: {p}")
            self.assertEqual(p.read_text(), content,
                             f"canary outside dest was modified: {p}")

    # ------------------------------------------------------------------ rsync
    @unittest.skipUnless(HAVE_RSYNC, "rsync not available")
    def test_rsync_dir_sync_copies_and_deletes_only_inside_dest(self):
        src = self.sandbox / "src"
        (src / "sub").mkdir(parents=True)
        (src / "a.txt").write_text("A")
        (src / "sub/b.txt").write_text("B")
        dest = self.cfg / "fakeapp"
        (dest / "sub").mkdir(parents=True)
        (dest / "stale.txt").write_text("stale")
        (dest / "sub/old.txt").write_text("old")
        canaries = self.plant_canaries()

        r = self.run_harness(f'rsync_dir__sync "{src}" "{dest}"')
        self.assert_ok(r)

        self.assertEqual((dest / "a.txt").read_text(), "A")
        self.assertEqual((dest / "sub/b.txt").read_text(), "B")
        # --delete: extraneous files removed, but only within the dest dir.
        self.assertFalse((dest / "stale.txt").exists(),
                         "--delete did not prune extraneous dest file")
        self.assertFalse((dest / "sub/old.txt").exists())
        self.assert_canaries(canaries)
        # Installed-files manifest records the new files by absolute dest path.
        listing = self.listfile.read_text()
        self.assertIn(str(dest / "a.txt"), listing)
        self.assertIn(str(dest / "sub/b.txt"), listing)

    @unittest.skipUnless(HAVE_RSYNC, "rsync not available")
    def test_rsync_dir_sync_exclude_honors_patterns(self):
        src = self.sandbox / "src"
        src.mkdir()
        (src / "a.txt").write_text("A")
        (src / "secret.key").write_text("src-key")   # excluded: must not be copied
        dest = self.cfg / "fakeapp"
        dest.mkdir(parents=True)
        (dest / "keep.key").write_text("user-key")   # excluded: must survive --delete
        (dest / "stale.txt").write_text("stale")     # not excluded: must be pruned
        canaries = self.plant_canaries()

        r = self.run_harness(f'rsync_dir__sync_exclude "{src}" "{dest}" "*.key"')
        self.assert_ok(r)

        self.assertEqual((dest / "a.txt").read_text(), "A")
        self.assertFalse((dest / "secret.key").exists(),
                         "excluded source file was copied")
        self.assertEqual((dest / "keep.key").read_text(), "user-key",
                         "excluded dest file was deleted/overwritten by --delete")
        self.assertFalse((dest / "stale.txt").exists())
        self.assert_canaries(canaries)

    @unittest.skipUnless(HAVE_RSYNC, "rsync not available")
    def test_rsync_dir_sync_exclude_from_honors_exclude_file(self):
        # Same contract as above, patterns supplied via a file (this is the
        # variant deploy uses with sdata/lib/deploy-exclude.txt).
        src = self.sandbox / "src"
        (src / "cache").mkdir(parents=True)
        (src / "a.txt").write_text("A")
        (src / "secret.key").write_text("src-key")
        (src / "cache/c.bin").write_text("c")
        exclude_file = self.sandbox / "excludes.txt"
        exclude_file.write_text("*.key\ncache/\n")
        dest = self.cfg / "fakeapp"
        dest.mkdir(parents=True)
        (dest / "keep.key").write_text("user-key")
        (dest / "stale.txt").write_text("stale")
        canaries = self.plant_canaries()

        r = self.run_harness(
            f'rsync_dir__sync_exclude_from "{src}" "{dest}" "{exclude_file}"')
        self.assert_ok(r)

        self.assertEqual((dest / "a.txt").read_text(), "A")
        self.assertFalse((dest / "secret.key").exists())
        self.assertFalse((dest / "cache").exists())
        self.assertEqual((dest / "keep.key").read_text(), "user-key")
        self.assertFalse((dest / "stale.txt").exists())
        self.assert_canaries(canaries)

    # ----------------------------------------------------------------- backup
    @unittest.skipUnless(HAVE_RSYNC, "rsync not available")
    def test_auto_backup_configs_backs_up_only_clashing_entries(self):
        # auto_backup_configs resolves dots/.config relative to $PWD (the repo
        # root during a real install); build a fake repo layout in the sandbox.
        repo = self.sandbox / "repo"
        (repo / "dots/.config/hypr").mkdir(parents=True)
        (repo / "dots/.config/hypr/hyprland.conf").write_text("repo")
        (repo / "dots/.config/onlyrepo").mkdir()
        (repo / "dots/.config/onlyrepo/x.conf").write_text("repo")
        (repo / "dots/.local/share/icons").mkdir(parents=True)
        (repo / "dots/.local/share/icons/repo-icon.txt").write_text("repo")

        (self.cfg / "hypr").mkdir()
        (self.cfg / "hypr/user.conf").write_text("mine")          # clash
        (self.cfg / "unrelated").mkdir()
        (self.cfg / "unrelated/keep.conf").write_text("mine")     # no clash
        (self.data / "icons").mkdir()
        (self.data / "icons/user-icon.txt").write_text("mine")    # clash
        (self.data / "fonts").mkdir()
        (self.data / "fonts/f.ttf").write_text("mine")            # no clash

        r = self.run_harness("auto_backup_configs", cwd=repo)
        self.assert_ok(r)

        # Clashing entries land under BACKUP_DIR mirroring .config/.local/share.
        self.assertEqual((self.backup / ".config/hypr/user.conf").read_text(),
                         "mine")
        self.assertEqual(
            (self.backup / ".local/share/icons/user-icon.txt").read_text(),
            "mine")
        # Non-clashing entries are NOT backed up.
        self.assertFalse((self.backup / ".config/unrelated").exists())
        self.assertFalse((self.backup / ".local/share/fonts").exists())
        # Backup is a copy: the originals stay in place, untouched.
        self.assertEqual((self.cfg / "hypr/user.conf").read_text(), "mine")
        self.assertEqual((self.data / "icons/user-icon.txt").read_text(), "mine")

    @unittest.skipUnless(HAVE_RSYNC, "rsync not available")
    def test_auto_backup_configs_skipped_when_backup_dir_exists(self):
        # ask=false + pre-existing BACKUP_DIR => no backup (never clobber a
        # previous backup non-interactively).
        repo = self.sandbox / "repo"
        (repo / "dots/.config/hypr").mkdir(parents=True)
        (repo / "dots/.config/hypr/hyprland.conf").write_text("repo")
        (repo / "dots/.local/share").mkdir(parents=True)
        (self.cfg / "hypr").mkdir()
        (self.cfg / "hypr/user.conf").write_text("mine")
        self.backup.mkdir(parents=True)
        (self.backup / "previous-backup-marker").write_text("old backup")

        r = self.run_harness("auto_backup_configs", cwd=repo)
        self.assert_ok(r)

        self.assertFalse((self.backup / ".config").exists(),
                         "backup ran despite pre-existing BACKUP_DIR")
        self.assertEqual((self.backup / "previous-backup-marker").read_text(),
                         "old backup")

    # ------------------------------------------------- install_file__auto_backup
    def test_install_file_auto_backup_firstrun_backs_up_then_installs(self):
        s = self.sandbox / "payload.conf"
        s.write_text("new")
        t = self.cfg / "app/thing.conf"
        t.parent.mkdir(parents=True)
        t.write_text("old")

        r = self.run_harness(f'install_file__auto_backup "{s}" "{t}"',
                             extra_env={"INSTALL_FIRSTRUN": "true"})
        self.assert_ok(r)

        self.assertEqual(t.read_text(), "new")
        backup = t.with_name(t.name + ".old")
        self.assertTrue(backup.is_file(), "clashing file not backed up as .old")
        self.assertEqual(backup.read_text(), "old")
        self.assertIn(str(t), self.listfile.read_text())

    def test_install_file_auto_backup_not_firstrun_keeps_existing(self):
        s = self.sandbox / "payload.conf"
        s.write_text("new")
        t = self.cfg / "app/thing.conf"
        t.parent.mkdir(parents=True)
        t.write_text("old")

        r = self.run_harness(f'install_file__auto_backup "{s}" "{t}"',
                             extra_env={"INSTALL_FIRSTRUN": "false"})
        self.assert_ok(r)

        # Existing file untouched; new content parked next to it as .new.
        self.assertEqual(t.read_text(), "old")
        self.assertEqual(t.with_name(t.name + ".new").read_text(), "new")
        self.assertFalse(t.with_name(t.name + ".old").exists())

    def test_install_file_auto_backup_fresh_target_just_installs(self):
        s = self.sandbox / "payload.conf"
        s.write_text("new")
        t = self.cfg / "app/thing.conf"

        r = self.run_harness(f'install_file__auto_backup "{s}" "{t}"',
                             extra_env={"INSTALL_FIRSTRUN": "true"})
        self.assert_ok(r)

        self.assertEqual(t.read_text(), "new")
        self.assertFalse(t.with_name(t.name + ".old").exists())
        self.assertFalse(t.with_name(t.name + ".new").exists())

    # ----------------------------------------------------- seed_default_config
    def test_seed_default_config_seeds_fresh_install(self):
        source = self.cfg / "quickshell/imi/defaults/config.json"
        source.parent.mkdir(parents=True)
        source.write_text('{"seed": 1}')

        r = self.run_harness("seed_default_config")
        self.assert_ok(r)

        target = self.cfg / "immaterial-impulse/config.json"
        self.assertEqual(target.read_text(), '{"seed": 1}')
        self.assertIn(str(target), self.listfile.read_text())

    def test_seed_default_config_never_overwrites_existing_config(self):
        source = self.cfg / "quickshell/imi/defaults/config.json"
        source.parent.mkdir(parents=True)
        source.write_text('{"seed": 1}')
        target = self.cfg / "immaterial-impulse/config.json"
        target.parent.mkdir(parents=True)
        target.write_text('{"user": 1}')

        r = self.run_harness("seed_default_config")
        self.assert_ok(r)

        self.assertEqual(target.read_text(), '{"user": 1}',
                         "seed_default_config clobbered the user's live config")
        self.assertIn("already exists", r.stdout)

    def test_seed_default_config_missing_source_is_a_soft_noop(self):
        r = self.run_harness("seed_default_config")
        self.assert_ok(r)
        self.assertFalse((self.cfg / "immaterial-impulse/config.json").exists())
        self.assertIn("not found", r.stdout)

    # ------------------------------------------------------- static guardrails
    def test_delete_flag_confined_to_sync_helper_functions(self):
        # Every --delete in 3.files.sh must be an 'rsync -a --delete' inside the
        # dedicated sync helpers; exactly the three known helpers use it.
        delete_lines = [l for l in FILES_TEXT.splitlines()
                        if "--delete" in l and not l.lstrip().startswith("#")]
        self.assertEqual(len(delete_lines), 3,
                         f"unexpected --delete call sites: {delete_lines}")
        for line in delete_lines:
            self.assertRegex(line, r"^\s*rsync -a --delete",
                             f"--delete outside a plain rsync helper line: {line}")
        # Each destroys only its dest argument, which it mkdir -p's first.
        for fn in ("rsync_dir__sync", "rsync_dir__sync_exclude",
                   "rsync_dir__sync_exclude_from"):
            body = re.search(rf"^{fn}\(\)\{{\n(.*?)^\}}", FILES_TEXT,
                             re.M | re.S)
            self.assertIsNotNone(body, f"{fn} definition missing")
            self.assertIn("mkdir -p", body.group(1))
        # The shared backup helper must never delete anything.
        self.assertNotIn("--delete", FUNCS_SH.read_text(encoding="utf-8"))

    def test_sync_helpers_only_called_through_echo_wrapper(self):
        # Call sites of the --delete helpers go through v() (echo-before-run);
        # bare invocations would silently destroy without showing the command.
        for line in FILES_TEXT.splitlines():
            stripped = line.strip()
            if stripped.startswith("rsync_dir__sync") and "(){" not in stripped:
                self.fail(f"bare (unwrapped) sync helper call: {line}")
        self.assertIn("v rsync_dir__sync ", FILES_TEXT)
        self.assertIn("v rsync_dir__sync_exclude ", FILES_TEXT)
        self.assertIn("v rsync_dir__sync_exclude_from ", FILES_TEXT)


class RestoreIconThemeTests(unittest.TestCase):
    """The dots sync ships kdeglobals with Theme=breeze-dark; the installer
    must re-apply the user's stored icon selection after every sync."""

    def setUp(self):
        self.text = FILES_SH.read_text()

    def test_restore_runs_after_files_dispatch(self):
        dispatch = self.text.index("3.files-legacy.sh")
        restore_call = self.text.index("v restore_icon_theme")
        seed = self.text.index("v seed_default_config")
        self.assertTrue(dispatch < restore_call < seed,
                        "restore_icon_theme must run after the sync, before seeding")

    def test_restore_reads_shell_config_and_apply_script(self):
        self.assertIn('appearance",{}).get("iconTheme', self.text)
        self.assertIn("scripts/icons/apply-icon-theme.sh", self.text)

    def test_restore_is_best_effort(self):
        # A missing config/script or an uninstalled theme must not abort the
        # installer - the function returns 0 and at worst keeps the default.
        block = self.text[self.text.index("function restore_icon_theme(){"):
                          self.text.index("function seed_default_config(){")]
        self.assertIn("return 0", block)
        self.assertNotIn("exit ", block)


if __name__ == "__main__":
    unittest.main()
