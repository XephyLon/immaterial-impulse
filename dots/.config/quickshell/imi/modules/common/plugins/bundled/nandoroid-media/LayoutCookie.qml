import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.functions as Functions
import qs.modules.common.widgets
import qs.modules.common.plugins
import qs.services
import "../../designsystem/widgets" as Expressive

// The 2x2 media widget: the cookie is the artwork, its lobes are the spectrum,
// and the track sits underneath. There are no transport buttons - the cookie is
// the only control, and it plays and pauses.
Item {
    id: root

    implicitWidth: Appearance.sizes.widgetGridSpanX(2)
    implicitHeight: Appearance.sizes.widgetGridSpanY(2)

    readonly property real cardInset: Appearance.spacing.space200
    readonly property bool useBlurBackground: PluginState.option("nandoroid_media", "blurEnabled", false)
    readonly property real backgroundOpacity: PluginState.effectiveBackgroundOpacity("nandoroid_media")

    readonly property bool managesBlurTint: true
    readonly property var blurRegions: [{
        x: bgCard.x, y: bgCard.y, width: bgCard.width, height: bgCard.height, radius: bgCard.radius
    }]

    readonly property string artUrl: MprisController.activePlayer?.trackArtUrl ?? ""
    readonly property bool hasArt: root.artUrl !== "" && albumArt.status === Image.Ready

    Rectangle {
        id: bgCard
        anchors.fill: parent
        radius: 30 * Appearance.effectiveScale
        color: root.useBlurBackground
            ? Functions.ColorUtils.applyAlpha(Appearance.colors.colOnPrimary, root.backgroundOpacity)
            : Appearance.colors.colOnPrimary
    }

    // The cookie takes whatever the track block leaves. Measured against the
    // column's *implicit* height rather than its height: the column is anchored
    // to three edges, so its actual height is the card's, and reading that back
    // would size the cookie to nothing.
    Expressive.VisualizerCookie {
        id: cookie
        anchors.top: parent.top
        anchors.topMargin: root.cardInset
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.max(0, Math.min(root.width - root.cardInset * 2,
            root.height - root.cardInset * 2 - trackColumn.implicitHeight - Appearance.spacing.space100))
        height: width

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
        anchors.centerIn: cookie
        width: cookie.width * 0.72
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

    ColumnLayout {
        id: trackColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.cardInset
        spacing: Appearance.spacing.space25

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Functions.StringUtils.cleanMusicTitle(MprisController.trackTitle) || "No Music Playing"
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.DemiBold
            color: Appearance.colors.colPrimary
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: {
                const rawTitle = (MprisController.trackTitle || "").trim().toLowerCase();
                const hasTitle = rawTitle !== "" && rawTitle !== "no media" && rawTitle !== "no music playing";
                const hasArtist = MprisController.trackArtist && MprisController.trackArtist.trim() !== "";
                if (hasTitle)
                    return hasArtist ? MprisController.trackArtist : "Unknown Artist";
                return "Play some media";
            }
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: Functions.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.75)
            elide: Text.ElideRight
            maximumLineCount: 1
        }
    }
}
