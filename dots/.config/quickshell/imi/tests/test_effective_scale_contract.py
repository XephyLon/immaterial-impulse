#!/usr/bin/env python3
"""One logical-pixel multiplier, and it is Appearance's.

`Appearance.effectiveScale` came in with the vendored expressive widget library
and reads 1.0 - which makes it look like dead compatibility plumbing and invites
two opposite mistakes. It is not dead: 629 call sites read it, and
`sizes.widgetGridSpanX/Y` and the drag lattice's gap multiply by it, so a value
other than 1 moves every desktop widget's box and every span
`plugin-state.json` holds. And it is not a zoom knob: the shell already gets
compositor/output scaling, so a second multiplier applied to widget geometry
alone fights the one Qt already applied to the whole scene.

What this pins is the shape rather than the number - a repo that wants a real
widget scale one day should get it as a declared setting with a migration, the
way every other user-facing value here arrives, not as this constant quietly
leaving 1 while nothing in the suite notices. So: exactly one declaration, no
second scale multiplier declared beside it, and every consumer reading it from
Appearance rather than folding a factor of its own into the same arithmetic.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APPEARANCE = ROOT / "modules/common/Appearance.qml"
DECLARATION = re.compile(r"^\s*readonly\s+property\s+real\s+effectiveScale\s*:\s*(.+)$",
                         re.MULTILINE)
# A literal factor multiplied INTO the scale at a call site: `0.75 *
# Appearance.effectiveScale` is the one that exists (AndroidToggle's smaller
# variant) and is fine - a per-widget proportion is not a second global scale.
# What is not fine is a second GLOBAL multiplier: a singleton declaring its own.
SINGLETON = re.compile(r"^\s*pragma\s+Singleton\s*$", re.MULTILINE)
OWN_SCALE = re.compile(
    r"^\s*(?:readonly\s+)?property\s+real\s+(effectiveScale|logicalScale|uiScale)\s*:",
    re.MULTILINE)


def qml_files():
    for path in sorted(ROOT.rglob("*.qml")):
        relative = path.relative_to(ROOT).as_posix()
        if relative.startswith("tests/"):
            continue
        yield relative, path


def test_the_multiplier_is_declared_once_and_reads_one():
    text = APPEARANCE.read_text(encoding="utf-8")
    declarations = DECLARATION.findall(text)
    assert len(declarations) == 1, (
        f"Appearance declares effectiveScale {len(declarations)} times: "
        f"{declarations}")
    value = declarations[0].split("//")[0].strip()
    assert value == "1.0", (
        f"effectiveScale is {value!r}. It multiplies widgetGridSpanX/Y and the "
        f"drag lattice's gap, so any other value moves every desktop widget's "
        f"box and every span the store already holds. Making it real is a "
        f"declared setting with a migration, not a changed constant - and this "
        f"test is where that decision gets written down.")


def test_the_reason_travels_with_it():
    text = APPEARANCE.read_text(encoding="utf-8")
    index = text.index("readonly property real effectiveScale")
    preamble = text[max(0, index - 1600):index]
    assert "compositor" in preamble, (
        "the comment above effectiveScale no longer says why it is 1. It reads "
        "as dead compatibility plumbing without that sentence, which is how a "
        "second scaling path gets added on top of the compositor's.")


def test_no_singleton_declares_a_second_global_scale():
    offenders = []
    for relative, path in qml_files():
        if relative == "modules/common/Appearance.qml":
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        if not SINGLETON.search(text):
            continue
        for match in OWN_SCALE.finditer(text):
            line = text.count("\n", 0, match.start()) + 1
            offenders.append(f"{relative}:{line} declares {match.group(1)}")
    assert not offenders, (
        f"a second global scale multiplier: {offenders}. One is the "
        f"compositor's job and the other is Appearance's; two of them multiply, "
        f"and only widget geometry reads the second, so the shell scales "
        f"unevenly with nothing reporting it.")


def test_the_vendored_library_reads_it_rather_than_carrying_one():
    tokens = ROOT / "modules/common/plugins/designsystem/ExpressiveTokens.qml"
    text = tokens.read_text(encoding="utf-8")
    assert re.search(r"readonly\s+property\s+real\s+scale\s*:\s*Appearance\.effectiveScale",
                     text), (
        "ExpressiveTokens.scale no longer forwards Appearance.effectiveScale. "
        "That singleton is the vendored library's whole door onto the shell's "
        "tokens; a literal there is a scale nothing else can see.")


if __name__ == "__main__":
    failures = 0
    for name, function in sorted(globals().items()):
        if not name.startswith("test_") or not callable(function):
            continue
        try:
            function()
        except AssertionError as error:
            failures += 1
            print(f"FAIL: {name}\n  {error}", file=sys.stderr)
    if failures:
        print(f"effective scale contract: {failures} failed", file=sys.stderr)
        sys.exit(1)
    print("Effective scale contract passed: one multiplier, reading 1, with its reason")
