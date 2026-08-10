#!/usr/bin/env python3
"""Settings search matches a hand-written index, so the index has to be checked
against the pages it claims to describe.

`SettingsContent.qml` carries a `sections:` list per page and
`pageMatches()` searches the page name and that list — nothing else. A section
rendered on a page but absent from the list is unreachable by search, and the
failure is silent in both directions: the sidebar filters every page out, and the
content pane keeps showing whatever page was already open, so the search looks
like it ran and found the page you were on.

It had drifted to **32 missing titles**. Every `ContentSubsection` in the whole
settings tree was missing, because the index only ever carried top-level
`ContentSection` names — so "Parallax", "Keyboard", "Touchpad", "Security",
"Web search" and "Corner open" were all untypeable. A user searching for a
setting they can see on screen got nothing.

Adding the missing strings is not the fix; they would drift again the next time
someone adds a subsection. This test is the fix.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT / "modules/imi/settings/SettingsContent.qml"
PAGES = ROOT / "modules/imi/settings/pages"

# `ContentSubsection { ... title: Translation.tr("X") }`.
# Bounded so a title further down the file cannot be attributed to a section
# header far above it.
SUBSECTION_TITLE = re.compile(
    r'ContentSubsection\s*\{(?:.{0,400}?)title:\s*Translation\.tr\("([^"]+)"\)', re.S)
PAGE_ENTRY = re.compile(
    r'component:\s*Qt\.resolvedUrl\("pages/(\w+\.qml)"\),\s*sections:\s*\[(?:.*?)\]'
    r'(?:,\s*searchTerms:\s*\[(.*?)\])?\s*\}', re.S)
TRANSLATED = re.compile(r'Translation\.tr\("([^"]+)"\)')


class SettingsSearchIndexTests(unittest.TestCase):
    def setUp(self):
        self.content = CONTENT.read_text(encoding="utf-8")
        self.index = {m.group(1): TRANSLATED.findall(m.group(2) or "")
                      for m in PAGE_ENTRY.finditer(self.content)}
        self.assertTrue(self.index, "no page entries parsed - the model's shape changed")

    def rendered_titles(self, page_file: str):
        """Subsections only. Top-level sections live in `sections:`, which is the
        sidebar's navigation metadata and is pinned separately by
        test_settings_navigation.py - putting a subsection there would make it a
        tree branch, which is why search needed an index of its own."""
        src = (PAGES / page_file).read_text(encoding="utf-8")
        seen, out = set(), []
        for match in SUBSECTION_TITLE.finditer(src):
            title = match.group(1)
            if title not in seen:
                seen.add(title)
                out.append(title)
        return out

    def test_every_rendered_section_is_searchable(self):
        missing = []
        for page_file, indexed in sorted(self.index.items()):
            known = set(indexed)
            for title in self.rendered_titles(page_file):
                if title not in known:
                    missing.append(f"{page_file}: {title!r}")
        self.assertEqual(
            missing, [],
            "these sections render but cannot be found by search. Add them to the "
            "page's `searchTerms:` list in SettingsContent.qml - a heading the index "
            "does not name is invisible, and the search reports nothing rather "
            "than failing visibly.")

    def test_the_index_does_not_name_sections_that_are_gone(self):
        """The other direction: a renamed section leaves a dead search term that
        matches a page which no longer contains it."""
        stale = []
        for page_file, indexed in sorted(self.index.items()):
            rendered = set(self.rendered_titles(page_file))
            if not rendered:
                # A page whose sections are built dynamically; nothing to check.
                continue
            for title in indexed:
                if title not in rendered:
                    stale.append(f"{page_file}: {title!r}")
        self.assertEqual(
            stale, [],
            "these titles are indexed but no longer rendered - searching them "
            "navigates to a page that does not contain them.")

    def test_every_indexed_page_file_exists(self):
        for page_file in sorted(self.index):
            self.assertTrue((PAGES / page_file).is_file(),
                            f"{page_file} is indexed but missing from pages/")


if __name__ == "__main__":
    unittest.main()
