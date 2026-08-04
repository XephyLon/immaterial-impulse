#!/usr/bin/env bash
#
# Regression guard: a .qml that uses a singleton as a bareword MUST import the
# module that singleton is declared in. QML imports are NOT transitive -
# `import qs.modules.common` does not bring in `qs.modules.common.functions` -
# and a missing one is not a load-time error. The bareword simply stays
# unresolved, and every use throws "ReferenceError: <X> is not defined" when it
# is evaluated. Inside a signal handler that means the handler silently does
# nothing at all.
#
# Two real bugs of exactly this shape:
#
#   Appearance - the appearance-token migration dropped `import qs.modules.common`
#                from several files. The undefined token feeds a positioner's
#                spacing/margin as NaN, relayout thrashes and a core pegs at 100%
#                CPU (see AGENT.md at the repo root).
#   Session    - services/EfiBoot.qml called Session.reboot() while importing only
#                qs.modules.common. "Reboot Into" armed the firmware's BootNext
#                through pkexec, the reboot call then threw ReferenceError, and
#                nothing happened - leaving the machine silently configured to
#                boot a different OS at its next restart, whenever that was (#104).
#
# That second one is why this check is now table-driven and scans services/ as
# well as modules/: the original knew only about Appearance and looked only under
# modules/, so it missed EfiBoot.qml on both counts.
#
# Adding a singleton to CHECKS costs one line and buys a whole class of silent
# failure. Exits non-zero and lists offenders.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# singleton:module-that-declares-it
CHECKS=(
    "Appearance:qs.modules.common"
    "Session:qs.modules.common.functions"
    "ColorUtils:qs.modules.common.functions"
    "StringUtils:qs.modules.common.functions"
)

# services/ is included deliberately: EfiBoot.qml lives there, not under modules/.
SEARCH_DIRS=("$PROJECT_ROOT/modules" "$PROJECT_ROOT/services")

violations=0

for check in "${CHECKS[@]}"; do
    singleton="${check%%:*}"
    module="${check#*:}"
    # Anchored at both ends, so `import qs.modules.common` cannot satisfy a
    # requirement for `qs.modules.common.functions`. Trailing comment allowed;
    # an aliased `... as X` is not.
    module_escaped="${module//./\\.}"

    while IFS= read -r -d '' f; do
        # A singleton's own declaration file refers to itself; skip it.
        [[ "$(basename "$f")" == "$singleton.qml" ]] && continue
        # Match against CODE only. Prose naming a singleton is not a use of it,
        # and a lint that cannot tell the difference gets switched off the first
        # time it fires on a comment explaining why the singleton is not used
        # here. Strips // line comments and /* */ block comments.
        code="$(sed 's://.*::' "$f" | sed ':a;N;$!ba;s:/\*[^*]*\*\+\([^/*][^*]*\*\+\)*/::g')"
        # Bareword `X.` = not preceded by a word char or a dot, so an aliased
        # `C.Appearance.foo` member access does not count.
        grep -qP "(?<![\w.])${singleton}\." <<<"$code" || continue
        grep -qP "^import ${module_escaped}(\s*//.*)?\s*\$" "$f" && continue
        echo "  MISSING 'import $module' (uses $singleton.*): ${f#$PROJECT_ROOT/}"
        violations=$((violations + 1))
    done < <(find "${SEARCH_DIRS[@]}" -name '*.qml' -print0 2>/dev/null)
done

if [ "$violations" -gt 0 ]; then
    echo "QML import lint FAILED: $violations file(s) use a singleton without importing its declaring module" >&2
    exit 1
fi

echo "QML import lint passed: all singleton users import the declaring module"
exit 0
