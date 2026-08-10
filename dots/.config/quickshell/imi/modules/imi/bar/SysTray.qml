import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    property bool vertical: false
    property bool invertSide: false
    property bool trayOverflowOpen: false
    property bool showSeparator: true
    property bool showOverflowMenu: true
    property var activeMenu: null
    readonly property bool isOnLeft: Config.options.bar.layouts.leftLayout.includes("sysTray")
    readonly property bool isMaterial: Config.options.bar.cornerStyle === 3

    visible: SystemTray.items.values.length > 0
    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : (isMaterial ? pill.implicitWidth - 4 : gridLayout.implicitWidth)
    implicitHeight: vertical ? gridLayout.implicitHeight + 6 : Appearance.sizes.barHeight

    property list<var> pinnedItems: TrayService.pinnedItems
    property list<var> unpinnedItems: TrayService.unpinnedItems
    onUnpinnedItemsChanged: {
        if (unpinnedItems.length == 0) root.closeOverflowMenu()
    }

    function grabFocus() {
        // Only one focus grab can be held at a time. While the overflow's
        // content sits on the shared card, the overlay is already holding one
        // that covers the bar, the card and this menu (it publishes the menu
        // through extraGrabWindows) - arming a second makes the compositor drop
        // one of the two, and whichever loses raises cleared, which closed a
        // tray menu about half a second after it opened. The overlay's grab
        // dismisses the menu and the overflow together in that case.
        if (overflowPopup.surfaceWindow)
            return;
        focusGrab.active = true
    }
    function setExtraWindowAndGrabFocus(window) {
        if (root.activeMenu && root.activeMenu !== window) {
            if (typeof root.activeMenu.close === "function")
                root.activeMenu.close()
            root.activeMenu = null
        }
        root.activeMenu = window
        root.grabFocus()
    }
    function releaseFocus() { focusGrab.active = false }
    function closeOverflowMenu() { focusGrab.active = false }

    onTrayOverflowOpenChanged: {
        // No grab is armed for the overflow popup any more: it lives on the
        // shared card, whose surface the overlay owns and grabs for. Arming one
        // here would grab a surface whose input region is the card, and while
        // the card is still growing that closes the popup on the next click.
        // Keep the bar from auto-hiding while the overflow popup is open, so it
        // isn't orphaned above a hidden bar (issue #31).
        GlobalStates.sysTrayOverflowOpen = root.trayOverflowOpen
    }

    // Tray *context menus* are still real windows of their own, so they keep a
    // grab - it just no longer covers the overflow popup's surface.
    HyprlandFocusGrab {
        id: focusGrab
        active: false
        windows: [root.QsWindow?.window, root.activeMenu].filter(window => window)
        onCleared: {
            if (root.activeMenu) {
                root.activeMenu.close()
                root.activeMenu = null
            }
        }
    }

    Rectangle {
        id: pill
        visible: false
        anchors.centerIn: parent
        color: "transparent"
        radius: Appearance.rounding.full
        implicitWidth: root.vertical ? 32 : gridLayout.implicitWidth
        implicitHeight: root.vertical ? gridLayout.implicitHeight + 12 : 32
    }

    GridLayout {
        id: gridLayout
        columns: root.vertical ? 1 : -1
        anchors.centerIn: parent
        rowSpacing: Appearance.spacing.space50
        columnSpacing: -Appearance.spacing.space75

        RippleButton {
            id: trayOverflowButton
            visible: root.showOverflowMenu && root.unpinnedItems.length > 0
            toggled: root.trayOverflowOpen
            downAction: () => root.trayOverflowOpen = !root.trayOverflowOpen

            Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
            background.implicitWidth: 24
            background.implicitHeight: 24
            background.anchors.centerIn: this
            colBackgroundToggled: Appearance.colors.colSecondaryContainer
            colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
            colRippleToggled: Appearance.colors.colSecondaryContainerActive

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                iconSize: Appearance.font.pixelSize.larger
                text: Config.options.bar.bottom ? "keyboard_control_key" : "expand_more"
                horizontalAlignment: Text.AlignHCenter
                color: root.trayOverflowOpen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                rotation: (root.trayOverflowOpen ? 180 : 0) - (90 * root.vertical) + (180 * root.invertSide)
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            StyledPopup {
                id: overflowPopup
                hoverTarget: trayOverflowButton
                // Click-toggled menu: hold it open explicitly. StyledPopup's
                // hover path reads containsMouse, which a QQC2-derived
                // RippleButton does not expose.
                pinnedOpen: root.trayOverflowOpen && root.unpinnedItems.length > 0
                // Bound, not assignable - so the overlay's grab asks rather
                // than writes, and this clears the flag the binding reads.
                onDismissRequested: root.trayOverflowOpen = false
                extraGrabWindows: root.activeMenu ? [root.activeMenu] : []
                // The overflow's delegates own tray menus anchored to whatever
                // window the card is on. Let them go before the card unparents.
                onAboutToRelease: {
                    if (root.activeMenu) {
                        root.activeMenu.close()
                        root.activeMenu = null
                    }
                    root.trayOverflowOpen = false
                }

                GridLayout {
                    id: trayOverflowLayout
                    anchors.centerIn: parent
                    columns: Math.ceil(Math.sqrt(root.unpinnedItems.length))
                    columnSpacing: Appearance.spacing.space75
                    rowSpacing: Appearance.spacing.space75

                    Repeater {
                        model: root.unpinnedItems
                        delegate: SysTrayItem {
                            required property SystemTrayItem modelData
                            item: modelData
                            Layout.fillHeight: !root.vertical
                            Layout.fillWidth: root.vertical
                            onMenuClosed: root.releaseFocus()
                            onMenuOpened: (qsWindow) => root.setExtraWindowAndGrabFocus(qsWindow)
                        }
                    }
                }
            }
        }

        Repeater {
            model: ScriptModel { values: root.pinnedItems }
            delegate: SysTrayItem {
                required property SystemTrayItem modelData
                item: modelData
                Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
                Layout.fillHeight: !root.vertical
                Layout.fillWidth: root.vertical
                Layout.leftMargin: Appearance.spacing.space100
                Layout.rightMargin: Appearance.spacing.space100
                onMenuClosed: root.releaseFocus()
                onMenuOpened: (qsWindow) => root.setExtraWindowAndGrabFocus(qsWindow)
            }
        }
    }
}
