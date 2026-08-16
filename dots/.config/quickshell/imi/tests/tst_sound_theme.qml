import QtQuick
import QtTest
import "../services/sound_theme.js" as SoundTheme

// The fixtures below are modelled on what is actually installed on a stock Arch
// machine, measured before this engine was written:
//   freedesktop  35 .oga, flat in stereo/
//   oxygen       63 .ogg, flat in stereo/, and no `complete` or `suspend-error`
//   Pop          25 .oga, none of them in stereo/ - all under
//                stereo/{alert,action,notification} per its Directories=
//   ocean        45 .oga plus 32 .oga.license sidecars beside them
// Each of those four shapes broke the double-ffplay implementation differently.
TestCase {
    name: "SoundThemeTest"

    readonly property string freedesktopIndex: "[Sound Theme]\nName=Default\nDirectories=stereo\n"

    readonly property string popIndex: "# a comment\n" +
        "[Sound Theme]\n" +
        "Name=Pop\n" +
        "Comment=The Pop Sound Theme\n" +
        "Directories=stereo/alert stereo/action stereo/notification\n" +
        "\n" +
        "[stereo/alert]\n" +
        "Context=Alert\n" +
        "OutputProfile=stereo\n"

    function makeCatalogue() {
        return SoundTheme.buildCatalogue({
            roots: ["/home/u/.local/share/sounds", "/usr/share/sounds"],
            entries: [
                {
                    theme: "freedesktop",
                    dir: "/usr/share/sounds/freedesktop",
                    index: freedesktopIndex,
                    files: [
                        "index.theme",
                        "stereo/power-plug.oga",
                        "stereo/power-unplug.oga",
                        "stereo/complete.oga",
                        "stereo/suspend-error.oga",
                        "stereo/dialog-warning.oga",
                        "stereo/alarm-clock-elapsed.oga"
                    ]
                },
                {
                    theme: "oxygen",
                    dir: "/usr/share/sounds/oxygen",
                    index: "[Sound Theme]\nName=Oxygen\nName[de]=Sauerstoff\nDirectories=stereo\n",
                    files: [
                        "index.theme",
                        "stereo/power-plug.ogg",
                        "stereo/power-unplug.ogg",
                        "stereo/dialog-warning.ogg",
                        "stereo/alarm-clock-elapsed.ogg"
                    ]
                },
                {
                    theme: "Pop",
                    dir: "/usr/share/sounds/Pop",
                    index: popIndex,
                    files: [
                        "index.theme",
                        "stereo/notification/power-plug.oga",
                        "stereo/notification/complete.oga",
                        "stereo/alert/alarm-clock-elapsed.oga"
                    ]
                },
                {
                    theme: "ocean",
                    dir: "/usr/share/sounds/ocean",
                    index: "[Sound Theme]\nName=Ocean\nDirectories=stereo\n",
                    files: [
                        "index.theme",
                        "index.theme.license",
                        "stereo/power-unplug.oga.license",
                        "stereo/power-plug.oga"
                    ]
                },
                {
                    theme: "alsa",
                    dir: "/usr/share/sounds/alsa",
                    index: "",
                    files: ["Front_Center.wav"]
                }
            ]
        });
    }

    function test_parseIndexThemeReadsOnlyTheSoundThemeGroup() {
        const parsed = SoundTheme.parseIndexTheme(popIndex);
        verify(parsed.valid);
        compare(parsed.name, "Pop");
        compare(parsed.directories.join("|"), "stereo/alert|stereo/action|stereo/notification");
        // Context/OutputProfile live in a per-directory group and must not leak
        // into the theme's own keys.
        compare(parsed.inherits.length, 0);
    }

    function test_parseIndexThemeAcceptsCommasAndWhitespace() {
        compare(SoundTheme.parseIndexTheme("[Sound Theme]\nInherits=ocean,freedesktop\n").inherits.join("|"),
            "ocean|freedesktop");
        compare(SoundTheme.parseIndexTheme("[Sound Theme]\nInherits= ocean ,  freedesktop \n").inherits.join("|"),
            "ocean|freedesktop");
    }

    function test_aDirectoryOfLooseFilesIsNotAThemeIndex() {
        const parsed = SoundTheme.parseIndexTheme("");
        verify(!parsed.valid);
        compare(parsed.directories.length, 0);
    }

    function test_resolvesAnOgaThemeWithoutGuessingTheExtension() {
        compare(SoundTheme.resolveEvent(makeCatalogue(), "freedesktop", "power-plug"),
            "/usr/share/sounds/freedesktop/stereo/power-plug.oga");
    }

    function test_resolvesAnOggOnlyThemeThroughTheSameCall() {
        compare(SoundTheme.resolveEvent(makeCatalogue(), "oxygen", "power-plug"),
            "/usr/share/sounds/oxygen/stereo/power-plug.ogg");
    }

    function test_aThemeWithContextSubdirectoriesIsSearchedInThemAll() {
        const catalogue = makeCatalogue();
        // Pop keeps nothing directly in stereo/. A hardcoded stereo/ path finds
        // 0 of its 25 sounds, which is silence with no error - the state the
        // shell shipped in for this theme.
        compare(SoundTheme.resolveEvent(catalogue, "Pop", "power-plug"),
            "/usr/share/sounds/Pop/stereo/notification/power-plug.oga");
        compare(SoundTheme.resolveEvent(catalogue, "Pop", "alarm-clock-elapsed"),
            "/usr/share/sounds/Pop/stereo/alert/alarm-clock-elapsed.oga");
    }

    function test_aSidecarFileIsNotASound() {
        // ocean ships power-unplug.oga.license and no power-unplug.oga, so
        // anything matching on "the event name followed by something" hands a
        // text file to the player.
        compare(SoundTheme.resolveEvent(makeCatalogue(), "ocean", "power-unplug"),
            "/usr/share/sounds/freedesktop/stereo/power-unplug.oga");
    }

    function test_anEventTheThemeLacksFallsBackToTheDefaultTheme() {
        const catalogue = makeCatalogue();
        // oxygen declares no Inherits= and ships neither of these. The spec's
        // implicit fallback is what keeps the battery-charged chime audible.
        compare(SoundTheme.resolveEvent(catalogue, "oxygen", "complete"),
            "/usr/share/sounds/freedesktop/stereo/complete.oga");
        compare(SoundTheme.resolveEvent(catalogue, "oxygen", "suspend-error"),
            "/usr/share/sounds/freedesktop/stereo/suspend-error.oga");
    }

    function test_aThemeThatIsNotInstalledStillResolvesThroughTheDefault() {
        compare(SoundTheme.resolveEvent(makeCatalogue(), "no-such-theme", "complete"),
            "/usr/share/sounds/freedesktop/stereo/complete.oga");
        compare(SoundTheme.resolveEvent(makeCatalogue(), "", "complete"),
            "/usr/share/sounds/freedesktop/stereo/complete.oga");
    }

    function test_anEventNoThemeHasResolvesToNothing() {
        compare(SoundTheme.resolveEvent(makeCatalogue(), "freedesktop", "device-added"), "");
    }

    function test_theInheritsChainIsWalkedInOrder() {
        const catalogue = SoundTheme.buildCatalogue({
            entries: [
                {
                    theme: "child",
                    dir: "/usr/share/sounds/child",
                    index: "[Sound Theme]\nName=Child\nDirectories=stereo\nInherits=middle,other\n",
                    files: ["stereo/own.oga"]
                },
                {
                    theme: "middle",
                    dir: "/usr/share/sounds/middle",
                    index: "[Sound Theme]\nName=Middle\nDirectories=stereo\n",
                    files: ["stereo/shared.oga"]
                },
                {
                    theme: "other",
                    dir: "/usr/share/sounds/other",
                    index: "[Sound Theme]\nName=Other\nDirectories=stereo\n",
                    files: ["stereo/shared.oga", "stereo/only-here.oga"]
                },
                {
                    theme: "freedesktop",
                    dir: "/usr/share/sounds/freedesktop",
                    index: freedesktopIndex,
                    files: ["stereo/shared.oga", "stereo/last-resort.oga"]
                }
            ]
        });
        compare(SoundTheme.themeChain(catalogue, "child").join("|"), "child|middle|other|freedesktop");
        compare(SoundTheme.resolveEvent(catalogue, "child", "own"), "/usr/share/sounds/child/stereo/own.oga");
        // First parent named wins over the second, and both win over the default.
        compare(SoundTheme.resolveEvent(catalogue, "child", "shared"), "/usr/share/sounds/middle/stereo/shared.oga");
        compare(SoundTheme.resolveEvent(catalogue, "child", "only-here"), "/usr/share/sounds/other/stereo/only-here.oga");
        compare(SoundTheme.resolveEvent(catalogue, "child", "last-resort"),
            "/usr/share/sounds/freedesktop/stereo/last-resort.oga");
    }

    function test_anInheritsCycleTerminates() {
        const catalogue = SoundTheme.buildCatalogue({
            entries: [
                {
                    theme: "a",
                    dir: "/s/a",
                    index: "[Sound Theme]\nDirectories=stereo\nInherits=b\n",
                    files: []
                },
                {
                    theme: "b",
                    dir: "/s/b",
                    index: "[Sound Theme]\nDirectories=stereo\nInherits=a\n",
                    files: ["stereo/ping.oga"]
                }
            ]
        });
        compare(SoundTheme.themeChain(catalogue, "a").join("|"), "a|b|freedesktop");
        compare(SoundTheme.resolveEvent(catalogue, "a", "ping"), "/s/b/stereo/ping.oga");
    }

    function test_aDiamondVisitsEachThemeOnce() {
        const catalogue = SoundTheme.buildCatalogue({
            entries: [
                { theme: "top", dir: "/s/top", index: "[Sound Theme]\nDirectories=stereo\nInherits=left,right\n", files: [] },
                { theme: "left", dir: "/s/left", index: "[Sound Theme]\nDirectories=stereo\nInherits=base\n", files: [] },
                { theme: "right", dir: "/s/right", index: "[Sound Theme]\nDirectories=stereo\nInherits=base\n", files: [] },
                { theme: "base", dir: "/s/base", index: "[Sound Theme]\nDirectories=stereo\n", files: ["stereo/ping.oga"] }
            ]
        });
        compare(SoundTheme.themeChain(catalogue, "top").join("|"), "top|left|right|base|freedesktop");
    }

    function test_aDisabledMarkerSilencesTheEventInsteadOfInheritingOne() {
        const catalogue = SoundTheme.buildCatalogue({
            entries: [
                {
                    theme: "quiet",
                    dir: "/s/quiet",
                    index: "[Sound Theme]\nDirectories=stereo\nInherits=freedesktop\n",
                    files: ["stereo/power-plug.disabled"]
                },
                {
                    theme: "freedesktop",
                    dir: "/usr/share/sounds/freedesktop",
                    index: freedesktopIndex,
                    files: ["stereo/power-plug.oga"]
                }
            ]
        });
        compare(SoundTheme.resolveEvent(catalogue, "quiet", "power-plug"), "");
        compare(SoundTheme.resolveEvent(catalogue, "freedesktop", "power-plug"),
            "/usr/share/sounds/freedesktop/stereo/power-plug.oga");
    }

    function test_aUserInstalledCopyShadowsTheSystemOneFileByFile() {
        const catalogue = SoundTheme.buildCatalogue({
            entries: [
                {
                    theme: "ocean",
                    dir: "/home/u/.local/share/sounds/ocean",
                    index: "[Sound Theme]\nName=Ocean\nDirectories=stereo\n",
                    files: ["stereo/power-plug.oga"]
                },
                {
                    theme: "ocean",
                    dir: "/usr/share/sounds/ocean",
                    index: "[Sound Theme]\nName=Ocean\nDirectories=stereo\n",
                    files: ["stereo/power-plug.oga", "stereo/power-unplug.oga"]
                }
            ]
        });
        compare(SoundTheme.resolveEvent(catalogue, "ocean", "power-plug"),
            "/home/u/.local/share/sounds/ocean/stereo/power-plug.oga");
        // The user's incomplete copy must not hide the rest of the system theme.
        compare(SoundTheme.resolveEvent(catalogue, "ocean", "power-unplug"),
            "/usr/share/sounds/ocean/stereo/power-unplug.oga");
    }

    function test_aThemeWithNoIndexIsSearchedAtItsRootAndUnderStereo() {
        const catalogue = makeCatalogue();
        compare(SoundTheme.resolveEvent(catalogue, "alsa", "Front_Center"),
            "/usr/share/sounds/alsa/Front_Center.wav");
    }

    function test_anEventNameIsAnIdentifierNotAPath() {
        const catalogue = makeCatalogue();
        verify(!SoundTheme.isPlayableEventName("../../../etc/passwd"));
        verify(!SoundTheme.isPlayableEventName(""));
        verify(!SoundTheme.isPlayableEventName(".."));
        verify(SoundTheme.isPlayableEventName("power-plug"));
        compare(SoundTheme.resolveEvent(catalogue, "freedesktop", "../stereo/power-plug"), "");
    }

    function test_thePickerOffersRealThemesSortedByTheirName() {
        const offered = SoundTheme.selectableThemes(makeCatalogue());
        compare(offered.map(theme => theme.id).join("|"), "freedesktop|ocean|oxygen|Pop");
        compare(offered[0].displayName, "Default");
        // alsa has no index.theme: reachable by name, but not a theme to offer.
        compare(offered.filter(theme => theme.id === "alsa").length, 0);
    }

    function test_anEmptyScanResolvesToNothingRatherThanThrowing() {
        const catalogue = SoundTheme.buildCatalogue(null);
        compare(SoundTheme.resolveEvent(catalogue, "freedesktop", "power-plug"), "");
        compare(SoundTheme.selectableThemes(catalogue).length, 0);
        compare(SoundTheme.themeChain(catalogue, "anything").join("|"), "anything|freedesktop");
    }
}
