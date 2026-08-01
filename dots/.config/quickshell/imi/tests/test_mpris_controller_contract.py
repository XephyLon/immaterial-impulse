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


if __name__ == "__main__":
    unittest.main()
