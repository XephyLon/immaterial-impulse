#!/usr/bin/env python3
"""Fail if a toolbar's title is built out of the shape a toolbar button uses.

`IconAndTextToolbarButton` is a `MaterialSymbol` followed by a `StyledText` in a
row. So is an icon-and-label title written directly into a toolbar - and sat
flat between two real buttons, that is not merely similar to a control, it is
the same construction with no container behind it. The one question a toolbar
has to answer is which of its children can be pressed, and Edit Mode's answered
it wrong at both ends: the title read as an unfilled button (#issue in review),
and before that `Done` rendered flat read as a second label, which is why it is
the one button in that toolbar carrying a filled primary container.

Neither failure produces an error, a warning, or a wrong pixel anywhere a frame
comparison looks - the toolbar renders exactly as written. It is only wrong to
a person deciding what to click, so it is pinned here instead.

The rule: inside a `Toolbar`, a non-interactive `StyledText` may not have a
`MaterialSymbol` as its immediately preceding sibling, and must carry a colour
role distinct from the one the toolbar's buttons put their labels in.
"""
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# The toolbars whose titles are written inline rather than by a button widget.
# Listed rather than discovered, because "a StyledText inside a Toolbar" is also
# every button's own label, and those are reached through the widgets.
TOOLBARS = [ROOT / "modules/imi/editMode/EditModeChromeContent.qml"]

# The button widget whose construction a title must not borrow.
BUTTON = ROOT / "modules/common/widgets/IconAndTextToolbarButton.qml"

BLOCK = re.compile(r"\b(MaterialSymbol|StyledText|Rectangle)\s*\{")


# Comments are stripped before any of this runs. A comment that NAMES the
# construction - which the fix's own comment does, since saying why the title is
# not a `MaterialSymbol` followed by a `StyledText` requires writing the pair
# down - is otherwise indistinguishable from the construction itself.
COMMENT = re.compile(r"//[^\n]*")


def uncommented(text):
    return COMMENT.sub("", text)


def _block_end(text, open_brace):
    """Index of the `}` closing the `{` at `open_brace`."""
    depth, index = 0, open_brace
    while index < len(text):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return index
        index += 1
    return len(text)


def toolbar_body(text):
    """The `Toolbar { ... }` blocks of a file, brace-matched."""
    text = uncommented(text)
    for match in re.finditer(r"\bToolbar\s*\{", text):
        yield text[match.end():_block_end(text, match.end() - 1)]


def outside_the_buttons(body):
    """`body` with every `*ToolbarButton { ... }` removed, brace-matched.

    Brace-matched rather than pattern-matched on the closing line: a regex
    anchored to an indentation level passes on any file that indents
    differently, which is how the first version of this lint let the very
    construction it names through.
    """
    while True:
        match = re.search(r"\b\w*ToolbarButton\s*\{", body)
        if not match:
            return body
        body = body[:match.start()] + body[_block_end(body, match.end() - 1) + 1:]


class ToolbarTitleIsNotAButton(unittest.TestCase):
    def test_the_button_widget_is_still_the_shape_this_guards_against(self):
        # If the button stops being an icon beside a label, the rule below is
        # guarding against a shape nothing uses any more and should be revised
        # rather than left passing vacuously.
        text = BUTTON.read_text()
        self.assertRegex(text, r"MaterialSymbol\s*\{",
                         "IconAndTextToolbarButton no longer draws an icon")
        self.assertRegex(text, r"StyledText\s*\{",
                         "IconAndTextToolbarButton no longer draws a label")

    def test_no_title_borrows_the_buttons_construction(self):
        for path in TOOLBARS:
            for body in toolbar_body(path.read_text()):
                outside = outside_the_buttons(body)
                blocks = [m.group(1) for m in BLOCK.finditer(outside)]
                for first, second in zip(blocks, blocks[1:]):
                    self.assertFalse(
                        first == "MaterialSymbol" and second == "StyledText",
                        f"{path.name}: a MaterialSymbol immediately followed by "
                        "a StyledText inside a Toolbar is exactly "
                        "IconAndTextToolbarButton's construction, so the title "
                        "reads as an unfilled button")

    def test_the_title_is_in_a_role_the_buttons_labels_are_not(self):
        for path in TOOLBARS:
            for body in toolbar_body(path.read_text()):
                outside = outside_the_buttons(body)
                if "StyledText" not in outside:
                    continue
                self.assertIn(
                    "colOnSurfaceVariant", outside,
                    f"{path.name}: the toolbar's title is in the same colour "
                    "role as a button's label, so nothing but its missing "
                    "container tells them apart")


if __name__ == "__main__":
    sys.exit(0 if unittest.main(exit=False).result.wasSuccessful() else 1)
