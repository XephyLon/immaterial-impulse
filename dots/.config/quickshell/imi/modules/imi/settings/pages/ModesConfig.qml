import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.imi.modes

/**
 * Settings for Modes & Routines (ported from the p3drovfx fork, rewritten
 * in this shell's page grammar: ContentSection > GroupedList rows). The
 * definitions themselves are edited in the manager (Super + Y); this page
 * holds what sits around them: whether automatic starts happen at all,
 * where the active mode shows, how games are recognised, and the data.
 */
ContentPage {
    id: page
    forceWidth: true
    readonly property var opts: Config.options.modes
    // The shortcut is bound in the Hyprland config, which the shell's own
    // update never touches - so it can be missing on an otherwise current
    // install and the overlay simply never opens.
    property bool keybindChecked: false
    property bool keybindFound: true
    property string seededText: ""
    // The bar pill is the "modeIndicator" widget in the bar's right layout
    // (this shell's layouts are lists of widget ids).
    readonly property bool barVisible: (Config.options.bar.layouts.rightLayout ?? []).indexOf("modeIndicator") !== -1

    function setBarVisible(on) {
        const list = Array.from(Config.options.bar.layouts.rightLayout ?? []).filter(id => id !== "modeIndicator");
        if (on) {
            const after = list.indexOf("recordIndicator");
            list.splice(after === -1 ? list.length : after + 1, 0, "modeIndicator");
        }
        Config.options.bar.layouts.rightLayout = list;
    }

    function windowSuggestions() {
        const seen = {};
        const out = [];
        for (const w of Array.from(HyprlandData.windowList ?? [])) {
            const cls = String(w.initialClass || w["class"] || "");
            if (!cls.length || seen[cls])
                continue;
            seen[cls] = true;
            out.push({ label: String(w.title || cls).slice(0, 40), value: cls });
        }
        return out;
    }

    Process {
        id: keybindProbe
        running: true
        // `hyprctl binds` shows "__lua" for every bind under the Lua config,
        // so the config text is read instead; -s keeps a missing dir quiet.
        command: ["grep", "-rqsF", "quickshell:modesToggle", `${FileUtils.trimFileProtocol(Directories.config)}/hypr`]
        onExited: (code, status) => {
            page.keybindFound = (code === 0);
            page.keybindChecked = true;
        }
    }

    NoticeBox {
        Layout.fillWidth: true
        visible: page.opts.overlayEnabled && page.keybindChecked && !page.keybindFound
        materialIcon: "keyboard_off"
        colBackground: Appearance.colors.colErrorContainer
        colOnBackground: Appearance.m3colors.m3onErrorContainer
        text: Translation.tr("Hyprland has no binding for the manager, so Super + Y does nothing. Update the Hyprland config (Settings > Update Dots) or bind quickshell:modesToggle yourself.")
    }

    NoticeBox {
        Layout.fillWidth: true
        materialIcon: "tune"
        text: {
            const modes = Modes.modes.length;
            const routines = Modes.routines.length;
            const line = Translation.tr("%1 mode(s) and %2 routine(s) set up.").arg(modes).arg(routines);
            if (Modes.active)
                return line + " " + Translation.tr("%1 is on right now.").arg(Modes.activeMode?.name ?? "");
            return line + " " + Translation.tr("Nothing is on right now. Super + Y opens the manager.");
        }
        RippleButton {
            implicitHeight: 34
            horizontalPadding: Appearance.spacing.space200
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            enabled: page.opts.overlayEnabled
            opacity: enabled ? 1 : 0.5
            onClicked: GlobalStates.modesOpen = true
            contentItem: StyledText {
                text: Translation.tr("Open the manager")
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                color: Appearance.colors.colOnPrimary
            }
        }
    }

    ContentSection {
        icon: "tune"
        title: Translation.tr("General")

        GroupedList {
            ConfigSwitch {
                buttonIcon: "autoplay"
                text: Translation.tr("Start and end things automatically")
                checked: page.opts.enable
                onToggleRequested: Config.options.modes.enable = !Config.options.modes.enable
                description: Translation.tr("Off: conditions are ignored everywhere. Modes and routines still work when you start them yourself, and whatever is on stays on.")
            }
            ConfigSwitch {
                buttonIcon: "dashboard"
                text: Translation.tr("Load the manager overlay")
                checked: page.opts.overlayEnabled
                onToggleRequested: Config.options.modes.overlayEnabled = !Config.options.modes.overlayEnabled
                description: Translation.tr("Super + Y, the bar pill and the sidebar toggle all open it. Off saves a little memory; the engine keeps running.")
            }
        }

        ContentSubsection {
            title: Translation.tr("Presets")

            GroupedList {
                ConfigRow {
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: page.seededText.length > 0 ? page.seededText
                            : Translation.tr("The built-in modes (Sleep, Work, Focus, Gaming, Theater, Presentation, Relax) are ordinary entries once added: edit or delete them freely. This puts back any you removed, without touching the ones still there.")
                    }
                    RippleButton {
                        Layout.rightMargin: Appearance.spacing.space100
                        implicitHeight: 32
                        padding: Appearance.spacing.space150
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSecondaryContainer
                        colRipple: Appearance.colors.colSecondaryContainerActive
                        onClicked: {
                            const added = Modes.seedPresets();
                            page.seededText = added.length === 0 ? Translation.tr("All presets are already there.")
                                : Translation.tr("Added: %1").arg(added.map(id => Modes.modeById(id)?.name ?? id).join(", "));
                        }
                        contentItem: StyledText {
                            text: Translation.tr("Restore missing presets")
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "campaign"
        title: Translation.tr("Where the active mode shows")

        GroupedList {
            ConfigSwitch {
                buttonIcon: "space_bar"
                text: Translation.tr("Pill in the bar")
                checked: page.barVisible
                onToggleRequested: page.setBarVisible(!page.barVisible)
                description: Translation.tr("The Mode widget from the bar layout editor, added to the right side: takes no room while nothing is on. Left-click opens the manager, right-click ends the mode.")
            }
        }

        ContentSubsection {
            title: Translation.tr("When a mode starts or ends")

            GroupedList {
                ConfigSelectionArray {
                    currentValue: page.opts.flash
                    onSelected: newValue => { Config.options.modes.flash = newValue; }
                    options: [
                        { "displayName": Translation.tr("Brief banner"), "value": "auto" },
                        { "displayName": Translation.tr("Nothing"), "value": "off" }
                    ]
                }
                ConfigRow {
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("A small top-centre pill for three seconds. Each mode and routine chooses its own start and end banner.")
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "timer"
        title: Translation.tr("Automatic ends")

        GroupedList {
            ConfigSpinBox {
                icon: "hourglass_bottom"
                text: Translation.tr("Grace period (seconds)")
                value: page.opts.graceSec
                from: 0
                to: 600
                stepSize: 5
                onValueModified: Config.options.modes.graceSec = newValue
                infoText: Translation.tr("How long a mode's conditions must stay false before it ends on its own, so a quick workspace switch or a brief alt-tab does not flap it.")
            }
        }
    }

    ContentSection {
        icon: "sports_esports"
        title: Translation.tr("Game detection")

        GroupedList {
            ConfigSwitch {
                buttonIcon: "rocket_launch"
                text: Translation.tr("Windows from game launchers")
                checked: page.opts.game.useLauncherClasses
                onToggleRequested: Config.options.modes.game.useLauncherClasses = !Config.options.modes.game.useLauncherClasses
                description: Translation.tr("Steam, Heroic, Lutris, Bottles, Prism Launcher and fullscreen Windows executables.")
            }
            ConfigSwitch {
                buttonIcon: "category"
                text: Translation.tr("Apps filed under Games")
                checked: page.opts.game.useDesktopCategory
                onToggleRequested: Config.options.modes.game.useDesktopCategory = !Config.options.modes.game.useDesktopCategory
                description: Translation.tr("Any window whose desktop entry has the Game category.")
            }
            ConfigSwitch {
                buttonIcon: "memory"
                text: Translation.tr("Fullscreen window keeping the GPU busy")
                checked: page.opts.game.useGpuHeuristic
                onToggleRequested: Config.options.modes.game.useGpuHeuristic = !Config.options.modes.game.useGpuHeuristic
                description: Translation.tr("Catches games nothing else recognises. Also catches a fullscreen video that decodes on the GPU; raise the threshold if that happens.")
            }
            ConfigSpinBox {
                property bool rowVisible: page.opts.game.useGpuHeuristic
                icon: "speed"
                text: Translation.tr("GPU above (%)")
                value: page.opts.game.gpuThreshold
                from: 10
                to: 100
                stepSize: 5
                onValueModified: Config.options.modes.game.gpuThreshold = newValue
            }
            ConfigSpinBox {
                property bool rowVisible: page.opts.game.useGpuHeuristic
                icon: "timelapse"
                text: Translation.tr("For at least (seconds)")
                value: page.opts.game.holdSec
                from: 5
                to: 300
                stepSize: 5
                onValueModified: Config.options.modes.game.holdSec = newValue
            }
        }

        ContentSubsection {
            title: Translation.tr("Always a game")

            GroupedList {
                ConfigRow {
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Appearance.spacing.space50
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            text: Translation.tr("Window classes treated as games no matter what. Pick from the windows open now, or type one.")
                        }
                        ChipInput {
                            Layout.fillWidth: true
                            values: page.opts.game.extraClasses
                            placeholder: Translation.tr("Window class")
                            suggestions: page.windowSuggestions()
                            onChanged: list => Config.options.modes.game.extraClasses = list
                        }
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: GameDetector.gameRunning ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                            text: GameDetector.gameRunning
                                ? Translation.tr("Detected now: %1").arg(GameDetector.reason)
                                : Translation.tr("No game detected right now.")
                        }
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "database"
        title: Translation.tr("Data")

        ContentSubsection {
            title: Translation.tr("Activity")

            GroupedList {
                ConfigRow {
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: {
                            const n = Modes.history.length;
                            const count = n === 1 ? Translation.tr("1 entry") : Translation.tr("%1 entries").arg(n);
                            return Translation.tr("%1 in the Activity tab. The newest 200 are kept.").arg(count);
                        }
                    }
                    RippleButton {
                        Layout.rightMargin: Appearance.spacing.space100
                        implicitHeight: 32
                        padding: Appearance.spacing.space150
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSecondaryContainer
                        colRipple: Appearance.colors.colSecondaryContainerActive
                        enabled: Modes.history.length > 0
                        opacity: enabled ? 1 : 0.5
                        // Two presses, the second within three seconds: the log is
                        // history, and a confirmation dialog does not belong on a page.
                        property bool armed: false
                        Timer { id: disarm; interval: 3000; onTriggered: parent.armed = false }
                        onClicked: {
                            if (!armed) { armed = true; disarm.restart(); return; }
                            Modes.clearHistory();
                            armed = false;
                        }
                        contentItem: StyledText {
                            text: parent.armed ? Translation.tr("Press again to clear") : Translation.tr("Clear activity")
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Where it lives")

            GroupedList {
                ConfigRow {
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("Modes and routines are saved in the shell config under \"modes\", so a config backup carries them. What is running and the activity log are state, kept separately and restored after a restart.")
                    }
                }
            }
        }
    }

}
