#!/usr/bin/env python3
"""A tmux pane never receives the terminal's default colours.

`applycolor.sh` pushes the generated OSC sequences into every interactive pty.
A tmux pane's pty is one of those, and tmux (3.4+) adopts an OSC 10/11/12 it
receives there as the pane's OWN default foreground/background/cursor - and
from then on paints the pane's background explicitly, every cell. In kitty,
which applies `background_opacity` only to its default background colour, that
is a translucent window turning into a solid slab. Measured on the live shell:
`#{pane_bg}` read #1b1b17 on every pane; resetting it with OSC 111 brought the
pane back to `default` and the blur back through it.

So a pane gets the palette (OSC 4) and a reset of the three defaults (OSC
110/111/112); the outer terminal, whose own pty runs the tmux client, still
gets the full set and the panes inherit from it.

The push is one of TWO ways the sequences reach a pane. The other is the shell
rc: every new shell `cat`s the generated file on start-up, and tmux starts a
shell in every new pane - so the panes came back opaque the day after the push
was fixed (`#{pane_bg}` read #1b1b17 on both panes of a fresh session; tmux's
default-command was fish and config.fish cat the full file). The rc files ship
in dots/, so they are pinned here too: inside tmux (`$TMUX` set) they send the
pane-safe file and never the full one.
"""

from pathlib import Path
import re
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
DOTS = ROOT.parents[2]
ZSH_RC = DOTS / ".config/zshrc.d/dots-hyprland.zsh"
FISH_RC = DOTS / ".config/fish/config.fish"
APPLY = ROOT / "scripts/colors/applycolor.sh"
FILTER = ROOT / "scripts/colors/terminal/pane_safe.sh"

ESC = "\x1b"
ST = ESC + "\\"
SAMPLE = "".join([
    f"{ESC}]4;0;#111111{ST}", f"{ESC}]4;1;#222222{ST}", f"{ESC}]1;0;#111111{ST}",
    f"{ESC}]10;#dddddd{ST}", f"{ESC}]11;#1b1b17{ST}", f"{ESC}]11;[70]#1b1b17{ST}",
    f"{ESC}]12;#eeeeee{ST}", f"{ESC}]13;#eeeeee{ST}", f"{ESC}]17;#333333{ST}",
    f"{ESC}]19;#dddddd{ST}", f"{ESC}]708;#1b1b17{ST}", f"{ESC}]4;2;#333333{ST}",
])


class PaneSafeFilterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.out = subprocess.run(["bash", str(FILTER)], input=SAMPLE, capture_output=True,
                                 text=True, check=True).stdout

    def test_the_defaults_are_stripped(self):
        for osc in ("10", "11", "12", "13", "17", "19", "708"):
            self.assertNotIn(f"{ESC}]{osc};", self.out, f"OSC {osc} must not reach a pane")

    def test_the_palette_survives_in_order(self):
        kept = re.findall(r"\x1b\]4;(\d+);", self.out)
        self.assertEqual(kept, ["0", "1", "2"])
        self.assertIn(f"{ESC}]1;0;#111111{ST}", self.out)

    def test_the_pane_is_told_to_forget_defaults_it_already_adopted(self):
        # A pane coloured by an earlier push recovers on the next one.
        for osc in ("110", "111", "112"):
            self.assertIn(f"{ESC}]{osc}{ST}", self.out)
        self.assertTrue(self.out.endswith(f"{ESC}]112{ST}"), "the resets come last")


class ApplyColorRoutesPanesTests(unittest.TestCase):
    def setUp(self):
        self.source = APPLY.read_text(encoding="utf-8")

    def test_every_tmux_server_is_asked_for_its_pane_ttys(self):
        self.assertIn("/tmp/tmux-\"$(id -u)\"/*", self.source)
        self.assertIn("list-panes -a -F '#{pane_tty}'", self.source)

    def test_a_pane_tty_gets_the_pane_safe_file_and_nothing_else_does(self):
        self.assertIn('"$SCRIPT_DIR/terminal/pane_safe.sh"', self.source)
        self.assertIn("sequences-pane.txt", self.source)
        loop = self.source[self.source.index("for file in /dev/pts/*"):]
        loop = loop[:loop.index("\n}")]
        self.assertIn('grep -qxF "$file" <<<"$pane_ttys"', loop)
        self.assertIn('cat "$payload" >"$file"', loop)
        self.assertNotIn('cat "$STATE_DIR"/user/generated/terminal/sequences.txt >"$file"', loop,
                         "the full set must go through the routing, not straight to every pty")


class ShellRcRoutesPanesTests(unittest.TestCase):
    """A new shell inside tmux sends the pane-safe file, never the full one."""

    FULL = "~/.local/state/quickshell/user/generated/terminal/sequences.txt"
    PANE = "~/.local/state/quickshell/user/generated/terminal/sequences-pane.txt"

    def test_zsh_picks_the_pane_file_under_tmux(self):
        rc = ZSH_RC.read_text(encoding="utf-8")
        self.assertIn('if [ -n "$TMUX" ]', rc, "the choice has to hang on $TMUX")
        self.assertIn(self.PANE, rc)
        self.assertNotIn(f"cat {self.FULL}", rc,
                         "the full file must never be cat directly - it has to go through the choice")
        self.assertRegex(rc, r'cat "\$_imi_seq"', "the one cat reads the chosen file")

    def test_fish_picks_the_pane_file_under_tmux(self):
        rc = FISH_RC.read_text(encoding="utf-8")
        self.assertIn("if set -q TMUX", rc, "the choice has to hang on $TMUX")
        self.assertIn(self.PANE, rc)
        self.assertNotIn(f"cat {self.FULL}", rc,
                         "the full file must never be cat directly - it has to go through the choice")
        self.assertRegex(rc, r"cat \$imi_seq", "the one cat reads the chosen file")


if __name__ == "__main__":
    unittest.main()
