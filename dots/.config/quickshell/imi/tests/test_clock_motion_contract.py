#!/usr/bin/env python3
"""The cookie clock's continuous motion is sampled, not animated per vsync.

On the background surface every commit carries whole-surface damage - Qt's GL
path reports no less - so a running animation there is the compositor
re-rendering all of a 5120x1440 screen and re-blurring every surface over it,
once per vsync. The cookie's 30-second spin and its per-second hand sweep did
exactly that, and measured at idle on the reporter's machine it was 38% of the
GPU against 10-12% with the spin off. Sampling the wall clock at 30Hz brought
it to 20%, with the rim of a 230px cookie moving 0.8px per tick.

Three things this pins, each of which is a one-line way back to the 38%:

- no infinite `RotationAnimation` / `NumberAnimation` on the body's rotation;
- the second hand is handed `animateRotation: false` and a `sweep` - its own
  Behavior is a one-second animation that refires every second, which is a
  continuous animation by another name;
- the tick rate stays at or under 30Hz. It is a declared number, and a
  declared number is the easiest thing in a file to nudge.
"""

import re
from pathlib import Path

from contract_runner import run

ROOT = Path(__file__).resolve().parent.parent
COOKIE = ROOT / "modules/common/plugins/bundled/clock/CookieClock.qml"
SECOND_HAND = ROOT / "modules/common/plugins/bundled/clock/SecondHand.qml"
MAX_TICK_HZ = 30


def code(path: Path) -> str:
    assert path.exists(), f"{path} is gone"
    text = path.read_text()
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def test_the_body_spin_is_a_function_of_sampled_time():
    text = code(COOKIE)
    assert not re.search(r"(Rotation|Number|Property)Animation\s+on\s+rotation", text), \
        "CookieClock animates its rotation per vsync again - that was 38% of the GPU at idle"
    assert "loops: Animation.Infinite" not in text, \
        "CookieClock carries an infinite animation again"
    assert re.search(r"rotation:\s*360\s*-\s*\(root\.motionClockMs", text), \
        "the body's rotation no longer derives from `motionClockMs` - what drives it now?"
    assert re.search(r"onTriggered:\s*root\.motionClockMs\s*=\s*Date\.now\(\)", text), \
        "nothing samples the wall clock into `motionClockMs`"


def test_the_second_hand_is_handed_a_sweep_not_an_animation():
    cookie = code(COOKIE)
    hand = code(SECOND_HAND)
    assert re.search(r"animateRotation:\s*false", cookie), \
        "CookieClock lets SecondHand animate its own rotation - a one-second Behavior refiring every second is a continuous animation"
    assert not re.search(r"animateRotation:\s*root\.constantlyRotate", cookie), \
        "the sweep is back on SecondHand's per-second Behavior"
    assert re.search(r"sweep:\s*root\.secondSweep", cookie), \
        "CookieClock no longer hands SecondHand its sampled sweep"
    assert re.search(r"property\s+real\s+sweep\b", hand) and re.search(r"clockSecond\s*\+\s*sweep", hand), \
        "SecondHand no longer folds `sweep` into its rotation"


def test_the_tick_rate_is_declared_and_capped():
    text = code(COOKIE)
    match = re.search(r"readonly\s+property\s+int\s+motionTickHz:\s*(\d+)", text)
    assert match, "`motionTickHz` is not a declared integer literal any more"
    hz = int(match.group(1))
    assert hz <= MAX_TICK_HZ, \
        (f"motionTickHz is {hz}; measured GPU at idle was 20% at 30Hz, 28% at 60Hz, 38% at vsync. "
         "Raise MAX_TICK_HZ here only with a new measurement")
    assert re.search(r"interval:\s*Math\.round\(1000\s*/\s*root\.motionTickHz\)", text), \
        "the tick Timer's interval is not derived from `motionTickHz`"
    assert re.search(r"running:\s*root\.constantlyRotate\s*&&\s*cookieBody\.visible", text), \
        "the tick is not gated on the cookie being ON SCREEN - a desktop behind a fullscreen game would pay for it"


if __name__ == "__main__":
    raise SystemExit(run(globals()))
