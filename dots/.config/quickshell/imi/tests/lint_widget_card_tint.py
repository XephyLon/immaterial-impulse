#!/usr/bin/env python3
"""A widget draws its surface with WidgetCard, not with a hand-rolled tint.

The card exists because the same container was written four times - three
byte-identical `useBlurBackground ? applyAlpha(tint, opacity) : tint`
Rectangles in weather, currency and the media cookie, and a fourth in calendar
that had already drifted to a different rounding token and colour source. Four
copies is how container motion becomes four slightly different tunings.

So the pattern that built those copies is now reserved to the component: the
blur-thinned tint conditional may appear in WidgetCard.qml and nowhere else.
This does not force a widget to use the card (the system monitor's three cards
are its own composition); it forces a widget that wants the *standard* card
look to get it from the standard card, where its motion can be tuned once.

calendar/Widget.qml is the one temporary exemption: it is scheduled to be
rebuilt on the card once the architecture settles on media and weather, and
its drifted copy is left alone until then rather than half-migrated. Remove
the exemption with the rebuild.
"""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {".git", "node_modules", "__pycache__", "tests"}

ALLOWED = {
    Path("modules/common/plugins/designsystem/widgets/WidgetCard.qml"),
    # Rebuilt on the card after media and weather settle - see docstring.
    Path("modules/common/plugins/bundled/calendar/Widget.qml"),
}

# The tint conditional, however the alpha helper is qualified and whatever the
# tint colour is: `useBlurBackground ? <something>applyAlpha(...)`.
TINT_PAIR = re.compile(r"useBlurBackground\s*\?\s*[\w.]*applyAlpha\s*\(", re.I)


def main() -> int:
    failures = []
    for path in sorted(ROOT.rglob("*.qml")):
        rel = path.relative_to(ROOT)
        if any(part in SKIP_DIRS for part in rel.parts) or rel in ALLOWED:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for match in TINT_PAIR.finditer(text):
            line = text.count("\n", 0, match.start()) + 1
            failures.append(
                f"{rel}:{line}: hand-rolled card tint. Use WidgetCard "
                f"(tint/useBlurBackground/backgroundOpacity) so the surface and "
                f"its motion are tuned in one place.")

    if failures:
        print("Widget card tint lint failed:\n", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1

    print("Widget card tint lint passed: the tint conditional lives in WidgetCard only")
    return 0


if __name__ == "__main__":
    sys.exit(main())
