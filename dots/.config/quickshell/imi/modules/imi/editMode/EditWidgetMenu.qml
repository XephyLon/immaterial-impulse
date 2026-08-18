import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.plugins

/**
 * The window that hosts the per-widget context menu: one full-screen `Overlay`
 * surface on the screen the widget was right-clicked on, existing only while
 * the menu is open - the desktop menu's exact shape, because it answers the
 * same question. A menu drawn on the background surface instead would sit on
 * `WlrLayer.Bottom`, under the bar, the dock and the mode's own chrome; and a
 * fourth region in the chrome surface's mask could never dismiss on a click
 * elsewhere, because every pixel outside the chrome's rects deliberately falls
 * through to the desktop being edited.
 *
 * The namespace is `quickshell:desktopMenu`, reused rather than minted: this
 * is the same kind of surface as the desktop's own context menu - full-screen,
 * transparent except for a small card of `colLayer0` rows - and that namespace
 * has carried exactly these pixels under the compositor's catch-all rules for
 * the life of the shell. A minted name would repeat rules.lua's threshold
 * exercise (spec §10.3's fourth property) to arrive at the same treatment.
 *
 * The card is anchored at the click's screen point, which arrived in
 * `GlobalStates.editWidgetMenuX/Y` already mapped through the widget's own
 * transform chain (PluginWidget's `mapToItem(null, ...)`) - so this window
 * does no viewport arithmetic at all, which is what the no-compensation
 * contract wants from everything outside `Background.qml`.
 *
 * Dismissal: a click anywhere outside the card (the full-screen MouseArea
 * under it), Escape through the canvas's ladder (`closeMenu` is its first
 * rung), leaving the mode (GlobalStates closes the menu with the drawer), and
 * the widget itself being destroyed (PluginWidget vacates from
 * `Component.onDestruction`).
 */
Scope {
    id: root

    Loader {
        active: GlobalStates.editWidgetMenuOpen
        sourceComponent: PanelWindow {
            id: menuWindow

            screen: Quickshell.screens.find(
                candidate => candidate.name === GlobalStates.editWidgetMenuScreenName)
                ?? Quickshell.screens[0]

            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:desktopMenu"
            WlrLayershell.layer: WlrLayer.Overlay
            // Explicitly None, not left to the default: this surface maps on
            // Overlay while the menu's own Escape rung (`closeMenu`) is
            // answered by WidgetCanvas on the BACKGROUND surface, so a menu
            // window holding the keyboard would swallow the exact key that
            // dismisses it - the same hazard the chrome surface pins, one
            // surface up.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: GlobalStates.editWidgetMenuOpen = false
            }

            // Swallows what the card's rows do not take (the title row, the
            // plates' padding), so a click ON the menu is never read as a
            // click away from it. Under the card in declaration order, over
            // the closer.
            MouseArea {
                x: card.x
                y: card.y
                width: card.width
                height: card.height
                acceptedButtons: Qt.AllButtons
            }

            EditWidgetMenuContent {
                id: card
                manifest: PluginManager.availablePlugins.find(
                    entry => entry.id === GlobalStates.editWidgetMenuPluginId) ?? null
                screenName: menuWindow.screen?.name ?? ""
                width: implicitWidth
                height: implicitHeight
                x: Math.min(Math.max(GlobalStates.editWidgetMenuX, 8),
                    menuWindow.width - width - 8)
                y: Math.min(Math.max(GlobalStates.editWidgetMenuY, 8),
                    menuWindow.height - height - 8)
                onDismissRequested: GlobalStates.editWidgetMenuOpen = false

                // The desktop menu's entrance, from the corner the pointer is
                // at rather than the card's centre - this card belongs to a
                // point, not to the middle of the screen.
                scale: 0.85
                opacity: 0
                transformOrigin: Item.TopLeft
                Component.onCompleted: {
                    scale = 1.0;
                    opacity = 1.0;
                }
                Behavior on scale {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }
    }
}
