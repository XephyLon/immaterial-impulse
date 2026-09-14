#!/usr/bin/env python3
"""The Ollama catalog talks to the daemon's HTTP API and starts nothing on
its own.

OllamaCatalog reaches /api/tags, /api/ps, /api/pull and /api/delete through
curl - never the `ollama` CLI - refreshes only while a view is watching, and
the only process it starts besides curl is the daemon, behind the explicit
Start button. The browse page asks before a pull (size and free space) and
refuses one that would not fit on disk.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "services/OllamaCatalog.qml"
PAGE = ROOT / "modules/imi/sidebarLeft/aiChat/OllamaBrowsePage.qml"
BROWSER = ROOT / "modules/imi/sidebarLeft/aiChat/BrowseModelsView.qml"
AI = ROOT / "services/Ai.qml"


def _strip(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


class OllamaCatalogContract(unittest.TestCase):
    def setUp(self):
        self.svc = _strip(SERVICE.read_text())
        self.page = _strip(PAGE.read_text())

    def test_the_daemon_api_not_the_cli(self):
        for endpoint in ("/api/tags", "/api/ps", "/api/pull", "/api/delete"):
            self.assertIn(endpoint, self.svc, endpoint)
        self.assertNotRegex(self.svc, r'\["ollama"', "no ollama CLI calls")
        self.assertNotRegex(self.svc, r'"ollama (pull|rm|list|ps)', "no ollama CLI calls")

    def test_refresh_is_gated_on_a_watcher_and_nothing_polls_alone(self):
        timer = self.svc[self.svc.index("Timer {"):]
        timer = timer[:timer.index("}")]
        self.assertIn("running: root.watchers > 0", timer)
        self.assertIn("Component.onCompleted: OllamaCatalog.watchers++", self.page)
        self.assertIn("Component.onDestruction: OllamaCatalog.watchers--", self.page)

    def test_the_only_non_curl_process_is_the_explicit_start(self):
        # The first argv element of every command the service can start.
        heads = re.findall(r'command:\s*\[\s*"([^"]+)"', self.svc)
        self.assertTrue(heads, "no commands parsed - the Process shape changed")
        for head in heads:
            self.assertIn(head, ("curl", "sh"), head)
        self.assertEqual(heads.count("sh"), 2, "df for free space, systemctl for the explicit start - nothing else")
        self.assertIn("systemctl --user start ollama.service", self.svc)
        self.assertIn("df -Pk", self.svc)
        self.assertNotIn("ollama serve", self.svc)

    def test_a_pull_asks_first_and_checks_disk(self):
        self.assertIn("if (root.armed !== ref) { root.armed = ref; return; }", self.page)
        self.assertIn("need > OllamaCatalog.diskFreeBytes", self.page)
        self.assertIn("Click again", self.page)

    def test_the_browser_hosts_the_page_behind_a_source_switch(self):
        browser = _strip(BROWSER.read_text())
        self.assertIn('readonly property bool ollamaMode: root.source === "ollama"', browser)
        self.assertIn("OllamaBrowsePage {", browser)
        self.assertIn("visible: root.ollamaMode", browser)

    def test_the_chat_can_refresh_and_forget_local_models(self):
        ai = _strip(AI.read_text())
        self.assertIn("function refreshOllamaModels()", ai)
        self.assertIn("function forgetOllamaModel(modelName)", ai)
        self.assertIn("Ai.refreshOllamaModels()", self.page)
        self.assertIn("Ai.forgetOllamaModel(name)", self.page)


if __name__ == "__main__":
    unittest.main()
