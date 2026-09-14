#!/usr/bin/env python3
"""The config split, stage 1: `Config.options` is an aggregator, appearance has
its own file, and everything outside the shell that reads appearance.* reads
that file first.

Pins: every top-level property declared on either adapter is an alias on the
aggregator and named in `Config.domains` (a domain that is declared but not
aliased silently vanishes from `Config.options`); the appearance block lives
on its own adapter behind its own FileView and is no longer on the main one;
`ready` waits for both files; the split takes the downgrade copy before it
writes; Directories creates config.d; switchwall, applycolor and presets read
config.d/appearance.json first. The runtime half is
tests/test_config_split_runtime.py.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "modules/common/Config.qml"
DIRECTORIES = ROOT / "modules/common/Directories.qml"
SCRIPTS = {
    "switchwall": ROOT / "scripts/colors/switchwall.sh",
    "applycolor": ROOT / "scripts/colors/applycolor.sh",
    "presets": ROOT / "scripts/presets.sh",
}


def _strip(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def _block(source, opener):
    start = source.index(opener) + len(opener)
    depth = 1
    for i in range(start, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return source[start:i]
    raise AssertionError(f"unterminated block after {opener!r}")


def _top_level_props(adapter_body):
    return re.findall(r"^            property (?:JsonObject|string|bool|int|real|list<[^>]+>|var) ([A-Za-z_]\w*)\s*:",
                      adapter_body, re.M)


class ConfigSplitContract(unittest.TestCase):
    def setUp(self):
        self.src = _strip(CONFIG.read_text())
        self.main = _block(self.src, "JsonAdapter {\n            id: configOptionsJsonAdapter")
        self.appearance = _block(self.src, "JsonAdapter {\n            id: appearanceAdapter")
        self.aggregate = _block(self.src, "QtObject {\n        id: aggregate")

    def test_every_declared_domain_is_aliased_and_listed(self):
        main_props = _top_level_props(self.main)
        app_props = _top_level_props(self.appearance)
        self.assertEqual(app_props, ["appearance"])
        self.assertNotIn("appearance", main_props, "appearance left the main adapter")
        aliases = dict(re.findall(r"property alias (\w+): (\w+\.\w+)", self.aggregate))
        for name in main_props:
            self.assertEqual(aliases.get(name), f"configOptionsJsonAdapter.{name}", name)
        self.assertEqual(aliases.get("appearance"), "appearanceAdapter.appearance")
        self.assertEqual(set(aliases), set(main_props) | {"appearance"}, "no alias without a declaration")
        domains = re.search(r"readonly property list<string> domains: \[([^\]]*)\]", self.src).group(1)
        listed = set(re.findall(r'"(\w+)"', domains))
        self.assertEqual(listed, set(aliases), "Config.domains enumerates exactly the aliased domains")
        self.assertIn("property alias options: aggregate", self.src)

    def test_ready_waits_for_both_files_and_the_split_backs_up_first(self):
        self.assertIn("if (root.ready || !root.mainLoaded || !root.appearanceLoaded) return;", self.src)
        self.assertNotIn("root.ready = true;\n            root.clearStaleKbOptions();", self.src,
                         "the migrations run from finishLoad, after both files")
        self.assertIn("path: root.mainLoaded ? root.appearanceFilePath : \"\"", self.src)
        self.assertIn('command: ["cp", "-n", root.filePath, `${root.filePath}.pre-split-${Qt.formatDate(new Date(), "yyyy-MM-dd")}`]', self.src)
        # The split writes the file only after the copy has exited.
        backup = _block(self.src, "Process {\n        id: preSplitBackup")
        self.assertIn('appearanceFileView.setText(JSON.stringify({ "appearance": root.legacyAppearance }, null, 2))', backup)
        self.assertNotIn("appearanceFileView.setText", _block(self.src, "FileView {\n        id: appearanceFileView"),
                         "the FileView itself never writes the split before the copy")
        # A timed-out directory migration never creates the file.
        self.assertIn("if (root.configDirTimedOut) {\n                    root.appearanceLoaded = true;", self.src)
        self.assertIn('Quickshell.execDetached(["mkdir", "-p", `${root.shellConfig}/config.d`])', DIRECTORIES.read_text())

    def test_scripts_read_the_split_file_first(self):
        for name, path in SCRIPTS.items():
            text = path.read_text()
            self.assertIn("config.d/appearance.json", text, name)
        sw = SCRIPTS["switchwall"].read_text()
        self.assertIn("jq -r '.appearance.wallpaperTheming.enableQtApps' \"$APPEARANCE_CONFIG_FILE\"", sw)
        self.assertNotRegex(sw, r"\.appearance\.[^\n]*\$SHELL_CONFIG_FILE", "no appearance read from, or write into, config.json")
        self.assertIn("'.appearance.palette.accentColor = $color' \"$APPEARANCE_CONFIG_FILE\" > \"$APPEARANCE_CONFIG_FILE.tmp\"", sw)
        ac = SCRIPTS["applycolor"].read_text()
        self.assertIn("jq -r '.appearance.wallpaperTheming.enableTerminal' \"$APPEARANCE_CONFIG_FILE\"", ac)
        self.assertIn('--config "$APPEARANCE_CONFIG_FILE"', ac)
        pr = SCRIPTS["presets"].read_text()
        self.assertIn("jq 'del(.appearance)' \"${CONFIG_FILE}.merged\"", pr)
        self.assertIn("{appearance: (.appearance // {})}", pr)


if __name__ == "__main__":
    unittest.main()
