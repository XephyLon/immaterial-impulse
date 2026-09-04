"""The compatibility scan runs OUTSIDE the shell, and its verdicts have one
reader.

we_compat.js decides (tst_we_compat.qml drives it). What no QML test can see:
that the scan is a spawned scanner process - a wallpaper that wedges or
crashes the renderer must kill the scanner, never the shell - and that the
grid's badge and filter both go through the service's one resolution, so a
tile and the hide switch cannot disagree about what "broken" means.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SERVICE = ROOT / "services/WallpaperEngineCompat.qml"
SCANNER = ROOT / "scripts/wallpapers/we_compat_scan.qml"
GRID = ROOT / "modules/imi/wallpaperSelector/WallpaperEngineGrid.qml"
SIDEBAR = ROOT / "modules/imi/wallpaperSelector/WallpaperSelectorSidebar.qml"


def _strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def _checks(service, scanner, grid, sidebar):
    # The scan is a spawned qs -p process, never a surface inside the shell.
    assert "we_compat_scan.qml" in service, \
        "the service no longer spawns the scanner config"
    assert "WallpaperEngineSurface" not in service, \
        ("the service builds a renderer surface in the SHELL - a wallpaper "
         "that wedges WE's setup() then detaches and leaks a thread inside "
         "the user's session, which is what the spawned scanner exists to absorb")
    assert "WallpaperEngineSurface" in scanner, \
        "the scanner no longer loads projects into a real surface"
    # The scanner ends itself on a timeout rather than switching past a
    # wedged load and testing everything after it over a leaked renderer.
    assert "Qt.quit()" in scanner

    # The store is a raw FileView (runtime project ids), its own file - the
    # reference's scan-managed/user-settings split, as a file boundary.
    assert "FileView" in service and "JsonAdapter" not in service
    assert "wallpaper-engine-compat.json" in service
    assert "configDirReady" in service

    # Badge and filter read the one resolution.
    assert "WallpaperEngineCompat.statusFor" in grid, \
        "the grid stopped asking the service for a project's verdict"
    assert "WallpaperEngineCompat.statusFor" in sidebar
    assert not re.search(r"results\[", grid), \
        "the grid reads the raw results map - a second spelling of statusOf"

    # The respawn ladder is bounded: a scanner that cannot start at all must
    # not loop forever.
    assert "respawnsLeft" in service


def test_we_compat_wiring():
    _checks(_strip_comments(SERVICE.read_text()),
            _strip_comments(SCANNER.read_text()),
            _strip_comments(GRID.read_text()),
            _strip_comments(SIDEBAR.read_text()))


def test_the_checks_can_fail():
    service = _strip_comments(SERVICE.read_text())
    scanner = _strip_comments(SCANNER.read_text())
    grid = _strip_comments(GRID.read_text())
    sidebar = _strip_comments(SIDEBAR.read_text())

    # Planted: the surface moved into the shell's own service.
    planted = service + "\n    WallpaperEngineSurface { }\n"
    try:
        _checks(planted, scanner, grid, sidebar)
    except AssertionError:
        pass
    else:
        raise AssertionError("an in-shell scan surface passed the contract")

    # Planted: the grid reading the raw map.
    planted = grid.replace("WallpaperEngineCompat.statusFor(project)",
                           'WallpaperEngineCompat.results[project.id]')
    try:
        _checks(service, scanner, planted, sidebar)
    except AssertionError:
        pass
    else:
        raise AssertionError("a raw results read passed the contract")


if __name__ == "__main__":
    import sys
    from contract_runner import run
    sys.exit(run(globals()))
