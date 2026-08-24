#!/usr/bin/env python3
"""Bar texts whose change is an EVENT slide-swap; the clock's tick stays a tick.

`StyledText.animateChange` is the shell's one spelling of a text swap (slide
out, bare-PropertyAction swap, slide in - see `tests/tst_deferred_property_swap.qml`
for the construct's semantics). docs/p3drovfx-animation-research-2026-08-16.md
§3.11 found the sibling fork shipped the same mode and never turned it on
anywhere, so its bar temperature hard-cut on every refresh - and ours did too,
because the flag was only wired at ~20 call sites elsewhere.

What this pins, and why each direction:

- The media widget's verbose bar label (default horizontal style) animates its
  change: a track change is an event the user notices and often caused.
- Every WeatherBar temperature label animates its change: a refresh lands a new
  number a few times an hour, an event rather than a tick.
- The two material media labels keep their hand-rolled split-flap `Behavior on
  text` and must NOT also set `animateChange`: StyledText's inner Behavior and
  a call-site Behavior on the same property would both arm, which is the
  doubled-motion family `lint_interaction_motion_double.py` exists for on
  another channel. One transition per property.
- ClockWidget carries no `animateChange` at all, and the refusal is pinned
  rather than left as an omission someone "fixes":
  - `DateTime.time`'s format is user-configurable (`Config.options.time.format`)
    down to seconds, so the swap would run once per second, forever, on a bar
    that stays `visible` while a fullscreen window covers it (53d1ff893
    ("fix(bar): drop the cava claim while a fullscreen window covers the bar") -
    occlusion happens below Qt, so no visibility gate can stand it down).
  - In the vertical styles the time is a Repeater over `time.split(...)` - a
    plain JS array model, which destroys and rebuilds every delegate per tick,
    so `animateChange` never fires there anyway: enabling it would animate one
    orientation and not the other.
  A per-minute tick is not an event the eye is on; the desktop DigitalClock
  animates its digits behind its own config switch, and that is where the
  ambient-motion argument lives.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from contract_runner import run  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / "modules/imi/bar/Media.qml"
WEATHER = ROOT / "modules/imi/bar/WeatherBar.qml"
CLOCK = ROOT / "modules/imi/bar/ClockWidget.qml"


def code(path: Path) -> str:
    assert path.exists(), f"{path} is gone"
    text = path.read_text()
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def styled_text_blocks(text: str) -> list[str]:
    blocks = []
    for match in re.finditer(r"\bStyledText\s*\{", text):
        depth = 0
        start = match.end() - 1
        for i in range(start, len(text)):
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
                if depth == 0:
                    blocks.append(text[match.start():i + 1])
                    break
    assert blocks, "no StyledText blocks found - did the sweep break?"
    return blocks


def test_the_media_bar_label_animates_a_track_change():
    blocks = [b for b in styled_text_blocks(code(MEDIA))
              if "bar.media.onlyTitle" in b]
    assert len(blocks) == 1, \
        f"expected exactly one verbose bar label in Media.qml, found {len(blocks)}"
    assert re.search(r"animateChange:\s*true", blocks[0]), \
        "the media widget's bar label hard-cuts on a track change again"


def test_the_media_material_labels_do_not_double_their_transition():
    for block in styled_text_blocks(code(MEDIA)):
        if re.search(r"Behavior\s+on\s+text", block):
            assert "animateChange" not in block, \
                ("a StyledText with its own `Behavior on text` also arms "
                 "animateChange - two transitions on one property")


def test_every_weather_temperature_animates_its_refresh():
    temp_blocks = [b for b in styled_text_blocks(code(WEATHER))
                   if "Weather.data?.temp" in b]
    assert len(temp_blocks) == 4, \
        (f"expected 4 temperature labels in WeatherBar.qml (row/col x "
         f"default/material), found {len(temp_blocks)}")
    for block in temp_blocks:
        assert re.search(r"animateChange:\s*true", block), \
            "a WeatherBar temperature hard-cuts on refresh again"


def test_the_clock_does_not_animate_its_tick():
    assert "animateChange" not in code(CLOCK), \
        ("ClockWidget arms animateChange - a per-minute (or, with seconds in "
         "Config.options.time.format, per-second) animation on a bar that "
         "stays `visible` under a fullscreen window, and one the vertical "
         "styles' split-digit Repeaters cannot fire anyway. Read this test's "
         "docstring before enabling it.")


if __name__ == "__main__":
    raise SystemExit(run(globals()))
