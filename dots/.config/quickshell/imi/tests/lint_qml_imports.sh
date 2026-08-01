#!/usr/bin/env bash
#
# Regression guard: a .qml that uses the `Appearance` singleton as a bareword
# (Appearance.colors, Appearance.spacing, ...) MUST import qs.modules.common,
# where the singleton is declared. The import is NOT transitive through
# qs.modules.common.widgets. Omitting it throws "ReferenceError: Appearance is
# not defined" on every binding evaluation; when the missing token feeds a
# positioner's spacing/margin, the resulting undefined -> NaN geometry thrashes
# relayout and pegs a core at 100% CPU (see AGENT.md at the repo root). The appearance-token
# migration introduced exactly this in several files, so this check keeps it
# from coming back.
#
# Exits non-zero and lists offenders if any file references bareword
# `Appearance.` without an (unaliased) `import qs.modules.common`.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

violations=0

while IFS= read -r -d '' f; do
    # Bareword `Appearance.` = not preceded by a word char or dot (so an aliased
    # `C.Appearance.` member access does not count).
    if ! grep -qP '(?<![\w.])Appearance\.' "$f"; then
        continue
    fi
    # Needs an unaliased `import qs.modules.common` (trailing comment allowed,
    # but not `import qs.modules.common as X`).
    if grep -qP '^import qs\.modules\.common(\s*//.*)?\s*$' "$f"; then
        continue
    fi
    echo "  MISSING 'import qs.modules.common': ${f#$PROJECT_ROOT/}"
    violations=$((violations + 1))
done < <(find "$PROJECT_ROOT/modules" -name '*.qml' -print0)

if [ "$violations" -gt 0 ]; then
    echo "QML import lint FAILED: $violations file(s) use Appearance.* without importing qs.modules.common" >&2
    exit 1
fi

echo "QML import lint passed: all Appearance.* users import qs.modules.common"
exit 0
