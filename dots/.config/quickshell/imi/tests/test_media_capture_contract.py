#!/usr/bin/env python3
"""The privacy indicator's capture detection is event-driven.

MediaCapture polled `pactl -f json list source-outputs` and
`fuser /dev/video*` every two seconds, all day - a spawn per second from a
shell that weighs gigabytes, for a state that changes when a call starts.
It now subscribes: `pactl subscribe` for source-outputs, inotify on the
V4L2 nodes for the camera, with the poll kept as a slow safety net.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "services/MediaCapture.qml"
CONFIG = ROOT / "modules/common/Config.qml"


def _strip(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


class MediaCaptureContract(unittest.TestCase):
    def setUp(self):
        self.src = _strip(SERVICE.read_text())

    def test_mic_changes_arrive_by_subscription(self):
        self.assertIn('command: ["pactl", "subscribe"]', self.src)
        self.assertRegex(self.src, r'indexOf\("source-output"\)')

    def test_camera_changes_arrive_by_inotify_with_a_quiet_fallback(self):
        self.assertIn("inotifywait -m -q -e open -e close", self.src)
        self.assertIn("command -v inotifywait >/dev/null 2>&1 || exit 0", self.src,
                      "a box without inotify-tools must fall back to the poll, not log errors")

    def test_the_poll_is_a_safety_net_not_the_fast_path(self):
        cfg = _strip(CONFIG.read_text())
        block = cfg[cfg.index("property JsonObject privacyIndicator"):]
        m = re.search(r"property int pollInterval:\s*(\d+)", block)
        self.assertIsNotNone(m)
        self.assertGreaterEqual(int(m.group(1)), 10000, "the poll is back to being the fast path")


if __name__ == "__main__":
    unittest.main()
