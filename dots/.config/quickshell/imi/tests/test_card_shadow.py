#!/usr/bin/env python3
"""The card's shadow, measured in pixels rather than in source text.

A structure test can only see that the wiring is spelled correctly. This
renders real WidgetCards on a white field under headless weston and reads the
strip just below each one: a shadow darkens it, a handled card's shadow
darkens it more, and a card in motion should not darken it at all - the
shadow is dropped for the duration of the movement, as the frost is.
"""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROBE = ROOT / "tests/run_card_shadow_probe.sh"

CARD_W, CARD_H, TOP = 200, 120, 60
COLUMNS = {"rest": 60, "dragged": 340, "moving": 620}


def darkness_below(shot, card_x):
    """Mean darkness (0 = untouched white) of the band under a card.

    ImageMagick does the averaging: piping raw grey out of it and summing by
    hand produced values that did not match the visible image at all.
    """
    top = TOP + CARD_H + 4
    geometry = f"{CARD_W - 40}x14+{card_x + 20}+{top}"
    mean = subprocess.run(
        ["magick", str(shot), "-crop", geometry, "+repage",
         "-colorspace", "Gray", "-format", "%[fx:mean]", "info:"],
        capture_output=True, text=True, timeout=60).stdout.strip()
    return (1.0 - float(mean)) * 255.0


def _runtime_available():
    # Same gate the other runtime probes use, plus the analyser: CI has no
    # compositor, and a test that hard-fails there is reporting the runner's
    # shape as a defect in the shadow.
    return all(shutil.which(tool) is not None
               for tool in ("qs", "weston", "magick"))


@unittest.skipUnless(_runtime_available(), "needs qs, weston and magick on PATH")
class CardShadowTest(unittest.TestCase):
    def test_the_card_casts_lifts_and_drops_its_shadow(self):
        with tempfile.TemporaryDirectory() as tmp:
            shot = Path(tmp) / "cards.png"
            env = dict(os.environ, CARD_SHADOW_SHOT=str(shot))
            result = subprocess.run([str(PROBE)], capture_output=True, text=True,
                                    timeout=180, env=env)
            self.assertIn("saved", result.stdout,
                          f"probe did not render:\n{result.stdout}\n{result.stderr}")
            self.assertTrue(shot.exists(), "no screenshot produced")

            measured = {name: darkness_below(shot, x) for name, x in COLUMNS.items()}
            detail = " ".join(f"{k}={v:.1f}" for k, v in measured.items())

            self.assertGreater(measured["rest"], 3.0,
                               f"a resting card casts no shadow ({detail})")
            self.assertGreater(measured["dragged"], measured["rest"] * 1.2,
                               f"a handled card does not lift ({detail})")
            self.assertLess(measured["moving"], 1.0,
                            f"a card in motion still casts one ({detail})")


if __name__ == "__main__":
    unittest.main(verbosity=2)
