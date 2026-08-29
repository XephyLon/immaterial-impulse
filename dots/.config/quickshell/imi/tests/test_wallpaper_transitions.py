#!/usr/bin/env python3
"""Contract tests for the wallpaper transition catalogue.

The list of switch transitions used to exist three times over - Background.qml's
random pool, the settings combo box, and the desktop menu's Wallpaper & style
submenu - and the copies had drifted: the submenu offered four of the eight
shaders, so "Peel" could be the *active* transition while being missing from the
menu meant to change it, and the one entry the submenu did show as selected was
the only one clicking on which did nothing (#142).

These are static source checks - the shell's QML is not instantiable here - but
they pin the two halves that actually rotted: that the catalogue names shaders
that exist on disk, and that no consumer has quietly grown its own copy again.
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from contract_runner import run  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
CATALOGUE = ROOT / "modules" / "common" / "WallpaperTransitions.qml"
SHADER_DIR = ROOT / "modules" / "imi" / "background" / "shaders"
BACKGROUND = ROOT / "modules" / "imi" / "background" / "Background.qml"
SETTINGS_PAGE = ROOT / "modules" / "imi" / "settings" / "pages" / "BackgroundConfig.qml"
SUBMENU = ROOT / "modules" / "imi" / "desktopMenu" / "WallpaperSubmenu.qml"

ENTRY = re.compile(r'\{\s*value:\s*"([^"]*)"[^}]*\}')


def read(path):
    return path.read_text(encoding="utf-8")


def shader_block():
    text = read(CATALOGUE)
    start = text.index("readonly property var shaders:")
    end = text.index("]", start)
    return text[start:end]


def catalogue_shaders():
    return ENTRY.findall(shader_block())


def test_catalogue_is_a_singleton():
    assert CATALOGUE.exists(), f"{CATALOGUE} is missing"
    assert "pragma Singleton" in read(CATALOGUE)


def test_every_catalogued_shader_has_a_compiled_shader():
    missing = [
        value
        for value in catalogue_shaders()
        if not (SHADER_DIR / f"{value}.frag.qsb").exists()
    ]
    assert not missing, f"catalogue names shaders with no .frag.qsb: {missing}"


def test_catalogue_is_not_empty_and_has_no_duplicates():
    values = catalogue_shaders()
    assert len(values) >= 2, f"suspiciously short catalogue: {values}"
    assert len(set(values)) == len(values), f"duplicate entries: {values}"


def test_the_shader_pool_excludes_none_and_random():
    values = catalogue_shaders()
    assert "" not in values, "an empty value means 'no transition', not a shader"
    assert "random" not in values, "'random' picking itself would be an infinite regress"


def test_none_and_random_are_offered_but_are_not_shaders():
    text = read(CATALOGUE)
    assert 'property var none: ({ value: ""' in text
    assert 'property var random: ({ value: "random"' in text
    assert "property var options:" in text


def test_consumers_read_the_catalogue_instead_of_their_own_list():
    for path, symbol in (
        (BACKGROUND, "WallpaperTransitions.shaderValues"),
        (SETTINGS_PAGE, "WallpaperTransitions.options"),
        (SUBMENU, "WallpaperTransitions.options"),
    ):
        assert symbol in read(path), f"{path.name} does not read {symbol}"


def test_no_consumer_hardcodes_a_shader_name():
    # The catalogue's values are the only place a shader basename should be
    # spelled out; Background.qml resolves `<currentShader>.frag.qsb` from it.
    for path in (SETTINGS_PAGE, SUBMENU):
        text = read(path)
        leaked = [value for value in catalogue_shaders() if f'"{value}"' in text]
        assert not leaked, f"{path.name} still names shaders directly: {leaked}"


def test_the_submenu_hides_the_active_transition():
    text = read(SUBMENU)
    assert "wallpaperAnimation" in text
    assert re.search(
        r"WallpaperTransitions\.options\.filter\(", text
    ), "the submenu must filter the catalogue, not render it whole"
    assert re.search(
        r"filter\([^)]*!==\s*Config\.options\.background\.wallpaperAnimation", text
    ), "the submenu must drop the entry that is already active"


if __name__ == "__main__":
    print("Wallpaper transition catalogue contract tests")
    sys.exit(run(globals()))
