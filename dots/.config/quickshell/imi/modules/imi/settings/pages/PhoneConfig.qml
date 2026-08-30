import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Settings > Devices & Phone: everything the Phone tab persists under
// `Config.options.phone.*`, on the settings row grammar Settings > Capture is
// the reference page for (AGENT.md, design language) - icon-led subsection
// headers, segmented choices whose every option carries an icon, toggle rows
// on icon chips, a dropdown that says which choice is recommended, text fields
// that float their labels, and an (i) wherever a row has a rationale.
//
// The webcam's and the microphone's own settings are deliberately NOT
// repeated here: they live on those features' sub-pages in the tab, next to
// the toggle that starts them, and two pages writing one key is how the two
// come to disagree about what it means.
ContentPage {
    id: page
    forceWidth: true

    readonly property var phoneConfig: Config.options.phone
    readonly property var scrcpyConfig: Config.options.phone?.scrcpy
    readonly property var appModeConfig: Config.options.phone?.scrcpy?.appMode
    readonly property var contactsConfig: Config.options.phone?.contacts

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
            icon: "smartphone"
            shape: MaterialShape.Shape.Cookie9Sided
            title: Translation.tr("Phone panel")

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "view_in_ar"
                    text: Translation.tr("Show the mirror, webcam and microphone cards")
                    infoText: Translation.tr("The bottom of the Phone tab. Turning this off leaves the tab's notifications, actions and pages alone; a pairing request still appears, because that is a question a phone asked rather than a peripheral.")
                    checked: page.phoneConfig?.showPeripheralCards ?? true
                    onToggleRequested: Config.options.phone.showPeripheralCards = !(page.phoneConfig?.showPeripheralCards ?? true)
                }
            }
        }

        ContentSection {
            icon: "contacts"
            shape: MaterialShape.Shape.Clover4Leaf
            title: Translation.tr("Contacts")

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "sync"
                    text: Translation.tr("Read the phone's contacts")
                    infoText: Translation.tr("KDE Connect writes one vCard per contact into ~/.local/share/kpeoplevcard when its Contacts plugin is on. Nothing is fetched over the network; this only reads what is already on disk.")
                    checked: page.contactsConfig?.enabled ?? true
                    onToggleRequested: Config.options.phone.contacts.enabled = !(page.contactsConfig?.enabled ?? true)
                }

                ConfigSwitch {
                    buttonIcon: "filter_alt"
                    text: Translation.tr("Hide contacts with no name")
                    infoText: Translation.tr("SIM imports and call-blocker lists arrive with a number where a name should be. A starred contact is never hidden - starring one is saying its number matters.")
                    checked: page.contactsConfig?.hideUnnamed ?? true
                    onToggleRequested: Config.options.phone.contacts.hideUnnamed = !(page.contactsConfig?.hideUnnamed ?? true)
                }

                ConfigSelectionArray {
                    text: Translation.tr("Sort by")
                    icon: "sort_by_alpha"
                    currentValue: page.contactsConfig?.sortBy ?? "first"
                    onSelected: value => Config.options.phone.contacts.sortBy = value
                    options: [
                        { displayName: Translation.tr("First name"), value: "first", icon: "person" },
                        { displayName: Translation.tr("Last name"), value: "last", icon: "family_history" }
                    ]
                }
            }
        }

        ContentSection {
            icon: "smart_display"
            shape: MaterialShape.Shape.PuffyDiamond
            title: Translation.tr("Screen mirroring")

            ContentSubsection {
                icon: "cable"
                title: Translation.tr("Connection")

                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "wifi_tethering"
                        text: Translation.tr("Reach the phone over the network")
                        infoText: Translation.tr("Off, adb chooses, and a phone plugged in over USB always wins. On, scrcpy is aimed at an address instead - which is what wireless debugging needs.")
                        checked: page.scrcpyConfig?.useWireless ?? false
                        onToggleRequested: Config.options.phone.scrcpy.useWireless = !(page.scrcpyConfig?.useWireless ?? false)
                    }

                    ConfigSwitch {
                        buttonIcon: "auto_mode"
                        text: Translation.tr("Use the address KDE Connect reports")
                        enabled: page.scrcpyConfig?.useWireless ?? false
                        checked: page.scrcpyConfig?.autoWirelessIp ?? true
                        onToggleRequested: Config.options.phone.scrcpy.autoWirelessIp = !(page.scrcpyConfig?.autoWirelessIp ?? true)
                    }

                    ConfigTextArea {
                        id: wirelessIpField
                        // `rowVisible`, never `visible`: a GroupedList row
                        // hidden with `visible` keeps a full-height empty
                        // plate where the row used to be.
                        property bool rowVisible: (page.scrcpyConfig?.useWireless ?? false)
                            && !(page.scrcpyConfig?.autoWirelessIp ?? true)
                        Layout.fillWidth: true
                        floatingLabel: true
                        buttonIcon: "lan"
                        text: Translation.tr("Phone address")
                        value: page.scrcpyConfig?.wirelessIp ?? ""
                        onValueChanged: wirelessIpDebounce.restart()

                        Timer {
                            id: wirelessIpDebounce
                            interval: 600
                            onTriggered: Config.options.phone.scrcpy.wirelessIp = wirelessIpField.value
                        }
                    }

                    ConfigTextArea {
                        id: wirelessPortField
                        property bool rowVisible: (page.scrcpyConfig?.useWireless ?? false)
                            && !(page.scrcpyConfig?.autoWirelessIp ?? true)
                        Layout.fillWidth: true
                        floatingLabel: true
                        buttonIcon: "tag"
                        // A string rather than a number, because Android 11+
                        // re-rolls the wireless-debugging port on every toggle
                        // and what the phone shows is what gets typed here.
                        text: Translation.tr("Wireless debugging port")
                        value: page.scrcpyConfig?.wirelessPort ?? ""
                        onValueChanged: wirelessPortDebounce.restart()

                        Timer {
                            id: wirelessPortDebounce
                            interval: 600
                            onTriggered: Config.options.phone.scrcpy.wirelessPort = wirelessPortField.value
                        }
                    }
                }
            }

            ContentSubsection {
                icon: "tune"
                title: Translation.tr("Mirror options")

                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "coffee"
                        text: Translation.tr("Keep the phone awake while mirroring")
                        checked: page.scrcpyConfig?.stayAwake ?? false
                        onToggleRequested: Config.options.phone.scrcpy.stayAwake = !(page.scrcpyConfig?.stayAwake ?? false)
                    }

                    ConfigSwitch {
                        buttonIcon: "mobile_off"
                        text: Translation.tr("Turn the phone's screen off")
                        checked: page.scrcpyConfig?.turnScreenOff ?? false
                        onToggleRequested: Config.options.phone.scrcpy.turnScreenOff = !(page.scrcpyConfig?.turnScreenOff ?? false)
                    }

                    ConfigSwitch {
                        buttonIcon: "power_settings_new"
                        text: Translation.tr("Do not wake the phone on connect")
                        checked: page.scrcpyConfig?.noPowerOn ?? false
                        onToggleRequested: Config.options.phone.scrcpy.noPowerOn = !(page.scrcpyConfig?.noPowerOn ?? false)
                    }

                    ConfigSwitch {
                        buttonIcon: "volume_off"
                        text: Translation.tr("Leave the phone's audio on the phone")
                        infoText: Translation.tr("scrcpy forwards the phone's audio to this machine by default. Off is what the Phone Microphone card wants, which captures the microphone instead.")
                        checked: page.scrcpyConfig?.noAudio ?? false
                        onToggleRequested: Config.options.phone.scrcpy.noAudio = !(page.scrcpyConfig?.noAudio ?? false)
                    }

                    ConfigSwitch {
                        buttonIcon: "touch_app"
                        text: Translation.tr("Show touches on the phone")
                        checked: page.scrcpyConfig?.showTouches ?? false
                        onToggleRequested: Config.options.phone.scrcpy.showTouches = !(page.scrcpyConfig?.showTouches ?? false)
                    }

                    ConfigSwitch {
                        buttonIcon: "fullscreen"
                        text: Translation.tr("Open the mirror fullscreen")
                        checked: page.scrcpyConfig?.fullscreen ?? false
                        onToggleRequested: Config.options.phone.scrcpy.fullscreen = !(page.scrcpyConfig?.fullscreen ?? false)
                    }

                    ConfigSwitch {
                        buttonIcon: "vertical_align_top"
                        text: Translation.tr("Keep the mirror above other windows")
                        checked: page.scrcpyConfig?.alwaysOnTop ?? false
                        onToggleRequested: Config.options.phone.scrcpy.alwaysOnTop = !(page.scrcpyConfig?.alwaysOnTop ?? false)
                    }

                    ConfigComboBox {
                        text: Translation.tr("Video bitrate")
                        buttonIcon: "network_cell"
                        infoText: Translation.tr("What scrcpy asks the phone to encode at. Higher costs battery and Wi-Fi; over USB it is nearly free.")
                        currentValue: page.scrcpyConfig?.bitRate ?? "8M"
                        onSelected: value => Config.options.phone.scrcpy.bitRate = value
                        model: [
                            { displayName: "2 Mbps", value: "2M" },
                            { displayName: "4 Mbps", value: "4M" },
                            { displayName: "8 Mbps", value: "8M", recommended: true },
                            { displayName: "16 Mbps", value: "16M" }
                        ]
                    }

                    ConfigSpinBox {
                        icon: "speed"
                        text: Translation.tr("Frame rate cap (0 = the phone's own)")
                        value: page.scrcpyConfig?.maxFps ?? 0
                        from: 0
                        to: 120
                        stepSize: 5
                        onValueModified: Config.options.phone.scrcpy.maxFps = newValue
                    }

                    ConfigSpinBox {
                        icon: "aspect_ratio"
                        text: Translation.tr("Longest side in pixels (0 = native)")
                        infoText: Translation.tr("Scales the stream down before it leaves the phone, which is the cheapest way to make a wireless mirror keep up.")
                        value: page.scrcpyConfig?.maxSize ?? 0
                        from: 0
                        to: 3840
                        stepSize: 120
                        onValueModified: Config.options.phone.scrcpy.maxSize = newValue
                    }

                    ConfigSpinBox {
                        icon: "av_timer"
                        text: Translation.tr("Video buffer (ms)")
                        infoText: Translation.tr("Trades latency for smoothness. Zero is the lowest latency and the one that stutters first on a busy network.")
                        value: page.scrcpyConfig?.videoBuffer ?? 0
                        from: 0
                        to: 1000
                        stepSize: 10
                        onValueModified: Config.options.phone.scrcpy.videoBuffer = newValue
                    }
                }
            }

            ContentSubsection {
                icon: "apps"
                title: Translation.tr("App Mode")

                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "apps"
                        text: Translation.tr("Offer the phone's apps")
                        infoText: Translation.tr("Needs scrcpy 4.0 or newer, which is what can start one app on a display of its own instead of mirroring the whole phone.")
                        checked: page.appModeConfig?.enabled ?? true
                        onToggleRequested: Config.options.phone.scrcpy.appMode.enabled = !(page.appModeConfig?.enabled ?? true)
                    }

                    ConfigSwitch {
                        buttonIcon: "desktop_windows"
                        text: Translation.tr("Give each app a display of its own")
                        infoText: Translation.tr("Off, an app is started on the phone's own screen and mirrored, so opening two means seeing one.")
                        checked: page.appModeConfig?.flexDisplay ?? true
                        onToggleRequested: Config.options.phone.scrcpy.appMode.flexDisplay = !(page.appModeConfig?.flexDisplay ?? true)
                    }

                    ConfigSwitch {
                        buttonIcon: "keep"
                        text: Translation.tr("Keep the app running when its window closes")
                        enabled: page.appModeConfig?.flexDisplay ?? true
                        checked: page.appModeConfig?.keepActive ?? true
                        onToggleRequested: Config.options.phone.scrcpy.appMode.keepActive = !(page.appModeConfig?.keepActive ?? true)
                    }

                    ConfigSwitch {
                        buttonIcon: "web_asset"
                        text: Translation.tr("Draw Android's own navigation bar")
                        enabled: page.appModeConfig?.flexDisplay ?? true
                        checked: page.appModeConfig?.systemDecorations ?? true
                        onToggleRequested: Config.options.phone.scrcpy.appMode.systemDecorations = !(page.appModeConfig?.systemDecorations ?? true)
                    }

                    ConfigSpinBox {
                        icon: "width"
                        text: Translation.tr("Virtual display width")
                        enabled: page.appModeConfig?.flexDisplay ?? true
                        value: page.appModeConfig?.displayWidth ?? 1280
                        from: 640
                        to: 2560
                        stepSize: 80
                        onValueModified: Config.options.phone.scrcpy.appMode.displayWidth = newValue
                    }

                    ConfigSpinBox {
                        icon: "height"
                        text: Translation.tr("Virtual display height")
                        enabled: page.appModeConfig?.flexDisplay ?? true
                        value: page.appModeConfig?.displayHeight ?? 960
                        from: 480
                        to: 1920
                        stepSize: 60
                        onValueModified: Config.options.phone.scrcpy.appMode.displayHeight = newValue
                    }

                    ConfigSpinBox {
                        icon: "density_medium"
                        text: Translation.tr("Virtual display density (dpi)")
                        infoText: Translation.tr("Android picks a phone or a tablet layout from this. 160 is one device-independent pixel per pixel, which is what makes an app look like a desktop window.")
                        enabled: page.appModeConfig?.flexDisplay ?? true
                        value: page.appModeConfig?.density ?? 160
                        from: 120
                        to: 480
                        stepSize: 40
                        onValueModified: Config.options.phone.scrcpy.appMode.density = newValue
                    }
                }
            }
        }
    }
}
