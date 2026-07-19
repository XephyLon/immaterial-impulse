#!/usr/bin/env python3
#
# Regression guard: spacing/padding/margin properties must use Appearance.spacing
# tokens, not raw pixel literals. The scale is 1, 2, 4, 8, 12, 16, 20, 24
# (hairline, unsharpen, verysmall, small, normal, large, verylarge, huge) - small
# values 1/2 for fine control, then multiples of 4. Any raw value in that range
# should be snapped to the nearest token.
#
# Conservative on purpose: it flags a property *assignment* whose value is a bare
# integer in the token range (|n| in 1..24). It ignores:
#   - 0 (a real "no gap")
#   - large one-off dimensions (|n| > 24)
#   - property *declarations* (e.g. `property int padding: 10` - a config/default,
#     not a usage), matched only when the property starts the line.
#
# Exits non-zero listing offenders. Wired into run_tests.sh / CI.

import re, glob, os, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "modules")
ROOT = os.path.normpath(ROOT)

PROP = re.compile(
    r'^\s*(spacing|padding|topPadding|bottomPadding|leftPadding|rightPadding'
    r'|Layout\.(?:margins|leftMargin|rightMargin|topMargin|bottomMargin)'
    r'|anchors\.(?:margins|leftMargin|rightMargin|topMargin|bottomMargin))'
    r'\s*:\s*(-?\d+)\s*$'
)

violations = []
for f in glob.glob(ROOT + "/**/*.qml", recursive=True):
    for i, line in enumerate(open(f)):
        m = PROP.match(line)
        if not m:
            continue
        n = int(m.group(2))
        if n == 0 or abs(n) > 24:
            continue
        violations.append((os.path.relpath(f, ROOT), i + 1, m.group(1), n))

if violations:
    print("Spacing lint FAILED: raw pixel values must use Appearance.spacing tokens "
          "(scale 1,2,4,8,12,16,20,24 - snap to nearest):", file=sys.stderr)
    for rel, ln, prop, n in violations:
        print(f"  modules/{rel}:{ln}  {prop}: {n}", file=sys.stderr)
    sys.exit(1)

print("Spacing lint passed: no raw spacing/padding/margin literals in token range")
sys.exit(0)
