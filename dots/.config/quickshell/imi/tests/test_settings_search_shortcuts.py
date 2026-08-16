#!/usr/bin/env python3
#
# Contract for the settings search shortcuts.
#
# Three ways in - the platform Find, Ctrl+K, and a bare slash - and one rule
# that is easy to lose in a refactor: the slash must be DISABLED while a text
# input has focus. Without that gate no settings page can ever receive a typed
# slash (a path, a command, a URL): the key would be swallowed to focus the
# search field instead. That is the assertion worth keeping; the others are here
# so the shortcuts do not quietly disappear.
#
# Static, because a Shortcut's activation needs a window, a compositor and a
# keyboard. What can be checked without those is that the wiring says what it
# should, and this catches the realistic regression: someone deleting the
# `enabled` line while tidying.

import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTENT = ROOT / "modules" / "imi" / "settings" / "SettingsContent.qml"


class SettingsSearchShortcutTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = CONTENT.read_text()

    def shortcut_block(self, key_line):
        """The Shortcut { ... } block whose sequence line matches."""
        blocks = re.findall(r"Shortcut \{(.*?)\n    \}", self.source, re.S)
        matching = [b for b in blocks if key_line in b]
        self.assertEqual(len(matching), 1, f"expected exactly one Shortcut with {key_line!r}")
        return matching[0]

    def test_all_three_shortcuts_focus_the_search_field(self):
        for key_line in ('sequence: StandardKey.Find', 'sequences: ["Ctrl+K"]', 'sequence: "/"'):
            block = self.shortcut_block(key_line)
            self.assertIn("focusSearch()", block,
                          f"{key_line} does not reach the search field")

    def test_slash_yields_while_a_text_input_has_focus(self):
        block = self.shortcut_block('sequence: "/"')
        self.assertIn("enabled: !root.typingSomewhere", block,
                      "the bare slash is not gated on whether something is being typed into")

    def test_the_gate_asks_the_focused_item_not_a_hardcoded_list(self):
        # Duck-typed on `selectedText` so any text input counts, including ones
        # added later; a list of type names would go stale silently.
        self.assertIn("activeFocusItem", self.source)
        self.assertIn("selectedText !== undefined", self.source)

    def test_ctrl_f_is_not_replaced_by_the_new_bindings(self):
        # The platform shortcut was there first and someone's fingers know it.
        self.assertIn("StandardKey.Find", self.source)

    def test_focusing_selects_what_is_already_there(self):
        match = re.search(r"function focusSearch\(\) \{(.*?)\n    \}", self.source, re.S)
        self.assertIsNotNone(match, "focusSearch() is gone")
        body = match.group(1)
        self.assertIn("forceActiveFocus()", body)
        self.assertIn("selectAll()", body)


if __name__ == "__main__":
    unittest.main(verbosity=1)
