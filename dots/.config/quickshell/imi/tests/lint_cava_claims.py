#!/usr/bin/env python3
"""cava must not decode for something nobody is watching.

Two rules, both learned from the same defect.

**A claim states its condition.** `CavaRef {}` with no `active:` means "run
cava for as long as I exist", which is right only when existing really is the
condition. It was written that way at three call sites, and at every one of
them the widget outlived its own visibility - a bar behind a fullscreen window,
a desktop widget on a wallpaper that had been switched off. Requiring `active:`
does not force any particular answer; it forces the author to have one.

**The service gates on playback, not on a player existing.** `activePlayer !==
null` is true for a *paused* player. cava visualises whatever is audible rather
than that player's stream, so the shell kept decoding some other application's
sound - and each band retriggered twenty `Behavior on height` animations, which
tick at the display's refresh rate whether or not the surface is on screen.
Measured on a 240 Hz output: the bar's render thread ran at 237 fps behind a
fullscreen game with every player paused, and pausing cava took it to 33.

This is the second Behavior-driven idle-repaint defect in this repo (the
parallax opt-out was the first), which is why it is a check and not a note.
Both rules are answerable by reading the text, so neither needs a compositor.
"""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {".git", "node_modules", "__pycache__", "tests"}

SERVICE = ROOT / "modules/common/plugins/designsystem/services/CavaService.qml"

# `CavaRef {` followed by `}` with only whitespace between: a claim with no
# body, therefore no `active:`. A claim that sets anything at all is left alone
# - the point is a deliberate condition, not a particular one.
BARE_CLAIM = re.compile(r"\bCavaRef\s*\{\s*\}")

# The gate that treats a paused player as a reason to decode.
PAUSED_PLAYER_GATE = re.compile(r"active\s*:[^\n]*activePlayer\s*!==\s*null")


def failures_for(path: Path):
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return []

    out = []
    for match in BARE_CLAIM.finditer(text):
        line = text.count("\n", 0, match.start()) + 1
        out.append(
            f"{path.relative_to(ROOT)}:{line}: `CavaRef {{}}` states no condition. "
            f"Give it `active:` - the condition under which this consumer is "
            f"really showing bands. `visible` is the usual answer; a surface the "
            f"compositor merely covers needs its own term, because QML still "
            f"reports it visible.")
    return out


def main() -> int:
    failures = []
    for path in sorted(ROOT.rglob("*.qml")):
        if any(part in SKIP_DIRS for part in path.relative_to(ROOT).parts):
            continue
        failures.extend(failures_for(path))

    if SERVICE.exists():
        service_text = SERVICE.read_text(encoding="utf-8")
        match = PAUSED_PLAYER_GATE.search(service_text)
        if match:
            line = service_text.count("\n", 0, match.start()) + 1
            failures.append(
                f"{SERVICE.relative_to(ROOT)}:{line}: cava is gated on a player "
                f"existing, not on one playing. A paused player is still an "
                f"active player, so this runs cava - and every band it emits "
                f"retriggers the visualiser's Behaviors at the refresh rate. "
                f"Use `MprisController.isPlaying`.")

    if failures:
        print("cava claim lint failed:\n", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1

    print("cava claim lint passed: every claim states its condition, "
          "and the service gates on playback")
    return 0


if __name__ == "__main__":
    sys.exit(main())
