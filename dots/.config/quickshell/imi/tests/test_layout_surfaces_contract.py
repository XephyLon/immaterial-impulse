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
    assert re.search(r"editUndoPush\(\(\) => PluginState\.setPosition\(id, screen, before, surface\)\)",
                     drag.group(1)), \
        ("PluginWidget's undo closure must pass the CAPTURED surface - resolving it at "
         "pop time writes a lock position into the desktop store from the other tab")
    assert re.search(r"placementStrategy: rootWidget\.placementStrategy\s*\}, surface\);", widget), \
        "PluginWidget's forward write must land on the captured surface too"

    # The drawer's drop.
    chrome = code(CHROME_SURFACE)
    drop = re.search(r"const surface = PluginState\.currentSurface;(.*?)root\.enablePlugin\(manifest\.id\);",
                     chrome, re.S)
    assert drop, "the drawer drop must capture `surface` before pushing its undo"
    assert "PluginState.setPosition(id, screen, beforePosition, surface)" in drop.group(1), \
        "the drop's undo closure must pass the captured surface"
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
    assert "PluginState.setGridSize(id, screen, before, surface)" in grip.group(1), \
        "the span commit's undo must pass the captured surface"
    menu = code(ROOT / "modules/imi/editMode/EditWidgetMenuContent.qml")
    assert "PluginState.setGridSize(id, screen, before, surface)" in menu, \
        "the Size stepper's undo must pass the captured surface"
    assert 'property string screenName' in menu, \
        "EditWidgetMenuContent must be told its screen - a span is per screen once forked"
    state = code(STATE)
    for fn in ("gridSize", "setGridSize", "lockRecords", "restoreLockRecords"):
        assert re.search(rf"function {fn}\(", state), f"PluginState lost {fn}()"
    # The re-link's undo restores whole records (position AND span), not a
    # position-only re-write that would drop every forked span.
    chrome = code(CHROME_SURFACE)
    reset = re.search(r"function resetLockLayout\(\)(.*?)\n    \}", chrome, re.S)
    assert reset and "PluginState.restoreLockRecords(screen, forked)" in reset.group(1), \
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


if __name__ == "__main__":
    raise SystemExit(run(globals()))
