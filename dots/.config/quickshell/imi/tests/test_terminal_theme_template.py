#!/usr/bin/env python3
"""The generated kitty theme is never a file kitty refuses.

kitty rejects its whole config over one bad colour line. Two ways the
generator handed it one: with material_colors.scss missing or empty the
colour lists were empty and the template went out with every `#$name #`
placeholder intact ("Invalid color name: '#$primary #'", a user's report),
and one template line carried a `//` comment, which kitty reads as part of
the colour. The generator now refuses to run without a palette, refuses to
install a theme with a placeholder left, and the template has no `//`.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "scripts/colors/applycolor.sh"
TEMPLATE = ROOT / "scripts/colors/terminal/kitty-theme.conf"


class KittyThemeTests(unittest.TestCase):
    def test_the_template_has_no_inline_comments(self):
        for lineno, line in enumerate(TEMPLATE.read_text(encoding="utf-8").splitlines(), 1):
            if line.lstrip().startswith("#"):
                continue
            self.assertNotIn("//", line, f"kitty-theme.conf:{lineno}: a trailing // is part of the colour to kitty")

    def test_every_template_colour_line_is_a_placeholder_kitty_can_take_once_replaced(self):
        for lineno, line in enumerate(TEMPLATE.read_text(encoding="utf-8").splitlines(), 1):
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            self.assertRegex(line, r"^\S+\s+#\$\w+ #\s*$", f"kitty-theme.conf:{lineno}: not the `key #$name #` shape the generator replaces")

    def test_the_generator_refuses_to_run_without_a_palette(self):
        src = GENERATOR.read_text(encoding="utf-8")
        self.assertRegex(src, r'if \[ ! -s "\$STATE_DIR/user/generated/material_colors\.scss" \]; then\s*\n\s*echo[^\n]*\n\s*exit 1')

    def test_the_generator_never_installs_a_theme_with_a_placeholder_left(self):
        src = GENERATOR.read_text(encoding="utf-8")
        body = src[src.index("apply_kitty()"):src.index("apply_anyterm()")]
        self.assertIn("grep -q '#\\$'", body)
        self.assertIn("rm -f \"$STATE_DIR\"/user/generated/terminal/kitty-theme.conf", body)
        self.assertLess(body.index("grep -q '#\\$'"), body.index("kill -SIGUSR1"), "the check runs before kitty is told to reload")


if __name__ == "__main__":
    unittest.main()
