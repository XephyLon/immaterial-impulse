"""Per-project Wallpaper Engine settings reach the renderer, and only through
the one resolution.

we_overrides.js decides (tst_we_overrides.qml drives it);
WallpaperEngineOverrides.qml owns the disk; `active` is the one live
derivation. What a QML unit test cannot see is the wiring - a renderer that
kept reading the raw config would make every sidebar override a silent no-op,
because the globals still hold the old value and nothing errors.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LAYER = ROOT / "modules/imi/background/WallpaperEngineLayer.qml"
BACKGROUND = ROOT / "modules/imi/background/Background.qml"
STORE = ROOT / "services/WallpaperEngineOverrides.qml"
SIDEBAR = ROOT / "modules/imi/wallpaperSelector/WallpaperSelectorSidebar.qml"
CONTENT = ROOT / "modules/imi/wallpaperSelector/WallpaperSelectorContent.qml"


def _strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def _checks(layer, background, store, sidebar, content):
    # The renderer reads the resolved settings, never the raw config keys -
    # a raw read is the silent no-op this file documents.
    assert "WallpaperEngineOverrides.active.fps" in layer, \
        "the surface's fps does not go through the override resolution"
    assert "WallpaperEngineOverrides.active.scaling" in layer, \
        "the surface's scaleMode does not go through the override resolution"
    # The live crop focus binds the same way, in-guarded for an older binary.
    assert 'WallpaperEngineOverrides.active.focus.x' in layer, \
        "the surface's focusX does not go through the override resolution"
    assert '"focusX" in root' in layer, \
        "focusX is bound unconditionally - an older renderer binary breaks on it"
    # renderScale (the Quality dial) binds through the resolution too, and
    # in-guarded like the rest - it is absent on a pre-0.3.x renderer binary.
    assert "WallpaperEngineOverrides.active.renderScale" in layer, \
        "the surface's renderScale does not go through the override resolution"
    assert '"renderScale" in root' in layer, \
        "renderScale is bound unconditionally - an older renderer binary breaks on it"
    assert not re.search(r"fps\s*:\s*Config\.options", layer), \
        "the surface reads fps straight off the config again"
    assert not re.search(r"scaleMode\s*:\s*Config\.options", layer), \
        "the surface reads scaling straight off the config again"

    # The audio route asks the same resolution about `silent`.
    assert "WallpaperEngineOverrides.active.silent" in background, \
        "weAudioOutput does not ask the override resolution about silent"

    # The store is a raw FileView keyed by runtime project ids - never a
    # JsonAdapter, whose undeclared children have segfaulted deserialization.
    assert "FileView" in store and "JsonAdapter" not in store, \
        "the overrides store is not a raw FileView"
    assert "configDirReady" in store, \
        "the store writes into shellConfig before the migration gate opens"
    assert "we_overrides.js" in store, \
        "the store spells its own resolution instead of using the module"

    # The sidebar's controls write through one function that routes to the
    # override or the global - a control writing the config directly while
    # the override switch is on edits a value nothing displays.
    assert "writeSetting(" in sidebar
    assert re.search(r'onActivated:.*writeSetting\("fps"', sidebar), \
        "the fps control does not write through the router"
    assert re.search(r'onActivated:.*writeSetting\("scaling"', sidebar), \
        "the scaling control does not write through the router"
    assert re.search(r'onActivated:.*writeSetting\("renderScale"', sidebar), \
        "the Quality control does not write through the router"

    # The content hosts the sidebar for exactly the two sources that have one.
    assert "WallpaperSelectorSidebar" in content
    assert not re.search(r"property var quickDirs", content), \
        "the toolbar's folder-chip list is back beside the sidebar's rail - two copies"


def test_we_override_wiring():
    _checks(_strip_comments(LAYER.read_text()),
            _strip_comments(BACKGROUND.read_text()),
            _strip_comments(STORE.read_text()),
            _strip_comments(SIDEBAR.read_text()),
            _strip_comments(CONTENT.read_text()))


def test_the_checks_can_fail():
    layer = _strip_comments(LAYER.read_text())
    good = dict(layer=layer,
                background=_strip_comments(BACKGROUND.read_text()),
                store=_strip_comments(STORE.read_text()),
                sidebar=_strip_comments(SIDEBAR.read_text()),
                content=_strip_comments(CONTENT.read_text()))

    # Planted: the renderer back on the raw config.
    planted = layer.replace("fps: WallpaperEngineOverrides.active.fps",
                            "fps: Config.options.wallpaperSelector.wallpaperEngine.fps")
    try:
        _checks(planted, good["background"], good["store"], good["sidebar"], good["content"])
    except AssertionError:
        pass
    else:
        raise AssertionError("a raw-config fps read passed the contract")

    # Planted: renderScale bound unconditionally (breaks an older binary).
    planted = layer.replace('"renderScale" in root', '"renderScaleXX" in root')
    try:
        _checks(planted, good["background"], good["store"], good["sidebar"], good["content"])
    except AssertionError:
        pass
    else:
        raise AssertionError("an unguarded renderScale binding passed the contract")

    # Planted: the store on a JsonAdapter.
    planted = good["store"].replace("FileView", "JsonAdapter")
    try:
        _checks(good["layer"] if "layer" in good else layer, good["background"], planted,
                good["sidebar"], good["content"])
    except AssertionError:
        pass
    else:
        raise AssertionError("a JsonAdapter store passed the contract")


if __name__ == "__main__":
    import sys
    from contract_runner import run
    sys.exit(run(globals()))
