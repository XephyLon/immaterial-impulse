#!/usr/bin/env python3
"""Inline answers in the launcher: opt-in, local-first, never on the keystroke path.

`services/AiInline.qml` answers a `@question` in one sentence under the Ask
row. This pins the shape that keeps it safe: the config keys default off; the
gate needs a usable model AND (loopback endpoint OR the cloud switch); the
launcher drives it from onQueryChanged (like the qalc spawn), never from the
results builder, and the row binds to it directly so a streaming answer never
rebuilds the list; Enter carries an existing answer into the chat instead of
asking again; the answer is bounded; AiInline never touches the chat's
requester or strategy instances. The runtime half (a fake OpenAI-compatible
server, a real shell) is tests/test_ai_inline_runtime.py.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INLINE = ROOT / "services/AiInline.qml"
SEARCH = ROOT / "services/LauncherSearch.qml"
ITEM = ROOT / "modules/imi/overview/SearchItem.qml"
CONFIG = ROOT / "modules/common/Config.qml"
PAGE = ROOT / "modules/imi/settings/pages/ServicesConfig.qml"


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


class InlineAnswerContract(unittest.TestCase):
    def setUp(self):
        self.inline = _strip(INLINE.read_text())
        self.search = _strip(SEARCH.read_text())
        self.item = _strip(ITEM.read_text())

    def test_config_defaults_off_and_names_the_cloud_switch(self):
        cfg = _strip(CONFIG.read_text())
        block = cfg[cfg.index("property JsonObject search: JsonObject"):]
        block = _block(block, "property JsonObject ai: JsonObject {")
        self.assertRegex(block, r"property bool inline:\s*false", "inline sends keystrokes: off by default")
        self.assertRegex(block, r"property bool inlineWithCloud:\s*false", "cloud costs money: a second, separate switch")
        self.assertRegex(block, r"property int inlineDelayMs:\s*700")
        self.assertRegex(block, r"property int inlineMinWords:\s*3")

    def test_the_gate_is_opt_in_usable_and_local_or_cloud_switch(self):
        gate = self.inline[self.inline.index("readonly property bool allowed:"):]
        gate = gate[:gate.index("\n\n")]
        self.assertIn("Config.options.search.ai.inline", gate)
        self.assertIn("Ai.currentModelHasApiKey", gate)
        self.assertIn("root.modelIsLocal || (Config.options.search.ai.inlineWithCloud", gate)
        local = self.inline[self.inline.index("readonly property bool modelIsLocal:"):]
        local = local[:local.index("\n")]
        for host in ("localhost", r"127\.0\.0\.1", r"\[::1\]"):
            self.assertIn(host, local)
        self.assertNotIn("requires_key", local, "keyless is not local: a remote keyless server still receives keystrokes")

    def test_driven_from_the_query_handler_never_from_the_builder(self):
        on_query = _block(self.search, "onQueryChanged: {")
        self.assertIn("root.refreshInlineAnswer()", on_query)
        builder = _block(self.search, "function buildResults() {")
        self.assertNotIn("AiInline", builder, "the results build runs per keystroke; no request may start from it")
        refresh = _block(self.search, "function refreshInlineAnswer() {")
        self.assertIn("AiInline.ask(StringUtils.cleanPrefix(root.query, aiPrefix))", refresh)
        self.assertIn("AiInline.cancel()", refresh)
        self.assertIn("function onOverviewOpenChanged() {\n            if (!GlobalStates.overviewOpen) AiInline.cancel();", self.search)

    def test_the_row_binds_to_the_singleton_and_the_builder_tags_the_row(self):
        self.assertIn('id: "ask-assistant"', self.search)
        self.assertIn('root.entry?.id === "ask-assistant"', self.item)
        self.assertIn("AiInline.question === root.itemName", self.item)
        self.assertIn("text: AiInline.answer !== \"\" ? AiInline.answer :", self.item)

    def test_enter_carries_an_existing_answer_into_the_chat(self):
        ask = _block(self.search, "function askAssistant(question) {")
        self.assertIn("const inlineAnswer = AiInline.take(text);", ask)
        self.assertIn("AiSessions.mint(text);", ask)
        self.assertIn('Ai.addMessage(text, "user");', ask)
        self.assertIn('Ai.addMessage(inlineAnswer, "assistant");', ask)
        self.assertIn("Ai.sendUserMessage(text);", ask)
        # The ordinary send is the fallback, not a second request on top.
        self.assertLess(ask.index('Ai.addMessage(inlineAnswer, "assistant");'), ask.index("Ai.sendUserMessage(text);"))
        self.assertIn("return;", ask[ask.index('Ai.addMessage(inlineAnswer, "assistant");'):ask.index("Ai.sendUserMessage(text);")])

    def test_debounced_bounded_and_isolated_from_the_chat(self):
        self.assertIn("debounce.restart()", self.inline)
        self.assertIn("Config.options.search.ai.inlineDelayMs", self.inline)
        self.assertIn("readonly property int maxChars: 200", self.inline)
        self.assertIn("root.answer.length >= root.maxChars", self.inline)
        self.assertRegex(self.inline, r'"tools"|\[\], \[\]\)', "no tools on the inline request")
        for forbidden in ("Ai.addMessage", "Ai.sendUserMessage", "Ai.currentApiStrategy", "Ai.apiStrategies", "requester.", "Ai.messageIDs"):
            self.assertNotIn(forbidden, self.inline, f"AiInline must not touch the chat: {forbidden}")
        for dialect in ("OpenAiApiStrategy {", "GeminiApiStrategy {", "MistralApiStrategy {", "AnthropicApiStrategy {"):
            self.assertIn(dialect, self.inline, "own strategy instances: a shared one carries tool-call state between lines")
        self.assertIn('readonly property string apiKeyEnvVarName: "API_KEY"', self.inline, "Gemini's strategy reads root.apiKeyEnvVarName unqualified")
        self.assertIn("one short sentence", self.inline)

    def test_settings_rows_come_and_go_with_rowvisible(self):
        page = _strip(PAGE.read_text())
        self.assertIn("Config.options.search.ai.inline = !Config.options.search.ai.inline", page)
        cloud = page[page.index("Config.options.search.ai.inlineWithCloud") - 400:page.index("Config.options.search.ai.inlineWithCloud")]
        self.assertIn("property bool rowVisible: Config.options.search.ai.inline", cloud)
        self.assertIn("Config.options.search.ai.inlineDelayMs = newValue", page)


if __name__ == "__main__":
    unittest.main()
