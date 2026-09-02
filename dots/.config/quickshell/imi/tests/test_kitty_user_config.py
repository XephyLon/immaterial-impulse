#!/usr/bin/env python3
"""A user's kitty settings survive an update.

kitty's directory was deployed with a `--delete` sync, so every update
rewrote kitty.conf over the user's edits ("transparency or blur values just
disappear after an update") and removed anything else in the directory. The
shipped kitty.conf is managed: it says so, and it includes user.conf LAST,
a file the installer never ships or deletes, so a user's own lines win and
persist. The deploy excludes user.conf and matugen's generated
colors-matugen.conf, the way fish keeps conf.d and tmux its plugins. The
opacity most users were hand-editing is a shell setting written into the
generated theme, so a preset carries it.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[5]
KITTY = ROOT / "dots/.config/kitty/kitty.conf"
FILES = ROOT / "sdata/subcmd-install/3.files-legacy.sh"
CONFIG = ROOT / "dots/.config/quickshell/imi/modules/common/Config.qml"
APPEARANCE_PAGE = ROOT / "dots/.config/quickshell/imi/modules/imi/settings/pages/AppearanceConfig.qml"


class KittyUserConfigTests(unittest.TestCase):
    def test_kitty_conf_is_marked_managed_and_includes_user_conf_last(self):
        lines = [l for l in KITTY.read_text(encoding="utf-8").splitlines() if l.strip() and not l.startswith("#")]
        self.assertEqual(lines[-1], "include user.conf", "user.conf must be the last directive so it overrides the shipped ones")
        self.assertIn("Managed by Immaterial Impulse", KITTY.read_text(encoding="utf-8").splitlines()[0])
        self.assertFalse((ROOT / "dots/.config/kitty/user.conf").exists(), "user.conf is the user's; never ship one")

    def test_the_deploy_keeps_the_users_files(self):
        text = FILES.read_text(encoding="utf-8")
        self.assertRegex(text, r"! -name 'tmux' ! -name 'kitty'", "kitty must leave the generic --delete sync")
        self.assertIn('install_dir__sync_exclude dots/.config/kitty "$XDG_CONFIG_HOME"/kitty "user.conf" "colors-matugen.conf"', text)

    def test_terminal_opacity_is_shell_config_with_a_control(self):
        config = re.sub(r"//[^\n]*", "", CONFIG.read_text(encoding="utf-8"))
        self.assertRegex(config, r"property JsonObject terminal: JsonObject \{\s*property real opacity: 1\.0")
        page = APPEARANCE_PAGE.read_text(encoding="utf-8")
        self.assertIn('text: Translation.tr("Terminal opacity")', page)
        self.assertIn("Config.options.appearance.terminal.opacity = rounded", page)
        self.assertRegex(page, r"terminal\.opacity = rounded\s*page\.scheduleTerminalBackgroundApply\(\)")


if __name__ == "__main__":
    unittest.main()
