import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
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

    // Re-assert the config's cursor keys into the generated lua on page open,
    // like HyprlandConfig.qml does for its keys: the settings page is the only
    // writer of shellOverrides/main.lua, so this is where config and lua get
    // re-synced. Theme/size are deliberately not re-applied here - startup
    // (apply_saved_cursor.sh) already did, and applying is a side-effectful
    // command rather than a config line.
    Component.onCompleted: {
        const c = Config.options.hyprland.cursor
        HyprlandConfig.setMany({
            "cursor:zoom_factor":      c.zoomFactor,
            "cursor:inactive_timeout": c.inactiveTimeout
        })
    }

    ColumnLayout {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Appearance.spacing.space250

        // Pointer
        ContentSection {
            icon: "arrow_selector_tool"
            shape: MaterialShape.Shape.Clover4Leaf
            title: Translation.tr("Pointer")

            StyledText {
                visible: !CursorThemes.available
                text: CursorThemes.loading
                    ? Translation.tr("Scanning cursor themes…")
                    : Translation.tr("No cursor themes found.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            GroupedList {
                ConfigSelectionArray {
                    text: Translation.tr("Theme")
                    icon: "mouse"
                    visible: CursorThemes.available
                    currentValue: CursorThemes.activeId
                    onSelected: newValue => {
                        if (newValue === CursorThemes.activeId) return
                        CursorThemes.apply(newValue, Config.options.hyprland.cursor.size)
                    }
                    options: CursorThemes.themes.map(theme => ({
                        displayName: theme.name,
                        icon: "mouse",
                        value: theme.id
                    }))
                }

                ConfigSpinBox {
                    icon: "aspect_ratio"
                    text: Translation.tr("Size")
                    infoText: Translation.tr("Pointer size in pixels. Pick one that matches your display scale.")
                    value: Config.options.hyprland.cursor.size
                    from: 16; to: 64; stepSize: 2
                    onValueModified: {
                        if (newValue === Config.options.hyprland.cursor.size) return
                        CursorThemes.apply(Config.options.hyprland.cursor.theme, newValue)
                    }
                }
            }
        }

        // Pointer behavior
        ContentSection {
            icon: "zoom_in"
            shape: MaterialShape.Shape.Cookie6Sided
            title: Translation.tr("Pointer behavior")

            GroupedList {
                ConfigSpinBox {
                    icon: "zoom_in"
                    text: Translation.tr("Default zoom")
                    infoText: Translation.tr("Screen magnification, in percent. The Super+Plus/Minus keybinds change it at runtime; this is the value a config reload returns to.")
                    value: Math.round(Config.options.hyprland.cursor.zoomFactor * 100)
                    from: 100; to: 300; stepSize: 10
                    onValueModified: {
                        const newVal = newValue / 100.0
                        if (newVal === Config.options.hyprland.cursor.zoomFactor) return
                        Config.options.hyprland.cursor.zoomFactor = newVal
                        HyprlandConfig.set("cursor:zoom_factor", newVal)
                    }
                }

                ConfigSpinBox {
                    icon: "timer"
                    text: Translation.tr("Hide when inactive (seconds)")
                    infoText: Translation.tr("Hide the pointer after this many seconds without movement. 0 never hides it.")
                    value: Config.options.hyprland.cursor.inactiveTimeout
                    from: 0; to: 60; stepSize: 1
                    onValueModified: {
                        if (newValue === Config.options.hyprland.cursor.inactiveTimeout) return
                        Config.options.hyprland.cursor.inactiveTimeout = newValue
                        HyprlandConfig.set("cursor:inactive_timeout", newValue)
                    }
                }
            }
        }
    }
}
