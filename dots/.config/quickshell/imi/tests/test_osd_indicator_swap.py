#!/usr/bin/env python3
"""The OSD's indicator swap waits for the outgoing indicator to leave.

`modules/imi/onScreenDisplay/OnScreenDisplay.qml` is one window that nine
sources write into. Changing volume and then brightness inside
`Config.options.osd.timeout` swaps `osdIndicatorLoader.source` under a surface
that is already up, so the swap is a transition the user watches - and a
`Loader.source` is a `url`, which QML cannot interpolate.

The construct that solves it is a `Behavior` on that non-animatable property
whose animation ends in a BARE `PropertyAction {}`: no target, no property, no
value. Inside a Behavior that means "apply the pending write here", so the
outgoing indicator gets its exit before it is destroyed. What it replaces is a
hand-written state machine - a pending-value field, a pair of chained Timers,
and two intervals that have to keep agreeing with two animations' durations.

Two halves, and neither is worth much alone:

  - `tests/tst_deferred_property_swap.qml` pins the CONSTRUCT's semantics
    against Qt itself, because if a Qt release stopped honouring the bare form
    the pending write would simply never be applied - the OSD would keep
    showing the indicator the user has navigated away from, with nothing in any
    log.
  - this file pins that our call site still uses it, and in particular that
    the `PropertyAction` stays bare. A `PropertyAction { target: x; property:
    "source" }` looks equivalent and is a hand-written re-derivation of what
    the bare form does automatically - two more places for a rename to make
    silently inert, which is exactly what `modules/imi/bar/Media.qml` and
    `modules/imi/sidebarLeft/SidebarPlayerControl.qml` already spell.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from contract_runner import run  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
OSD = ROOT / "modules/imi/onScreenDisplay/OnScreenDisplay.qml"

BARE_PROPERTY_ACTION = re.compile(r"PropertyAction\s*\{\s*\}")


def loader_block() -> str:
    """The Loader's body with `//` comments stripped.

    The comments explaining the construct name the things it replaced, so a
    check reading the raw text would match its own explanation.
    """
    text = "\n".join(re.sub(r"//.*$", "", line)
                     for line in OSD.read_text(encoding="utf-8").splitlines())
    start = text.index("Loader {\n                            id: osdIndicatorLoader")
    brace = text.index("{", start)
    depth = 0
    for index in range(brace, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[brace:index + 1]
    raise AssertionError("osdIndicatorLoader's body never closes")


def test_the_source_swap_is_deferred_by_a_behavior():
    block = loader_block()
    assert "Behavior on source" in block, (
        "the OSD's indicator Loader swaps `source` with no Behavior, so an "
        "indicator arriving while the OSD is already up cuts the previous one "
        "off in the frame it is destroyed.")


def test_the_property_action_stays_bare():
    block = loader_block()
    assert BARE_PROPERTY_ACTION.search(block), (
        "the swap's PropertyAction is not bare. Only a PropertyAction with no "
        "target, no property and no value means `apply the pending write "
        "here`; naming the target and the property re-derives by hand what the "
        "bare form does from the Behavior it sits in, and a rename then makes "
        "the action match nothing with no warning.")


def test_the_exit_runs_before_the_swap_and_the_enter_after_it():
    """Order is the whole content of the technique."""
    block = loader_block()
    behavior = block[block.index("Behavior on source"):]
    action = BARE_PROPERTY_ACTION.search(behavior)
    before, after = behavior[:action.start()], behavior[action.end():]
    assert "to: 0" in before, \
        "nothing fades out before the pending source is applied"
    assert "to: 1" in after, \
        "nothing fades back in after the pending source is applied"
    assert "elementMoveExit" in before and "elementMoveEnter" in after, (
        "the two halves are not the exit and entrance tiers. "
        "docs/M3_GUIDELINES.md §2 puts an accelerating exit before a "
        "decelerating entrance, and taking both tiers whole is what keeps the "
        "swap off Easing.Linear.")


def test_the_swap_no_longer_needs_a_hand_written_wait():
    """A Timer whose interval restates an animation's duration is the drift."""
    block = loader_block()
    assert "Timer" not in block, (
        "the indicator Loader carries a Timer again. The point of the "
        "Behavior is that the wait IS the animation, so no interval has to be "
        "kept in agreement with a duration declared somewhere else.")


if __name__ == "__main__":
    sys.exit(run(globals()))
