#!/usr/bin/env python3
"""The shipped tmux config and its installer wiring.

Guards the invariants that make the tmux dots safe to sync onto a machine
where tmux is already in use: the shipped config must be machine-portable and
degrade cleanly (no fish, no tpm), and every install path must preserve the
two runtime artifacts the config sources but never contains - plugins/ (tpm
state) and matugen.conf (regenerated from the palette). A plain MISC sync
would rsync --delete both, which is why tmux has its own gated step.
"""
import pathlib
import re
import unittest

# Shipped dots and the installer live at the repo root, a few levels up from
# this test (the deployed config dir never contains tests/, so the climb only
# runs where sdata/ actually exists).
ROOT = pathlib.Path(__file__).resolve()
while not (ROOT / "sdata").exists():
    ROOT = ROOT.parent
TMUX_CONF = ROOT / "dots/.config/tmux/tmux.conf"
LEGACY = ROOT / "sdata/subcmd-install/3.files-legacy.sh"
OPTIONS = ROOT / "sdata/subcmd-install/options.sh"
EXP_YAML = ROOT / "sdata/subcmd-install/3.files-exp.yaml"
TUI_FZF = ROOT / "sdata/subcmd-install/tui.sh"
TUI_WHIPTAIL = ROOT / "sdata/subcmd-install/tui-whiptail.sh"


def code_only(text):
    return "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("#"))


class ShippedTmuxConfigTests(unittest.TestCase):
    def setUp(self):
        self.conf = TMUX_CONF.read_text()
        self.code = code_only(self.conf)

    def test_is_machine_portable(self):
        self.assertNotIn("/home/", self.conf)

    def test_fish_is_default_but_guarded(self):
        # A bare default-command on a fishless machine spawns a broken pane;
        # the if-shell guard makes fish the default only where it exists.
        self.assertRegex(self.code,
                         r"if-shell 'command -v fish' 'set -g default-command fish'")
        self.assertNotRegex(self.code, r"(?m)^set(-option)? -g default-shell")

    def test_sources_the_matugen_theme_quietly(self):
        # -q: a machine that has never run a palette switch has no
        # matugen.conf yet, and that must not be a startup error.
        self.assertIn("source-file -q ~/.config/tmux/matugen.conf", self.code)

    def test_tpm_is_guarded_and_no_theme_plugin_remains(self):
        self.assertRegex(
            self.code,
            r"if-shell 'test -x ~/.config/tmux/plugins/tpm/tpm' 'run ~/.config/tmux/plugins/tpm/tpm'")
        # The status line belongs to the matugen template now; a theme plugin
        # would overwrite it after every prefix+I.
        self.assertNotRegex(self.code, r"@plugin.*(gruvbox|catppuccin|dracula|powerline)")


class TmuxInstallWiringTests(unittest.TestCase):
    def test_legacy_misc_loop_excludes_tmux(self):
        legacy = code_only(LEGACY.read_text())
        find_line = next(l for l in legacy.splitlines() if "find dots/.config/" in l)
        self.assertIn("! -name 'tmux'", find_line)

    def test_legacy_step_preserves_runtime_artifacts(self):
        legacy = code_only(LEGACY.read_text())
        match = re.search(
            r'case "\$\{SKIP_TMUX\}" in.*?install_dir__sync_exclude dots/\.config/tmux'
            r' "\$XDG_CONFIG_HOME"/tmux ([^\n]*)', legacy, re.S)
        self.assertIsNotNone(match, "SKIP_TMUX-gated install step missing")
        self.assertIn('"plugins"', match.group(1))
        self.assertIn('"matugen.conf"', match.group(1))

    def test_options_declare_and_handle_skip_tmux(self):
        options = code_only(OPTIONS.read_text())
        getopt_line = next(l for l in options.splitlines() if l.strip().startswith("-l help,"))
        self.assertIn("skip-tmux", getopt_line)
        self.assertIn("--skip-tmux) SKIP_TMUX=true;shift;;", options)
        core_line = next(l for l in options.splitlines() if l.strip().startswith("--core)"))
        self.assertIn("SKIP_TMUX=true", core_line)

    def test_exp_yaml_entry_preserves_runtime_artifacts(self):
        yaml_text = EXP_YAML.read_text()
        match = re.search(
            r'- from: "dots/\.config/tmux"\n\s+to: "\$XDG_CONFIG_HOME/tmux"\n'
            r'\s+mode: "sync"\n\s+excludes: \[([^\]]*)\]', yaml_text)
        self.assertIsNotNone(match, "tmux entry missing from 3.files-exp.yaml")
        self.assertIn('"plugins"', match.group(1))
        self.assertIn('"matugen.conf"', match.group(1))


class TuiTmuxToggleTests(unittest.TestCase):
    """Both interactive front-ends must surface the tmux component.

    --skip-tmux existing only at flag level is invisible: Update Dots runs the
    TUI, and a component absent from its menus cannot be chosen or declined
    there at all.
    """

    def test_fzf_tui_offers_tmux_and_maps_to_skip_flag(self):
        tui = code_only(TUI_FZF.read_text())
        self.assertRegex(tui, r"\[TMUX\]=", "TMUX missing from the fzf STATE/LABELS globals")
        order_lines = [l for l in tui.splitlines() if re.match(r"\s*ORDER=\(", l)]
        self.assertTrue(any("TMUX" in l for l in order_lines),
                        "TMUX not in any fzf toggle ORDER")
        self.assertRegex(tui, r'"\$TMUX_ON" == on \]\] \|\| INSTALL_FLAGS\+=\(--skip-tmux\)')

    def test_whiptail_tui_offers_tmux_and_maps_to_skip_flag(self):
        tui = code_only(TUI_WHIPTAIL.read_text())
        self.assertRegex(tui, r'"TMUX"\s+".*"\s+"\$tmux_state"',
                         "TMUX row missing from the whiptail checklist")
        self.assertRegex(
            tui,
            r'case "\$COMPONENTS" in\s*\n\s*\*TMUX\*\) : ;;\s*\n\s*\*\) INSTALL_FLAGS\+=\(--skip-tmux\) ;;')

    def test_both_tuis_precheck_ours_but_not_a_foreign_config(self):
        # The whiptail header's own rule: already-installed components
        # pre-select so updates reach them. For tmux "installed" means the
        # deployed config is ours (it sources the matugen theme); a tmux.conf
        # without that line is the user's own and must default to unticked
        # rather than being clobbered by rsync --delete.
        for path in (TUI_FZF, TUI_WHIPTAIL):
            tui = code_only(path.read_text())
            self.assertRegex(tui, r"grep -q 'tmux/matugen\\?\.conf'",
                             f"{path.name}: no ours-vs-foreign detection on tmux.conf")


if __name__ == "__main__":
    unittest.main()
