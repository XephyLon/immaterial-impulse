#!/usr/bin/env python3
"""The left sidebar's tab set, pinned.

`SidebarLeftContent.qml` holds the tabs as parallel literal arrays that
have to stay index-aligned by hand: the tab-bar entries (`tabButtonList`),
the untranslated ids a deep link resolves against (`tabIdList`), and the
SwipeView's `contentChildren`. There is no registry behind them, so a tab
added on one side alone shows the WRONG PAGE - silently, because every
index is still a valid index. That is a class of bug nothing else in the
suite can see: the QML tests never build these widgets, and a mis-aligned
SwipeView renders perfectly.

Two asymmetries make the alignment fragile enough to be worth a check
rather than a comment. The placeholder page sits between the last real tab
and Anime with NO tab-bar entry of its own, and closet mode
(`policies.weeb === 2`) puts an Anime PAGE in the SwipeView with no entry
either - so the two lists are legitimately different lengths, and only the
entries before the placeholder are aligned. A reader who "fixes" that by
adding a placeholder entry, or who appends a new tab after Anime, breaks
the alignment in a way that reads correctly.

Shaped after `tests/test_edit_mode_contract.py`'s tab-list check, which is
the only other place in the tree that pins a tab set.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTENT = ROOT / "modules" / "imi" / "sidebarLeft" / "SidebarLeftContent.qml"
BAR_BUTTON = ROOT / "modules" / "imi" / "bar" / "LeftSidebarButton.qml"
GLOBAL_STATES = ROOT / "GlobalStates.qml"

# Every tab, in order: the gate it is drawn behind, the label the tab bar
# shows, the id a deep link names, and the component the SwipeView builds.
# A tab added to the shell is a row here and nowhere else in this file.
TABS = [
    ("root.aiChatEnabled", "Intelligence", "intelligence", "aiChat"),
    ("root.translatorEnabled", "Translator", "translator", "translator"),
    ("root.mediaEnabled", "Media", "media", "media"),
    ("root.phoneEnabled", "Phone", "phone", "phone"),
    # Anime's tab-bar entry carries the extra `!animeCloset` term: in closet
    # mode the page is still built and the entry is not.
    ("(root.animeEnabled && !root.animeCloset)", "Anime", "anime", "anime"),
]


def _array(name: str) -> str:
    text = CONTENT.read_text()
    match = re.search(rf"{name}:\s*\[(.*?)\n\s*\]", text, re.S)
    assert match, f"{name} is not declared as a literal array in SidebarLeftContent.qml"
    return match.group(1)


def test_the_tab_bar_draws_the_declared_tabs_in_order():
    entries = re.findall(r'\{"icon": "(\w+)", "name": Translation\.tr\("([\w ]+)"\)\}',
                         _array("tabButtonList"))
    assert [name for _, name in entries] == [tab[1] for tab in TABS], (
        f"the tab bar draws {[name for _, name in entries]}, expected {[t[1] for t in TABS]}"
    )
    assert all(icon for icon, _ in entries), "a tab entry carries no icon"


def test_every_tab_bar_entry_is_gated_on_that_tab_s_own_flag():
    lines = [line.strip() for line in _array("tabButtonList").splitlines() if line.strip()]
    assert len(lines) == len(TABS), f"expected {len(TABS)} tab entries, found {len(lines)}"
    for line, (gate, name, _, _) in zip(lines, TABS):
        assert line.startswith(f"...({gate} ?"), (
            f'the "{name}" entry is gated on {line.split("?")[0]!r}, not on {gate}'
        )


def test_the_ids_are_index_aligned_with_the_tab_bar_and_are_not_translated():
    """The ids exist because a deep link cannot resolve against the labels:
    every `name` in the tab bar is a Translation.tr(...) call, so a link
    matched on one stops working the moment the user changes language - and
    silently, since `indexOf` returns -1 and the sidebar simply opens on
    whichever tab was last shown. The same trap 1c674c8f5 fixed for the
    settings deep link. An INDEX is not the alternative either: a hardcoded
    one goes stale the day a tab is inserted."""
    ids = _array("tabIdList")
    assert "Translation.tr" not in ids, "a tab id goes through Translation.tr"
    lines = [line.strip() for line in ids.splitlines() if line.strip()]
    assert len(lines) == len(TABS), f"expected {len(TABS)} tab ids, found {len(lines)}"
    for line, (gate, name, tab_id, _) in zip(lines, TABS):
        assert line.startswith(f'...({gate} ? ["{tab_id}"]'), (
            f'the id row for "{name}" is {line!r}, expected {gate} -> ["{tab_id}"]'
        )


def test_the_pages_carry_the_same_tabs_in_the_same_order_before_the_placeholder():
    """The SwipeView is where a mis-alignment actually costs something, and
    it is legitimately LONGER than the tab bar: the placeholder has no entry
    and closet mode's Anime page has none either. So the check is that every
    tab's page comes before the placeholder, in the tab bar's own order."""
    children = _array("contentChildren")
    lines = [line.strip() for line in children.splitlines() if line.strip()]
    placeholder = [i for i, line in enumerate(lines) if "placeholder.createObject()" in line]
    assert len(placeholder) == 1, "expected exactly one placeholder page"
    before = lines[:placeholder[0]]
    assert len(before) == len(TABS) - 1, (
        f"expected the {len(TABS) - 1} non-Anime pages before the placeholder, found {before}"
    )
    for line, (gate, name, _, component) in zip(before, TABS[:-1]):
        assert line.startswith(f"...({gate} ?"), (
            f'the "{name}" page is gated on {line.split("?")[0]!r}, not on {gate}'
        )
        assert f"{component}.createObject()" in line, (
            f'the "{name}" page builds {line!r}, expected {component}.createObject()'
        )
    after = lines[placeholder[0] + 1:]
    assert len(after) == 1 and "anime.createObject()" in after[0], (
        f"only the Anime page may follow the placeholder, found {after}"
    )
    assert after[0].startswith("...(root.animeEnabled ?"), (
        "the Anime PAGE is gated on animeEnabled alone - closet mode hides its "
        f"tab entry, not the page: {after[0]!r}"
    )


def test_a_tab_request_is_resolved_against_the_ids_and_then_cleared():
    """`GlobalStates.sidebarLeftTab` is consumed, not merely read. Left set,
    the sidebar would return to that tab on every later open - the deep link
    would stop being a link and become a preference nobody chose."""
    text = CONTENT.read_text()
    show = re.search(r"function showTab\(.*?\n    \}", text, re.S)
    assert show, "showTab() missing - nothing resolves a tab request"
    assert "root.tabIdList.indexOf(id)" in show.group(0), (
        "showTab resolves against something other than the id list"
    )
    assert "if (index < 0) return;" in show.group(0), (
        "an unknown id must be declined, not applied as an index"
    )
    consume = re.search(r"function consumeTabRequest\(.*?\n    \}", text, re.S)
    assert consume, "consumeTabRequest() missing"
    assert 'GlobalStates.sidebarLeftTab = ""' in consume.group(0), (
        "the request is not cleared once honoured"
    )
    assert "root.consumeTabRequest();" in text, "nothing calls consumeTabRequest()"
    assert re.search(r"^\s*property string sidebarLeftTab: \"\"$", GLOBAL_STATES.read_text(), re.M), (
        "GlobalStates.sidebarLeftTab is not a string defaulting to empty"
    )


def test_the_bar_button_is_hidden_only_when_every_tab_is_off():
    """A user who has switched everything off but one tab must still have a
    way into the sidebar from the bar. The button already omits
    `mediaEnabled` - a known hole, kept rather than widened here - so this
    pins the tabs the button does claim to cover, Phone included."""
    text = BAR_BUTTON.read_text()
    visible = re.search(r"^\s*visible: (.+)$", text, re.M)
    assert visible, "the bar button declares no visibility"
    terms = {term.strip() for term in visible.group(1).split("||")}
    for flag in ("aiChatEnabled", "translatorEnabled", "animeEnabled", "phoneEnabled"):
        assert flag in terms, f"the bar button's visibility does not include {flag}"
        assert re.search(rf"^\s*property bool {flag}:", text, re.M), (
            f"{flag} is not declared on the bar button"
        )


if __name__ == "__main__":
    import sys
    from contract_runner import run
    sys.exit(run(globals()))
