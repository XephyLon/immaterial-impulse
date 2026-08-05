import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: page
    forceWidth: true

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
            page.contentY = Math.max(0, pos.y - 0)
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
                    currentValue: Config.options.screenRecord.quality
                    onSelected: value => { Config.options.screenRecord.quality = value }
                    options: [
                        { displayName: Translation.tr("Medium"), value: "medium" },
                        { displayName: Translation.tr("High"), value: "high" },
                        { displayName: Translation.tr("Very high"), value: "very_high" },
                        { displayName: Translation.tr("Ultra"), value: "ultra" }
                    ]
                }
                ConfigSelectionArray {
                    text: Translation.tr("Codec")
                    icon: "memory"
                    // No _hdr entries: recording an HDR monitor already picks
                    // the HDR variant of whichever of these is chosen, so
                    // listing them would be a second way to say the same thing
                    // - and one a user could get wrong by selecting HDR on an
                    // SDR display. H.264 has no HDR variant, so choosing it on
                    // an HDR monitor notifies at record time instead.
                    // (ConfigSelectionArray has no `description`; that belongs
                    // to ConfigSwitch. DesignSystemCompile catches the mix-up.)
                    currentValue: Config.options.screenRecord.codec
                    onSelected: value => { Config.options.screenRecord.codec = value }
                    options: [
                        { displayName: Translation.tr("Auto"), value: "auto" },
                        { displayName: "H.264", value: "h264" },
                        { displayName: "HEVC", value: "hevc" },
                        { displayName: "AV1", value: "av1" }
                    ]
                }
                ConfigSpinBox {
                    icon: "speed"
                    text: Translation.tr("Frame rate (FPS)")
                    value: Config.options.screenRecord.fps
                    from: 24
                    to: 240
                    stepSize: 6
                    onValueModified: { Config.options.screenRecord.fps = newValue }
                }
                ConfigSwitch {
                    buttonIcon: "volume_up"
                    text: Translation.tr("Record desktop audio")
                    checked: Config.options.screenRecord.recordAudio
                    onCheckedChanged: { Config.options.screenRecord.recordAudio = checked }
                }
                ConfigSwitch {
                    buttonIcon: "mic"
                    text: Translation.tr("Merge microphone into the audio track")
                    checked: Config.options.screenRecord.recordMic
                    onCheckedChanged: { Config.options.screenRecord.recordMic = checked }
                }
                ConfigSwitch {
                    buttonIcon: "point_scan"
                    text: Translation.tr("Show cursor")
                    checked: Config.options.screenRecord.showCursor
                    onCheckedChanged: { Config.options.screenRecord.showCursor = checked }
                }
                ConfigSwitch {
                    buttonIcon: "brightness_6"
                    text: Translation.tr("Record SDR on HDR displays")
                    description: Translation.tr("HDR recordings look washed out in players that can't tonemap (VLC, Discord, browsers). On: fullscreen recordings capture through the screen-share portal — correctly toned SDR instantly, with a one-time approval it remembers. Region recordings and replays record HDR and convert to SDR in the background a few seconds after saving. Off = true HDR files.")
                    checked: Config.options.screenRecord.tonemapSdr
                    onCheckedChanged: { Config.options.screenRecord.tonemapSdr = checked }
                }
            }

            ContentSubsection {
                title: Translation.tr("Instant replay")
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "replay"
                        text: Translation.tr("Enable (keep the last moments in a buffer)")
                        checked: Config.options.screenRecord.replay.enable
                        onCheckedChanged: { Config.options.screenRecord.replay.enable = checked }
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
                        buttonIcon: "save"
                        text: Translation.tr("Buffer on disk instead of RAM")
                        checked: Config.options.screenRecord.replay.storage === "disk"
                        onCheckedChanged: { Config.options.screenRecord.replay.storage = checked ? "disk" : "ram" }
                    }
                    ConfigTextArea {
                        id: replayPathField
                        Layout.fillWidth: true
                        fieldWidth: 250
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
                    buttonIcon: "preview"
                    text: Translation.tr("Show result popup")
                    description: Translation.tr("Preview with save/edit/discard after every screenshot")
                    checked: Config.options.screenshotResult.enable
                    onCheckedChanged: Config.options.screenshotResult.enable = checked
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
                title: Translation.tr("Hint target regions")
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "select_window"
                        text: Translation.tr('Windows')
                        checked: Config.options.regionSelector.targetRegions.windows
                        onCheckedChanged: {
                            Config.options.regionSelector.targetRegions.windows = checked;
                        }
                    }
                    ConfigSwitch {
                        buttonIcon: "right_panel_open"
                        text: Translation.tr('Layers')
                        checked: Config.options.regionSelector.targetRegions.layers
                        onCheckedChanged: {
                            Config.options.regionSelector.targetRegions.layers = checked;
                        }
                    }
                    ConfigSwitch {
                        buttonIcon: "nearby"
                        text: Translation.tr('Content')
                        checked: Config.options.regionSelector.targetRegions.content
                        onCheckedChanged: {
                            Config.options.regionSelector.targetRegions.content = checked;
                        }
                    }
                }
            }

            ContentSubsection {
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
                title: Translation.tr("Rectangular selection")
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "point_scan"
                        text: Translation.tr("Show aim lines")
                        checked: Config.options.regionSelector.rect.showAimLines
                        onCheckedChanged: {
                            Config.options.regionSelector.rect.showAimLines = checked;
                        }
                    }
                }
            }

            ContentSubsection {
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
                    fieldWidth: 250
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
                    fieldWidth: 250
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
