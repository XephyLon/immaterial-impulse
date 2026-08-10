#!/usr/bin/env python3
"""The cava spectrum has one producer, one band contract, and one gate.

Issue #155: `CavaService` declared a reference count, a band count and a
`values` array, and nothing in the tree ever assigned `values` or started a
process. Three widgets read it, three incremented `refCount`, and all of them
rendered nothing - silently, with nothing in the log, while the bands the shell
actually drew came from a `Process` inside `MediaControls` at a different band
count and a different range.

None of that is reachable from a unit test: the QML suite never builds these
widgets and there is no audio server. What *is* checkable is the shape that
made it possible - a reference count with no producer behind it, a band count
that disagrees with the config the process is launched with, and consumers
each carrying their own copy of the range.
"""

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "modules/common/plugins/designsystem/services/CavaService.qml"
REF = ROOT / "modules/common/plugins/designsystem/services/CavaRef.qml"
CAVA_CONFIG = ROOT / "scripts/cava/raw_output_config.txt"
BANDS = ROOT / "modules/common/functions/cavaBands.js"

# Everything the shell loads. `tests/` is excluded: its mocks and its symlinked
# import tree are test doubles, not shell sources, and some of those links are
# deliberately dangling.
QML_FILES = sorted(path for path in ROOT.rglob("*.qml")
                   if "tests" not in path.relative_to(ROOT).parts)


def qml_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class CavaContractTest(unittest.TestCase):
    def test_a_reference_count_always_has_a_producer_behind_it(self):
        """The trap, generalised.

        `refCount` reads as "this shared resource is started and stopped for
        you", so a service that declares one and starts nothing is a service
        every consumer will be written against and none of them will work.
        Whatever declares a reference count must own the thing it is counting
        references to.
        """
        for path in QML_FILES:
            text = qml_text(path)
            if not re.search(r"property\s+int\s+refCount\b", text):
                continue
            self.assertRegex(
                text, r"\bProcess\s*\{",
                f"{path.relative_to(ROOT)} declares refCount but starts nothing - "
                "consumers written against it will be silently inert")

    def test_the_process_is_gated_on_the_reference_count(self):
        """cava decodes audio continuously; an idle desktop must not run it."""
        text = qml_text(SERVICE)
        gate = re.search(r"readonly\s+property\s+bool\s+active:([^\n]*)", text)
        self.assertIsNotNone(gate, "the service needs one named gate expression")
        self.assertIn("refCount > 0", gate.group(1))
        self.assertIn("activePlayer !== null", gate.group(1),
                      "with no player there is nothing to decode")
        self.assertRegex(text, r"\brunning:\s*root\.active\b",
                         "the process must run on the gate, not on its own condition")

    def test_the_band_count_is_the_one_the_process_is_asked_for(self):
        """`barCount: 32` against a config asking for 50 bars is how this drifted."""
        bars = re.search(r"^\s*bars\s*=\s*(\d+)\s*$",
                         CAVA_CONFIG.read_text(encoding="utf-8"), re.M)
        self.assertIsNotNone(bars, "the cava config must declare a bar count")
        declared = re.search(r"readonly\s+property\s+int\s+barCount:\s*(\d+)",
                             qml_text(SERVICE))
        self.assertIsNotNone(declared, "the service must declare the band count")
        self.assertEqual(declared.group(1), bars.group(1),
                         "CavaService.barCount and the cava config's `bars` are the "
                         "same number seen from two sides")
        self.assertRegex(qml_text(SERVICE), r"readonly\s+property\s+real\s+maxValue:\s*\d+",
                         "the value range belongs on the service too")

    def test_the_command_launches_that_config(self):
        self.assertIn("cava/raw_output_config.txt", qml_text(SERVICE),
                      "the band count above is only pinned while this is the config used")

    def test_nothing_counts_itself_in_by_hand(self):
        """Three hand-written copies of this bookkeeping existed and disagreed.

        Each had to remember a third thing - whether it was currently counted -
        and one of them balanced its increment only on destruction.
        """
        allowed = {SERVICE, REF}
        for path in QML_FILES:
            if path in allowed:
                continue
            text = qml_text(path)
            self.assertNotRegex(
                text, r"CavaService\.refCount\s*(\+\+|--|\+=|-=)",
                f"{path.relative_to(ROOT)} should declare a CavaRef instead of "
                "incrementing the count by hand")

    def test_no_consumer_carries_its_own_copy_of_the_range(self):
        """The coupling the service exists to remove.

        A consumer that reads the spectrum and then divides by a literal is one
        cava config edit away from being wrong, and nothing reports it.
        """
        for path in QML_FILES:
            text = qml_text(path)
            if "CavaService.values" not in text:
                continue
            self.assertNotRegex(
                text, r"maxVisualizerValue:\s*\d",
                f"{path.relative_to(ROOT)} must take the range from CavaService.maxValue")
            self.assertNotRegex(
                text, r"/\s*1000\b",
                f"{path.relative_to(ROOT)} must take the range from CavaService.maxValue")

    def test_the_retired_mirror_is_gone_for_good(self):
        """`GlobalStates.visualizerPoints` was the old publication channel.

        Leaving it declared is worse than removing it: it would still read as a
        live band source, and a consumer wired to it would be inert in exactly
        the way this issue is about.
        """
        states = qml_text(ROOT / "GlobalStates.qml")
        self.assertNotIn("visualizerPoints", states)
        for path in QML_FILES:
            self.assertNotIn("GlobalStates.visualizerPoints", qml_text(path),
                             f"{path.relative_to(ROOT)} reads a property that no longer exists")

    def test_the_band_shaping_is_pure_and_shared(self):
        """It is the one part of this that can be tested without a compositor."""
        text = BANDS.read_text(encoding="utf-8")
        self.assertTrue(text.startswith(".pragma library"))
        for symbol in ("function resample(", "function normalize(", "function bands("):
            self.assertIn(symbol, text)
        self.assertTrue((ROOT / "tests/tst_cava_bands.qml").exists(),
                        "the arithmetic is only shared if it is also tested")


if __name__ == "__main__":
    unittest.main()
