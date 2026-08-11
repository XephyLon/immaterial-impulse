#!/usr/bin/env python3
"""Regression checks for the media widgets' MprisController API contract."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


class MprisControllerContractTests(unittest.TestCase):
    def test_controller_exposes_every_widget_field(self):
        controller = (ROOT / "services/MprisController.qml").read_text(encoding="utf-8")
        for name, qml_type, source in (
            ("trackTitle", "string", "activePlayer?.trackTitle"),
            ("trackArtist", "string", "activePlayer?.trackArtist"),
            ("position", "real", "activePlayer?.position"),
            ("length", "real", "activePlayer?.length"),
        ):
            self.assertRegex(
                controller,
                rf"readonly\s+property\s+{qml_type}\s+{name}\s*:\s*{re.escape(source)}",
            )

    def test_media_widgets_only_use_declared_controller_fields(self):
        controller = (ROOT / "services/MprisController.qml").read_text(encoding="utf-8")
        declared = set(re.findall(r"\bproperty\s+\w+(?:<[^>]+>)?\s+(\w+)\s*[:;]", controller))
        methods = set(re.findall(r"\bfunction\s+(\w+)\s*\(", controller))
        allowed = declared | methods

        for relative in (
            "modules/common/plugins/designsystem/widgets/DesktopMediaWidget.qml",
        ):
            widget = (ROOT / relative).read_text(encoding="utf-8")
            used = set(re.findall(r"MprisController\.(\w+)", widget))
            self.assertFalse(used - allowed, f"{relative}: undeclared fields {sorted(used - allowed)}")

    def test_only_one_place_resolves_the_preferred_player(self):
        """The bar, the media popup, the right sidebar and the lock screen each
        carried their own copy of the preferred-player block, and the four had
        already drifted apart (issue #170). MprisController resolves it now, and
        everything else reads `activePlayer` / `meaningfulPlayers` from there.

        `Config.qml` migrates the stored value and `BarConfig.qml` is the picker
        that writes it, so those two name the key legitimately.
        """
        owners = {
            "services/MprisController.qml",
            "modules/common/Config.qml",
            "modules/imi/settings/pages/BarConfig.qml",
        }
        offenders = []
        for path in ROOT.rglob("*.qml"):
            relative = path.relative_to(ROOT).as_posix()
            if relative.startswith("tests/") or relative in owners:
                continue
            if "media.preferredPlayer" in path.read_text(encoding="utf-8"):
                offenders.append(relative)
        self.assertFalse(offenders, f"preferred-player resolution copied into {sorted(offenders)}")


if __name__ == "__main__":
    unittest.main()
