#!/usr/bin/env python3
"""Every source the launcher's result builder reads is a source it observes.

`services/LauncherSearch.qml`'s `results` used to be a live binding, so QML
tracked its dependencies for it: whatever the expression touched, it re-ran
for. It is a plain property rebuilt through `Qt.callLater` now - one rebuild
per turn of the event loop instead of one per input change - and the price of
that is the tracking. `resultInputs` is the hand-written replacement, and a
source missing from it is not an error anywhere: the list simply stops
refreshing when that source answers, which for the asynchronous ones (the fd
scan, the desktop-entry registry populating seconds after startup, fourteen
settings-keyword greps, qalc) is the whole point of observing them at all.

AGENT.md's "State propagation is reactive, or it is a bug waiting" is the rule;
this is the check. For every singleton `buildResults()` names, `resultInputs`
must name it too - or it must be listed below with a reason, which is the
decision this check exists to force rather than to make.

Runs from `tests/run_tests.sh`. The self-check below runs first, on fixtures
held in this file, so the machinery is proven independently of what the tree
contains.
"""
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SHELL_ROOT = HERE.parent
SOURCE = SHELL_ROOT / "services" / "LauncherSearch.qml"

# Reviewed: named by the builder, deliberately not observed. A new entry here
# is a claim that re-reading this thing cannot change what the list shows.
EXEMPT = {
    # Language and engine namespaces - no observable state of their own.
    "Math": "JS built-in",
    "JSON": "JS built-in",
    "Object": "JS built-in",
    "Array": "JS built-in",
    "Set": "JS built-in",
    "Boolean": "JS built-in",
    "String": "JS built-in",
    "Number": "JS built-in",
    "Qt": "engine namespace; the calls here are callLater and openUrlExternally",
    "Quickshell": "clipboardText and execDetached are writes, made when a row is picked",
    # Pure helpers: functions over their arguments, holding nothing.
    "StringUtils": "pure string helpers",
    "FileUtils": "pure path helpers",
    "MathQuery": "pure .pragma library over the query text",
    # State the builder writes rather than reads.
    "GlobalStates": "written from a settings row's execute closure, never read while building",
    # The type of the objects being built.
    "LauncherSearchResult": "the enum namespace of the result type itself",
}

# The head of a dotted chain only: `LauncherSearchResult.IconType.Material` is
# one name to decide about, not three. The lookbehind is what keeps `IconType`
# out - it is reached through a name that is already accounted for.
IDENTIFIER = re.compile(r"(?<![.\w$])([A-Z][A-Za-z0-9_]*)\.")
LINE_COMMENT = re.compile(r"//[^\n]*")
BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.DOTALL)


def _strip_comments(text):
    return LINE_COMMENT.sub("", BLOCK_COMMENT.sub("", text))


def _block(source, opener):
    """The text of the brace/bracket block introduced by `opener`."""
    start = source.index(opener) + len(opener)
    close = {"{": "}", "[": "]"}[opener.strip()[-1]]
    open_char = opener.strip()[-1]
    depth = 1
    for i in range(start, len(source)):
        if source[i] == open_char:
            depth += 1
        elif source[i] == close:
            depth -= 1
            if depth == 0:
                return source[start:i]
    raise AssertionError(f"unterminated block after {opener!r}")


def offences(source):
    if "function buildResults()" not in source:
        return ["declares no buildResults(); the result list is built somewhere unchecked"]
    if "readonly property var resultInputs: [" not in source:
        return ["declares no resultInputs; nothing observes what the builder reads"]

    body = _strip_comments(_block(source, "function buildResults() {"))
    tracker = _strip_comments(_block(source, "readonly property var resultInputs: ["))

    observed = set(IDENTIFIER.findall(tracker))
    found = []
    for name in sorted(set(IDENTIFIER.findall(body))):
        if name in observed or name in EXEMPT:
            continue
        found.append(
            f"buildResults() reads `{name}` and resultInputs does not name it - "
            "the result list will not refresh when it answers")
    return found


FIXTURE_CLEAN = """
    readonly property var resultInputs: [
        root.query, Cliphist.entries,
    ]
    function buildResults() {
        const a = Cliphist.entries;
        Quickshell.clipboardText = a;
        return [root.query];
    }
"""

FIXTURE_UNOBSERVED = """
    readonly property var resultInputs: [
        root.query, Cliphist.entries,
    ]
    function buildResults() {
        const a = Cliphist.entries;
        const b = PrismLauncher.instances;
        return [a, b];
    }
"""


def main():
    if offences(FIXTURE_CLEAN):
        print("self-check: a fully observed builder was reported as an offence", file=sys.stderr)
        return 1
    if not offences(FIXTURE_UNOBSERVED):
        print("self-check: an unobserved source was not reported", file=sys.stderr)
        return 1

    problems = offences(SOURCE.read_text())
    if problems:
        print("Launcher result-input observation check failed:", file=sys.stderr)
        for problem in problems:
            print(f"  services/LauncherSearch.qml: {problem}", file=sys.stderr)
        return 1

    print("Launcher result-input observation check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
