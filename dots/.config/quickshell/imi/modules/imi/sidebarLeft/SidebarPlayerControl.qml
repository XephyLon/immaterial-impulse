pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.imi.mediaControls
import qs.services
import qs.modules.common.functions
import "../../common/functions/media_art.js" as MediaArt
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Item {
    id: root
    // Follow MprisController's list rather than the raw Mpris one: it filters
    // out the duplicate/bogus players and already resolves which player is
    // active, so the sidebar and the bar cannot disagree about what is playing.
    readonly property var availablePlayers: MprisController.players
    property var player: availablePlayers[playerSelector.currentIndex] ?? MprisController.activePlayer
    // Falls back to a YouTube thumbnail when a browser player gives no
    // art (empty mpris:artUrl) but xesam:url is a watch link.
    property var artUrl: MediaArt.resolve(player?.trackArtUrl ?? "", player?.metadata)
    MediaArtSource {
        id: artSource
        artUrl: root.artUrl
    }
    readonly property string displayedArtFilePath: artSource.displayedArtFilePath
    readonly property bool downloaded: artSource.downloaded
    property color artDominantColor: Config.options.sidebar.media.artColors
        ? ColorUtils.mix(
            (artSource.colors[0] ?? Appearance.colors.colPrimary),
            Appearance.colors.colPrimaryContainer,
            0.8
          )
        : Appearance.colors.colPrimaryContainer

    // Poke the player for a fresh position only while this control can be seen.
    // The left sidebar is built once and never destroyed, so without the open
    // gate this fired every updateInterval for the whole session whenever any
    // player was playing, re-evaluating position bindings nothing was showing.
    Timer {
        running: GlobalStates.sidebarLeftOpen
            && root.player?.playbackState == MprisPlaybackState.Playing
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: root.player?.positionChanged()
    }


    property QtObject blendedColors: AdaptedMaterialScheme {
        color: artDominantColor
    }

    Rectangle {
        id: background
        anchors.fill: parent
        anchors.leftMargin: Appearance.spacing.space50
        anchors.rightMargin: Appearance.spacing.space50
        anchors.topMargin: -Appearance.spacing.space25
        anchors.bottomMargin: Appearance.spacing.space50
        // A touch stronger than the old 0.9 so the cover tint actually reads
        // on the dark sidebar rather than washing out to grey.
        color: ColorUtils.transparentize(artDominantColor, 0.8)
        radius: Appearance.rounding.normal

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: parent.height * 0.04
            spacing: 0

            // ── Player selector ──
            StyledComboBox {
                id: playerSelector
                // Transparent at rest so it sits on the media card's cover-art
                // tint instead of a filled pill; hover/active keep a faint
                // overlay for affordance.
                colBackground: "transparent"
                colBackgroundHover: ColorUtils.applyAlpha(Appearance.colors.colOnLayer0, 0.06)
                colBackgroundActive: ColorUtils.applyAlpha(Appearance.colors.colOnLayer0, 0.10)
                // A manual pick wins until that player disappears; otherwise the
                // selector follows whichever player became active.
                property bool userSelected: false

                function syncToActivePlayer() {
                    if (userSelected && currentIndex >= 0
                        && currentIndex < root.availablePlayers.length) return;
                    userSelected = false;
                    const index = root.availablePlayers.indexOf(MprisController.activePlayer);
                    currentIndex = index >= 0 ? index : 0;
                }

                visible: root.availablePlayers.length > 1
                Layout.fillWidth: true
                Layout.bottomMargin: Appearance.spacing.space100
                model: root.availablePlayers.map(p => p.identity ?? p.desktopEntry ?? "Unknown")
                currentIndex: 0
                onActivated: userSelected = true
                Component.onCompleted: syncToActivePlayer()

                Connections {
                    target: MprisController
                    function onActivePlayerChanged() { playerSelector.syncToActivePlayer(); }
                    function onPlayersChanged() { playerSelector.syncToActivePlayer(); }
                }
            }

            // ── Album art ──
            Rectangle {
                id: artBackground
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.min(parent.width * 1, parent.height * 0.45)
                Layout.preferredHeight: Layout.preferredWidth
                radius: Appearance.rounding.normal
                color: Appearance.colors.colPrimaryContainer

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: artBackground.width
                        height: artBackground.height
                        radius: artBackground.radius
                    }
                }

                StyledImage {
                    anchors.fill: parent
                    source: root.displayedArtFilePath
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                    antialiasing: true
                    sourceSize.width: artBackground.width * 2
                    sourceSize.height: artBackground.height * 2
                }

                MaterialSymbol {
                    visible: MprisController.activePlayer === null
                    anchors.centerIn: parent 
                    fill: 1
                    text: "music_note"
                    color: Appearance.colors.colPrimary
                    iconSize: Appearance.font.pixelSize.hugeass + 100
                }
            }

            // ── Title & Artist ──
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: Appearance.spacing.space250
                spacing: Appearance.spacing.space100

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: titleText.implicitHeight
                    clip: true

                    StyledText {
                        id: titleText
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.Bold
                        color: blendedColors.colOnLayer0
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: StringUtils.cleanMusicTitle(root.player?.trackTitle) || "Play"

                        Behavior on text {
                            SequentialAnimation {
                                NumberAnimation { target: titleText; property: "x"; to: -titleText.width; duration: Appearance.animation.elementMoveFaster.duration; easing.type: Easing.InQuad }
                                PropertyAction { target: titleText; property: "text" }
                                NumberAnimation { target: titleText; property: "x"; from: titleText.width; to: 0; duration: Appearance.animation.elementMoveFaster.duration; easing.type: Easing.OutQuad }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: artistText.implicitHeight
                    clip: true

                    StyledText {
                        id: artistText
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        font.pixelSize: Appearance.font.pixelSize.large 
                        color: blendedColors.colSubtext
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: root.player?.trackArtist || "Something"

                        Behavior on text {
                            SequentialAnimation {
                                NumberAnimation { target: artistText; property: "x"; to: -artistText.width; duration: Appearance.animation.elementMoveFaster.duration; easing.type: Easing.InQuad }
                                PropertyAction { target: artistText; property: "text" }
                                NumberAnimation { target: artistText; property: "x"; from: artistText.width; to: 0; duration: Appearance.animation.elementMoveFaster.duration; easing.type: Easing.OutQuad }
                            }
                        }
                    }
                }
            }

            // ── Lyrics ──
            Lyrics {
                id: lyricsComp
                opacity: MprisController.activePlayer !== null ? 1 : 0 
                Layout.fillWidth: true
                Layout.fillHeight: true
                textAlignment: Text.AlignHCenter
                textColor: blendedColors.colOnLayer0
                activeColor: blendedColors.colPrimary
                dimColor: blendedColors.colSubtext
                indicatorColor: {
                    let c = blendedColors.colPrimaryContainer
                    return (c && c != "#000000" && c != "transparent") ? c : root.artDominantColor
                }
                indicatorShapeColor: {
                    let c = blendedColors.colOnPrimaryContainer
                    if (c && c != "#000000" && c != "#ffffff" && c != "transparent") return c
                    return blendedColors.colPrimary || Appearance.colors.colPrimary
                }
            }

            // ── Progress ──
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Appearance.spacing.space100
                spacing: Appearance.spacing.space150

                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: blendedColors.colSubtext
                    font.letterSpacing: -0.4
                    font.features: { "tnum": 1 }
                    // root itself can be null while this component is still
                    // incubating or being torn down, so guard the root deref too.
                    text: StringUtils.friendlyTimeForSeconds(root?.player?.position ?? 0)
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: Math.max(sliderLoader.implicitHeight, progressBarLoader.implicitHeight)

                    Loader {
                        id: sliderLoader
                        anchors.fill: parent
                        active: root.player?.canSeek ?? false  
                        sourceComponent: StyledSlider {
                            configuration: StyledSlider.Configuration.Wavy
                            highlightColor: blendedColors.colPrimary
                            trackColor: blendedColors.colSecondaryContainer
                            handleColor: blendedColors.colPrimary
                            value: (root.player?.length ?? 0) > 0 ? root.player.position / root.player.length : 0
                            onMoved: {
                                // No lyrics refetch on seek: LyricsService
                                // re-anchors from the new position on its own.
                                root.player.position = value * root.player.length
                            }
                        }
                    }

                    Loader {
                        id: progressBarLoader
                        anchors {
                            verticalCenter: parent.verticalCenter
                            left: parent.left
                            right: parent.right
                        }
                        active: !(root.player?.canSeek ?? false)  
                        sourceComponent: StyledProgressBar {
                            wavy: root.player?.isPlaying ?? false  
                            highlightColor: blendedColors.colPrimary
                            trackColor: blendedColors.colSecondaryContainer
                            value: (root.player?.length ?? 0) > 0 ? root.player.position / root.player.length : 0
                        }
                    }
                }

                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.normal 
                    color: blendedColors.colSubtext
                    font.letterSpacing: -0.4
                    font.features: { "tnum": 1 }
                    text: StringUtils.friendlyTimeForSeconds(root.player?.length ?? 0)
                }
            }

            // ── Controls ──
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Appearance.spacing.space250
                Layout.alignment: Qt.AlignHCenter
                spacing: Appearance.spacing.space200

                RippleButton {
                    property real baseSize: Math.max(42, parent.parent.height * 0.06)
                    implicitWidth: baseSize * 1.5
                    implicitHeight: baseSize * 1.5
                    buttonRadius: Appearance.rounding.verylarge
                    colBackground: ColorUtils.transparentize(blendedColors.colSecondaryContainer, 0.7)
                    colBackgroundHover: blendedColors.colSecondaryContainerHover
                    colRipple: blendedColors.colSecondaryContainerActive
                    downAction: () => root.player?.previous()
                    contentItem: MaterialSymbol {
                        verticalAlignment: Text.AlignVCenter
                        iconSize: 25
                        fill: 1
                        horizontalAlignment: Text.AlignHCenter
                        color: blendedColors.colOnSecondaryContainer
                        text: "skip_previous"
                    }
                }

                RippleButton {
                    property real baseSize: Math.max(70, parent.parent.height * 0.1)
                    Layout.fillWidth: true
                    implicitHeight: baseSize
                    buttonRadius: (root.player?.isPlaying ?? false) ? Appearance.rounding.verylarge : baseSize / 2  
                    colBackground: (root.player?.isPlaying ?? false) ? blendedColors.colPrimary : blendedColors.colSecondaryContainer
                    colBackgroundHover: (root.player?.isPlaying ?? false) ? blendedColors.colPrimaryHover : blendedColors.colSecondaryContainerHover
                    colRipple: (root.player?.isPlaying ?? false) ? blendedColors.colPrimaryActive : blendedColors.colSecondaryContainerActive
                    downAction: () => root.player?.togglePlaying()  
                    contentItem: MaterialSymbol {
                        verticalAlignment: Text.AlignVCenter
                        iconSize: 50
                        fill: 1
                        horizontalAlignment: Text.AlignHCenter
                        color: (root.player?.isPlaying ?? false) ? blendedColors.colOnPrimary : blendedColors.colOnSecondaryContainer
                        text: (root.player?.isPlaying ?? false) ? "pause" : "play_arrow"
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }
                }

                RippleButton {
                    property real baseSize: Math.max(42, parent.parent.height * 0.06)
                    implicitWidth: baseSize * 1.5
                    implicitHeight: baseSize * 1.5
                    buttonRadius: Appearance.rounding.verylarge
                    colBackground: ColorUtils.transparentize(blendedColors.colSecondaryContainer, 0.7)
                    colBackgroundHover: blendedColors.colSecondaryContainerHover
                    colRipple: blendedColors.colSecondaryContainerActive
                    downAction: () => root.player?.next()
                    contentItem: MaterialSymbol {
                        verticalAlignment: Text.AlignVCenter
                        iconSize: 25
                        fill: 1
                        horizontalAlignment: Text.AlignHCenter
                        color: blendedColors.colOnSecondaryContainer
                        text: "skip_next"
                    }
                }
            }

            // ── Volume ──
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Appearance.spacing.space150
                spacing: Appearance.spacing.space100

                RippleButton {
                    property real baseSize: Math.max(36, parent.parent.height * 0.05)
                    implicitWidth: baseSize
                    implicitHeight: baseSize
                    buttonRadius: Appearance.rounding.large
                    colBackground: ColorUtils.transparentize(blendedColors.colSecondaryContainer, 0.7)
                    colBackgroundHover: blendedColors.colSecondaryContainerHover
                    colRipple: blendedColors.colSecondaryContainerActive
                    downAction: () => {
                        if (root.player) root.player.volume = (root.player.volume > 0) ? 0 : 1.0  
                    }
                    contentItem: MaterialSymbol {
                        verticalAlignment: Text.AlignVCenter
                        iconSize: 18
                        fill: 1
                        horizontalAlignment: Text.AlignHCenter
                        color: blendedColors.colOnSecondaryContainer
                        text: (root.player?.volume ?? 1) <= 0 ? "volume_off"
                            : (root.player?.volume ?? 1) < 0.5 ? "volume_down"
                            : "volume_up"
                    }
                }

                RippleButton {
                    property real baseSize: Math.max(36, parent.parent.height * 0.05)
                    Layout.fillWidth: true
                    implicitHeight: baseSize
                    buttonRadius: Appearance.rounding.large
                    colBackground: ColorUtils.transparentize(blendedColors.colSecondaryContainer, 0.7)
                    colBackgroundHover: blendedColors.colSecondaryContainerHover
                    colRipple: blendedColors.colSecondaryContainerActive
                    downAction: () => {
                        if (root.player) root.player.volume = Math.max(0, (root.player.volume ?? 1) - 0.1)  
                    }
                    contentItem: MaterialSymbol {
                        verticalAlignment: Text.AlignVCenter
                        iconSize: 18
                        fill: 1
                        horizontalAlignment: Text.AlignHCenter
                        color: blendedColors.colOnSecondaryContainer
                        text: "volume_down"
                    }
                }

                RippleButton {
                    property real baseSize: Math.max(36, parent.parent.height * 0.05)
                    Layout.fillWidth: true
                    implicitHeight: baseSize
                    buttonRadius: Appearance.rounding.large
                    colBackground: ColorUtils.transparentize(blendedColors.colSecondaryContainer, 0.7)
                    colBackgroundHover: blendedColors.colSecondaryContainerHover
                    colRipple: blendedColors.colSecondaryContainerActive
                    downAction: () => {
                        if (root.player) root.player.volume = Math.min(1.5, (root.player.volume ?? 1) + 0.1)  
                    }
                    contentItem: MaterialSymbol {
                        verticalAlignment: Text.AlignVCenter
                        iconSize: 18
                        fill: 1
                        horizontalAlignment: Text.AlignHCenter
                        color: blendedColors.colOnSecondaryContainer
                        text: "volume_up"
                    }
                }
            }
        }
    }
}