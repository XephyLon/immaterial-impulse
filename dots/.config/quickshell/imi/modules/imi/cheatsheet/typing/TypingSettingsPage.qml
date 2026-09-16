pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Everything the typing test can be tuned to, inside the panel itself.
 *
 * The launcher is keyboard-first and modal: sending someone to the Settings
 * window to change a caret style would end their session. These write the same
 * Config keys the Settings window would, so the two never diverge - and they
 * are drawn by the same row widgets, so the two do not diverge in shape
 * either: subsection headers lead with an icon, every option row carries a
 * plain leading glyph, and GroupedList paints the plates.
 */
Item {
    id: root

    readonly property var options: Config.options.cheatsheet.typingTest

    /**
     * A choice row takes {displayName, value} pairs; a language and a sound
     * pack are both {id, label}. QML's JS engine has no Object.fromEntries,
     * but it does have Array.prototype.map, which is all this needs.
     */
    function chipOptions(entries) {
        return Array.from(entries).map(entry => ({
            displayName: entry.label ?? entry.id,
            value: entry.id
        }));
    }

    signal requestClose

    StyledFlickable {
        id: scroller
        anchors.fill: parent
        contentHeight: settingsColumn.implicitHeight
        clip: true

        // One column, not the two this page used to pair rows in: a
        // GroupedList row is a full-width plate with its control on the right
        // edge, and two of them side by side put two right edges on one line.
        ColumnLayout {
            id: settingsColumn
            width: scroller.width
            spacing: Appearance.spacing.space150

            // ── Language ──────────────────────────────────────────────
            ContentSubsection {
                icon: "language"
                title: Translation.tr("Language")

                GroupedList {
                    // Unlabelled: the subsection header above already says
                    // "Language", and the chips wrap across the panel's width
                    // rather than starting after a label that repeats it.
                    ConfigSelectionArray {
                        currentValue: root.options.language
                        options: root.chipOptions(TypingLanguages.languages)
                        onSelected: value => {
                            root.options.language = value;
                            TypingLanguages.request(value);
                        }
                    }
                }
            }

            // ── Test length ───────────────────────────────────────────
            ContentSubsection {
                icon: "timer"
                title: Translation.tr("Test length")

                // The toolbar carries the four presets; anything else belongs
                // here rather than as a text field wedged into that row.
                GroupedList {
                    // ConfigSlider has no `stepSize` - the granularity lives
                    // in the write-back, which is the only place it ever
                    // reached the config from anyway.
                    ConfigSlider {
                        text: Translation.tr("Time")
                        buttonIcon: "timer"
                        usePercentTooltip: false
                        from: 5
                        to: 300
                        value: root.options.time
                        onValueModified: newValue => {
                            root.options.time = Math.round(newValue / 5) * 5;
                        }
                    }

                    ConfigSlider {
                        text: Translation.tr("Words")
                        buttonIcon: "article"
                        usePercentTooltip: false
                        from: 5
                        to: 200
                        value: root.options.words
                        onValueModified: newValue => {
                            root.options.words = Math.round(newValue / 5) * 5;
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "self_improvement"
                        text: Translation.tr("Guided zen")
                        description: Translation.tr("Zen types generated words instead of your own, with no limit")
                        checked: root.options.zenGuided
                        onToggleRequested: root.options.zenGuided = !root.options.zenGuided
                    }
                }
            }

            // ── Typing surface ────────────────────────────────────────
            ContentSubsection {
                icon: "text_fields"
                title: Translation.tr("Typing surface")

                GroupedList {
                    ConfigSlider {
                        text: Translation.tr("Text size")
                        buttonIcon: "format_size"
                        usePercentTooltip: false
                        from: 16
                        to: 44
                        value: root.options.fontSize
                        onValueModified: newValue => {
                            root.options.fontSize = Math.round(newValue);
                        }
                    }

                    ConfigSelectionArray {
                        text: Translation.tr("Visible lines")
                        icon: "table_rows"
                        infoText: Translation.tr("How much of the test stays on screen")
                        currentValue: root.options.visibleLines
                        options: [
                            { displayName: "2", value: 2 },
                            { displayName: "3", value: 3 },
                            { displayName: "4", value: 4 },
                            { displayName: "5", value: 5 }
                        ]
                        onSelected: value => {
                            root.options.visibleLines = value;
                        }
                    }

                    ConfigSelectionArray {
                        text: Translation.tr("Caret")
                        icon: "text_select_start"
                        currentValue: root.options.caretStyle
                        options: [
                            { displayName: Translation.tr("line"), value: "line" },
                            { displayName: Translation.tr("block"), value: "block" },
                            { displayName: Translation.tr("underline"), value: "underline" },
                            { displayName: Translation.tr("off"), value: "off" }
                        ]
                        onSelected: value => {
                            root.options.caretStyle = value;
                        }
                    }

                    ConfigSwitch {
                        buttonIcon: "animation"
                        text: Translation.tr("Smooth caret and line motion")
                        checked: root.options.smoothCaret
                        onToggleRequested: root.options.smoothCaret = !root.options.smoothCaret
                    }

                    ConfigSwitch {
                        buttonIcon: "highlight"
                        text: Translation.tr("Highlight the current word")
                        description: Translation.tr("Dims every other word while you type")
                        checked: root.options.highlightCurrentWord
                        onToggleRequested: root.options.highlightCurrentWord = !root.options.highlightCurrentWord
                    }

                    ConfigSwitch {
                        buttonIcon: "visibility_off"
                        text: Translation.tr("Blind mode")
                        description: Translation.tr("Hides mistakes until the result")
                        checked: root.options.blindMode
                        onToggleRequested: root.options.blindMode = !root.options.blindMode
                    }
                }
            }

            // ── Live stats ────────────────────────────────────────────
            ContentSubsection {
                icon: "speed"
                title: Translation.tr("While typing")

                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "speed"
                        text: Translation.tr("Live speed")
                        checked: root.options.showLiveWpm
                        onToggleRequested: root.options.showLiveWpm = !root.options.showLiveWpm
                    }

                    ConfigSwitch {
                        buttonIcon: "percent"
                        text: Translation.tr("Live accuracy")
                        checked: root.options.showLiveAccuracy
                        onToggleRequested: root.options.showLiveAccuracy = !root.options.showLiveAccuracy
                    }

                    ConfigSwitch {
                        buttonIcon: "done_all"
                        text: Translation.tr("Finish on the last word")
                        description: Translation.tr("No trailing space needed to end a words test")
                        checked: root.options.finishOnLastWord
                        onToggleRequested: root.options.finishOnLastWord = !root.options.finishOnLastWord
                    }

                    ConfigSwitch {
                        buttonIcon: "restart_alt"
                        text: Translation.tr("Tab restarts immediately")
                        description: Translation.tr("Otherwise Tab points at restart and Enter presses it")
                        checked: root.options.quickRestart
                        onToggleRequested: root.options.quickRestart = !root.options.quickRestart
                    }
                }
            }

            // ── Keyboard ──────────────────────────────────────────────
            ContentSubsection {
                icon: "keyboard"
                title: Translation.tr("Keyboard preview")

                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "keyboard"
                        text: Translation.tr("Show the keyboard")
                        checked: root.options.keyboard.enable
                        onToggleRequested: root.options.keyboard.enable = !root.options.keyboard.enable
                    }

                    ConfigSwitch {
                        buttonIcon: "ads_click"
                        text: Translation.tr("Point at the next key")
                        checked: root.options.keyboard.highlightNextKey
                        onToggleRequested: root.options.keyboard.highlightNextKey = !root.options.keyboard.highlightNextKey
                    }

                    ConfigSelectionArray {
                        text: Translation.tr("Layout")
                        icon: "keyboard_alt"
                        currentValue: root.options.keyboard.layout
                        options: [
                            { displayName: "qwerty", value: "qwerty" },
                            { displayName: "qwertz", value: "qwertz" },
                            { displayName: "azerty", value: "azerty" },
                            { displayName: "dvorak", value: "dvorak" },
                            { displayName: "colemak", value: "colemak" }
                        ]
                        onSelected: value => {
                            root.options.keyboard.layout = value;
                        }
                    }
                }
            }

            // ── Sound ─────────────────────────────────────────────────
            ContentSubsection {
                icon: "volume_up"
                title: Translation.tr("Sound")

                // Every row below the first is gated on it. The dim is the
                // widgets' own - a second `opacity` here would multiply with
                // theirs (lint_disabled_opacity).
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "volume_up"
                        text: Translation.tr("Key sounds")
                        checked: root.options.sounds.enable
                        onToggleRequested: root.options.sounds.enable = !root.options.sounds.enable
                    }

                    ConfigSwitch {
                        buttonIcon: "error"
                        text: Translation.tr("Sound on mistakes")
                        enabled: root.options.sounds.enable
                        checked: root.options.sounds.errorSound
                        onToggleRequested: root.options.sounds.errorSound = !root.options.sounds.errorSound
                    }

                    ConfigSelectionArray {
                        text: Translation.tr("Key sound")
                        icon: "music_note"
                        enabled: root.options.sounds.enable
                        currentValue: root.options.sounds.theme
                        options: root.chipOptions(TypingSoundPacks.clickPacks)
                        onSelected: value => {
                            root.options.sounds.theme = value;
                        }
                    }

                    ConfigSelectionArray {
                        text: Translation.tr("Mistake sound")
                        icon: "notification_important"
                        enabled: root.options.sounds.enable && root.options.sounds.errorSound
                        currentValue: root.options.sounds.errorTheme
                        options: root.chipOptions(TypingSoundPacks.errorPacks)
                        onSelected: value => {
                            root.options.sounds.errorTheme = value;
                        }
                    }

                    ConfigSlider {
                        text: Translation.tr("Volume")
                        buttonIcon: "tune"
                        enabled: root.options.sounds.enable
                        from: 0
                        to: 100
                        value: root.options.sounds.volume
                        onValueModified: newValue => {
                            root.options.sounds.volume = Math.round(newValue / 5) * 5;
                        }
                    }
                }
            }

            // ── Shortcuts ─────────────────────────────────────────────
            ContentSubsection {
                icon: "shortcut"
                title: Translation.tr("Keyboard shortcuts")

                // The bottom bar only has room for the common ones; the full
                // set lives here so nothing is discoverable by accident alone.
                // A group whose rows come from a list uses GroupedList's own
                // model/rowDelegate rather than a surface of its own
                // (M3_GUIDELINES.md, "Grouped Settings").
                GroupedList {
                    model: [
                        { keys: ["Esc"], label: Translation.tr("Back, or leave this page") },
                        { keys: ["Ctrl", "R"], label: Translation.tr("Restart") },
                        { keys: ["Tab", "↵"], label: Translation.tr("Point at restart, then press it") },
                        { keys: ["Tab"], label: Translation.tr("Restart outright, when enabled above") },
                        { keys: ["Shift", "↵"], label: Translation.tr("Finish zen, or start the next test") },
                        { keys: ["Ctrl", "⌫"], label: Translation.tr("Erase the current word") },
                        { keys: ["Ctrl", "1-3"], label: Translation.tr("Time, words or zen") },
                        { keys: ["Ctrl", "G"], label: Translation.tr("Free or guided zen") },
                        { keys: ["Ctrl", "[", "]"], label: Translation.tr("Previous or next length") },
                        { keys: ["Ctrl", "P"], label: Translation.tr("Punctuation") },
                        { keys: ["Ctrl", "N"], label: Translation.tr("Numbers") },
                        { keys: ["Ctrl", "L"], label: Translation.tr("Next language") },
                        { keys: ["Ctrl", ","], label: Translation.tr("These settings") },
                        { keys: ["Ctrl", "H"], label: Translation.tr("Score history") },
                        { keys: ["Ctrl", "S"], label: Translation.tr("Statistics") }
                    ]
                    rowDelegate: Component {
                        CatalogueRow {
                            id: shortcutRow
                            property var modelData: null

                            title: shortcutRow.modelData?.label ?? ""
                            titleFillsWidth: true
                            titleElides: true
                            affordance: [
                                KeyHint {
                                    keys: shortcutRow.modelData?.keys ?? []
                                    // The plate under the row, so the key
                                    // faces are mixed off what is behind them.
                                    surface: Appearance.colors.colLayer1
                                    onSurface: Appearance.colors.colOnLayer1
                                }
                            ]
                        }
                    }
                }
            }

            // ── History ───────────────────────────────────────────────
            ContentSubsection {
                icon: "history"
                title: Translation.tr("Score history")

                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "save"
                        text: Translation.tr("Keep results on this machine")
                        description: Translation.tr("Aggregate scores only — never the words or the keys")
                        checked: root.options.history.enable
                        onToggleRequested: root.options.history.enable = !root.options.history.enable
                    }

                    ConfigSlider {
                        text: Translation.tr("Results kept")
                        buttonIcon: "format_list_numbered"
                        usePercentTooltip: false
                        enabled: root.options.history.enable
                        from: 10
                        to: 500
                        value: root.options.history.maxEntries
                        onValueModified: newValue => {
                            root.options.history.maxEntries = Math.round(newValue / 10) * 10;
                        }
                    }

                    // No ConfigSwitch shape fits a row whose affordance is an
                    // action rather than a state, so this is the catalogue row
                    // with a dialog button in its affordance slot - the same
                    // pairing Settings > Services uses for "Index now".
                    CatalogueRow {
                        rowIcon: "delete_sweep"
                        title: Translation.tr("Clear every stored result")
                        titleFillsWidth: true
                        titleElides: true
                        description: Translation.tr("%1 results, %2 personal bests and every lifetime total")
                            .arg(String(TypingHistory.results.length))
                            .arg(String(TypingHistory.personalBests.length))
                        affordance: [
                            DialogButton {
                                buttonText: Translation.tr("Clear")
                                colBackground: Appearance.colors.colErrorContainer
                                colBackgroundHover: Appearance.colors.colErrorContainerHover
                                colRipple: Appearance.colors.colErrorContainerActive
                                colText: Appearance.colors.colOnErrorContainer
                                onClicked: TypingHistory.clear()
                            }
                        ]
                    }
                }
            }
        }
    }

    TypingStageFade {
        target: scroller
        fadeSize: 36
    }
}
