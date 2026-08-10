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
            icon: "lock"
            title: Translation.tr("Lock screen")
            shape: MaterialShape.Shape.Pentagon

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "water_drop"
                    text: Translation.tr("Use Hyprlock (instead of Quickshell)")
                    checked: Config.options.lock.useHyprlock
                    onToggleRequested: Config.options.lock.useHyprlock = !Config.options.lock.useHyprlock
                }
                ConfigSwitch {
                    buttonIcon: "account_circle"
                    text: Translation.tr("Launch on startup")
                    checked: Config.options.lock.launchOnStartup
                    onToggleRequested: Config.options.lock.launchOnStartup = !Config.options.lock.launchOnStartup
                }
                ConfigSwitch {
                    buttonIcon: "widgets"
                    text: Translation.tr("Show Widgets")
                    checked: Config.options.lock.showWidgets
                    onToggleRequested: Config.options.lock.showWidgets = !Config.options.lock.showWidgets
                }
                ConfigSwitch {
                    buttonIcon: "tools_installation_kit"
                    text: Translation.tr("Show Toolbars")
                    checked: Config.options.lock.showToolbars
                    onToggleRequested: Config.options.lock.showToolbars = !Config.options.lock.showToolbars
                }
                ConfigSwitch {
                    buttonIcon: "music_note"
                    enabled: Config.options.lock.showToolbars
                    text: Translation.tr("Show media player info")
                    checked: Config.options.lock.showMedia
                    onToggleRequested: Config.options.lock.showMedia = !Config.options.lock.showMedia
                }
            }

            ContentSubsection {
                title: Translation.tr("Security")
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "settings_power"
                        text: Translation.tr("Require password to power off/restart")
                        checked: Config.options.lock.security.requirePasswordToPower
                        onToggleRequested: Config.options.lock.security.requirePasswordToPower = !Config.options.lock.security.requirePasswordToPower
                    }
                    ConfigSwitch {
                        buttonIcon: "key_vertical"
                        text: Translation.tr("Also unlock keyring")
                        checked: Config.options.lock.security.unlockKeyring
                        onToggleRequested: Config.options.lock.security.unlockKeyring = !Config.options.lock.security.unlockKeyring
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Style: General")
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "center_focus_weak"
                        text: Translation.tr("Center clock")
                        checked: Config.options.lock.centerClock
                        onToggleRequested: Config.options.lock.centerClock = !Config.options.lock.centerClock
                    }
                    ConfigSwitch {
                        buttonIcon: "info"
                        text: Translation.tr('Show "Locked" text')
                        checked: Config.options.lock.showLockedText
                        onToggleRequested: Config.options.lock.showLockedText = !Config.options.lock.showLockedText
                    }
                    ConfigSwitch {
                        buttonIcon: "shapes"
                        text: Translation.tr("Use varying shapes for password characters")
                        checked: Config.options.lock.materialShapeChars
                        onToggleRequested: Config.options.lock.materialShapeChars = !Config.options.lock.materialShapeChars
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Style: Blurred")
                GroupedList {
                    ConfigSwitch {
                        buttonIcon: "blur_on"
                        text: Translation.tr("Enable blur")
                        checked: Config.options.lock.blur.enable
                        onToggleRequested: Config.options.lock.blur.enable = !Config.options.lock.blur.enable
                    }
                    ConfigSpinBox {
                        icon: "deblur"
                        text: Translation.tr("Samples")
                        value: Config.options.lock.blur.size
                        from: 20; to: 200; stepSize: 10
                        onValueModified: { Config.options.lock.blur.size = newValue }
                    }
                    ConfigSpinBox {
                        icon: "loupe"
                        text: Translation.tr("Extra wallpaper zoom (%)")
                        value: Config.options.lock.blur.extraZoom * 100
                        from: 1; to: 150; stepSize: 2
                        onValueModified: { Config.options.lock.blur.extraZoom = newValue / 100 }
                    }
                }
            }
        }

        ContentSection {
            icon: "coffee"
            title: Translation.tr("Keep awake")
            shape: MaterialShape.Shape.Clover8Leaf

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "desktop_windows"
                    text: Translation.tr("Keep awake while an external monitor is connected")
                    description: Translation.tr("Combines with the \"Keep awake\" quick toggle: the system stays awake while either is active")
                    checked: Config.options.idleInhibitor.autoOnExternalMonitor
                    onToggleRequested: Config.options.idleInhibitor.autoOnExternalMonitor = !Config.options.idleInhibitor.autoOnExternalMonitor
                }
            }
        }

        ContentSection {
            icon: "wb_twilight"
            title: Translation.tr("Screensaver")
            shape: MaterialShape.Shape.Pentagon

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "bedtime"
                    text: Translation.tr("Enable OLED screensaver")
                    checked: Config.options.screensaver.enable
                    onToggleRequested: Config.options.screensaver.enable = !Config.options.screensaver.enable
                }
                ConfigSelectionArray {
                    text: Translation.tr("Mode")
                    icon: "wallpaper"
                    currentValue: Config.options.screensaver.mode
                    onSelected: newValue => { Config.options.screensaver.mode = newValue; }
                    options: [
                        { displayName: Translation.tr("Black"), icon: "dark_mode", value: "black" },
                        { displayName: Translation.tr("Clock"), icon: "schedule", value: "clock" }
                    ]
                }
            }
        }

        ContentSection {
            icon: "work_alert"
            shape: MaterialShape.Shape.PuffyDiamond
            title: Translation.tr("Work safety")
            GroupedList {
                ConfigSwitch {
                    buttonIcon: "assignment"
                    text: Translation.tr("Hide clipboard images copied from sussy sources")
                    checked: Config.options.workSafety.enable.clipboard
                    onToggleRequested: Config.options.workSafety.enable.clipboard = !Config.options.workSafety.enable.clipboard
                }
                ConfigSwitch {
                    buttonIcon: "wallpaper"
                    text: Translation.tr("Hide sussy/anime wallpapers")
                    checked: Config.options.workSafety.enable.wallpaper
                    onToggleRequested: Config.options.workSafety.enable.wallpaper = !Config.options.workSafety.enable.wallpaper
                }
            }
        }
    }
}
