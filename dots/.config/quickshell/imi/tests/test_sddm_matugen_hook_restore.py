#!/usr/bin/env python3
"""`restore_sddm_matugen_hook` must restore the whole block, pointing at the
theme that is actually there and at the apply script sudo will actually accept.

We ship our own `~/.config/matugen/config.toml` and deploy it with
`rsync --delete`, which removes the SDDM theme's `[templates.iisddmtheme]` block
on every update - so the login screen stops following the wallpaper until it is
put back. `sdata/subcmd-install/3.files-legacy.sh` restores it.

Three things have to be right, and each has been wrong:

1. **The whole block, not just the hook.** The restore used to write a bare
   `post_hook` under `[config]`, which is worse than writing nothing: the hook
   fires - now after every matugen run, not just this template's - while the
   `input_path`/`output_path` pair that regenerates `Colors.qml` is gone, so
   there is nothing for it to publish. The greeter's palette froze and the
   function reported success (issue #101). Its guard (`grep ^post_hook`) then
   matched its own half-restore forever, so it never corrected the state it had
   created.

2. **The theme's directory name.** It installs as `imi-sddm-theme` now, and
   installs from before that rename are still under `ii-sddm-theme` until the
   theme's own installer migrates them. During a migrating update both exist for
   a moment, and a block written against the one about to be deleted is broken
   the instant the migration finishes.

3. **The apply script's path.** It is installed root-owned at
   `/usr/local/lib/<theme>/`, because the NOPASSWD sudoers rule names it and
   sudo matches by path - a rule pointing anywhere the user can write is
   equivalent to `NOPASSWD: ALL`. A hook naming any other location prompts for a
   password from a backgrounded hook, which is a hang rather than an error.

Hermetic: sources just this function out of 3.files-legacy.sh (the file is
meant to be sourced by ./setup and has a procedural body) and runs it against a
sandbox HOME, with the privileged directory rewritten into that sandbox.
"""

import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve()
while not (ROOT / "sdata").exists():
    if ROOT.parent == ROOT:
        raise AssertionError("could not locate the repo root")
    ROOT = ROOT.parent

SCRIPT = ROOT / "sdata/subcmd-install/3.files-legacy.sh"
FUNCTION = "restore_sddm_matugen_hook"

BASE_CONF = "[config]\nreload_apps = true\n"
BLOCK_HEADER = "[templates.iisddmtheme]"

# The apply script's real home. The harness rewrites this to reach the sandbox;
# test_the_privileged_path_is_where_we_think_it_is keeps the rewrite honest, so
# a change to the install path fails loudly instead of silently exercising the
# real /usr/local/lib.
PRIV_LITERAL = "/usr/local/lib/${theme_name}"


def _extract_function(text, name):
    start = text.index(f"{name}(){{")
    end = text.index("\n}\n", start) + len("\n}\n")
    return text[start:end]


class SddmMatugenHookRestoreTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.function = _extract_function(SCRIPT.read_text(), FUNCTION)

    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-sddm-hook-"))
        self.addCleanup(
            __import__("shutil").rmtree, self.home, ignore_errors=True)
        self.config = self.home / "config"
        (self.config / "matugen").mkdir(parents=True)
        self.matugen_conf = self.config / "matugen/config.toml"
        self.matugen_conf.write_text(BASE_CONF)
        # Stands in for /usr/local/lib.
        self.priv = self.home / "usr-local-lib"
        self.priv.mkdir()

    def install_theme(self, name, with_generate_settings=True,
                      privileged_apply=True, legacy_apply=False):
        """Lay out an install the way the theme's setup.sh leaves one.

        `SddmColors.qml` is the template's input_path and the marker the restore
        keys off; the apply script is *not* in this directory on a current
        install, it is root-owned under the privileged directory.
        """
        theme = self.config / name
        theme.mkdir(parents=True)
        (theme / "SddmColors.qml").write_text("// stub\n")
        if with_generate_settings:
            (theme / "generate_settings.py").write_text("# stub\n")
        if privileged_apply:
            priv_theme = self.priv / name
            priv_theme.mkdir(parents=True)
            (priv_theme / "sddm-theme-apply.sh").write_text("#!/bin/sh\n")
        if legacy_apply:
            (theme / "sddm-theme-apply.sh").write_text("#!/bin/sh\n")

    def apply_path(self, name):
        return f"{self.priv}/{name}/sddm-theme-apply.sh"

    def run_restore(self):
        function = self.function.replace(PRIV_LITERAL, f"{self.priv}/${{theme_name}}")
        script = textwrap.dedent(f"""\
            #!/usr/bin/env bash
            set -uo pipefail
            XDG_CONFIG_HOME="{self.config}"
            STY_BLUE=""; STY_RST=""
            {function}
            {FUNCTION}
            """)
        path = self.home / "drive.sh"
        path.write_text(script)
        proc = subprocess.run(["bash", str(path)], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.stdout = proc.stdout
        return self.matugen_conf.read_text()

    def block_of(self, conf):
        """The [templates.iisddmtheme] body as key -> value."""
        body, seen = {}, False
        for line in conf.splitlines():
            if line.strip() == BLOCK_HEADER:
                seen = True
                continue
            if seen and line.startswith("["):
                break
            if seen and "=" in line:
                key, _, value = line.partition("=")
                body[key.strip()] = value.strip().strip("'")
        self.assertTrue(seen, f"no {BLOCK_HEADER} block in:\n{conf}")
        return body

    # --- the whole block, not just the hook (#101) --------------------------

    def test_the_template_block_is_restored_in_full(self):
        """A post_hook with no input_path/output_path regenerates nothing: the
        hook fires and publishes a Colors.qml nobody wrote."""
        self.install_theme("imi-sddm-theme")
        block = self.block_of(self.run_restore())
        self.assertEqual(block["input_path"],
                         "~/.config/imi-sddm-theme/SddmColors.qml")
        self.assertEqual(block["output_path"],
                         "~/.config/imi-sddm-theme/Colors.qml")
        self.assertIn("post_hook", block)

    def test_the_hook_lives_under_the_template_not_under_config(self):
        """A `[config] post_hook` is global - it runs after every matugen
        invocation, dragging a sudo call along with it."""
        self.install_theme("imi-sddm-theme")
        conf = self.run_restore()
        head = conf.split(BLOCK_HEADER)[0]
        self.assertNotIn("post_hook", head)

    def test_a_stray_global_post_hook_is_cleaned_up(self):
        """The state the old restore left on every machine it ran on. Left in
        place alongside a correct block it runs the apply script twice per
        wallpaper change, once of them outside the template."""
        self.matugen_conf.write_text(
            "[config]\n"
            "post_hook = 'python3 ~/.config/imi-sddm-theme/generate_settings.py"
            " && sudo ~/.config/imi-sddm-theme/sddm-theme-apply.sh &'\n"
            "reload_apps = true\n")
        self.install_theme("imi-sddm-theme")
        conf = self.run_restore()
        self.assertEqual(conf.count("post_hook"), 1, conf)
        self.assertEqual(conf.count("sddm-theme-apply.sh"), 1, conf)
        self.assertIn("stray global matugen post_hook", self.stdout)
        self.assertIn("reload_apps = true", conf)

    def test_a_post_hook_that_is_not_ours_is_left_alone(self):
        """Only a global hook naming the theme's apply script is ours to
        delete; the user's own belongs to them."""
        self.matugen_conf.write_text("[config]\npost_hook = 'notify-send hi'\n")
        self.install_theme("imi-sddm-theme")
        conf = self.run_restore()
        self.assertIn("post_hook = 'notify-send hi'", conf)

    def test_the_guard_is_the_block_not_the_word_post_hook(self):
        """`grep ^post_hook` matched the old version's own half-restore, so it
        could never tell "the theme's block survived" from "only the bare hook I
        wrote last time is here" - and never repaired the latter."""
        self.matugen_conf.write_text(
            "[config]\npost_hook = 'sudo /somewhere/sddm-theme-apply.sh &'\n")
        self.install_theme("imi-sddm-theme")
        self.block_of(self.run_restore())

    # --- the apply script's path --------------------------------------------

    def test_the_hook_calls_the_privileged_apply_script(self):
        """sudo matches the NOPASSWD rule by path. The in-home path is not what
        the rule names any more, and a password prompt from a backgrounded hook
        is a hang, not a message."""
        self.install_theme("imi-sddm-theme")
        hook = self.block_of(self.run_restore())["post_hook"]
        self.assertIn(f"sudo {self.apply_path('imi-sddm-theme')}", hook)
        self.assertIn("python3 ~/.config/imi-sddm-theme/generate_settings.py", hook)

    def test_an_install_predating_the_move_keeps_the_in_home_path(self):
        """Those installs' sudoers rule still names the in-config copy;
        rewriting the hook to a path that does not exist there would break a
        working install."""
        self.install_theme("imi-sddm-theme", privileged_apply=False,
                           legacy_apply=True)
        hook = self.block_of(self.run_restore())["post_hook"]
        self.assertIn("sudo ~/.config/imi-sddm-theme/sddm-theme-apply.sh", hook)

    def test_no_apply_script_anywhere_means_no_block(self):
        """A block whose hook names a path that does not exist is not an
        improvement on no block."""
        self.install_theme("imi-sddm-theme", privileged_apply=False)
        self.assertEqual(self.run_restore(), BASE_CONF)

    def test_the_privileged_path_is_where_we_think_it_is(self):
        """This literal is what the harness rewrites into the sandbox."""
        self.assertIn(PRIV_LITERAL, self.function)

    # --- resolving the theme's name -----------------------------------------

    def test_the_current_name_is_used(self):
        self.install_theme("imi-sddm-theme")
        conf = self.run_restore()
        self.assertIn("~/.config/imi-sddm-theme/SddmColors.qml", conf)
        self.assertNotIn("~/.config/ii-sddm-theme/", conf)

    def test_an_unmigrated_install_still_gets_its_block(self):
        """Pre-rename installs exist until the theme's installer migrates them,
        and they need the block restored just as much."""
        self.install_theme("ii-sddm-theme")
        conf = self.run_restore()
        self.assertIn("~/.config/ii-sddm-theme/SddmColors.qml", conf)

    def test_with_both_present_the_current_name_wins(self):
        """A migrating update has both on disk at once. Writing the block
        against the directory about to be removed breaks it immediately."""
        self.install_theme("ii-sddm-theme")
        self.install_theme("imi-sddm-theme")
        conf = self.run_restore()
        self.assertIn("~/.config/imi-sddm-theme/", conf)
        self.assertNotIn("~/.config/ii-sddm-theme/", conf)

    def test_the_theme_is_detected_by_the_templates_input_file(self):
        """sddm-theme-apply.sh used to be the marker and is not installed in the
        config directory at all any more, so that marker matches nothing on a
        current install - the restore would silently never run."""
        detection = self.function.split("for theme_name in")[1][:400]
        self.assertIn("SddmColors.qml", detection)

    # --- modes, idempotency, no-ops -----------------------------------------

    def test_the_matugen_only_mode_gets_no_generate_settings_call(self):
        """generate_settings.py ships only with the ii+matugen mode; calling it
        where it does not exist makes the hook fail every wallpaper change."""
        self.install_theme("imi-sddm-theme", with_generate_settings=False)
        hook = self.block_of(self.run_restore())["post_hook"]
        self.assertEqual(hook, f"sudo {self.apply_path('imi-sddm-theme')} &")

    def test_no_theme_means_no_block(self):
        self.assertEqual(self.run_restore(), BASE_CONF)

    def test_an_existing_block_is_not_duplicated(self):
        self.install_theme("imi-sddm-theme")
        first = self.run_restore()
        self.assertEqual(first.count(BLOCK_HEADER), 1)
        self.assertEqual(self.run_restore(), first)

    def test_the_trailing_ampersand_survives(self):
        """The hook ends in `&` so matugen does not block on it. It has been
        eaten before: `&` in a sed replacement means the whole match, which is
        why the block is appended rather than spliced in."""
        self.install_theme("imi-sddm-theme")
        conf = self.run_restore()
        self.assertIn("sddm-theme-apply.sh &'", conf)
        self.assertNotIn("[config]'", conf)


if __name__ == "__main__":
    unittest.main()
