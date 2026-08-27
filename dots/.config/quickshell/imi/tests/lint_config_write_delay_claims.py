#!/usr/bin/env python3
"""Nobody assigns `Config.readWriteDelay`, and a claim on it states its condition.

`Config` debounces `writeAdapter()` and the reload its own write provokes, at
`readWriteDelay`. `modules/imi/settings/SettingsContent.qml` set that global to
0 from its own `Component.onCompleted` and never restored it - and the settings
host is built at `Config.ready` rather than when its window opens, so every
config write in the shell had been undebounced from startup, for the whole
session, whether or not anyone ever opened Settings. One window's preference,
leaked into a global, with no release path in the code at all.

The repair is a resolution rather than a saved value: a surface declares a
`ConfigWriteDelayRef`, `Config.readWriteDelay` is derived from the live claims,
and a claim's release IS its own lifetime. Five things hold that shape, and
each of them is a way the old defect could come back:

  A. nothing assigns `Config.readWriteDelay`. That is the defect verbatim, and
     it is also #158's shape - the property is a binding now, so an assignment
     would destroy the derivation rather than merely mis-set it once.
  B. `immediateWriteClaims` has exactly one writer, the claim component. Two
     places counting is how the hand-written `refCount++`/`--` pairs this
     replaced came to disagree (see CavaRef).
  C. every claim states `active:`. A bare `ConfigWriteDelayRef {}` would mean
     "for as long as I exist", which is the sentence that was wrong.
  D. a claim made from inside the shell's own tree (`modules/`, `services/`)
     may not be `active: true`. Those objects outlive the gesture that wants
     the faster flush - the settings host outlives every open of its window -
     so the condition has to name the gesture. `welcome.qml` and
     `killDialog.qml` are separate `qs -p` processes whose whole life IS the
     window, which is why they sit outside those directories and may say so.
  E. `Config.qml` still derives `readWriteDelay`, readonly, from the claims.
     Turning it back into a settable `property int` re-opens A silently: every
     other check here would stay green over it.

Answerable by reading the text, so it needs no compositor. The self-check runs
first, on fixtures held in this file, so the machinery is proven independently
of what the tree contains - a source-text check is code with no tests of its
own, and this repo's static checks have shipped green over the thing they exist
to refuse before.

Run from `tests/run_tests.sh`.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {".git", "node_modules", "__pycache__", "tests"}

CONFIG = ROOT / "modules/common/Config.qml"
CLAIM = ROOT / "modules/common/ConfigWriteDelayRef.qml"

# The directories that are the one long-lived `qs -c imi` process. A claim
# declared in one of them belongs to an object that outlives whatever gesture
# wanted the faster flush.
SHELL_TREE = ("modules/", "services/", "panelFamilies/")

# `Config.readWriteDelay = ...`, and the bare `readWriteDelay = ...` a file
# inside modules/common could write without the prefix. `==`/`===` are
# comparisons and `:` is a declaration, so both are excluded.
ASSIGN_DELAY = re.compile(r"(?:\bConfig\.)?\breadWriteDelay\s*=(?!=)")

# The claim count. Only the component may move it.
WRITE_CLAIMS = re.compile(r"\bimmediateWriteClaims\s*(?:=(?!=)|\+\+|--|\+=|-=)")

# A claim's whole declaration, up to the closing brace of its (never nested)
# body, so `active:` can be looked for inside it.
CLAIM_BLOCK = re.compile(r"\bConfigWriteDelayRef\s*\{([^{}]*)\}")

ACTIVE_TERM = re.compile(r"^\s*active\s*:\s*(.+?)\s*$", re.M)

# The derivation, spelled loosely enough to survive reformatting and tightly
# enough that a settable `property int readWriteDelay: 50` fails.
DERIVED_DELAY = re.compile(
    r"readonly\s+property\s+int\s+readWriteDelay\s*:[^\n]*immediateWriteClaims")


def strip_comments(text):
    """Line and block comments out, so a paragraph quoting the old spelling is
    prose rather than an offence. Every other check in this tree that reads
    source does this first, and the one that did not was kept green by a header
    comment describing the interface it was checking."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def line_of(text, index):
    return text.count("\n", 0, index) + 1


def offences_for(rel, source):
    """rel is the path as written in a message; source is raw QML."""
    text = strip_comments(source)
    out = []

    for match in ASSIGN_DELAY.finditer(text):
        out.append(
            f"{rel}:{line_of(text, match.start())}: assigns `readWriteDelay`. "
            f"It is a readonly derivation over the live claims now, so this "
            f"destroys the derivation rather than setting a value - and an "
            f"assignment has no release path, which is how one window's "
            f"preference became the whole session's. Declare a "
            f"`ConfigWriteDelayRef` with the condition under which the faster "
            f"flush is really wanted.")

    if rel != "modules/common/ConfigWriteDelayRef.qml":
        for match in WRITE_CLAIMS.finditer(text):
            out.append(
                f"{rel}:{line_of(text, match.start())}: writes "
                f"`immediateWriteClaims`. The count has one writer, "
                f"`ConfigWriteDelayRef`; a second place counting is how the "
                f"hand-written refCount pairs it replaced came to disagree.")

    for match in CLAIM_BLOCK.finditer(text):
        line = line_of(text, match.start())
        active = ACTIVE_TERM.search(match.group(1))
        if active is None:
            out.append(
                f"{rel}:{line}: `ConfigWriteDelayRef` states no `active:`. "
                f"An unstated condition reads as \"for as long as I exist\", "
                f"which is the sentence that left the shell undebounced for "
                f"whole sessions. Name the condition under which this surface "
                f"really wants its writes flushed immediately.")
        elif (any(rel.startswith(prefix) for prefix in SHELL_TREE)
                and active.group(1).rstrip(";") == "true"):
            out.append(
                f"{rel}:{line}: `ConfigWriteDelayRef` is held unconditionally "
                f"inside the shell's own tree, so it is held for the session. "
                f"Objects here outlive the gesture that wants the faster flush "
                f"- the settings host is built at `Config.ready` and outlives "
                f"every open of its window. Bind `active` to the gesture. "
                f"(A standalone `qs -p` entry point whose whole process is one "
                f"window may say `true`; it does not live in these "
                f"directories.)")

    return out


FIXTURES = [
    ("modules/imi/settings/SettingsContent.qml",
     "Item {\n    Component.onCompleted: {\n        Config.readWriteDelay = 0\n    }\n}\n",
     ["assigns `readWriteDelay`"]),
    ("modules/imi/settings/Settings.qml",
     "Scope {\n    ConfigWriteDelayRef {\n        active: settingsWindow.visible\n    }\n}\n",
     []),
    ("modules/imi/settings/Settings.qml",
     "Scope {\n    ConfigWriteDelayRef {\n    }\n}\n",
     ["states no `active:`"]),
    ("modules/imi/settings/Settings.qml",
     "Scope {\n    ConfigWriteDelayRef {\n        active: true\n    }\n}\n",
     ["held unconditionally"]),
    # The two standalone processes may: their whole life is the one window.
    ("welcome.qml",
     "ApplicationWindow {\n    ConfigWriteDelayRef {\n        active: true\n    }\n}\n",
     []),
    # A comment quoting the old spelling is prose, not an offence.
    ("modules/common/ConfigWriteDelayRef.qml",
     "// a `Config.readWriteDelay = 0` line at the call site\n"
     "QtObject {\n    function sync() { Config.immediateWriteClaims += 1; }\n}\n",
     []),
    # ...but a second counter is one, wherever it lives.
    ("services/Something.qml",
     "Singleton {\n    function f() { Config.immediateWriteClaims++; }\n}\n",
     ["writes `immediateWriteClaims`"]),
    # A comparison is not an assignment.
    ("modules/common/Config.qml",
     "Singleton {\n    readonly property bool fast: readWriteDelay === 0\n}\n",
     []),
]


def self_check():
    """Every fixture's expected offences, and only those."""
    failures = []
    for rel, source, expected in FIXTURES:
        found = offences_for(rel, source)
        for needle in expected:
            if not any(needle in offence for offence in found):
                failures.append(
                    f"self-check: {rel} fixture should have reported {needle!r}, got {found}")
        if len(found) != len(expected):
            failures.append(
                f"self-check: {rel} fixture expected {len(expected)} offence(s), got {found}")
    return failures


def main() -> int:
    failures = self_check()

    swept = 0
    for path in sorted(ROOT.rglob("*.qml")):
        rel = path.relative_to(ROOT)
        if any(part in SKIP_DIRS for part in rel.parts):
            continue
        try:
            source = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        swept += 1
        failures.extend(offences_for(rel.as_posix(), source))

    if not swept:
        failures.append(
            "the sweep found no QML at all, so a clean run says nothing - "
            "check the tree layout rather than trusting this result")

    if not CLAIM.exists():
        failures.append(
            "modules/common/ConfigWriteDelayRef.qml is gone. It is the only "
            "sanctioned way to ask for an undebounced config write; without it "
            "the next surface that wants one assigns the global again.")

    if CONFIG.exists():
        config_text = strip_comments(CONFIG.read_text(encoding="utf-8"))
        if not DERIVED_DELAY.search(config_text):
            failures.append(
                "modules/common/Config.qml no longer derives `readWriteDelay` "
                "readonly from `immediateWriteClaims`. A settable property here "
                "re-opens the leak silently: every other check in this file "
                "would stay green over it.")
    else:
        failures.append("modules/common/Config.qml is missing")

    if failures:
        print("config write delay claim lint failed:\n", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1

    print(f"config write delay claim lint passed ({swept} QML files): the delay is "
          f"resolved from claims, every claim states its condition, and no claim "
          f"inside the shell is held for the session")
    return 0


if __name__ == "__main__":
    sys.exit(main())
