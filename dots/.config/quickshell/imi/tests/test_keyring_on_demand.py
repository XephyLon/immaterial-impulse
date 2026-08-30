#!/usr/bin/env python3
"""The keyring loads on demand, so every demand has to ask.

KeyringStorage does not read the keyring at startup - the lock screen, the
Google Cloud service and the AI chat ask for it when they need a key. The
custom-provider path did not: with a local model selected nothing loaded the
keyring, the settings page's key fields read "" and dropped what was typed
into them, and every "Fetch Models" went out with an empty bearer - a 401
the page called "Failed to fetch", whatever key the user had entered. A user's
last successful key save dated from the last time something else had loaded
it, a week earlier.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PAGE = ROOT / "modules/imi/settings/pages/ServicesConfig.qml"
AI = ROOT / "services/Ai.qml"
KEYRING = ROOT / "services/KeyringStorage.qml"


def code(path):
    return re.sub(r"//[^\n]*", "", path.read_text())


class KeyringOnDemandTests(unittest.TestCase):
    def test_the_keyring_is_still_loaded_on_demand(self):
        """If this ever loads at startup, the two asks below become moot -
        and this test should be retired with them, not worked around."""
        self.assertNotIn("Component.onCompleted", code(KEYRING),
                         "KeyringStorage now loads itself; retire the on-demand asks")

    def test_the_ai_settings_page_asks_for_the_keyring(self):
        text = code(PAGE)
        self.assertRegex(text, r"Component\.onCompleted:\s*\{[^}]*KeyringStorage\.fetchKeyringData\(\)",
                         "ServicesConfig must ask for the keyring when it opens")

    def test_the_custom_model_fetch_waits_for_the_keyring(self):
        text = code(AI)
        body = text.split("function fetchCustomModels()", 1)[1]
        self.assertIn("if (!KeyringStorage.loaded)", body[:600],
                      "fetchCustomModels must check the keyring before reading keys")
        self.assertIn("KeyringStorage.fetchKeyringData()", body[:600])
        self.assertIn("function onLoadedChanged()", text,
                      "the fetch has to re-run once the keyring arrives")


if __name__ == "__main__":
    unittest.main()
