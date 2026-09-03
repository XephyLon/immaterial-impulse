#!/usr/bin/env python3
"""The clock's options page shows only the chosen style's rows.

The clock declares 28 options for three styles, and every one of them rendered
whether or not the style it belongs to was selected: eleven `cookie*` rows on
a digital clock, five `digitalFont*` rows on a cookie. The manifest says which
style each row belongs to in its own key prefix, so the rule is mechanical: a
`digital*`, `cookie*` or `pixel*` option carries a `visibleWhen` that matches
that style on `style` OR on `styleLocked` - the desktop and the lock screen can
show different clocks, and a row has something to say if either of them is the
style it configures.

`color` is the one row whose key does not carry its style; its label does
("Digital: color"), and Widget.qml reads it inside the digital block only.

The predicate itself is pinned by tst_option_visibility.qml. This is the
adoption, which is what decays: a 29th option added without a rule renders on
every style again and nothing notices.
"""

import json
import re
from pathlib import Path

from contract_runner import run

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "modules/common/plugins/bundled/clock/manifest.json"
STYLES = ("digital", "cookie", "pixel")
# Rows every style shares. Anything else must name a style.
SHARED = {"style", "styleLocked", "showOnlyWhenLocked", "quoteEnable", "quoteFollowClock", "quoteText"}
# Rows whose key does not carry the style they belong to.
STYLE_OF = {"color": "digital"}


def options():
    manifest = json.loads(MANIFEST.read_text())
    opts = manifest.get("options") or []
    assert len(opts) >= 20, f"the clock manifest has {len(opts)} options - this sweep expects the real one"
    return opts


def expected_style(key: str):
    if key in STYLE_OF:
        return STYLE_OF[key]
    for style in STYLES:
        if key.startswith(style):
            return style
    return None


def matches(rule, style: str) -> bool:
    """Whether `rule` is exactly 'style == S on either key'."""
    branches = rule.get("anyOf") if isinstance(rule, dict) else None
    if not isinstance(branches, list) or len(branches) != 2:
        return False
    keys = sorted(b.get("key") for b in branches if isinstance(b, dict))
    return keys == ["style", "styleLocked"] and all(b.get("in") == [style] for b in branches)


def test_every_style_bound_row_is_gated_on_its_style():
    seen = 0
    for option in options():
        key = option["key"]
        style = expected_style(key)
        if style is None:
            assert key in SHARED, \
                (f"clock option `{key}` names no style and is not in the shared set - either "
                 "prefix it with its style, add it to STYLE_OF, or say here that every style shows it")
            assert "visibleWhen" not in option, \
                f"shared clock option `{key}` carries a visibleWhen - it is shown on every style"
            continue
        seen += 1
        assert "visibleWhen" in option, \
            f"clock option `{key}` belongs to the {style} style and has no visibleWhen - it renders on every style"
        assert matches(option["visibleWhen"], style), \
            (f"clock option `{key}`'s rule is {option['visibleWhen']!r}; expected {style} on "
             "`style` OR `styleLocked` - the desktop and the lock screen can show different clocks")
    assert seen >= 20, f"only {seen} style-bound rows found - the sweep is looking at the wrong file"


def test_style_bound_rows_are_grouped_and_carry_no_style_prefix():
    # The style is the group's heading, not each label's first word: eleven
    # "Cookie: ..." rows read as a list of one word (the maintainer, 2026-09-03).
    for option in options():
        style = expected_style(option["key"])
        if style is None and not option["key"].startswith("quote"):
            continue
        assert option.get("group"), f"{option['key']} names no group; its heading is what says which style it belongs to"
        assert not re.match(r"^(Digital|Cookie|Pixel|Quote): ", option.get("label", "")), \
            f"{option['key']} still spells its group into its label: {option.get('label')!r}"


def test_no_style_is_left_without_rows():
    by_style = {s: 0 for s in STYLES}
    for option in options():
        style = expected_style(option["key"])
        if style:
            by_style[style] += 1
    for style, count in by_style.items():
        assert count >= 1, f"the {style} style has no options of its own - did a prefix change?"


if __name__ == "__main__":
    raise SystemExit(run(globals()))
