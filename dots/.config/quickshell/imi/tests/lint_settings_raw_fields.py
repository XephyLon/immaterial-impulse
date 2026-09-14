#!/usr/bin/env python3
"""A settings page takes text through ConfigTextArea, never a raw field.

`MaterialTextField` is the QQC2 Material `TextField` with the shell's colours
poured in - the outlined box with the floating label in the accent colour.
It predates the settings row grammar (test_settings_row_grammar.py) and the
maintainer retired it from the pages on 2026-09-14 when two folder rows
shipped with it next to rows drawn by `ConfigTextArea`: "using the wrong UI
component for those. This one should be obsolete at this point."

So under modules/imi/settings/pages/ no file declares a single-line
`MaterialTextField` or `TextField` of its own; the row widgets (ConfigTextArea
and friends) are the only way a line of text is asked for there. A multi-line
`MaterialTextArea` (the system prompt, an autostart list) is a different
control and stays.
"""
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PAGES = ROOT / "modules/imi/settings/pages"
RAW = re.compile(r"^\s*(MaterialTextField|TextField)\s*\{", re.M)


def _strip(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def offences():
    found = []
    for page in sorted(PAGES.glob("*.qml")):
        src = _strip(page.read_text())
        for m in RAW.finditer(src):
            line = src.count("\n", 0, m.start()) + 1
            found.append(f"{page.name}:{line}: {m.group(1)} - use ConfigTextArea (the settings row grammar)")
    return found


class SettingsRawFields(unittest.TestCase):
    def test_no_settings_page_declares_a_raw_text_field(self):
        self.assertEqual(offences(), [], "\n".join(offences()))

    def test_the_regex_sees_the_widget_it_bans(self):
        self.assertTrue(RAW.search("    MaterialTextField {\n"))
        self.assertTrue(RAW.search("    TextField {\n"))
        self.assertFalse(RAW.search("    ConfigTextArea {\n"), "the row widget is the allowed one")
        self.assertFalse(RAW.search("    MaterialTextArea {\n"), "a multi-line area is a different control")
        self.assertFalse(RAW.search("property alias textArea: textArea"))


if __name__ == "__main__":
    unittest.main()
