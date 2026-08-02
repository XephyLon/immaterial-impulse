#!/usr/bin/env python3
"""Static guards on the note store's ownership and on note text being inert.

Two properties here are easy to undo by accident and expensive to notice:

  * One owner. The bundled notes plugin, which is instantiated once per
    monitor, and the overlay notes editor both used to hold their own FileView
    over the same file. Giving either one back a FileView reintroduces surfaces
    that disagree with each other about what the user wrote.

  * Note bodies are user content read off disk, and `StyledText` is a bare
    `Text` with no `textFormat`, so it inherits `Text.AutoText` and renders
    markup. Every place a note is displayed or edited must say PlainText.

The behavioural halves are `NotesSurfacesRuntimeTest.qml` and
`tests/test_notes_migration_runtime.py`.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "services/Notes.qml"
STORE_JS = ROOT / "modules/common/functions/notesStore.js"
WIDGET = ROOT / "modules/common/plugins/bundled/notes/Widget.qml"
OVERLAY = ROOT / "modules/imi/overlay/notes/NotesContent.qml"
FILTER_CHIP = ROOT / "modules/common/widgets/FilterChip.qml"
CONFIG = ROOT / "modules/common/Config.qml"
DIRECTORIES = ROOT / "modules/common/Directories.qml"


def read(path):
    return path.read_text()


class NoteStoreOwnershipTest(unittest.TestCase):
    def test_the_service_owns_notespath(self):
        source = read(SERVICE)
        self.assertIn("property string filePath: Directories.notesPath", source)
        self.assertIn("property string legacyFilePath: Directories.desktopNotesPath",
                      source)

    def test_the_service_parses_through_the_shared_store_logic(self):
        self.assertIn('import "../modules/common/functions/notesStore.js" as NotesStore',
                      read(SERVICE))
        self.assertTrue(STORE_JS.exists())

    def test_the_legacy_store_is_never_written(self):
        source = read(SERVICE)
        self.assertNotIn("legacyNotesFileView.setText", source)
        # ...nor removed by anything else in the shell.
        for path in (SERVICE, WIDGET, OVERLAY):
            self.assertNotRegex(read(path), r"(rm|unlink|remove).{0,40}desktopNotesPath")

    def test_neither_surface_opens_the_store_itself(self):
        for path in (WIDGET, OVERLAY):
            source = read(path)
            self.assertNotIn("FileView", source,
                             f"{path.name} must go through the Notes singleton")
            self.assertNotIn("Directories.notesPath", source)

    def test_both_surfaces_read_and_write_the_same_singleton(self):
        for path in (WIDGET, OVERLAY):
            source = read(path)
            self.assertIn("import qs.services", source)
            self.assertIn("Notes.deleteNote", source)
        self.assertIn("Notes.addNote", read(WIDGET))
        self.assertIn("Notes.addNote", read(OVERLAY))

    def test_directories_still_owns_both_paths(self):
        source = read(DIRECTORIES)
        self.assertIn("property string notesPath:", source)
        self.assertIn("property string desktopNotesPath:", source)


class NoteMigrationMarkerTest(unittest.TestCase):
    def test_the_marker_exists_in_the_config_schema(self):
        self.assertIn("property bool importedLegacyStore: false", read(CONFIG))

    def test_the_marker_is_written_after_the_store(self):
        source = read(SERVICE)
        write = source.index("notesFileView.setText(JSON.stringify(root.list))",
                             source.index("function tryMigrate"))
        marker = source.index("Config.options.notes.importedLegacyStore = true")
        self.assertLess(write, marker,
                        "a launch that dies mid-migration must migrate again, "
                        "not record an import that never landed")

    def test_the_import_is_gated_on_the_marker(self):
        self.assertIn("const importLegacy = !Config.options.notes.importedLegacyStore",
                      read(SERVICE))

    def test_migration_waits_for_both_stores_and_the_config(self):
        self.assertIn(
            "if (root.ready || !root.primaryLoaded || !root.legacyLoaded || !Config.ready)",
            read(SERVICE))


class NoteTextIsInertTest(unittest.TestCase):
    """Every note body reaches the screen as plain text."""

    def _assert_plain_text_near(self, path, anchor, window=12):
        lines = read(path).splitlines()
        for index, line in enumerate(lines):
            if anchor in line:
                block = "\n".join(lines[max(0, index - window):index + window])
                self.assertRegex(
                    block, r"textFormat:\s*(Text|TextEdit)\.PlainText",
                    f"{path.name}: '{anchor}' renders a note without PlainText")
                return
        self.fail(f"{path.name}: never found '{anchor}'")

    def test_the_widget_list_row_is_plain(self):
        self._assert_plain_text_near(WIDGET, "text: noteRow.modelData.content")

    def test_the_widget_editor_is_plain(self):
        self._assert_plain_text_near(WIDGET, "id: editArea")

    def test_the_overlay_editor_is_plain(self):
        self._assert_plain_text_near(OVERLAY, "id: textInput")

    # The overlay labels its chips with the note's own first line.
    def test_the_chip_label_is_plain(self):
        self._assert_plain_text_near(FILTER_CHIP, "text: chip.label")

    def test_no_note_body_reaches_a_richtext_display(self):
        for path in (WIDGET, OVERLAY):
            self.assertNotRegex(
                read(path), r"textFormat:\s*(Text|TextEdit)\.(RichText|StyledText|MarkdownText)")


class NoteStoreLogicTest(unittest.TestCase):
    def test_corrupt_input_is_never_reset_to_empty(self):
        source = read(STORE_JS)
        self.assertIn("return [noteFromText(text)];", source,
                      "unparseable store content must survive as a note")

    def test_the_widget_keeps_its_grid_span(self):
        source = read(WIDGET)
        self.assertIn("Appearance.sizes.widgetGridSpanX(2)", source)
        self.assertIn("Appearance.sizes.widgetGridSpanY(2)", source)

    def test_the_store_logic_has_no_qml_dependencies(self):
        # It is a .pragma library so the unit tests can call it directly.
        source = read(STORE_JS)
        self.assertTrue(source.lstrip().startswith(".pragma library"))
        self.assertIsNone(re.search(r"^\s*import ", source, re.MULTILINE))


if __name__ == "__main__":
    unittest.main()
