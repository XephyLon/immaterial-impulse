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

    // The screen minus what the bar and the dock occupy - `edit_mode.js`'s
    // `areaRect`, interpolated on the same progress as `card`. The two bands the
    // chrome sits in are the gaps between the two rectangles, so a bar of any
    // height and a dock on any edge push the chrome rather than being drawn over
    // by it. Defaults to the whole item, which is the geometry the mode had
    // before it knew about either panel.
    property rect area: Qt.rect(0, 0, root.width, root.height)

    // The drawer's reveal - `edit_mode.js`'s `drawerRect`, interpolated on the
    // same pair of scalars as everything else here. Defaults to a zero-width
    // rect parked at the right edge, so an unconnected instance (the look
    // probe's) has no drawer and paints exactly what it painted before the
    // drawer existed.
    property rect drawer: Qt.rect(root.width, 0, 0, root.height)

    signal doneRequested()
    signal drawerToggleRequested()
    signal widgetDropRequested(var manifest, real dropX, real dropY)
    signal widgetToggleRequested(var manifest)
    signal barWidgetAddRequested(string widgetId, string bucket)
    signal dockAppToggleRequested(string appId)

    // Published for the surface's input mask: these three rects are the only
    // pixels of a screen-sized layer surface that may take a click, because
    // everything else on it is the desktop being edited. The drawer's item is
    // its REVEAL, so closed it is a zero-width rect and the mask built from it
    // is empty - the edge it lives on keeps its clicks.
    readonly property alias toolbarItem: toolbar
    readonly property alias tabBarItem: tabBar
    readonly property alias drawerItem: drawerPanel

    Toolbar {
        id: toolbar
        // Centred on the CARD rather than on the screen: the two are the same
        // point today and stop being one the moment stage 5's drawer
        // translates the desktop, and the chrome belongs to the desktop.
        x: root.card.x + (root.card.width - width) / 2
        // Centred in the band between the usable area's top edge and the card's
        // - the screen's top edge only while nothing is on that edge. The
        // viewport reserves `margin + toolbarHeight + margin` there, so this
        // lands with a margin above and below it and cannot reach the bar.
        y: root.area.y + (root.card.y - root.area.y - height) / 2
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

        // The drawer's toggle, drawn as state rather than as a verb: the
        // toggled container is what says the panel on the right belongs to
        // this button once it is open.
        IconAndTextToolbarButton {
            id: drawerButton
            Layout.alignment: Qt.AlignVCenter
            iconText: "widgets"
            text: Translation.tr("Add widgets")
            toggled: GlobalStates.editDrawerOpen
            onClicked: root.drawerToggleRequested()
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
        // ...and the mirror band, between the card's bottom edge and the usable
        // area's. The card is centred in that area, so the two bands are the
        // same height and the two pieces travel by the same amount - which is
        // true with a bar on one edge and a dock on the other, and was true
        // before only because neither was accounted for.
        y: root.card.y + root.card.height
            + (root.area.y + root.area.height - root.card.y - root.card.height - height) / 2

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

    // The drawer's shadow lives OUT here because the drawer clips to its
    // reveal - a shadow drawn inside would fall entirely outside the clip and
    // vanish. Around the reveal it grows with the slide, and the gate keeps a
    // zero-width rect from being given a blur of its own while the drawer is
    // closed.
    StyledRectangularShadow {
        target: drawerPanel
        visible: drawerPanel.width > 0
        radius: Appearance.rounding.verylarge
    }

    EditModeDrawer {
        id: drawerPanel
        x: root.drawer.x
        y: root.drawer.y
        width: root.drawer.width
        height: root.drawer.height
        ghostParent: root
        onAddRequested: (manifest, dropX, dropY) => root.widgetDropRequested(manifest, dropX, dropY)
        onToggleRequested: (manifest) => root.widgetToggleRequested(manifest)
        onBarAddRequested: (widgetId, bucket) => root.barWidgetAddRequested(widgetId, bucket)
        onDockToggleRequested: (appId) => root.dockAppToggleRequested(appId)
    }
}
