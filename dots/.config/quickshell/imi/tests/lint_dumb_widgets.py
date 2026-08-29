#!/usr/bin/env python3
"""A shared widget is presentational. This is the ratchet that keeps it so.

`modules/common/widgets` is a promise: anything in it can be used by any
surface. A widget that reads the user's config, writes global state, talks to a
service or spawns a process breaks that promise silently - it keeps working, and
the next person reaching for it inherits a dependency nobody mentioned.

An audit of the folder found 23 files doing exactly that. Most were not widgets
that grew a brain; they were feature code filed in the wrong folder, and eleven
of them moved out to the module that was their only consumer. What is left is
listed below, each with the reason it is still here - so the list can shrink and
cannot quietly grow.

What counts as reaching past presentation:

  - a service singleton (anything under `services/`, except `Translation`,
    which is text and belongs everywhere);
  - `Config.options.*`, read or written. A dumb widget takes what it draws as a
    property; the caller reads the config;
  - `GlobalStates.*`, likewise. A widget that asks whether a particular panel is
    open cannot be used in another one, which is the concrete bug this rule
    prevents;
  - a `Process` or `execDetached`. A component that can run a command is not a
    component.

`Appearance` is deliberately NOT on that list: design tokens are what makes
these widgets consistent, and a widget reading them is the system working.

Comments are stripped before matching. The first version of this scan accused
StaggerWave over the word `GlobalStates` inside a comment explaining why it does
NOT read one.
"""
import re
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SHELL = HERE.parent
WIDGETS = SHELL / "modules/common/widgets"
SERVICES = SHELL / "services"
ALLOWED_SINGLETONS = {"Translation"}

# file -> why it is still allowed to reach past presentation.
EXCLUDED = {
    "DropShelf.qml":
        "not a widget at all: `pragma Singleton` with a call-site API "
        "(DropShelf.show(...)) owning four GlobalStates keys. A service in the "
        "wrong folder - and moving a singleton changes registration, so it "
        "wants its own change",
    "Player.qml":
        "the media cluster: Player pulls PlayerControls, PlayerControlsLyrics "
        "and Lyrics with it and has consumers in two modules. A cluster move, "
        "not a file move",
    "PlayerControls.qml":
        "reads GlobalStates.sidebarRightOpen to decide its own behaviour; "
        "moves with the Player cluster",
    "Lyrics.qml": "LyricsService; moves with the Player cluster",
    "NotificationItem.qml":
        "Notifications, and reads GlobalStates.sidebarRightOpen. The second is "
        "the one to invert: a card that asks whether a particular panel is "
        "open is a card the phone tab cannot reuse, which is exactly what it "
        "could not, for a release",
    "NotificationGroup.qml": "Notifications, with NotificationItem",
    "NotificationListView.qml":
        "Notifications, reached through the NotificationController seam - the "
        "list is the seam's consumer, so this one is likely correct as it is",
    "StyledPopup.qml":
        "the bar popup protocol. Its arbitration moved to the slot "
        "(GlobalStates.claimBarPopup) and what remains is this object ASKING - "
        "the inverted shape. Named here so the exception stays visible",
    "KeybindEditor.qml":
        "HyprlandKeybindOverrides and HyprlandSubmap. A keybind editor is a "
        "feature; it wants moving to settings beside the cheatsheet that uses it",
    "LightDarkPreferenceButton.qml":
        "spawns the theme switch - and has NO consumer, because QuickConfig "
        "declares its own local copy instead. Dead code to delete, not to fix",
    "Favicon.qml":
        "spawns a fetch for a site icon. Wants a service behind it, the way "
        "every other network read in this shell has one",
    "AttachedFileIndicator.qml":
        "spawns to inspect a file; belongs with the AI chat that uses it",
    "WeekRow.qml":
        "DateTime, for today's column. Wants the date as a property from the "
        "calendar that builds it",
    "PasswordField.qml": "reads Config.options for its own reveal policy",
    "BarWidgetSwitcher.qml":
        "reads the bar's layout config to switch bar widgets - a bar component "
        "in the shared folder, which is the same misfiling as the eleven that "
        "moved, just with two consumers",
    "BarWidgetSwitcherArea.qml": "with BarWidgetSwitcher",
}


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return "\n".join(re.sub(r"//.*$", "", line) for line in text.splitlines())


def service_names():
    return {p.stem for p in SERVICES.glob("*.qml")} - ALLOWED_SINGLETONS


def offences(path, services):
    text = strip_comments(path.read_text(errors="replace"))
    found = []
    used = sorted({name for name in services if re.search(rf"\b{name}\.", text)})
    if used:
        found.append("services: " + ", ".join(used))
    if re.search(r"\bConfig\.options\.", text):
        found.append("reads Config.options")
    if re.search(r"\bGlobalStates\.", text):
        found.append("reads or writes GlobalStates")
    if re.search(r"\bProcess\s*\{|execDetached", text):
        found.append("spawns a process")
    return found


class DumbWidgetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.services = service_names()

    def test_shared_widgets_stay_presentational(self):
        broken = {}
        for path in sorted(WIDGETS.glob("*.qml")):
            if path.name in EXCLUDED:
                continue
            found = offences(path, self.services)
            if found:
                broken[path.name] = found
        self.assertEqual(broken, {}, "\n".join([
            "These live in modules/common/widgets but reach past presentation.",
            "Move the file to the module that uses it, invert the dependency",
            "into a property its caller supplies, or add it to EXCLUDED here",
            "WITH THE REASON - a bare name teaches the next reader nothing:",
            *(f"  {name}: {', '.join(found)}" for name, found in broken.items()),
        ]))

    def test_the_exclusion_list_only_shrinks(self):
        """An entry that no longer offends is an entry to delete."""
        clean = []
        for name in sorted(EXCLUDED):
            path = WIDGETS / name
            if not path.exists():
                continue
            if not offences(path, self.services):
                clean.append(name)
        self.assertEqual(clean, [], "\n".join([
            "These are excluded but no longer reach past presentation.",
            "Delete their entries so the list keeps meaning something:",
            *(f"  {name}" for name in clean),
        ]))

    def test_the_exclusion_list_names_real_files(self):
        stale = sorted(name for name in EXCLUDED if not (WIDGETS / name).exists())
        self.assertEqual(stale, [], "\n".join([
            "EXCLUDED names files that are no longer in the shared folder -",
            "they moved out, which is the outcome this lint wants. Delete:",
            *(f"  {name}" for name in stale),
        ]))


if __name__ == "__main__":
    unittest.main()
