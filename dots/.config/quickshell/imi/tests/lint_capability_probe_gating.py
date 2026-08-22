#!/usr/bin/env python3
"""Fail if a capability flag is only probed from inside the feature that uses it.

A capability probe answers "is this tool installed" - a question the UI asks
BEFORE the feature is switched on. `OpenRgb.grimAvailable` was probed only from
`onAmbientActiveChanged`, so on any machine where the ambient RGB loop had never
been activated the flag sat at its `false` default for the whole session. And
Settings > Wallpaper & Colors reads it to caption a row:

    description: OpenRgb.grimAvailable || !OpenRgb.monitorMode
        ? "Follow the screen only while a fullscreen app runs..."
        : "The grim command was not found - install grim to sample the monitor"

So the shell told the user grim was missing while `/usr/bin/grim` was installed
and being used by the screenshot feature two menus away. Nothing errors; the
string is simply false, and only someone who reads that row with the feature off
ever sees it.

The rule: a `Process` whose command is a bare `command -v <tool>` capability
check must start on its own (`running: true`, or a `Component.onCompleted`),
not exclusively from a handler for the feature's own activation.
"""
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMMENT = re.compile(r"//[^\n]*")
PROBE_CMD = re.compile(r'command:\s*\[[^\]]*"command -v [^"]+"\s*\]')


def _block_end(text, open_brace):
    depth, i = 0, open_brace
    while i < len(text):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return len(text)


class CapabilityProbeGating(unittest.TestCase):
    def test_capability_probes_start_themselves(self):
        offenders = []
        for path in sorted(ROOT.rglob("*.qml")):
            if ".git" in path.parts:
                continue
            text = COMMENT.sub("", path.read_text(errors="ignore"))
            for match in re.finditer(r"\bProcess\s*\{", text):
                body = text[match.end():_block_end(text, match.end() - 1)]
                if not PROBE_CMD.search(body):
                    continue
                starts_itself = (
                    re.search(r"running:\s*(true|[A-Za-z_])", body)
                    or "Component.onCompleted" in body)
                if not starts_itself:
                    offenders.append(path.relative_to(ROOT).as_posix())
        self.assertEqual(
            [], offenders,
            "these run a `command -v` capability probe but never start it "
            "themselves, so the flag it sets keeps its default until something "
            "else happens to trigger it: " + ", ".join(offenders))


if __name__ == "__main__":
    sys.exit(0 if unittest.main(exit=False).result.wasSuccessful() else 1)
