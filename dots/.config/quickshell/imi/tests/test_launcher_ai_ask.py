#!/usr/bin/env python3
"""The assistant in the overview: an "Ask" row, never a request while typing.

`@question` offers an Ask row under its own prefix; with `search.ai.fallthrough`
on, a long query nothing else matched gets the same row last. The row exists
only while the selected model is usable, Enter opens the Intelligence tab and
sends, and nothing is sent before Enter. The static half lives here; the
runtime half (a real shell, a keyless probe model) is
tests/test_launcher_ask_runtime.py.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEARCH = ROOT / "services/LauncherSearch.qml"
BAR = ROOT / "modules/imi/overview/SearchBar.qml"
WIDGET = ROOT / "modules/imi/overview/SearchWidget.qml"
CONFIG = ROOT / "modules/common/Config.qml"
PAGE = ROOT / "modules/imi/settings/pages/ServicesConfig.qml"


def _strip(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


class AskRowContract(unittest.TestCase):
    def setUp(self):
        self.search = _strip(SEARCH.read_text())
        self.build = self.search[self.search.index("function buildResults()"):]

    def test_config_declares_the_prefix_and_the_opt_in_fallthrough(self):
        cfg = _strip(CONFIG.read_text())
        prefix = cfg[cfg.index("property JsonObject prefix: JsonObject"):]
        self.assertRegex(prefix, r'property string ai:\s*"@"')
        block = cfg[cfg.index("property JsonObject search: JsonObject"):]
        block = block[block.index("property JsonObject ai: JsonObject"):]
        self.assertRegex(block, r"property bool fallthrough:\s*false", "fallthrough changes what Enter does on a miss: off by default")
        self.assertRegex(block, r"property int fallthroughMinWords:\s*4")

    def test_the_row_exists_only_for_a_usable_model(self):
        self.assertIn("Ai.currentModelHasApiKey", self.build)
        self.assertRegex(self.build, r"const aiUsable = !!aiModel && Ai\.currentModelHasApiKey")
        self.assertRegex(self.build, r"aiUsable && aiQuestion\.length > 0\) \? resultComp\.createObject")

    def test_nothing_is_sent_while_typing(self):
        # The only call into Ai from the builder is a read; the send lives in
        # askAssistant, reached from the row's execute closure.
        builder_sends = re.findall(r"Ai\.(sendUserMessage|makeRequest)", self.build[:self.build.index("function askAssistant")])
        self.assertEqual(builder_sends, [])
        self.assertIn("execute: () => {\n                root.askAssistant(aiQuestion);", self.search)
        ask = self.search[self.search.index("function askAssistant"):]
        self.assertIn('GlobalStates.sidebarLeftTab = "intelligence"', ask)
        self.assertIn("GlobalStates.sidebarLeftOpen = true", ask)
        self.assertIn("Ai.sendUserMessage(text)", ask)

    def test_the_prefix_wins_and_the_fallthrough_is_last_and_gated(self):
        self.assertIn("else if (startsWithAiPrefix && aiResultObject) {\n            result.push(aiResultObject);", self.build)
        fall = self.build[self.build.index("Fallthrough") if "Fallthrough" in self.build else self.build.index("Config.options.search.ai.fallthrough"):]
        for guard in ("appResultObjects.length === 0", "settingsResults.length === 0",
                      "launcherActionObjects.length === 0", "fallthroughMinWords"):
            self.assertIn(guard, fall, guard)

    def test_the_builder_observes_what_it_reads(self):
        inputs = self.search[self.search.index("readonly property var resultInputs: ["):self.search.index("onResultInputsChanged")]
        for key in ("Config.options.search.prefix.ai", "Config.options.search.ai.fallthrough",
                    "Ai.models", "Ai.currentModelId", "Ai.currentModelHasApiKey"):
            self.assertIn(key, inputs, key)

    def test_the_bar_and_the_query_highlight_know_the_prefix(self):
        bar = _strip(BAR.read_text())
        self.assertIn("Ai, DefaultSearch", bar)
        self.assertIn("SearchBar.SearchPrefixType.Ai", bar)
        self.assertRegex(bar, r'case SearchBar\.SearchPrefixType\.Ai: return "star_shine"')
        widget = WIDGET.read_text()
        self.assertIn("Config.options.search.prefix.webSearch, Config.options.search.prefix.ai])", widget)

    def test_settings_exposes_the_prefix_and_the_switch(self):
        page = PAGE.read_text()
        self.assertIn("Config.options.search.prefix.ai", page)
        self.assertIn("Config.options.search.ai.fallthrough", page)


if __name__ == "__main__":
    unittest.main()
