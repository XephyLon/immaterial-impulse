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
            page.scrollToY(pos.y)
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

            // A wrapping card grid, NOT a ConfigSelectionArray: the chip strip
            // is a single row, so with more than a handful of installed themes
            // it ran off the right edge of the page and clipped its own label.
            // Same shape as the icon-pack selector, minus the image previews -
            // cursor themes ship Xcursor binaries Qt cannot decode, so the
            // cards carry names only.
            GridLayout {
                Layout.fillWidth: true
                visible: CursorThemes.available
                columns: 3
                columnSpacing: Appearance.spacing.space50
                rowSpacing: Appearance.spacing.space50

                Repeater {
                    model: CursorThemes.themes
                    delegate: Rectangle {
                        id: themeCard
                        required property var modelData
                        readonly property bool isActive: modelData.id === CursorThemes.activeId
                        Layout.fillWidth: true
                        implicitHeight: cardRow.implicitHeight + Appearance.spacing.space100 * 2
                        radius: Appearance.rounding.normal
                        color: themeCardArea.containsMouse
                            ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
                        border.width: themeCard.isActive
                            ? Appearance.borderWidth.emphasis : Appearance.borderWidth.standard
                        border.color: themeCard.isActive
                            ? Appearance.colors.colPrimary : "transparent"

                        MouseArea {
                            id: themeCardArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (themeCard.modelData.id === CursorThemes.activeId) return
                                CursorThemes.apply(themeCard.modelData.id, Config.options.hyprland.cursor.size)
                            }
                        }

                        RowLayout {
                            id: cardRow
                            anchors.centerIn: parent
                            width: parent.width - Appearance.spacing.space100 * 2
                            spacing: Appearance.spacing.space50
                            // The theme's own pointer, extracted to PNG by the
                            // scanner (Qt cannot decode Xcursor files). Falls
                            // back to an icon for themes whose pointer could
                            // not be parsed.
                            Image {
                                visible: (themeCard.modelData.previewPath ?? "") !== ""
                                source: (themeCard.modelData.previewPath ?? "") !== ""
                                    ? "file://" + themeCard.modelData.previewPath : ""
                                sourceSize.width: 28
                                sourceSize.height: 28
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: false // regenerated on every scan; stale cache shows the old theme
                            }
                            MaterialSymbol {
                                visible: (themeCard.modelData.previewPath ?? "") === ""
                                text: "mouse"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: themeCard.modelData.name
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer2
                                elide: Text.ElideRight
                            }
                            MaterialSymbol {
                                visible: themeCard.isActive
                                text: "check_circle"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colPrimary
                            }
                        }
                    }
                }
            }

            GroupedList {
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
