import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import "../../../common/functions/record_bitrate.js" as RecordBitrate

// The reference page for the settings row grammar (AGENT.md, design
// language): subsection headers lead with an icon, every option of a
// segmented choice carries an icon, a computed hint sits under the quality
// choice, toggle rows carry an icon chip, the codec dropdown says which
// choice is recommended, the path fields float their labels, and every
// rationale rides the (i). Other pages adopt the same pieces in later PRs.
ContentPage {
    id: page
    forceWidth: true

    // The screen the settings window is on, as hyprctl reports it - width,
    // height and refresh rate in physical pixels and Hz - falling back to the
    // focused monitor while the window has none yet. Null when hyprctl has
    // answered nothing, in which case the quality hint is hidden rather than
    // drawn for a screen that does not exist.
    readonly property var recordScreen: {
        const name = page.QsWindow.window?.screen?.name ?? "";
        return HyprlandData.monitors.find(m => m.name === name)
            ?? HyprlandData.monitors.find(m => m.focused)
            ?? null;
    }

    function goTo(term) {
        const t = term.toLowerCase().trim()

        function findTarget(rootItem) {
            for (let i = 0; i < rootItem.children.length; i++) {
                let child = rootItem.children[i]
                if (child.title && child.title.toLowerCase().includes(t)) {
                    return child
                }
            }

            for (let i = 0; i < rootItem.children.length; i++) {
                let found = findTarget(rootItem.children[i])
                if (found) return found
            }
            return null
        }

        let target = findTarget(mainLayout)
        if (target) {
            let pos = target.mapToItem(mainLayout, 0, 0)
            page.scrollToY(pos.y)
        }
    }

    ColumnLayout {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Appearance.spacing.space200

        ContentSection {
            icon: "screen_record"
            shape: MaterialShape.Shape.Cookie7Sided
            title: Translation.tr("Screen recorder")

            GroupedList {
                ConfigSelectionArray {
                    text: Translation.tr("Quality")
                    icon: "high_quality"
                    infoText: Translation.tr("Constant quality: the recorder spends whatever bitrate the picture needs, so the figure below is an estimate for this screen, not a cap.")
                    currentValue: Config.options.screenRecord.quality
                    onSelected: value => { Config.options.screenRecord.quality = value }
                    options: [
                        { displayName: Translation.tr("Medium"), value: "medium", icon: "sd" },
                        { displayName: Translation.tr("High"), value: "high", icon: "hd" },
                        { displayName: Translation.tr("Very high"), value: "very_high", icon: "high_quality" },
                        { displayName: Translation.tr("Ultra"), value: "ultra", icon: "high_res" }
                    ]
                    detailContent: [
                        StyledText {
                            Layout.fillWidth: true
                            visible: page.recordScreen !== null
                            text: {
                                const screen = page.recordScreen;
                                if (screen === null)
                                    return "";
                                const fps = RecordBitrate.effectiveFps(Config.options.screenRecord.fps, screen.refreshRate);
                                const mbps = RecordBitrate.estimateMbps(screen.width, screen.height, fps, Config.options.screenRecord.quality);
                                return Translation.tr("~%1 Mbps - %2x%3 - %4 fps on this screen")
                                    .arg(mbps).arg(screen.width).arg(screen.height).arg(fps);
                            }
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.WordWrap
                        }
                    ]
                }
                ConfigComboBox {
                    text: Translation.tr("Codec")
                    buttonIcon: "memory"
                    // No _hdr entries: recording an HDR monitor already picks
                    // the HDR variant of whichever of these is chosen, so
                    // listing them would be a second way to say the same thing
                    // - and one a user could get wrong by selecting HDR on an
                    // SDR display. H.264 has no HDR variant, so choosing it on
                    // an HDR monitor notifies at record time instead.
                    infoText: Translation.tr("On an HDR display the HDR variant of the chosen codec is picked for you, so there is no HDR entry to get wrong here. H.264 cannot carry HDR - choosing it on an HDR display is explained at record time rather than silently swapped.")
                    currentValue: Config.options.screenRecord.codec
                    onSelected: value => { Config.options.screenRecord.codec = value }
                    model: [
                        { displayName: Translation.tr("Auto"), value: "auto", recommended: true },
                        { displayName: "H.264", value: "h264" },
                        { displayName: "HEVC", value: "hevc" },
                        { displayName: "AV1", value: "av1" }
                    ]
                }
                ConfigSpinBox {
                    icon: "speed"
                    text: Translation.tr("Frame rate (FPS)")
                    infoText: Translation.tr("A capture cannot outrun the screen: on a 60 Hz monitor a higher setting records at 60.")
                    value: Config.options.screenRecord.fps
                    from: 24
                    to: 240
                    stepSize: 6
                    onValueModified: { Config.options.screenRecord.fps = newValue }
                }
                ConfigSwitch {
                    iconChip: true
                    buttonIcon: "volume_up"
                    text: Translation.tr("Record desktop audio")
                    checked: Config.options.screenRecord.recordAudio
                    onToggleRequested: Config.options.screenRecord.recordAudio = !Config.options.screenRecord.recordAudio
                }
                ConfigSwitch {
                    iconChip: true
                    buttonIcon: "mic"
                    text: Translation.tr("Merge microphone into the audio track")
                    checked: Config.options.screenRecord.recordMic
                    onToggleRequested: Config.options.screenRecord.recordMic = !Config.options.screenRecord.recordMic
                }
                ConfigSwitch {
                    iconChip: true
                    buttonIcon: "point_scan"
                    text: Translation.tr("Show cursor")
                    checked: Config.options.screenRecord.showCursor
                    onToggleRequested: Config.options.screenRecord.showCursor = !Config.options.screenRecord.showCursor
                }
                ConfigSwitch {
                    iconChip: true
                    buttonIcon: "brightness_6"
                    text: Translation.tr("Record SDR on HDR displays")
                    infoText: Translation.tr("HDR recordings look washed out in players that can't tonemap (VLC, Discord, browsers). On: fullscreen recordings capture through the screen-share portal — correctly toned SDR instantly, with a one-time approval it remembers. Region recordings and replays record HDR and convert to SDR in the background a few seconds after saving. Off = true HDR files.")
                    checked: Config.options.screenRecord.tonemapSdr
                    onToggleRequested: Config.options.screenRecord.tonemapSdr = !Config.options.screenRecord.tonemapSdr
                }
            }

            ContentSubsection {
                icon: "replay"
                title: Translation.tr("Instant replay")
                GroupedList {
                    ConfigSwitch {
                        iconChip: true
                        buttonIcon: "replay"
                        text: Translation.tr("Enable (keep the last moments in a buffer)")
                        checked: Config.options.screenRecord.replay.enable
                        onToggleRequested: Config.options.screenRecord.replay.enable = !Config.options.screenRecord.replay.enable
                    }
                    ConfigSpinBox {
                        icon: "history"
                        text: Translation.tr("Buffer length (seconds)")
                        value: Config.options.screenRecord.replay.duration
                        from: 10
                        to: 600
                        stepSize: 10
                        onValueModified: { Config.options.screenRecord.replay.duration = newValue }
                    }
                    ConfigSwitch {
                        iconChip: true
                        buttonIcon: "save"
                        text: Translation.tr("Buffer on disk instead of RAM")
                        infoText: Translation.tr("A long buffer at a high quality is gigabytes; on disk it costs storage instead of memory.")
                        checked: Config.options.screenRecord.replay.storage === "disk"
                        onToggleRequested: Config.options.screenRecord.replay.storage = Config.options.screenRecord.replay.storage === "disk" ? "ram" : "disk"
                    }
                    ConfigTextArea {
                        id: replayPathField
                        Layout.fillWidth: true
                        floatingLabel: true
                        buttonIcon: "video_library"
                        text: Translation.tr("Replay path (empty = recording path)")
                        value: Config.options.screenRecord.replay.savePath
                        onValueChanged: { replayPathDebounceTimer.restart() }
                        Timer {
                            id: replayPathDebounceTimer
                            interval: 600
                            repeat: false
                            onTriggered: { Config.options.screenRecord.replay.savePath = replayPathField.value }
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: Appearance.spacing.space100
                        text: Translation.tr("Save a clip: Alt+F10, the bar button, or `qs -c imi ipc call record replaySave`")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        ContentSection {
            icon: "screenshot_monitor"
            title: Translation.tr("Screenshot popup")
            shape: MaterialShape.Shape.Clover4Leaf

            GroupedList {
                ConfigSwitch {
                    iconChip: true
                    buttonIcon: "preview"
                    text: Translation.tr("Show result popup")
                    description: Translation.tr("Preview with save/edit/discard after every screenshot")
                    checked: Config.options.screenshotResult.enable
                    onToggleRequested: Config.options.screenshotResult.enable = !Config.options.screenshotResult.enable
                }
                ConfigSpinBox {
                    enabled: Config.options.screenshotResult.enable
                    icon: "timer"
                    text: Translation.tr("Auto-dismiss (ms)")
                    value: Config.options.screenshotResult.timeoutMs
                    from: 1500
                    to: 30000
                    stepSize: 500
                    onValueModified: Config.options.screenshotResult.timeoutMs = newValue
                }
            }
        }

        ContentSection {
            icon: "screenshot_frame_2"
            shape: MaterialShape.Shape.PuffyDiamond
            title: Translation.tr("Region selector (screen snipping/Google Lens)")

            ContentSubsection {
                icon: "select_window"
                title: Translation.tr("Hint target regions")
                GroupedList {
                    ConfigSwitch {
                        iconChip: true
                        buttonIcon: "select_window"
                        text: Translation.tr('Windows')
                        checked: Config.options.regionSelector.targetRegions.windows
                        onToggleRequested: Config.options.regionSelector.targetRegions.windows = !Config.options.regionSelector.targetRegions.windows
                    }
                    ConfigSwitch {
                        iconChip: true
                        buttonIcon: "right_panel_open"
                        text: Translation.tr('Layers')
                        checked: Config.options.regionSelector.targetRegions.layers
                        onToggleRequested: Config.options.regionSelector.targetRegions.layers = !Config.options.regionSelector.targetRegions.layers
                    }
                    ConfigSwitch {
                        iconChip: true
                        buttonIcon: "nearby"
                        text: Translation.tr('Content')
                        checked: Config.options.regionSelector.targetRegions.content
                        onToggleRequested: Config.options.regionSelector.targetRegions.content = !Config.options.regionSelector.targetRegions.content
                    }
                }
            }

            ContentSubsection {
                icon: "search"
                title: Translation.tr("Google Lens")

                GroupedList {
                    ConfigSelectionArray {
                        text: Translation.tr("Selection Type")
                        icon: "ink_selection"
                        currentValue: Config.options.search.imageSearch.useCircleSelection ? "circle" : "rectangles"
                        onSelected: newValue => {
                            Config.options.search.imageSearch.useCircleSelection = (newValue === "circle");
                        }
                        options: [
                            { icon: "activity_zone", value: "rectangles", displayName: Translation.tr("Rectangular selection") },
                            { icon: "gesture", value: "circle", displayName: Translation.tr("Circle to Search") }
                        ]
                    }
                }
            }

            ContentSubsection {
                icon: "crop_square"
                title: Translation.tr("Rectangular selection")
                GroupedList {
                    ConfigSwitch {
                        iconChip: true
                        buttonIcon: "point_scan"
                        text: Translation.tr("Show aim lines")
                        checked: Config.options.regionSelector.rect.showAimLines
                        onToggleRequested: Config.options.regionSelector.rect.showAimLines = !Config.options.regionSelector.rect.showAimLines
                    }
                }
            }

            ContentSubsection {
                icon: "circle"
                title: Translation.tr("Circle selection")

                GroupedList {
                    ConfigSpinBox {
                        icon: "eraser_size_3"
                        text: Translation.tr("Stroke width")
                        value: Config.options.regionSelector.circle.strokeWidth
                        from: 1
                        to: 20
                        stepSize: 1
                        onValueModified: {
                            Config.options.regionSelector.circle.strokeWidth = newValue;
                        }
                    }

                    ConfigSpinBox {
                        icon: "screenshot_frame_2"
                        text: Translation.tr("Padding")
                        value: Config.options.regionSelector.circle.padding
                        from: 0
                        to: 100
                        stepSize: 5
                        onValueModified: {
                            Config.options.regionSelector.circle.padding = newValue;
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "file_open"
            shape: MaterialShape.Shape.Slanted
            title: Translation.tr("Save paths")

            GroupedList {
                ConfigTextArea {
                    id: videoRecordPathField
                    Layout.fillWidth: true
                    floatingLabel: true
                    buttonIcon: "video_file"
                    text: Translation.tr("Video Recording Path")
                    value: Config.options.screenRecord.savePath
                    onValueChanged: {
                        videoRecordPathDebounceTimer.restart();
                    }

                    Timer {
                        id: videoRecordPathDebounceTimer
                        interval: 600
                        repeat: false
                        onTriggered: {
                            Config.options.screenRecord.savePath = videoRecordPathField.value;
                        }
                    }
                }

                ConfigTextArea {
                    id: screenshotPathField
                    Layout.fillWidth: true
                    floatingLabel: true
                    buttonIcon: "screenshot_monitor"
                    text: Translation.tr("Screenshot Path (leave empty to just copy)")
                    value: Config.options.screenSnip.savePath
                    onValueChanged: {
                        screenshotPathDebounceTimer.restart();
                    }

                    Timer {
                        id: screenshotPathDebounceTimer
                        interval: 600
                        repeat: false
                        onTriggered: {
                            Config.options.screenSnip.savePath = screenshotPathField.value;
                        }
                    }
                }
            }
        }
    }
}
