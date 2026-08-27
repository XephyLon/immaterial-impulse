#!/usr/bin/env python3
"""JavaScript this tree may not use, because CI's Qt is older than yours.

The QML engine's JS dialect is the Qt version's, and the two Qts in play are
not the same one: a developer here runs Arch's current qt6-declarative, while
`.github/workflows/tests.yml` installs Ubuntu's. Syntax the newer parser
accepts is a COMPILE error on the older one, and a compile error in a
`tst_*.qml` reads as `FAIL!  : ...::compile() Unexpected token` with no hint
about which token or why - green on the machine that wrote it, red only after
the push.

That is what happened to `tst_phone_cards.qml`: numeric separators
(`1_090_000`, ES2021) parsed here and did not parse there, where `1` is a
number and `_090_000` is an identifier - hence "Unexpected token
`identifier'". Seven of them, seven errors.

So the rule is written down instead of remembered. Each construct below is
banned with the plain-JS spelling that replaces it; nothing here is about
style, only about what both parsers accept.

Strings, template literals and comments are stripped before matching, because
`"alsa_output.pci-0000_00_1f.3"` is a device name, not a numeric separator,
and a rule that cannot tell the difference is a rule people delete.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCAN_DIRS = ("modules", "services", "tests", "scripts")
SUFFIXES = (".qml", ".js")

# (name, pattern, what to write instead)
BANNED = (
    (
        "numeric separator",
        re.compile(r"(?<![\w.])\d[\d]*_[\d_]*\d(?![\w.])"),
        "write the digits without underscores (1090000, not 1_090_000)",
    ),
    (
        "logical assignment",
        re.compile(r"(?<![=!<>])(\?\?=|\|\|=|&&=)"),
        "write it out (a = a ?? b), which every Qt parses",
    ),
    (
        "optional catch binding",
        re.compile(r"\bcatch\s*\{"),
        "name the error (catch (e) {}), even when it goes unused",
    ),
)


def strip_literals(source: str) -> str:
    """Blank out comments and string bodies, keeping line structure intact.

    Replacing rather than deleting keeps every line number honest, so a hit
    reports the line the author has to open.
    """
    out = []
    i = 0
    n = len(source)
    while i < n:
        ch = source[i]
        if ch == "/" and i + 1 < n and source[i + 1] == "/":
            j = source.find("\n", i)
            j = n if j == -1 else j
            out.append(" " * (j - i))
            i = j
        elif ch == "/" and i + 1 < n and source[i + 1] == "*":
            j = source.find("*/", i + 2)
            j = n if j == -1 else j + 2
            out.append("".join(c if c == "\n" else " " for c in source[i:j]))
            i = j
        elif ch in "\"'`":
            quote = ch
            j = i + 1
            while j < n:
                if source[j] == "\\":
                    j += 2
                    continue
                if source[j] == quote:
                    j += 1
                    break
                if source[j] == "\n" and quote != "`":
                    break
                j += 1
            out.append("".join(c if c == "\n" else " " for c in source[i:j]))
            i = j
        else:
            out.append(ch)
            i += 1
    return "".join(out)


def main() -> int:
    failures = []
    for directory in SCAN_DIRS:
        base = ROOT / directory
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*")):
            if path.suffix not in SUFFIXES or not path.is_file() or path.is_symlink():
                continue
            source = strip_literals(path.read_text(encoding="utf-8", errors="replace"))
            for line_no, line in enumerate(source.splitlines(), start=1):
                for name, pattern, advice in BANNED:
                    match = pattern.search(line)
                    if match:
                        failures.append(
                            f"{path.relative_to(ROOT)}:{line_no}: {name} "
                            f"`{match.group(0)}` - {advice}"
                        )

    if failures:
        print("JavaScript CI's older Qt cannot parse:")
        for failure in failures:
            print(f"  {failure}")
        print(
            "\nThese compile here and fail in CI as "
            "`compile() Unexpected token`, which names neither the file's "
            "real problem nor this rule."
        )
        return 1

    print("QML/JS dialect: no syntax CI's Qt would reject")
    return 0


if __name__ == "__main__":
    sys.exit(main())
