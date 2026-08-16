#!/usr/bin/env python3
"""A settings page is addressed by its id; its name is only ever read.

`SettingsContent.qml`'s page catalogue carries two strings per page. `name` is a
`Translation.tr(...)` call - what the sidebar draws and what the search matches,
because that is the text the user is looking at when they type. `id` is a plain
untranslated literal, and it is the only thing a link may be resolved against:
`GlobalStates.settingsPage` used to be matched on `name`, so every deep link -
the desktop menu's two rows, every settings hit in the launcher - resolved only
while the shell happened to be in English. The miss is silent by construction:
findIndex returns -1, the handler clears the request regardless, and the window
opens on whatever page was last shown.

The realistic regression is not someone re-writing the resolver. It is someone
adding a fifteenth page, or a third deep link, by copying the shape next to it -
so this checks the catalogue, both directions of the resolver, and *every*
`GlobalStates.settingsPage` write in the tree, rather than the one line that was
wrong.

The search half is pinned in the opposite direction on purpose. Moving
navigation onto ids while also moving search onto them would leave a user unable
to find a page by the name printed in front of them, which is a worse bug than
the one being fixed and would look like a deliberate part of it.

Static, because the catalogue is a QML property built from a singleton that
needs an engine, and `qmltestrunner` cannot construct the Quickshell types the
file imports.
"""

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT / "modules/imi/settings/SettingsContent.qml"
PAGES = ROOT / "modules/imi/settings/pages"
LAUNCHER = ROOT / "services/LauncherSearch.qml"

ID_LITERAL = re.compile(r'\bid:\s*"([^"]*)"')
ID_ANY = re.compile(r'\bid:\s*([^,}]+)')
NAME_TR = re.compile(r'\bname:\s*Translation\.tr\("([^"]+)"\)')
VALID_ID = re.compile(r'^[a-z0-9]+(?:-[a-z0-9]+)*$')

# `GlobalStates.settingsPage = <expression>` up to the end of the statement. The
# negative lookahead keeps `settingsPage === ""` out - a comparison is a read,
# and counting it as a write reports the handler's own guard as a bad producer.
SETTINGS_PAGE_WRITE = re.compile(r'GlobalStates\.settingsPage\s*=(?!=)\s*([^;\n]+)')


def qml_sources():
    for path in sorted(ROOT.rglob("*.qml")):
        if "/tests/" in str(path):
            continue
        yield path


def catalogue_entries():
    """One (line, id, name) per page declared in SettingsContent's `pages`."""
    source = CONTENT.read_text(encoding="utf-8")
    block = re.search(r"property var pages:\s*\{(.*?)\n    \}", source, re.S)
    assert block, "SettingsContent's `pages` catalogue could not be located"
    out = []
    for line in block.group(1).splitlines():
        if "component: Qt.resolvedUrl(" not in line:
            continue
        literal = ID_LITERAL.search(line)
        any_id = ID_ANY.search(line)
        name = NAME_TR.search(line)
        out.append((line.strip(),
                    literal.group(1) if literal else None,
                    any_id.group(1).strip() if any_id else None,
                    name.group(1) if name else None))
    assert out, "no page entries parsed - the catalogue's shape changed"
    return out


class PageCatalogueTests(unittest.TestCase):
    def setUp(self):
        self.entries = catalogue_entries()
        self.ids = [entry[1] for entry in self.entries]

    def test_every_page_declares_an_untranslated_id(self):
        for line, literal, raw, _name in self.entries:
            self.assertIsNotNone(
                literal,
                "a settings page is declared with no plain-string `id:` - it can "
                "only be addressed by its translated name, which is the bug this "
                f"guards against. Give it one: {line}"
                + (f" (its id reads {raw!r})" if raw else ""))
            self.assertRegex(
                literal, VALID_ID,
                f"a page id must be a stable lowercase-hyphen token: {line}")

    def test_a_page_id_is_never_a_translated_string(self):
        for line, _literal, raw, _name in self.entries:
            self.assertNotIn(
                "Translation.tr", raw or "",
                "a page id that goes through Translation.tr moves with the "
                f"user's language, which is exactly what an id is for: {line}")

    def test_page_ids_are_unique(self):
        duplicates = {i for i in self.ids if self.ids.count(i) > 1}
        self.assertEqual(duplicates, set(),
                         "two settings pages share an id, so one of them is "
                         "unreachable by any link")

    def test_every_page_still_has_a_translated_display_name(self):
        for line, _literal, _raw, name in self.entries:
            self.assertIsNotNone(
                name,
                "a page's `name` must stay a Translation.tr() call - it is what "
                f"the sidebar draws and what search matches: {line}")


class DeepLinkResolverTests(unittest.TestCase):
    def setUp(self):
        self.source = CONTENT.read_text(encoding="utf-8")
        match = re.search(
            r"function onSettingsPageChanged\(\) \{(.*?)\n        \}", self.source, re.S)
        self.assertIsNotNone(match, "the settings deep-link handler is gone")
        self.handler = match.group(1)

    def test_the_handler_resolves_the_page_by_id(self):
        self.assertRegex(
            self.handler, r"findIndex\(\s*p\s*=>\s*p\.id\b",
            "the deep-link handler no longer resolves a page by its id")

    def test_the_handler_does_not_look_at_a_page_name(self):
        self.assertNotIn(
            ".name", self.handler,
            "the deep-link handler reads a page's translated display name; a "
            "link matched on it resolves only in English and fails silently in "
            "every other language")


class ProducerTests(unittest.TestCase):
    """Every writer of GlobalStates.settingsPage addresses a real id.

    A half-applied rename is worse than none: the producer that was missed goes
    on sending a display name, which resolves to nothing and reports nothing.
    """

    def setUp(self):
        self.ids = {entry[1] for entry in catalogue_entries()}

    def writes(self):
        for path in qml_sources():
            source = path.read_text(encoding="utf-8")
            for match in SETTINGS_PAGE_WRITE.finditer(source):
                rhs = match.group(1).strip().rstrip(";").strip()
                line = source[:match.start()].count("\n") + 1
                yield f"{path.relative_to(ROOT)}:{line}", rhs

    def test_at_least_two_producers_are_swept(self):
        # The sweep is worthless if the pattern stops matching; the desktop menu
        # and the launcher are the two that exist.
        found = {where.split(":")[0] for where, rhs in self.writes() if rhs != '""'}
        self.assertGreaterEqual(len(found), 2,
                                f"the settingsPage sweep found {found} - it has "
                                "stopped matching real call sites")

    def test_every_literal_deep_link_names_a_declared_page_id(self):
        for where, rhs in self.writes():
            if not rhs.startswith('"'):
                continue
            value = rhs.strip('"')
            if value == "":
                # The handler clearing its own request.
                continue
            page = value.split(":")[0]
            self.assertIn(
                page, self.ids,
                f"{where} deep-links to {page!r}, which is not a page id in "
                "SettingsContent's catalogue. A link is addressed by id, not by "
                "the name printed on the page.")

    def test_a_computed_deep_link_is_built_from_an_id(self):
        for where, rhs in self.writes():
            if rhs.startswith('"'):
                continue
            self.assertIn(
                ".id", rhs,
                f"{where} builds a deep link out of {rhs!r} with no page id in "
                "it - if that is a display name it will stop resolving as soon "
                "as the shell is not in English.")


class LauncherIndexTests(unittest.TestCase):
    def setUp(self):
        self.ids = {entry[1] for entry in catalogue_entries()}
        source = LAUNCHER.read_text(encoding="utf-8")
        block = re.search(r"property var settingsIndex:\s*\[(.*?)\n    \]", source, re.S)
        self.assertIsNotNone(block, "the launcher's settings index is gone")
        self.entries = [line.strip() for line in block.group(1).splitlines()
                        if line.strip().startswith("{")]
        self.assertTrue(self.entries, "no launcher index entries parsed")

    def test_every_indexed_page_carries_a_known_id(self):
        for entry in self.entries:
            literal = ID_LITERAL.search(entry)
            self.assertIsNotNone(literal, f"launcher index entry has no id: {entry}")
            self.assertIn(
                literal.group(1), self.ids,
                f"the launcher indexes {literal.group(1)!r}, which SettingsContent "
                "does not declare - its results would open the settings window "
                "and leave it wherever it already was.")

    def test_every_indexed_page_file_exists(self):
        # The keyword harvest greps this path. grep over a missing file writes
        # nothing and exits non-zero, and the harvester ignores exitCode, so a
        # stale path reads exactly like a page with no sections.
        for entry in self.entries:
            path = re.search(r'path:\s*"([^"]+)"', entry)
            self.assertIsNotNone(path, f"launcher index entry has no path: {entry}")
            self.assertTrue((PAGES / path.group(1)).is_file(),
                            f"{path.group(1)} is indexed but missing from pages/")


class SearchStaysTranslatedTests(unittest.TestCase):
    """Navigation moved to ids. Search must not follow it.

    The user types the words on their screen, and on a translated shell those
    are the `Translation.tr` names - so matching an id here would make the
    search field useless in every language but English.
    """

    def setUp(self):
        self.source = CONTENT.read_text(encoding="utf-8")

    def body(self, signature):
        match = re.search(re.escape(signature) + r"\s*\{(.*?)\n    \}", self.source, re.S)
        self.assertIsNotNone(match, f"{signature} is gone")
        return match.group(1)

    def test_page_matching_compares_the_translated_name(self):
        body = self.body("function pageMatches(pageIndex, page)")
        self.assertIn("normalized(page.name)", body,
                      "settings search stopped matching the page's display name")
        self.assertNotIn("page.id", body,
                         "settings search matches the page id - the user types "
                         "the name they can see, not an internal token")

    def test_first_match_navigation_compares_the_translated_name(self):
        body = self.body("function navigateFirstMatch()")
        self.assertIn("pages[pageIndex].name", body,
                      "Enter in the search field stopped matching display names")

    def test_the_launcher_filters_on_the_display_name(self):
        source = LAUNCHER.read_text(encoding="utf-8")
        self.assertIn("page.name.toLowerCase().includes(query)", source,
                      "the launcher's settings search stopped matching the "
                      "page's display name")


if __name__ == "__main__":
    unittest.main(verbosity=1)
