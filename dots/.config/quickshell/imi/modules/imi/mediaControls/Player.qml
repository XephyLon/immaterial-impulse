pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs
import qs.services
import qs.modules.common.functions
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
    required property MprisPlayer player
    property var artUrl: MediaArt.resolve(player?.trackArtUrl ?? "", player?.metadata)
    MediaArtSource {
        id: artSource
        artUrl: root.artUrl
    }
    readonly property string displayedArtFilePath: artSource.displayedArtFilePath
    readonly property bool downloaded: artSource.downloaded
    property color artDominantColor: ColorUtils.mix(
        (artSource.colors[0] ?? Appearance.colors.colPrimary),
        Appearance.colors.colPrimaryContainer,
        0.8) || Appearance.m3colors.m3secondaryContainer
    property list<real> visualizerPoints: []
    property real maxVisualizerValue: 1000
    property int visualizerSmoothing: 2
    property real radius
    property bool showLyrics: false

    property QtObject blendedColors: AdaptedMaterialScheme {
        color: artDominantColor
    }

    Timer {
        running: root.player?.playbackState == MprisPlaybackState.Playing
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: root.player.positionChanged()
    }

    StyledRectangularShadow {
        target: background
    }

    Rectangle {
        id: background
        anchors.fill: parent
        anchors.margins: Appearance.sizes.elevationMargin
        color: ColorUtils.applyAlpha(blendedColors.colLayer0, 1)
        radius: root.radius

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: background.width
                height: background.height
                radius: background.radius
            }
        }

        Image {
            id: blurredArt
            anchors.fill: parent
            source: root.displayedArtFilePath
            sourceSize.width: background.width
            sourceSize.height: background.height
            fillMode: Image.PreserveAspectCrop
            cache: false
            antialiasing: true
            asynchronous: true

            layer.enabled: true
            layer.effect: StyledBlurEffect {
                source: blurredArt
            }

            Rectangle {
                anchors.fill: parent
                color: ColorUtils.transparentize(blendedColors.colLayer0, 0.3)
                radius: root.radius
            }
        }

        WaveVisualizer {
            id: visualizerCanvas
            anchors.fill: parent
            live: root.player?.isPlaying
            points: root.visualizerPoints
            maxVisualizerValue: root.maxVisualizerValue
            smoothing: root.visualizerSmoothing
            color: blendedColors.colPrimary
        }

        Loader {
            id: layoutLoader
            anchors.fill: parent

            sourceComponent: root.showLyrics ? lyricsComponent : controlsComponent

            Component {
                id: controlsComponent
                PlayerControls {
        lyricsToggleShown: !GlobalStates.sidebarRightOpen
                    player: root.player
                    blendedColors: root.blendedColors
                    displayedArtFilePath: root.displayedArtFilePath
                    radius: root.radius
                    onToggleLyrics: root.showLyrics = !root.showLyrics
                }
            }

            Component {
                id: lyricsComponent
                PlayerControlsLyrics {
                    player: root.player
                    blendedColors: root.blendedColors
                    displayedArtFilePath: root.displayedArtFilePath
                    radius: root.radius
                    artDominantColor: root.artDominantColor
                    onToggleLyrics: root.showLyrics = !root.showLyrics
                }
            }
        }
    }
}
