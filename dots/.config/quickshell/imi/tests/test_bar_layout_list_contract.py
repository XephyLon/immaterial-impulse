#!/usr/bin/env python3
"""Source contract: the Bar layout section stays on the shared arithmetic.

The reorderable list is dumb and the section is its coordinator, which is
exactly the split BarEditController already proved for the same three
lists - so the rules are the same ones its contract states: every write
goes through layout_ops, the stored paths are literal, and no second copy
of the reorder arithmetic grows in the page.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
PAGE = ROOT / "modules/imi/settings/pages/BarConfig.qml"
WIDGET = ROOT / "modules/common/widgets/ReorderableList.qml"


def test_the_section_commits_only_through_layout_ops():
    body = PAGE.read_text(encoding="utf-8")
    writes = re.findall(r'Config\.options\.bar\.layouts\.\w+Layout\s*=\s*(.+)$',
                        body, re.MULTILINE)
    assert writes, "the page no longer writes the bar layouts at all"
    for rhs in writes:
        assert "LayoutOps." in rhs or rhs.strip() in ("list;", "list"), (
            f"a layout write bypasses layout_ops: {rhs.strip()}")
    assert "writeLayout" in body and "storedLayout" in body, (
        "the literal-path helpers are gone; a computed store key is not an "
        "allowlist")


def test_the_page_uses_the_reorderable_list_and_the_chips_are_gone():
    body = PAGE.read_text(encoding="utf-8")
    assert "ReorderableList" in body
    # Word-bounded: the section's own id is barLayoutSection, which is not
    # a use of the retired widget.
    assert not re.search(r"\bLayoutSection\b", body), (
        "the chip flows must be fully retired")
    assert not (ROOT / "modules/common/widgets/LayoutSection.qml").exists(), (
        "LayoutSection lost its only consumer and is deleted with this change")


def test_the_widget_stays_dumb():
    """Belt beside lint_dumb_widgets' braces: the widget the section leans
    on must never grow a store of its own."""
    body = WIDGET.read_text(encoding="utf-8")
    for forbidden in ("Config.options", "GlobalStates.", "execDetached", "Process {"):
        assert forbidden not in body, f"ReorderableList reaches for {forbidden}"


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from contract_runner import run
    sys.exit(run(globals()))
