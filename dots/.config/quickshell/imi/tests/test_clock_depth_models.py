#!/usr/bin/env python3
"""The picker's columns come from the producer, and the fallback must agree.

`scripts/background/subject_mask.py` is the authority on which models exist and
what each one is asked with - `status` reports them, and `ClockDepth` takes the
list from that answer, so the picker draws one column per model without holding
an opinion about which models there are.

It keeps one literal copy anyway, as the value shown on the frame the picker
opens rather than 200ms later when the first `status` lands. That is a pair that
has to agree, and the failure is silent in the direction that matters: a model
the fallback does not name simply has no column for the moment before the query
answers, and a model it names wrongly draws a column with a dead button. So the
pair is pinned here rather than trusted.

The order matters too, because it is the order the columns are drawn in and the
producer's answer replaces the fallback in place - two lists in different orders
would make the columns jump sideways a fifth of a second after the picker opens.
"""
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/background/subject_mask.py"
SERVICE = ROOT / "services/ClockDepth.qml"
PICKER = ROOT / "modules/imi/wallpaperSelector/ClockDepthPicker.qml"

sys.path.insert(0, str(SCRIPT.parent))
import subject_mask  # noqa: E402


def declared_fallback(source):
    """The `modelSpecs` literal out of ClockDepth.qml, as a list of pairs.

    Read as JSON rather than by a per-field regex: the whole value is a JSON
    array in QML's own syntax, so parsing it is both simpler and unable to
    silently match half a declaration after a reformat.
    """
    marker = re.search(r"property\s+var\s+modelSpecs:\s*\[", source)
    if not marker:
        return None
    opening = source.index("[", marker.start())
    depth = 0
    for index in range(opening, len(source)):
        if source[index] == "[":
            depth += 1
        elif source[index] == "]":
            depth -= 1
            if depth == 0:
                literal = source[opening:index + 1]
                break
    else:
        return None
    return [(entry["name"], entry["kind"]) for entry in json.loads(literal)]


class ModelListParityTest(unittest.TestCase):
    def setUp(self):
        self.producer = [(name, spec["kind"])
                         for name, spec in subject_mask.MODELS.items()]

    def test_the_fallback_names_the_producers_models_in_the_producers_order(self):
        fallback = declared_fallback(SERVICE.read_text())
        self.assertIsNotNone(fallback,
                             "ClockDepth.qml declares no modelSpecs literal - the "
                             "picker would draw nothing until the first status lands")
        self.assertEqual(fallback, self.producer)

    def test_status_reports_the_models_so_the_shell_need_not_know_them(self):
        with tempfile.TemporaryDirectory() as tmp:
            wallpaper = Path(tmp) / "wall.png"
            wallpaper.write_bytes(b"wallpaper")
            proc = subprocess.run(
                [sys.executable, str(SCRIPT), "--cache-dir", str(Path(tmp) / "cache"),
                 "status", str(wallpaper)],
                capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        reported = [(entry["name"], entry["kind"])
                    for entry in json.loads(proc.stdout)["models"]]
        self.assertEqual(reported, self.producer)

    def test_exactly_one_model_answers_a_click(self):
        """The picker resolves the prompted column by asking which model is
        prompted, and `ClockDepth.promptedModel` returns the first. A second one
        would leave the other's column clickable and wired to the first's cache
        entry - the same mask under two headings."""
        prompted = [name for name, kind in self.producer if kind == "prompted"]
        self.assertEqual(len(prompted), 1, prompted)

    def test_the_picker_asks_the_kind_rather_than_naming_the_model(self):
        """A branch on `"mobile-sam"` in the picker is the drift this removes.

        The producer decides which models take clicks; a picker that decides for
        itself is a second answer, and the one that goes stale is the picker's,
        because a model it does not know about simply renders as a column whose
        Run button spawns a verb the producer refuses.
        """
        source = PICKER.read_text()
        for name, kind in self.producer:
            if kind != "prompted":
                continue
            self.assertNotIn(f'"{name}"', source,
                             f"ClockDepthPicker.qml names {name} directly; it must "
                             f"branch on the model's kind instead")


if __name__ == "__main__":
    unittest.main()
