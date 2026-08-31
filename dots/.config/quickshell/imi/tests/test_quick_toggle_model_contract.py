#!/usr/bin/env python3
"""Source contract: what keeps the quick toggle grid's delegates alive.

`tests/tst_quick_toggle_layout.qml` scores the arithmetic and
`QuickTogglesLayoutRuntimeTest.qml` drives the real panel, but the second needs
a Wayland session and skips in CI - which is exactly where the three rules below
would be undone quietly, because every one of them fails by being SILENT. A
delegate rebuilt where it should have moved renders the right grid; a chooser
keyed on a rewritable role renders the wrong toggle only after an edit; and a
sync that runs per notification renders correctly a fraction of a second after
destroying the tile the user was dragging.

Each rule is a thing this branch measured rather than a preference:

  * the chooser picks on an IDENTITY role, because `DelegateChooser` never
    re-picks for a delegate it can keep (81379796b);
  * the model writes only PAYLOAD roles, so no spelling in it can retype a live
    row;
  * the panel syncs once per turn, because a live `list<var>` notifies per
    element written - one `moveInPlace` on the stored list was observed in nine
    intermediate states, each a list with a toggle duplicated or missing.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
PANEL = ROOT / "modules/imi/sidebarRight/quickToggles/AndroidQuickPanel.qml"
CHOOSER = ROOT / "modules/imi/sidebarRight/quickToggles/androidStyle/AndroidToggleDelegateChooser.qml"
MODEL = ROOT / "modules/imi/sidebarRight/quickToggles/androidStyle/StableQuickToggleModel.qml"
ARITHMETIC = ROOT / "modules/common/functions/quick_toggle_layout.js"

ROLE_LIST = re.compile(r'var (?P<name>PAYLOAD_ROLES|IDENTITY_ROLES) = \[(?P<body>[^\]]*)\]')
SET_PROPERTY = re.compile(r'setProperty\s*\([^,]+,\s*(?P<role>[^,]+),')
CHOOSER_ROLE = re.compile(r'^\s*role:\s*"(?P<role>[^"]+)"', re.MULTILINE)
REPEATER_MODEL = re.compile(r'Repeater\s*\{\s*(?:\n\s*)?model:\s*(?P<model>\S+)')


def roles(name):
    body = ARITHMETIC.read_text(encoding="utf-8")
    match = next(m for m in ROLE_LIST.finditer(body) if m.group("name") == name)
    return [entry.strip().strip('"') for entry in match.group("body").split(",") if entry.strip()]


def test_the_role_lists_parse():
    # Everything below reads these two lists, so a rename that made them
    # unparseable would turn the whole module green over nothing.
    assert roles("PAYLOAD_ROLES"), "PAYLOAD_ROLES parsed to nothing"
    assert roles("IDENTITY_ROLES"), "IDENTITY_ROLES parsed to nothing"
    assert not set(roles("PAYLOAD_ROLES")) & set(roles("IDENTITY_ROLES")), \
        "a role is both identity and payload, so an update may rewrite it"


def test_the_chooser_picks_on_a_role_a_surviving_row_cannot_be_given():
    """A delegate that survives a model update keeps the component it was built
    with. That is only safe while the role the chooser picked it by is one the
    plan never writes - key it on a payload role and every resize hands the
    surviving delegate a new answer it will not act on."""
    role = CHOOSER_ROLE.search(CHOOSER.read_text(encoding="utf-8"))
    assert role, f"{CHOOSER.name} declares no chooser role"
    assert role.group("role") in roles("IDENTITY_ROLES"), (
        f"{CHOOSER.name} picks a delegate by \"{role.group('role')}\", which "
        f"quick_toggle_layout.js may rewrite on a live row")


def test_the_model_writes_no_identity_role():
    """The one thing this model may not do, written so that it cannot: the
    update branch iterates PAYLOAD_ROLES, so there is no list in this file for
    an identity role to be added to by someone extending it."""
    body = MODEL.read_text(encoding="utf-8")
    for call in SET_PROPERTY.finditer(body):
        role = call.group("role").strip()
        assert role.startswith("role") or "PAYLOAD_ROLES" in role, (
            f"{MODEL.name} writes {role} by name; a role written by name is one "
            f"an identity role can be added beside")
    for identity in roles("IDENTITY_ROLES"):
        assert f'"{identity}"' not in body, (
            f"{MODEL.name} names the identity role \"{identity}\"; the only "
            f"place a row may be given one is an insert")


def test_the_grid_is_one_flat_keyed_model_per_page():
    """A per-row model cannot move a delegate between rows; with pages the
    same rule holds per page: each page draws from ONE keyed model declared
    in its delegate, the unused shelf from its own, and no Repeater may draw
    from the raw pages value - normalise returns a fresh array every
    evaluation, so that Repeater would rebuild every delegate on every
    edit."""
    body = PANEL.read_text(encoding="utf-8")
    models = [match.group("model") for match in REPEATER_MODEL.finditer(body)]
    toggle_models = sorted(set(m for m in models if m in ("pageModel", "unusedModel")))
    assert toggle_models == ["pageModel", "unusedModel"], (
        f"the panel's toggle Repeaters draw from {models}, expected pageModel "
        f"and unusedModel")
    for name in ("pageModel", "unusedModel"):
        assert re.search(rf'StableQuickToggleModel\s*\{{\s*id:\s*{name}\b', body), (
            f"{name} is not a StableQuickToggleModel")
    for model in models:
        assert "pages" not in model, (
            f"a Repeater draws from {model}; the raw pages value rebuilds "
            f"every delegate on every edit")


def test_the_panel_syncs_once_per_turn_and_not_per_notification():
    """A burst of change notifications inside one gesture must land as one
    sync - the signature handlers go through requestSync, which coalesces
    the turn."""
    body = PANEL.read_text(encoding="utf-8")
    handlers = re.findall(r'^\s*on(?:Pages|Unused)SignatureChanged:(.*)$', body, re.MULTILINE)
    assert len(handlers) == 2, "the panel no longer observes both signatures"
    for handler in handlers:
        assert "requestSync" in handler, (
            "a signature handler syncs a model directly; it must go through "
            "requestSync, which coalesces the turn")
    assert re.search(r'function requestSync\(\)[^}]*Qt\.callLater', body, re.DOTALL), (
        "requestSync no longer defers the sync to the end of the turn")


def test_every_page_write_reassigns_the_store():
    """An inner array of a nested list<var> mutated in place never notifies
    the outer property, so the one legal write spelling is reassignment of
    the pages key. moveInPlace on the store is the regression shape."""
    chooser = CHOOSER.read_text(encoding="utf-8")
    assert "moveInPlace" not in chooser, (
        "the chooser mutates the stored list in place; nested pages must be "
        "reassigned")
    assert "Config.options.sidebar.quickToggles.android.pages =" in chooser
    panel = PANEL.read_text(encoding="utf-8")
    assert "Config.options.sidebar.quickToggles.android.toggles =" not in panel, (
        "the legacy key is the migration source and is never written")


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from contract_runner import run
    sys.exit(run(globals()))
