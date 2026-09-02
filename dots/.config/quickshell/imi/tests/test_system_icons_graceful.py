#!/usr/bin/env python3
"""The System Icons bar widget never snaps an icon in or out.

Recorded: the notification bell, a Loader with `visible: active`, was gone
between two frames a sixth of a second apart and the icons beside it jumped
left to close the gap. The mic-mute icon beside it had always slid closed
through a Revealer. Bluetooth and VPN toggled a bare `visible:` the same way
the bell did. The rule the repo already has - elements enter and leave
gracefully - applies to every icon here that comes and goes: it lives inside
a Revealer, which follows the bar's orientation, and the bell's Loader stays
loaded while the revealer is still closing over it. The badge on the bell is
a Presence, so the dot fades when the last unread is read.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
ICONS = ROOT / "modules/imi/bar/SystemIcons.qml"
COUNT = ROOT / "modules/imi/bar/NotificationUnreadCount.qml"


def strip_comments(text):
    return re.sub(r"//[^\n]*", "", text)


class SystemIconsGracefulTests(unittest.TestCase):
    def setUp(self):
        self.icons = strip_comments(ICONS.read_text(encoding="utf-8"))
        self.count = strip_comments(COUNT.read_text(encoding="utf-8"))

    def test_no_icon_in_the_row_toggles_visible_on_a_state(self):
        grid = self.icons[self.icons.index("GridLayout {"):]
        # Direct children of the grid sit at 8 spaces; a `visible:` at 12 is
        # one of them deciding to snap.
        self.assertNotRegex(grid, r"\n {12}visible:",
                            "an icon in the row toggles `visible:` on a state, which snaps it in and out")

    def test_every_state_driven_icon_is_inside_a_revealer(self):
        for state in ("BluetoothStatus.available", "Vpn.anyActive", "Notifications.silent || Notifications.unread > 0"):
            self.assertRegex(self.icons, r"Revealer \{[^}]*reveal: " + re.escape(state),
                             f"{state} must drive a Revealer, not a `visible:`")

    def test_every_revealer_follows_the_bars_orientation(self):
        revealers = re.findall(r"Revealer \{(.*?)\n {12}[A-Z]", self.icons, re.S)
        self.assertGreaterEqual(len(revealers), 4)
        for body in revealers:
            self.assertIn("vertical: root.vertical", body,
                          "a Revealer that always collapses width slides sideways in a vertical bar")

    def test_the_bell_stays_loaded_while_its_revealer_closes(self):
        loader = re.search(r"Loader \{\s*id: notifLoader(.*?)\n {12}\}", self.icons, re.S)
        self.assertIsNotNone(loader)
        self.assertRegex(loader.group(1), r"active: notifRevealer\.reveal \|\| notifRevealer\.visible",
                         "a Loader that unloads the moment the state drops slides an empty gap closed")
        self.assertNotIn("visible: active", loader.group(1))

    def test_the_badge_is_a_presence(self):
        self.assertRegex(self.count, r"Presence \{\s*shown: !Notifications\.silent && Notifications\.unread > 0")
        self.assertNotRegex(self.count, r"\n {8}visible: !Notifications",
                            "the badge must fade through Presence, not toggle `visible:`")


if __name__ == "__main__":
    unittest.main()
