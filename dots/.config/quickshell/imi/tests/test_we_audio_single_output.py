#!/usr/bin/env python3
"""The wallpaper's sound plays on ONE output, whatever the monitor count.

Issue #338: with a Wallpaper Engine wallpaper unmuted on a two-monitor setup,
the same audio track played twice, slightly out of phase. There is nothing
subtle about the cause once the shape is visible - `Background.qml` is a
`Variants` over `Quickshell.screens`, so there is one `WallpaperEngineSurface`
per output, and every one of them bound its `audioEnabled` to the same global
`silent` flag. It was N-fold on N monitors, not merely doubled.

Audio is a LOAD-TIME decision inside WE (toggling it reloads the wallpaper),
which rules out following the focused monitor: that would reload wallpapers on
every focus change. So the rule is a named output, and these pin it.

The unplug case is the one worth stating: if the named monitor is gone, the
sound must move to a screen that exists rather than going silent, because a
user who unplugs a monitor has not asked for their wallpaper to mute.
"""

import pathlib
import re
import sys

SHELL = pathlib.Path(__file__).resolve().parent.parent
LAYER = SHELL / "modules/imi/background/WallpaperEngineLayer.qml"
BACKGROUND = SHELL / "modules/imi/background/Background.qml"
CONFIG = SHELL / "modules/common/Config.qml"


def test_the_layer_does_not_decide_for_itself_whether_to_play_sound():
    """A per-output surface cannot read a global flag and be right."""
    body = LAYER.read_text()
    assert "property bool audioWanted" in body, (
        "the layer must take the decision from whoever knows which screen it is on")
    match = re.search(r'audioEnabled = Qt\.binding\(\(\) =>([^;]*)\);', body, re.S)
    assert match, "audioEnabled should still be bound dynamically"
    bound = match.group(1)
    assert "audioWanted" in bound, "audioEnabled must follow audioWanted"
    assert "silent" not in bound, (
        "reading `silent` here is the #338 bug: every output would answer the same")


def test_the_background_names_one_output_and_falls_back_to_one_that_exists():
    body = BACKGROUND.read_text()
    match = re.search(r'readonly property bool weAudioOutput: \{(.*?)\n        \}', body, re.S)
    assert match, "Background must decide which output carries the audio"
    rule = match.group(1)
    assert "silent" in rule, "a muted wallpaper plays on no output at all"
    assert "audioMonitor" in rule, "the chosen output is config, not a guess"
    # The fallback: a named monitor that is no longer connected must not
    # silence the wallpaper.
    assert "screens" in rule and "some(" in rule, (
        "the named monitor must be checked against the connected screens, so an "
        "unplugged one falls back instead of silencing the wallpaper")
    assert re.search(r'property: "audioWanted"', body), (
        "the decision must reach the layer through a Binding, the way `covered` does")


def test_the_chosen_output_is_a_declared_option():
    body = CONFIG.read_text()
    assert "property string audioMonitor" in body, (
        "which monitor plays the sound has to be settable; the shell cannot know "
        "which screen has the speakers")


if __name__ == "__main__":
    from contract_runner import run
    sys.exit(run(globals()))
