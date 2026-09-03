#!/usr/bin/env python3
"""Two widget layouts in one store, and the places that must agree about it.

Spec §4.3 as amended 2026-08-18: the lock screen's widget layout inherits the
desktop's until the first move on the Lockscreen tab forks it. The arithmetic
is `layout_surfaces.js` and `tst_layout_surfaces.qml` drives it bare; the real
drag path is `EditModeRuntimeTest.qml`. What this module pins is the drift that
would be silent between them:

- every position WRITE that can be undone captures the surface at push time -
  a closure that resolved it at pop time writes a lock position into the
  desktop store when the user undoes from the other tab, and the store still
  reads as valid;
- the store carries `lockPositions` beside `desktopPositions` from the empty
  state, through the loader's shape check, and through `presets.sh` in BOTH
  directions - a preset saved by this shell carries the lock layout, and a
  preset from an older shell that lacks the key does not wipe a user's fork
  (the same `has()` shape the desktop map already uses);
- PRESENCE forks under that same rule and in the same file, and the master
  gate stays above it: `lock.showWidgets` is what a user already has set, so
  the per-widget choice is a term beside it rather than a replacement for it;
- the surface a read or write follows by DEFAULT is the one derivation of the
  lock look, so a widget on the Lockscreen tab and a widget under a real lock
  read the same store.

Sweeps assert they FOUND what they swept.
"""

import re
from pathlib import Path

from contract_runner import run

ROOT = Path(__file__).resolve().parent.parent
MODULE = ROOT / "modules/common/plugins/layout_surfaces.js"
STATE = ROOT / "modules/common/plugins/PluginState.qml"
WIDGET = ROOT / "modules/common/plugins/PluginWidget.qml"
CHROME_SURFACE = ROOT / "modules/imi/editMode/EditModeChromeSurface.qml"
PRESETS = ROOT / "scripts/presets.sh"


def read(path: Path) -> str:
    assert path.exists(), f"{path} is gone - the sweep has nothing to look at"
    text = path.read_text()
    assert text.strip(), f"{path} is empty"
    return text


def code(path: Path) -> str:
    text = re.sub(r"/\*.*?\*/", "", read(path), flags=re.S)
    return "\n".join(re.sub(r"//.*$", "", line) for line in text.splitlines())


def test_the_default_surface_is_the_lock_look_derivation():
    state = code(STATE)
    match = re.search(r"currentSurface:\s*GlobalStates\.lockLookActive", state)
    assert match, ("PluginState.currentSurface must read GlobalStates.lockLookActive - "
                   "the ONE derivation of the lock look - so the Lockscreen tab and a "
                   "real lock read the same store")
    for fn in ("rawPosition", "position", "setPosition"):
        sig = re.search(rf"function {fn}\(([^)]*)\)", state)
        assert sig and "surface" in sig.group(1), \
            f"PluginState.{fn} must take an explicit surface parameter"
    assert "surface ?? root.currentSurface" in state, \
        "an omitted surface must fall back to currentSurface, not to the desktop"


def test_every_undoable_position_write_captures_its_surface_at_push_time():
    # The widget's own drag commit.
    widget = code(WIDGET)
    drag = re.search(r"const surface = PluginState\.currentSurface;(.*?)PluginState\.setPosition\(id, screenName,",
                     widget, re.S)
    assert drag, "PluginWidget's drag commit must capture `surface` before pushing its undo"
    # The entry is edit_mode.js's swap now (undo AND redo from one closure);
    # its write lambda is where the captured surface must appear.
    assert re.search(r"editUndoPush\(EditMode\.swap\(\s*\(\) => PluginState\.position\(id, screen, surface\),"
                     r"\s*\(value\) => PluginState\.setPosition\(id, screen, value, surface\),\s*before\)\)",
                     drag.group(1)), \
        ("PluginWidget's undo entry must read and write the CAPTURED surface - resolving it at "
         "pop time writes a lock position into the desktop store from the other tab")
    assert re.search(r"placementStrategy: rootWidget\.placementStrategy\s*\}, surface\);", widget), \
        "PluginWidget's forward write must land on the captured surface too"

    # The drawer's drop.
    chrome = code(CHROME_SURFACE)
    drop = re.search(r"const surface = PluginState\.currentSurface;(.*?)root\.enablePlugin\(manifest\.id\);",
                     chrome, re.S)
    assert drop, "the drawer drop must capture `surface` before pushing its undo"
    assert "PluginState.setPosition(id, screen, value.position, surface)" in drop.group(1) \
        and "position: beforePosition" in drop.group(1), \
        "the drop's undo entry must write the captured position back on the captured surface"
    assert re.search(r"placementStrategy: \"free\" \}, surface\);", drop.group(1)), \
        "the drop's forward write must land on the captured surface"
    assert "PluginState.rawPosition(id, screen, surface)" in drop.group(1), \
        ("the drop's 'had a position before' check must ask the RAW store on the same "
         "surface - position() answers the default for an absent entry")

    # The re-link.
    assert re.search(r"function resetLockLayout\(\)", chrome), \
        "the chrome surface no longer offers the lock layout re-link"
    reset = re.search(r"function resetLockLayout\(\)(.*?)\n    \}", chrome, re.S)
    assert reset and "GlobalStates.editUndoPush" in reset.group(1), \
        "the re-link must be undoable"


def test_every_widget_option_read_and_write_names_its_surface():
    # A widget's own settings fork per surface too (2026-09-03: the resource
    # monitor rotated for the lock screen was rotated on the desktop). The
    # store's accessors take a trailing surface with the position API's
    # default; Settings names its surface on EVERY call, because its switch
    # and not the look the desktop is showing is what the user pressed.
    state = code(STATE)
    for fn in ("option", "setOption"):
        sig = re.search(rf"function {fn}\(([^)]*)\)", state)
        assert sig and "surface" in sig.group(1), \
            f"PluginState.{fn} must take an explicit surface parameter"
    assert "Surfaces.rawOption(root.state, surface ?? root.currentSurface" in state, \
        "option() must read through layout_surfaces.rawOption on the default surface"
    assert "Surfaces.withOption(root.state, surface ?? root.currentSurface" in state, \
        "setOption() must write through layout_surfaces.withOption on the default surface"
    assert re.search(r"lockOptions: parsed\.lockOptions", state), \
        "loadText must carry lockOptions, or a restart forgets every lock setting"

    options = code(ROOT / "modules/common/plugins/PluginOptions.qml")
    assert 'property string surface: PluginState.desktopSurface' in options, \
        "PluginOptions must own the surface its rows edit"
    calls = re.findall(r"PluginState\.(?:option|setOption)\([^;]*?\)", options, re.S)
    assert len(calls) >= 15, f"expected the card's reads and writes, found {len(calls)}"
    naked = [call for call in calls if "root.surface" not in call]
    assert naked == [], \
        "every PluginOptions read and write must pass root.surface:\n" + "\n".join(naked)
    assert "Surfaces.isSharedOptionKey(modelData.key)" in options, \
        "the lock card must hide the shared policy toggles"
    assert "root.onLock ? [] : GridSizes.offeredSizes(manifest.grid)" in options, \
        "the lock card offers no size row - the lock's span lives in its layout record"

    presets = read(ROOT / "scripts/presets.sh")
    assert presets.count("lockOptions: (.lockOptions // {})") == 3, \
        "presets.sh must capture lockOptions in every state shape it builds"
    assert 'if ($preset | has("lockOptions"))' in presets, \
        "presets.sh must apply lockOptions under the has() rule lockPositions follows"
    assert ".lockOptions[$id] = $current.lockOptions[$id]" in presets, \
        "the presetPersist carve-out must shield a plugin's lock settings too"

    widget = code(WIDGET)
    for key in ("positionLocked", "clickThrough"):
        assert re.search(rf'PluginState\.option\(manifest\.id, "{key}", [^)]*\)\n', widget), \
            f"PluginWidget reads {key} with no surface - it is a shared key and must stay so"


def test_every_span_read_and_write_goes_through_the_surface_api():
    # The span forks with the position: a widget at 3x2 on the desktop and
    # 1x2 on the lock (the report) needs the lock's span in the lock record.
    # No live reader or writer of a widget's span may reach `__gridSize`
    # through PluginState.option/setOption any more - those are the DESKTOP
    # store by definition and would read/write the wrong surface on the
    # Lockscreen tab. Settings' size row is the one exception (PluginOptions):
    # it is a desktop-only control by construction.
    for path, label in ((WIDGET, "PluginWidget"),
                        (ROOT / "modules/imi/editMode/EditWidgetMenuContent.qml", "EditWidgetMenuContent"),
                        (CHROME_SURFACE, "EditModeChromeSurface")):
        text = code(path)
        assert not re.search(r'PluginState\.(option|setOption)\([^)]*"__gridSize"', text), \
            f"{label} reads or writes __gridSize through option()/setOption(); use PluginState.gridSize()/setGridSize()"
    widget = code(WIDGET)
    assert "PluginState.gridSize(manifest.id, screenName)" in widget, \
        "PluginWidget.storedGridSize must read the span through PluginState.gridSize()"
    grip = re.search(r"const surface = PluginState\.currentSurface;\s*const next = GridSizes\.formatSize\(size\);(.*?)PluginState\.setGridSize\(id, screen, next, surface\);",
                     widget, re.S)
    assert grip, "PluginWidget's span commit must capture the surface and write through setGridSize on it"
    assert "PluginState.setGridSize(id, screen, value, surface)" in grip.group(1) \
        and re.search(r"\bbefore\)\);", grip.group(1)), \
        "the span commit's undo entry must write the captured span back on the captured surface"
    menu = code(ROOT / "modules/imi/editMode/EditWidgetMenuContent.qml")
    assert "PluginState.setGridSize(id, screen, value, surface)" in menu, \
        "the Size stepper's undo entry must write on the captured surface"
    assert 'property string screenName' in menu, \
        "EditWidgetMenuContent must be told its screen - a span is per screen once forked"
    state = code(STATE)
    for fn in ("gridSize", "setGridSize", "lockRecords", "restoreLockRecords"):
        assert re.search(rf"function {fn}\(", state), f"PluginState lost {fn}()"
    # The re-link's undo restores whole records (position AND span), not a
    # position-only re-write that would drop every forked span.
    chrome = code(CHROME_SURFACE)
    reset = re.search(r"function resetLockLayout\(\)(.*?)\n    \}", chrome, re.S)
    assert reset and "PluginState.restoreLockRecords(screen, value)" in reset.group(1) \
        and re.search(r"\bforked\)\);", reset.group(1)), \
        "the re-link's undo must restore the whole lock records, or forked spans are lost on undo"


def test_the_store_carries_the_lock_layout_from_empty_through_load():
    state = code(STATE)
    empty = re.search(r"function emptyState\(\)\s*\{(.*?)\n    \}", state, re.S)
    assert empty and "lockPositions: {}" in empty.group(1), \
        "PluginState.emptyState() must declare lockPositions beside desktopPositions"
    assert re.search(r"lockPositions: parsed\.lockPositions\s*&&\s*typeof parsed\.lockPositions === \"object\"",
                     state), \
        "PluginState's loader must shape-check lockPositions like it does desktopPositions"


def test_presets_carry_the_lock_layout_both_ways():
    presets = read(PRESETS)
    saves = re.findall(r"lockPositions: \(\.lockPositions // \{\}\)", presets)
    assert len(saves) >= 3, \
        (f"presets.sh captures lockPositions at {len(saves)} sites; the two --save "
         f"paths and the --apply current-state read all need it")
    apply_rule = re.search(
        r"\.lockPositions = \(if \(\$preset \| has\(\"lockPositions\"\)\)\s*"
        r"then \(\$preset\.lockPositions // \{\}\)\s*"
        r"else \(\$current\.lockPositions // \{\}\) end\)", presets)
    assert apply_rule, \
        ("presets.sh --apply must take the preset's lockPositions only if the preset "
         "HAS the key, and keep the user's otherwise - an older preset must not wipe "
         "a fork")


def test_the_module_states_the_inheritance_rule():
    module = code(MODULE)
    for fn in ("storeKey", "isForked", "rawPosition", "withPosition", "withoutLockLayout"):
        assert re.search(rf"function {fn}\(", module), f"layout_surfaces.js lost {fn}()"
    # ONE fork helper, seeded from the DESKTOP screen and carrying each
    # widget's span - shared by both writers so they cannot disagree about
    # what a fork copies.
    fork = re.search(r"function forkedScreen\(state, screenName\) \{(.*?)\n\}", module, re.S)
    assert fork, "layout_surfaces.js lost forkedScreen()"
    assert "state.desktopPositions" in fork.group(1), \
        "forkedScreen must seed the new lock screen from desktopPositions"
    assert "rawGridSize(state, DESKTOP" in fork.group(1), \
        "forkedScreen must copy each widget's desktop span into its lock record"
    assert module.count("forkedScreen(state, screenName)") >= 3, \
        "both withPosition and withGridSize must fork through forkedScreen()"



# ---- presence forks the same way -------------------------------------------

DRAWER = ROOT / "modules/imi/editMode/EditModeDrawer.qml"
BACKGROUND = ROOT / "modules/imi/background/Background.qml"


def test_the_module_states_the_presence_rule():
    module = code(MODULE)
    for fn in ("isPresenceForked", "forkedPresence", "lockPresent",
               "withLockPresence", "withoutLockPresence", "containsId"):
        assert re.search(rf"function {fn}\(", module), \
            f"layout_surfaces.js lost {fn}()"
    fork = re.search(r"function withLockPresence\((.*?)\n\}", module, re.S)
    assert fork, "layout_surfaces.js lost withLockPresence()"
    assert "forkedPresence(desktopEnabled)" in fork.group(1), \
        ("the first pick must snapshot the desktop's enabled set - a fork that "
         "starts empty is a lock screen the first toggle cleared")
    # Neither shape check may go through Array's brand: a `list<string>` that
    # crossed into a .pragma library is typeof "object" and fails
    # Array.isArray (109e6d897), and an empty map is a legitimate forked state.
    assert "Array.isArray" not in module, \
        ("layout_surfaces.js must not test a QML sequence with Array.isArray - "
         "the brand does not survive the boundary")


def test_the_store_carries_the_lock_presence_from_empty_through_load():
    state = code(STATE)
    empty = re.search(r"function emptyState\(\)\s*\{(.*?)\n    \}", state, re.S)
    assert empty and "lockPresence: null" in empty.group(1), \
        ("PluginState.emptyState() must declare lockPresence as null - absence "
         "is 'the lock follows the desktop', and an empty map is not that")
    assert re.search(r"lockPresence: parsed\.lockPresence\s*&&\s*"
                     r"typeof parsed\.lockPresence === \"object\"", state), \
        "PluginState's loader must shape-check lockPresence"
    for fn in ("lockPresenceForked", "lockWidgetEnabled", "setLockWidgetEnabled",
               "lockPresenceRecords", "restoreLockPresence", "resetLockPresence"):
        assert re.search(rf"function {fn}\(", state), f"PluginState lost {fn}()"
    # None of them take a screen: presence is one global set, the way
    # `plugins.enabled` is, and a per-screen one would invent a capability the
    # desktop itself does not have.
    for fn in ("lockPresenceForked", "lockWidgetEnabled", "resetLockPresence"):
        sig = re.search(rf"function {fn}\(([^)]*)\)", state)
        assert sig and "screen" not in sig.group(1), \
            f"PluginState.{fn} takes a screen - presence is not per screen"


def test_the_master_gate_stays_above_the_per_widget_choice():
    # The upgrade guarantee, and the reason `lock.showWidgets` is not
    # superseded: it is a setting users already have set. With it off nothing
    # shows, as before; with it on and the choice following, all of them do.
    widget = code(WIDGET)
    # A BRANCH, not a disjunction: with the gate off a widget's own opt-in is
    # the whole answer (the clock, as before), and with it on the per-widget
    # choice is - including when that choice says no, which an `||` with the
    # opt-in could never express and which would leave the clock's row in the
    # picker unable to do anything.
    assert re.search(r"visibleWhenLocked:\s*Config\.options\.lock\.showWidgets\s*"
                     r"\?\s*PluginState\.lockWidgetEnabled\([^)]*\)\s*"
                     r":\s*pluginNode\.wantsVisibleWhenLocked", widget), \
        ("a widget's lock visibility must branch on the master gate and then "
         "read the per-widget choice - either term alone drops a decision the "
         "user has already made")
    assert re.search(r"visibleOnDesktop:\s*!rootWidget\.lockOnlyWidget", widget), \
        ("the desktop needs a filter of its own, or a widget picked for the "
         "lock alone is drawn on the desktop too")
    only = re.search(r"readonly property bool lockOnlyWidget:(.*?)\n    visibleOnDesktop",
                     widget, re.S)
    assert only and "!Config.options.plugins.enabled.includes" in only.group(1), \
        ("lockOnlyWidget must be narrower than 'not enabled': a widget being "
         "removed from BOTH is in neither list, and hiding it here races the "
         "host loader's exit fade")
    # The host builds a widget or it does not, so the loader gate is the union.
    background = code(BACKGROUND)
    shown = re.search(r"shown: modelData\.desktopWidget !== undefined(.*?)enterDuration",
                      background, re.S)
    assert shown, "Background's plugin loader gate is gone"
    assert "PluginState.lockWidgetEnabled(modelData.id)" in shown.group(1), \
        ("the loader gate must be the union of the two choices, or a widget "
         "picked for the lock alone is never built")


def test_presets_carry_the_lock_widget_choice_both_ways():
    presets = read(PRESETS)
    saves = re.findall(r"lockPresence: \(\.lockPresence // null\)", presets)
    assert len(saves) >= 3, \
        (f"presets.sh captures lockPresence at {len(saves)} sites; the two "
         f"--save paths and the --apply current-state read all need it")
    apply_rule = re.search(
        r"\.lockPresence = \(if \(\$preset \| has\(\"lockPresence\"\)\)\s*"
        r"then \$preset\.lockPresence\s*"
        r"else \$current\.lockPresence end\)", presets)
    assert apply_rule, \
        ("presets.sh --apply must take the preset's lockPresence only if the "
         "preset HAS the key - an older preset must not wipe a picked set, and "
         "a null from a newer one must re-link rather than read as absent")


def test_the_drawer_offers_the_choice_and_the_surface_writes_it():
    drawer = code(DRAWER)
    assert "lockWidgetToggleRequested" in drawer and "lockPresenceResetRequested" in drawer, \
        "the drawer's Lock section no longer offers the per-widget choice"
    assert "PluginState.lockPresenceForked()" in drawer, \
        ("the drawer must say which state the choice is in - the following/"
         "forked row is how a user finds out that it forked")
    for wording in ("Widget choice follows the desktop", "Widget choice is separate"):
        assert wording in drawer, \
            (f"the presence row must reuse the layout row's vocabulary, not "
             f"invent a second one ({wording!r} missing)")
    assert "PluginState.set" not in drawer, \
        "the drawer writes the choice itself - it reports gestures, the surface writes"
    surface = code(CHROME_SURFACE)
    for fn in ("toggleLockWidget", "resetLockPresence"):
        body = re.search(rf"function {fn}\([^)]*\)(.*?)\n    \}}", surface, re.S)
        assert body, f"the chrome surface lost {fn}()"
        assert "GlobalStates.editUndoPush" in body.group(1), \
            f"{fn} must be undoable - it is a committed mutation"
        assert "PluginState.restoreLockPresence(" in body.group(1), \
            (f"{fn}'s undo must restore the whole choice, including the null "
             f"that means 'following' - a re-pick from the desktop is a "
             f"different set the moment the enabled list has moved")


if __name__ == "__main__":
    raise SystemExit(run(globals()))
