#!/usr/bin/env python3
"""Notification timeouts: the app's expire_timeout is a request, not an order.

Some apps ask for absurd display times, or 0 for "never dismiss". The
`notifications.respectAppTimeout` option (default on, the old behaviour)
lets the shell's own `timeout` win over whatever the app asked for.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "services/Notifications.qml"
CONFIG = ROOT / "modules/common/Config.qml"
PAGE = ROOT / "modules/imi/settings/pages/NotificationsConfig.qml"


def _strip(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


class NotificationTimeoutPolicy(unittest.TestCase):
    def test_the_option_exists_and_defaults_to_the_old_behaviour(self):
        cfg = _strip(CONFIG.read_text())
        block = cfg[cfg.index("property JsonObject notifications:"):]
        self.assertRegex(block, r"property bool respectAppTimeout:\s*true")

    def test_the_service_lets_the_shell_timeout_win_when_asked(self):
        src = _strip(SERVICE.read_text())
        self.assertIn("notifications.respectAppTimeout", src)
        # Off: even expire_timeout == 0 ("never") gets a timer ...
        self.assertRegex(src, r"if \(!respectApp \|\| notification\.expireTimeout != 0\)")
        # ... and the interval is the shell's, whatever the app asked for.
        self.assertRegex(src, r"\(!respectApp \|\| notification\.expireTimeout < 0\) \? shellTimeout")

    def test_settings_exposes_the_switch_beside_the_timeout_spinner(self):
        page = PAGE.read_text()
        switch = page.index("notifications.respectAppTimeout")
        spinner = page.index("Timeout duration (if not defined by notification)")
        self.assertLess(switch, spinner, "the policy switch sits right above the duration it governs")


if __name__ == "__main__":
    unittest.main()
