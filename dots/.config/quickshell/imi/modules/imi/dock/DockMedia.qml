pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.imi.mediaControls
import qs.modules.common.functions
import qs.services
import qs.modules.common.models
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "../../common/functions/media_art.js" as MediaArt

Item {
    id: root

    property real cardWidth:     240
    property real artMargin:     Appearance.spacing.space50

    property var player: MprisController.activePlayer

    property var    artUrl:      MediaArt.resolve(player?.trackArtUrl ?? "", player?.metadata)
    property string trackTitle:  player?.trackTitle  ?? ""
    property string trackArtist: player?.trackArtist ?? ""
    property bool   isPlaying:   player?.isPlaying   ?? false
    property bool   hasTrack:    trackTitle.length > 0

    MediaArtSource {
        id: artSource
        artUrl: root.artUrl
    }
    readonly property string displayedArtFilePath: artSource.displayedArtFilePath
    readonly property bool artDownloaded: artSource.downloaded

    property color artDominantColor: ColorUtils.mix(
        artSource.colors[0] ?? Appearance.colors.colPrimary,
        Appearance.colors.colPrimaryContainer,
        0.8)

    property QtObject blendedColors: AdaptedMaterialScheme {
        color: root.artDominantColor
    }

    visible:        root.hasTrack
    implicitWidth:  root.hasTrack ? root.cardWidth : 0
    implicitHeight: parent?.height ?? 46

    Behavior on implicitWidth {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    StyledRectangularShadow {
        target: card
    }

    Rectangle {
        id: card
        anchors.fill:         parent
        anchors.topMargin:    Appearance.sizes.hyprlandGapsOut
        anchors.bottomMargin: Appearance.sizes.hyprlandGapsOut
        anchors.leftMargin:   Appearance.sizes.hyprlandGapsOut
        anchors.rightMargin:  Appearance.sizes.hyprlandGapsOut - Appearance.spacing.space25
        radius: Appearance.rounding.normal
        color:  "transparent"

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width:  card.width
                height: card.height
                radius: card.radius
            }
        }

        Rectangle {
            anchors.fill: parent
            color: ColorUtils.applyAlpha(root.blendedColors.colLayer0, 1)
            z: 0
        }

        // Blur art 
        Image {
            id: blurredArt
            anchors.fill: parent
            source: root.displayedArtFilePath
            // Bound the decode to the card, not the file: a 1200x1200 cover
            // decoded full-res only to be blurred behind a small card wasted
            // memory and decode time.
            sourceSize.width: Math.max(1, Math.round(card.width))
            sourceSize.height: Math.max(1, Math.round(card.height))
            fillMode: Image.PreserveAspectCrop
            cache: false
            antialiasing: true
            asynchronous: true
            z: 1
            layer.enabled: true
            layer.effect: StyledBlurEffect {
                source: blurredArt
            }
        }

        // Overlay
        Rectangle {
            anchors.fill: parent
            color: ColorUtils.transparentize(root.blendedColors.colLayer0, 0.3)
            z: 2
        }

        RowLayout {
            width:  card.width
            height: card.height
            clip:   true
            spacing: Appearance.spacing.space100
            z: 3

            // Art
            Rectangle {
                id: artRect
                Layout.alignment:  Qt.AlignVCenter
                Layout.leftMargin: root.artMargin + 2
                implicitWidth:     36
                implicitHeight:    36
                color:  ColorUtils.transparentize(root.blendedColors.colLayer1, 0.5)
                radius: Appearance.rounding.small

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width:  artRect.width
                        height: artRect.height
                        radius: artRect.radius
                    }
                }

                StyledImage {
                    anchors.fill: parent
                    source: root.displayedArtFilePath
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                    antialiasing: true
                    sourceSize.width:  artRect.width
                    sourceSize.height: artRect.height
                }
            }

            // Artist + Title
            ColumnLayout {
                Layout.fillWidth:  true
                Layout.fillHeight: true
                spacing: -Appearance.spacing.space25

                Item { Layout.fillHeight: true }

                StyledText {
                    Layout.fillWidth: true
                    text: root.trackArtist
                    font.pixelSize: Appearance.font.pixelSize.small - 2
                    color: root.blendedColors.colSubtext
                    elide: Text.ElideRight
                    // Keep RTL scripts (Arabic) left-anchored beside the art like
                    // the LTR case, instead of auto-aligning to the right edge.
                    horizontalAlignment: Text.AlignLeft
                    // Arabic's natural line box is much taller than Latin's, which
                    // pushed the two lines past the fixed-height card and clipped
                    // them top and bottom. Fix each slot's height and center the
                    // line box in it, so tall metrics overflow symmetrically into
                    // empty space instead of growing the layout.
                    Layout.preferredHeight: font.pixelSize * 1.3
                    verticalAlignment: Text.AlignVCenter
                }

                StyledText {
                    Layout.fillWidth: true
                    text: StringUtils.cleanMusicTitle(root.trackTitle) || "Untitled"
                    font.pixelSize: Appearance.font.pixelSize.normal - 4
                    color: root.blendedColors.colOnLayer0
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignLeft
                    Layout.preferredHeight: font.pixelSize * 1.3
                    verticalAlignment: Text.AlignVCenter
                    opacity: 0.7
                }

                Item { Layout.fillHeight: true }
            }

            // Buttons
            RowLayout {
                Layout.rightMargin: Appearance.spacing.space50
                Layout.alignment:   Qt.AlignVCenter
                spacing: Appearance.spacing.space50

                // Play / Pause
                RippleButton {
                    implicitWidth:  26
                    implicitHeight: 26
                    buttonRadius: root.isPlaying
                        ? Appearance.rounding.normal
                        : implicitWidth / 2
                    colBackground: root.isPlaying
                        ? root.blendedColors.colPrimary
                        : root.blendedColors.colSecondaryContainer
                    colBackgroundHover: root.isPlaying
                        ? root.blendedColors.colPrimaryHover
                        : root.blendedColors.colSecondaryContainerHover
                    colRipple: root.isPlaying
                        ? root.blendedColors.colPrimaryActive
                        : root.blendedColors.colSecondaryContainerActive
                    downAction: () => root.player?.togglePlaying()
                    contentItem: MaterialSymbol {
                        verticalAlignment: Text.AlignVCenter
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: root.isPlaying ? "pause" : "play_arrow"
                        iconSize: Appearance.font.pixelSize.large
                        fill: 1
                        color: root.isPlaying
                            ? root.blendedColors.colOnPrimary
                            : root.blendedColors.colOnSecondaryContainer
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }
                }

                // Next
                RippleButton {
                    implicitWidth:  28
                    implicitHeight: 28
                    colBackground:      ColorUtils.transparentize(root.blendedColors.colSecondaryContainer, 1)
                    colBackgroundHover: root.blendedColors.colSecondaryContainerHover
                    colRipple:          root.blendedColors.colSecondaryContainerActive
                    downAction: () => root.player?.next()
                    contentItem: MaterialSymbol {
                        verticalAlignment: Text.AlignVCenter
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "skip_next"
                        iconSize: Appearance.font.pixelSize.large
                        fill: 1
                        color: root.blendedColors.colOnSecondaryContainer
                    }
                }
            }
        }
    }
}
