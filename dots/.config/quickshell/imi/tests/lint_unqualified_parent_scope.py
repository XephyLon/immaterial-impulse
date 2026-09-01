#!/usr/bin/env python3
"""No unqualified `parent` inside scopes that have none.

Three bugs in one day, same shape: an unqualified `parent` written inside a
QML construct that is not an Item resolves up the component scope chain to
whatever declares the name - usually the root item's parent - and the
assignment of undefined aborts a handler or a binding silently.

  - Connections handler: `parent.lineAdvance` -> undefined -> the lyric
    glide never fired (the snap).
  - GradientStop position: `parent.parent.shownProgress` -> undefined ->
    the sweep rendered as a full solid.
  - (The first of the class, weeks earlier in spirit: any QObject-scoped
    unqualified reference.)

The rule: inside a Connections block or on a GradientStop line, `parent`
must not appear unqualified. Name the object you mean and reference the id.
Comments and strings are stripped before matching, per the suite's usual
reasoning: a comment naming the pattern must not trip the lint.
"""
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

PARENT_REF = re.compile(r"(?<![\w.])parent(?![\w])")


def strip_comments_and_strings(text):
    text = re.sub(r"/\*.*?\*/", lambda m: re.sub(r"[^\n]", " ", m.group(0)), text, flags=re.DOTALL)
    text = re.sub(r"//[^\n]*", "", text)
    text = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', text)
    text = re.sub(r"'(?:[^'\\\n]|\\.)*'", "''", text)
    text = re.sub(r"`(?:[^`\\]|\\.)*`", "``", text)
    return text


def block_spans(text, opener):
    """(start, end) spans of `opener { ... }` blocks, brace-matched."""
    spans = []
    for match in re.finditer(re.escape(opener) + r"\s*\{", text):
        depth, i = 0, match.end() - 1
        for j in range(i, len(text)):
            if text[j] == "{":
                depth += 1
            elif text[j] == "}":
                depth -= 1
                if depth == 0:
                    spans.append((match.start(), j + 1))
                    break
    return spans


def offences(path):
    text = strip_comments_and_strings(path.read_text(encoding="utf-8"))
    found = []
    for start, end in block_spans(text, "Connections"):
        body = text[start:end]
        for m in PARENT_REF.finditer(body):
            line = text[:start + m.start()].count("\n") + 1
            found.append(f"{path.relative_to(ROOT)}:{line} unqualified `parent` in Connections")
    for m in re.finditer(r"GradientStop\s*\{[^}]*\}", text):
        if PARENT_REF.search(m.group(0)):
            line = text[:m.start()].count("\n") + 1
            found.append(f"{path.relative_to(ROOT)}:{line} unqualified `parent` in GradientStop")
    return found


class UnqualifiedParentScopeTests(unittest.TestCase):
    def test_selfcheck_catches_both_shapes(self):
        bad = ('Item { Connections { target: x\n'
               'function onFoo() { y = parent.width } } }\n'
               'Gradient { GradientStop { position: parent.p; color: "red" } }')
        import tempfile, os
        with tempfile.NamedTemporaryFile("w", suffix=".qml", dir=ROOT, delete=False) as f:
            f.write(bad)
            tmp = Path(f.name)
        try:
            found = offences(tmp)
        finally:
            os.unlink(tmp)
        self.assertEqual(len(found), 2, found)

    def test_selfcheck_ignores_comments_and_items(self):
        good = ('Item { // parent is fine to mention here\n'
                'Connections { target: x\nfunction onFoo() { y = box.width } } }\n'
                'Rectangle { width: parent.width }')
        import tempfile, os
        with tempfile.NamedTemporaryFile("w", suffix=".qml", dir=ROOT, delete=False) as f:
            f.write(good)
            tmp = Path(f.name)
        try:
            found = offences(tmp)
        finally:
            os.unlink(tmp)
        self.assertEqual(found, [])

    def test_tree_is_clean(self):
        broken = []
        for path in sorted(ROOT.rglob("*.qml")):
            if "tests/" in str(path.relative_to(ROOT)):
                continue
            broken += offences(path)
        self.assertEqual(broken, [], "\n".join(
            ["Unqualified `parent` in a scope that has none - name the id:"] + broken))


if __name__ == "__main__":
    unittest.main()
