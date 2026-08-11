import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.functions as Functions
import qs.modules.common.widgets
import qs.modules.common.plugins
import qs.services
import "../../designsystem/widgets" as Expressive
import "cookie_layout.js" as CookieLayout

// The 2x2 media widget: the cookie clock's shape, with transport controls where
// its date badges are. One cookie fills a square frame centred in the tile,
// previous sits in the frame's top-left corner (the clock's day bubble) and
// next in its bottom-right (the clock's month bubble), each overlapping the
// cookie's edge.
//
// There is deliberately no title and no artist here. The clock carries no text
// either, and the two cannot both fit: a text block under the cookie is paid
// for out of the cookie's diameter, and shrinking the cookie moves the badges
// off its edge, which is the whole relationship this size exists to draw. The
// 3x2 is the size that names the track.
Item {
    id: root

    implicitWidth: Appearance.sizes.widgetGridSpanX(2)
    implicitHeight: Appearance.sizes.widgetGridSpanY(2)

    readonly property real cardInset: Appearance.spacing.space150
    readonly property bool useBlurBackground: PluginState.option("nandoroid_media", "blurEnabled", false)
    readonly property real backgroundOpacity: PluginState.effectiveBackgroundOpacity("nandoroid_media")

    readonly property bool managesBlurTint: true
    readonly property var blurRegions: [{
        x: bgCard.x, y: bgCard.y, width: bgCard.width, height: bgCard.height, radius: bgCard.radius
    }]

    readonly property string artUrl: MprisController.activePlayer?.trackArtUrl ?? ""
    readonly property bool hasArt: root.artUrl !== "" && albumArt.status === Image.Ready

    // The tile is 276x228 and the clock's structure is square, so the square is
    // centred in it rather than stretched to it. See cookie_layout.js.
    readonly property var frame: CookieLayout.frame(root.width, root.height, root.cardInset)

    // The same pair the 2x1's pills use, so the three sizes draw one widget's
    // controls rather than three widgets'.
    readonly property color controlColor: Appearance.m3colors.darkmode
        ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colSecondaryContainer
    readonly property color controlIconColor: Appearance.m3colors.darkmode
        ? Appearance.colors.colTertiaryContainer : Appearance.colors.colOnSecondaryContainer

    // Two badges differing only by glyph, corner and action. Written as an
    // inline component rather than reusing the clock's `BubbleDate`: that one
    // reads its own text off `DateTime` and branches on `isMonth` for both its
    // shape and its colours, so it has no slot to put a glyph in - "reusing" it
    // means rewriting it generic and re-parameterising the clock's two call
    // sites, for a shape this widget already draws in LayoutCompact.
    component TransportBadge: Rectangle {
        id: badge

        property string glyph: ""
        signal triggered

        implicitWidth: CookieLayout.badgeSize(root.frame.size)
        implicitHeight: badge.implicitWidth
        width: badge.implicitWidth
        height: badge.implicitHeight
        radius: badge.height / 2
        color: root.controlColor

        MaterialSymbol {
            anchors.centerIn: parent
            text: badge.glyph
            iconSize: badge.height * 0.46
            fill: 0
            color: badgeArea.containsMouse ? Appearance.colors.colPrimary : root.controlIconColor
            Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
        }

        MouseArea {
            id: badgeArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: badge.triggered()
        }
    }

    Rectangle {
        id: bgCard
        anchors.fill: parent
        radius: 30 * Appearance.effectiveScale
        color: root.useBlurBackground
            ? Functions.ColorUtils.applyAlpha(Appearance.colors.colOnPrimary, root.backgroundOpacity)
            : Appearance.colors.colOnPrimary
    }

    Item {
        id: cookieFrame
        x: root.frame.x
        y: root.frame.y
        width: root.frame.size
        height: root.frame.size

        Expressive.VisualizerCookie {
            id: cookie
            anchors.fill: parent

            lobes: 12
            // Claimed only while something is playing: the claim starts cava, and a
            // paused desktop has no spectrum to draw. The lobes decay back to the
            // resting cookie on their own when the claim drops.
            audioReactive: MprisController.isPlaying
            color: Appearance.colors.colPrimary
        }

        // Clipped to a circle rather than to the cookie: the lobes are what ripples,
        // so masking the artwork with the same moving outline would swallow the
        // motion instead of showing it. The circle sits inside the lobes' valleys,
        // which is what leaves the scalloped edge visible all the way round.
        Item {
            id: artClip
            anchors.centerIn: parent
            width: cookieFrame.width * 0.72
            height: width
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: artClip.width
                    height: artClip.height
                    radius: width / 2
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Appearance.colors.colOnPrimary
            }

            Image {
                id: albumArt
                anchors.fill: parent
                source: root.artUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: root.hasArt
            }

            Rectangle {
                anchors.fill: parent
                color: Appearance.colors.colOnPrimary
                opacity: !root.hasArt ? 0 : (cookieTap.containsMouse ? 0.55 : 0)
                Behavior on opacity { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration } }
            }
        }

        MaterialSymbol {
            anchors.centerIn: artClip
            text: MprisController.isPlaying ? "pause" : "play_arrow"
            iconSize: artClip.width * 0.42
            fill: 1
            color: Appearance.colors.colPrimary
            opacity: (!root.hasArt || cookieTap.containsMouse) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration } }
        }

        // Only the artwork takes the press, not the cookie's whole bounding box: a
        // nested MouseArea claims it from the host's drag-to-move, and a target the
        // size of the cookie would leave the card with almost nothing to drag by.
        MouseArea {
            id: cookieTap
            anchors.centerIn: artClip
            width: artClip.width
            height: artClip.height
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: MprisController.togglePlaying()
        }

        // Declared after the cookie so they draw over its edge, which is the
        // DateIndicator stacking too - a badge under the lobes would be eaten
        // by whichever one happens to be pushed out at the time.
        TransportBadge {
            anchors.left: parent.left
            anchors.top: parent.top
            glyph: "skip_previous"
            onTriggered: MprisController.previous()
        }

        TransportBadge {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            glyph: "skip_next"
            onTriggered: MprisController.next()
        }
    }
}
