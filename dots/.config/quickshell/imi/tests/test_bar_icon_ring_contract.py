#!/usr/bin/env python3
"""An icon in a circle on the bar is outlined under every style but M3.

The maintainer's rule (2026-09-02), with the resource monitor's rings as the
reference: a bar widget that puts a glyph in a circle draws an OUTLINED ring
unless the bar style is M3, where the tonal pill is the container and the
circle is filled. The media widget's progress circle and the Docker widget's
cube were filled discs under every style; both are progress rings now in the
resource monitor's vocabulary - ClippedOutlineCircularProgress, with the
filled ring only for M3 - so the next widget does not decide it for itself.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


def source(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


class BarIconRingContractTests(unittest.TestCase):
    def test_the_docker_circle_is_a_progress_ring_in_the_resource_monitors_vocabulary(self):
        docker = source("modules/imi/bar/DockerPlugin.qml")
        self.assertIn("readonly property bool isMaterial: Config.options.bar.cornerStyle === 3", docker)
        self.assertIn("readonly property real containerProgress:", docker)
        self.assertEqual(docker.count("sourceComponent: root.isMaterial ? filledRing : outlineRing"), 2,
                         "one ring per orientation, chosen by style")
        outline = docker.split("id: outlineRing", 1)[1].split("Component {", 1)[0]
        self.assertIn("ClippedOutlineCircularProgress {", outline)
        self.assertIn("value: root.containerProgress", outline)
        self.assertIn("color: root.tone", outline)
        filled = docker.split("id: filledRing", 1)[1].split("\n    }\n", 1)[0]
        self.assertIn("ClippedFilledCircularProgress {", filled)
        self.assertIn("value: root.containerProgress", filled)
        self.assertNotRegex(docker, r"Rectangle \{[^}]*radius: Appearance\.rounding\.full",
                            "no hand-drawn disc is left behind the cube")

    def test_the_media_progress_circle_is_the_outline_ring(self):
        media = source("modules/imi/bar/Media.qml")
        self.assertNotIn("ClippedFilledCircularProgress", media)
        self.assertEqual(media.count("ClippedOutlineCircularProgress {"), 2, "horizontal and vertical")

    def test_the_filled_progress_ring_stays_the_m3_or_opted_in_shape(self):
        # Resource: the user's own Filled/Outline knob. Docker and the Bluetooth
        # battery widget: the M3 branch (test_bluetooth_battery_widget.py pins
        # the spelling).
        # LockSurface predates the rule and is not a bar widget.
        users = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "modules").rglob("*.qml")
                       if "ClippedFilledCircularProgress {" in p.read_text(encoding="utf-8")
                       and p.name != "ClippedFilledCircularProgress.qml")
        self.assertEqual(users, ["modules/imi/bar/BluetoothBattery.qml", "modules/imi/bar/DockerPlugin.qml",
                                 "modules/imi/bar/Resource.qml", "modules/imi/lock/LockSurface.qml"], users)
        docker = source("modules/imi/bar/DockerPlugin.qml")
        self.assertIn("root.isMaterial ? filledRing : outlineRing", docker)

    def test_no_shared_ring_widget_reads_the_bar_style(self):
        # A shared widget stays presentational (lint_dumb_widgets); the style
        # decision belongs to the bar widget, which passes the choice down.
        self.assertFalse((ROOT / "modules/common/widgets/BarIconRing.qml").exists())


if __name__ == "__main__":
    unittest.main()
