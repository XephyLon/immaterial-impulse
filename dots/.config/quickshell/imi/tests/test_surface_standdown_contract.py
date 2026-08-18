#!/usr/bin/env python3
"""A screen-sized Overlay surface must not stay mapped with nothing to show.

A surface on the Overlay layer sits above every fullscreen window on its output
for as long as it exists, and the compositor composites it each frame whether or
not the shell painted anything into it. `quickshell:barPopup` is 5120x1440 on
this machine and was mapped for the whole session to host the bar's hover cards.
Measured against FINAL FANTASY XIV's own frame counter, fullscreen, static
scene: 98 fps with it mapped and idle, 105 with it unmapped.

NOT a rule about the background surface, deliberately. That one is also
screen-sized and also stays mapped, and unmapping it measures better still - but
`visible: false` on a WlrLayershell window destroys it, and destroying the
background surface is what left the embedded Wallpaper Engine renderer sampling
a dead texture with the desktop strobing at 30Hz: a photosensitive-seizure
hazard, not a cosmetic bug. `test_background_fullscreen_suppression.py` pins
that surface the other way and its pin wins. The frames that were going there
came back by stopping what kept the window BUSY instead - see
tests/lint_infinite_animation_visibility.py.

Source-level, because the property is about a Wayland layer surface and weston
implements no wlr-layer-shell: no harness in this tree can map one and ask the
compositor about it.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BAR_POPUP = ROOT / "modules/imi/bar/BarPopupOverlay.qml"


def check(failures, condition, message):
    if not condition:
        failures.append(message)


def main():
    failures = []

    popup = BAR_POPUP.read_text(encoding="utf-8")
    window = re.search(r"id:\s*overlayWindow\n(.*?)\n\s*mask:", popup, re.S)
    check(failures, window is not None, "BarPopupOverlay's window is gone")
    if window:
        body = window.group(1)
        visible = re.search(r"visible:\s*(.+?)\n\s*exclusionMode", body, re.S)
        check(failures, visible is not None,
              "BarPopupOverlay's PanelWindow does not gate `visible`. It is a "
              "screen-sized surface on the Overlay layer, so leaving it mapped "
              "puts a 5120x1440 sheet over every fullscreen window for the "
              "whole session.")
        if visible:
            binding = visible.group(1)
            # The predicate has to outlast the exit: a popup's content tree is
            # reparented INTO this window, and `release()` is what hands it
            # back. Unmapping first would take the tree with it.
            for term in ("current", "outgoing", "exiting", "card."):
                check(failures, term in binding,
                      f"BarPopupOverlay's visibility does not consider `{term}` "
                      f"- the window may only go once finishExit() has released "
                      f"both content trees and collapsed the card, or it takes "
                      f"a reparented tree with it.")

    if failures:
        print("Surface stand-down contract failed:\n", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1

    print("Surface stand-down contract passed (barPopup checked)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
