#!/usr/bin/env python3
#
# Regression guard: spacing/padding/margin properties must use Appearance.spacing
# tokens, not raw pixel literals. The Material 3 system scale is
# 0,2,4,8,12,16,20,24,32,36,40,48,56,64,72 - the two fine values, then
# multiples of 4. Any raw spacing value in
# that range should be snapped to the nearest token.
#
# It flags property assignments and spacing-like local property declarations
# containing integer literals in the M3 token range. It ignores:
#   - 0 (a real "no gap")
#   - large one-off dimensions (|n| > 72)
#   - Config.qml schema defaults (Appearance depends on Config)
#
# Exits non-zero listing offenders. Wired into run_tests.sh / CI.

import re, glob, os, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "modules")
ROOT = os.path.normpath(ROOT)

PROP = re.compile(
    r'^\s*(spacing|padding|topPadding|bottomPadding|leftPadding|rightPadding'
    r'|Layout\.(?:margins|leftMargin|rightMargin|topMargin|bottomMargin)'
    r'|anchors\.(?:margins|leftMargin|rightMargin|topMargin|bottomMargin))'
    r'\s*:\s*(.+)$'
)

DECL = re.compile(
    r'^\s*property\s+(?:int|real)\s+'
    r'(\w*(?:spacing|padding|margin)\w*)\s*:\s*(.+)$',
    re.IGNORECASE,
)

BARE_LITERAL = re.compile(r'^\s*(-?\d+)\s*$')
BRANCH_LITERAL = re.compile(r'(?:\?|:)\s*(-?\d+)(?=\s*(?:[:,)]|$))')

LEGACY_ALIAS = re.compile(
    r'Appearance\.spacing\.('
    r'hairline|unsharpen|verysmall|small|normal|large|verylarge|huge'
    # Retired: the scale keeps 2 and 4, then multiples of 4 only. 6, 10 and 14
    # round up to space100, space150 and space200.
    r'|space75|space125|space175'
    r')\b'
)

violations = []
for f in glob.glob(ROOT + "/**/*.qml", recursive=True):
    rel = os.path.relpath(f, ROOT)
    for i, line in enumerate(open(f)):
        legacy = LEGACY_ALIAS.search(line)
        if legacy:
            violations.append((rel, i + 1,
                               "legacy alias", legacy.group(1)))
            continue

        m = PROP.match(line)
        if not m and rel != "common/Config.qml":
            m = DECL.match(line)
        if not m:
            continue
        expression = m.group(2).split("//", 1)[0]
        bare = BARE_LITERAL.match(expression)
        literals = [bare.group(1)] if bare else BRANCH_LITERAL.findall(expression)
        for literal in literals:
            n = int(literal)
            if n == 0 or abs(n) > 72:
                continue
            violations.append((rel, i + 1, m.group(1), n))

if violations:
    print("Spacing lint FAILED: raw pixel values must use Appearance.spacing tokens "
          "(scale 0,2,4,8,12,16,20,24,32,36,40,48,56,64,72 - snap to nearest):", file=sys.stderr)
    for rel, ln, prop, n in violations:
        print(f"  modules/{rel}:{ln}  {prop}: {n}", file=sys.stderr)
    sys.exit(1)

print("Spacing lint passed: no raw spacing/padding/margin literals in token range")
sys.exit(0)
