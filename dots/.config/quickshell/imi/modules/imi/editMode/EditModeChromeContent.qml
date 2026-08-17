import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Edit Mode's chrome: the toolbar above the shrunk desktop and the tab bar
 * below it.
 *
 * Split out of the surface that hosts it for the reason `EditModeCard` is split
 * out of `Background.qml` - weston implements no wlr-layer-shell, so the only
 * way anything here is ever looked at by a test is as a plain `Item` a probe
 * can put in a window of its own.
 *
 * ---- where it sits --------------------------------------------------------
 *
 * Everything is placed off `card`, the rectangle the desktop is drawn at, which
 * is `edit_mode.js`'s `cardRect` - the same arithmetic the desktop's own
 * transform is built out of. So the chrome cannot be a pixel off the thing it
 * frames, and it does not need a second copy of the geometry to be wrong about.
 *
 * That also gives the motion for free, and gives it the RIGHT shape: `card` is
 * a function of `GlobalStates.editProgress`, so the toolbar rises out of the
 * top edge and the tab bar out of the bottom one exactly as fast as the desktop
 * shrinks away from them. At progress 0 both bands have zero height and both
 * pieces are parked half off screen, which is why nothing here needs a
 * `Behavior` of its own - and must not have one: a Behavior whose target moves
 * every frame restarts every frame and never ticks (b710ef731 ("fix(plugins):
 * stop the position Behavior swallowing the parallax cancellation")).
 *
 * ---- what it is made of ---------------------------------------------------
 *
 * `Toolbar` and `ToolbarTabBar`, which is the shell's M3 expressive toolbar and
 * its toolbar tab bar - the same pieces the cheatsheet, the region selector,
 * the recording controls and the lock islands are built from. A bespoke card
 * matching the desktop's own outline and 30px corner was the other option and
 * would have been a second toolbar look minted for one mode, which is the drift
 * this repo keeps paying for. What ties it to the card is the shadow both carry
 * and the symmetry of the two bands, not a copied radius.
 */
Item {
    id: root

    // The desktop's rectangle on screen. Defaults to the whole of this item, so
    // an unconnected instance parks its chrome off both edges rather than
    // somewhere arbitrary.
    property rect card: Qt.rect(0, 0, root.width, root.height)

    signal doneRequested()

    // Published for the surface's input mask: these two rects are the only
    // pixels of a screen-sized layer surface that may take a click, because
    // everything else on it is the desktop being edited.
    readonly property alias toolbarItem: toolbar
    readonly property alias tabBarItem: tabBar

    Toolbar {
        id: toolbar
        // Centred on the CARD rather than on the screen: the two are the same
        // point today and stop being one the moment stage 5's drawer
        // translates the desktop, and the chrome belongs to the desktop.
        x: root.card.x + (root.card.width - width) / 2
        // Centred in the band between the screen's top edge and the card's.
        y: (root.card.y - height) / 2
        spacing: Appearance.spacing.space150

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            Layout.leftMargin: Appearance.spacing.space75
            text: "edit"
            iconSize: 22
            color: Appearance.colors.colOnSurfaceVariant
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            text: Translation.tr("Edit layout")
            font.pixelSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colOnSurface
        }

        // The mode's real way out. Two things about it are deliberate. It
        // carries its label rather than being an icon-only button paired off to
        // the side the way the region selector separates its close - a mode the
        // user cannot see how to leave is the one failure that costs them the
        // whole session, and a checkmark is not a word. And it is FILLED, on
        // the primary role: rendered flat beside the toolbar's own title it
        // read as a second label rather than as a control, which is the same
        // "is this clickable" question with a worse answer.
        IconAndTextToolbarButton {
            id: doneButton
            Layout.alignment: Qt.AlignVCenter
            iconText: "done"
            text: Translation.tr("Done")
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            colText: Appearance.colors.colOnPrimary
            onClicked: root.doneRequested()
        }
    }

    Toolbar {
        id: tabBar
        x: root.card.x + (root.card.width - width) / 2
        // ...and the mirror band, between the card's bottom edge and the
        // screen's. The card is centred, so the two bands are the same height
        // and the two pieces travel by the same amount.
        y: root.card.y + root.card.height
            + (root.height - root.card.y - root.card.height - height) / 2

        // A tab bar with one tab in it, and not a label that will grow into
        // one. The Lockscreen tab (spec §1.4) is stage 9's, and it arrives as
        // a second entry in this list rather than as a rewrite of whatever a
        // label had become. There is deliberately no `GlobalStates` tab
        // property yet: a stored choice with one legal value is plumbing for a
        // feature that does not exist, and the Escape ladder already answers
        // `desktopTab` from the module.
        ToolbarTabBar {
            id: tabs
            tabButtonList: [{ name: Translation.tr("Desktop"), icon: "wallpaper" }]
        }
    }
}
