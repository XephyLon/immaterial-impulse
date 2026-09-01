import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.plugins
import qs.modules.common.functions as Functions
import qs.services
import qs.modules.imi.mediaControls
import "."

Item {
    id: root
    implicitWidth: 420 * Appearance.effectiveScale
    implicitHeight: 228 * Appearance.effectiveScale

    // Hosted by the media widget's one tree (nandoroid-media/Widget.qml): the
    // tree owns the card, the transport, the slider and the time label, so
    // this instance draws only what is unshared - title, artist, the lyrics
    // page and its toggles. Standalone (the component registry) it stays the
    // complete widget it always was.
    property bool chromeless: false

    property bool showLyrics: Config.options.appearance.mediaWidget.showLyrics
    property bool viewLyrics: false
    readonly property int crossfadeDuration: Appearance.animation.elementMove.duration
    property bool useBlurBackground: false
    // Handled state, for the card's elevation.
    property bool dragging: false
    // The host's box is animating; the cards drop their shadow for it.
    property bool boxInMotion: false
    // The host wrapper overrides this with its own plugin id; the fallback keeps
    // the toggle honoured for a component instantiated without one.

    property real backgroundOpacity: PluginState.effectiveBackgroundOpacity("", 0.1)
    readonly property bool managesBlurTint: true
    readonly property var blurRegions: [{
        x: bgCard.x, y: bgCard.y, width: bgCard.width, height: bgCard.height, radius: bgCard.radius
    }]


    // Main Card Background. Card bg = play/pause icon color (user request).
    WidgetCard {
        id: bgCard
        visible: !root.chromeless
        anchors.fill: parent
        dragging: root.dragging
        hostMotionActive: root.boxInMotion
        useBlurBackground: root.useBlurBackground
        backgroundOpacity: root.backgroundOpacity
    }

    // Toggle button in top right corner (M3 Styled Shape)
    Item {
        id: lyricsToggleBtn
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 16 * Appearance.effectiveScale
        anchors.rightMargin: 16 * Appearance.effectiveScale
        implicitWidth: 32 * Appearance.effectiveScale
        implicitHeight: 32 * Appearance.effectiveScale
        z: 20

        MaterialShape {
            anchors.fill: parent
            // Morphs with state, not a static frame: ShapeCanvas animates any
            // `shape` change through its built-in prev->current polygon morph
            // (elementMoveSmall clock), so the silhouette actually travels
            // between the two faces - cookie at rest, clover while lyrics are
            // up. The fill rides the same clock via the Behavior below, so
            // shape and colour cross together instead of the colour snapping.
            shape: viewLyrics ? MaterialShape.Shape.Clover4Leaf : MaterialShape.Shape.Cookie4Sided
            // Using colTertiaryContainer in dark mode and colSecondaryContainer in light mode for soft pastel visual
            color: viewLyrics
                ? Appearance.colors.colPrimary
                : (Appearance.m3colors.darkmode ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colSecondaryContainer)
            Behavior on color {
                ColorAnimation {
                    duration: Appearance.animation.elementMoveSmall.duration
                    easing.type: Appearance.animation.elementMoveSmall.type
                    easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: viewLyrics ? "music_note" : "lyrics"
                iconSize: 18 * Appearance.effectiveScale
                fill: 0
                color: viewLyrics
                    ? Appearance.colors.colOnPrimary
                    : (Appearance.m3colors.darkmode ? Appearance.colors.colTertiaryContainer : Appearance.colors.colOnSecondaryContainer)
                // The glyph's colour crosses on the shape's clock too.
                Behavior on color {
                    ColorAnimation {
                        duration: Appearance.animation.elementMoveSmall.duration
                        easing.type: Appearance.animation.elementMoveSmall.type
                        easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    viewLyrics = !viewLyrics;
                }
            }
        }
    }

    // Crossfade between Media Control (0) and Lyrics (1). A StackLayout
    // swapped them instantly; both pages are stacked now and cross-fade on
    // viewLyrics, so the switch is seamless. The hidden page drops to opacity
    // 0 and visible:false, so it takes no input.
    Item {
        id: mainStack
        anchors.fill: parent
        anchors.margins: 17 * Appearance.effectiveScale
        anchors.bottomMargin: 22 * Appearance.effectiveScale

        // PAGE 0: Media Control & Info View
        ColumnLayout {
            anchors.fill: parent
            opacity: root.viewLyrics ? 0 : 1
            visible: opacity > 0
            enabled: !root.viewLyrics
            Behavior on opacity { NumberAnimation { duration: root.crossfadeDuration; easing.type: Easing.InOutQuad } }
            spacing: 2 * Appearance.effectiveScale // Tighter spacing for title/artist

            // 1. TITLE (Centered, bounded from lyrics button)
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 48 * Appearance.effectiveScale
                Layout.rightMargin: 48 * Appearance.effectiveScale
                horizontalAlignment: Text.AlignHCenter
                text: Functions.StringUtils.cleanMusicTitle(MprisController.trackTitle) || "No Music Playing"
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colPrimary // Title on colOnPrimary dark card
                elide: Text.ElideRight
            }

            // 2. ARTIST (Centered, bounded from lyrics button)
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 48 * Appearance.effectiveScale
                Layout.rightMargin: 48 * Appearance.effectiveScale
                horizontalAlignment: Text.AlignHCenter
                text: {
                    let rawTitle = (MprisController.trackTitle || "").trim().toLowerCase();
                    let hasTitle = rawTitle !== "" && rawTitle !== "no media" && rawTitle !== "no music playing";
                    let hasArtist = MprisController.trackArtist && MprisController.trackArtist.trim() !== "";
                    if (hasTitle) {
                        return hasArtist ? MprisController.trackArtist : "Unknown Artist";
                    }
                    return "Play some media";
                }
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: Functions.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.75) // Artist subtitle on dark card
                elide: Text.ElideRight
            }
            
            Item { Layout.fillHeight: true } // Flexible spacer to push down to center

            // 3. BUTTONS (Centered, SANGAT BESAR)
            RowLayout {
                visible: !root.chromeless
                Layout.alignment: Qt.AlignHCenter
                spacing: 12 * Appearance.effectiveScale

                // Prev Button
                Item {
                    id: prevBtn
                    implicitWidth: 62 * Appearance.effectiveScale
                    implicitHeight: 62 * Appearance.effectiveScale

                    property bool hovered: false
                    property bool pressed: false

                    // Only the scalloped shape rotates; the icon and hit area are
                    // siblings so the skip glyph stays upright. Both cogs spin the
                    // same way (clockwise) like the two reels of a cassette while
                    // playing, easing back to rest when paused. The 12-fold shape
                    // makes the loop's 360deg wrap seamless. See issue #60.
                    MaterialShape {
                        id: prevShape
                        anchors.fill: parent
                        shape: MaterialShape.Shape.Cookie12Sided
                        color: Appearance.m3colors.darkmode ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colSecondaryContainer

                        // `visible` beside the transport state: a reel spinning
                        // inside a hidden desktop still dirties the scene every
                        // frame, and the compositor repaints the output for each
                        // frame the shell commits.
                        property bool spinning: MprisController.isPlaying && prevShape.visible
                        RotationAnimator on rotation {
                            from: 0
                            to: 360
                            duration: 9000
                            loops: Animation.Infinite
                            running: prevShape.spinning
                        }
                        onSpinningChanged: if (!spinning) rotation = 0
                        Behavior on rotation {
                            enabled: !prevShape.spinning
                            RotationAnimation { direction: RotationAnimation.Shortest; duration: 300; easing.type: Easing.OutCubic }
                        }
                    }

                    MaterialSymbol {
                        id: prevIcon
                        anchors.centerIn: parent
                        text: "skip_previous"
                        iconSize: 28 * Appearance.effectiveScale
                        fill: 0
                        color: prevBtn.hovered
                            ? (Appearance.m3colors.darkmode ? Appearance.colors.colTertiaryContainer : Appearance.colors.colPrimary)
                            : (Appearance.m3colors.darkmode ? Appearance.colors.colTertiaryContainer : Appearance.colors.colOnSecondaryContainer)
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onEntered: prevBtn.hovered = true
                        onExited: prevBtn.hovered = false
                        onPressed: prevBtn.pressed = true
                        onReleased: prevBtn.pressed = false
                        onClicked: MprisController.previous()
                    }
                }

                // Play Button (Wide Pill)
                Rectangle {
                    id: playBtn
                    implicitWidth: 192 * Appearance.effectiveScale
                    implicitHeight: 66 * Appearance.effectiveScale
                    radius: 33 * Appearance.effectiveScale
                    color: Appearance.colors.colPrimary
                    Layout.alignment: Qt.AlignVCenter

                    property bool hovered: false
                    property bool pressed: false

                    MaterialSymbol {
                        id: playIcon
                        anchors.centerIn: parent
                        text: MprisController.isPlaying ? "pause" : "play_arrow"
                        iconSize: 40 * Appearance.effectiveScale
                        fill: 0
                        color: playBtn.pressed
                            ? Functions.ColorUtils.applyAlpha(Appearance.colors.colOnPrimary, 0.7)
                            : Appearance.colors.colOnPrimary
                        Behavior on color { ColorAnimation { duration: 100 } }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: Appearance.colors.colOnPrimary
                        opacity: playBtn.pressed ? 0.15 : (playBtn.hovered ? 0.08 : 0)
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onEntered: playBtn.hovered = true
                        onExited: playBtn.hovered = false
                        onPressed: playBtn.pressed = true
                        onReleased: playBtn.pressed = false
                        onClicked: MprisController.togglePlaying()
                    }
                }

                // Next Button
                Item {
                    id: nextBtn
                    implicitWidth: 62 * Appearance.effectiveScale
                    implicitHeight: 62 * Appearance.effectiveScale

                    property bool hovered: false
                    property bool pressed: false

                    // Second cassette reel: spins clockwise in lockstep with the
                    // prev cog, icon and hit area stay put. See issue #60.
                    MaterialShape {
                        id: nextShape
                        anchors.fill: parent
                        shape: MaterialShape.Shape.Cookie12Sided
                        color: Appearance.m3colors.darkmode ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colSecondaryContainer

                        property bool spinning: MprisController.isPlaying && nextShape.visible
                        RotationAnimator on rotation {
                            from: 0
                            to: 360
                            duration: 9000
                            loops: Animation.Infinite
                            running: nextShape.spinning
                        }
                        onSpinningChanged: if (!spinning) rotation = 0
                        Behavior on rotation {
                            enabled: !nextShape.spinning
                            RotationAnimation { direction: RotationAnimation.Shortest; duration: 300; easing.type: Easing.OutCubic }
                        }
                    }

                    MaterialSymbol {
                        id: nextIcon
                        anchors.centerIn: parent
                        text: "skip_next"
                        iconSize: 28 * Appearance.effectiveScale
                        fill: 0
                        color: nextBtn.hovered
                            ? (Appearance.m3colors.darkmode ? Appearance.colors.colTertiaryContainer : Appearance.colors.colPrimary)
                            : (Appearance.m3colors.darkmode ? Appearance.colors.colTertiaryContainer : Appearance.colors.colOnSecondaryContainer)
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onEntered: nextBtn.hovered = true
                        onExited: nextBtn.hovered = false
                        onPressed: nextBtn.pressed = true
                        onReleased: nextBtn.pressed = false
                        onClicked: MprisController.next()
                    }
                }
            }
            
            Item { Layout.fillHeight: true } // Flexible spacer to balance vertical distribution

            // 4. DURASI SAAT INI / DURASI TOTAL (Centered with tabular figures)
            StyledText {
                Layout.fillWidth: true
                visible: !root.chromeless
                horizontalAlignment: Text.AlignHCenter
                text: Functions.StringUtils.friendlyTimeForSeconds(MprisController.position) + " / " + Functions.StringUtils.friendlyTimeForSeconds(MprisController.length)
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.family: Appearance.font.family.numbers
                font.features: { "tnum": 1 }
                font.weight: Font.DemiBold
                color: Appearance.colors.colPrimary
                renderType: Text.QtRendering
            }

            // 5. PROGRESS BAR
            StyledSlider {
                id: progressSlider
                visible: !root.chromeless
                Layout.preferredWidth: 170 * Appearance.effectiveScale
                Layout.fillWidth: false
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredHeight: 12 * Appearance.effectiveScale
                handleMargins: 0
                configuration: StyledSlider.Configuration.Wavy
                stopIndicatorValues: []
                animateValue: false
                value: (MprisController.length > 0 ? (MprisController.position / MprisController.length) : 0) || 0
                wavy: MprisController.isPlaying
                highlightColor: Appearance.colors.colPrimary
                trackColor: Functions.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.25)

                // Circle dot handle
                handle: Rectangle {
                    x: progressSlider.leftPadding + (progressSlider.visualPosition * (progressSlider.availableWidth - width))
                    y: (progressSlider.height - height) / 2
                    width: 14 * Appearance.effectiveScale
                    height: 14 * Appearance.effectiveScale
                    radius: width / 2
                    color: Appearance.colors.colPrimary
                }

                onMoved: {
                    if (MprisController.activePlayer && MprisController.activePlayer.canSeek) {
                        MprisController.activePlayer.position = value * MprisController.activePlayer.length;
                    }
                }

                Connections {
                    target: MprisController
                    function onPositionChanged() {
                        if (!progressSlider.pressed) {
                            progressSlider.value = (MprisController.length > 0 ? (MprisController.position / MprisController.length) : 0) || 0;
                        }
                    }
                }
            }
        }

        // PAGE 1: Lyrics - the shared word-synced component (the widget's
        // own five-line renderer was line-level with no word sync; this is
        // the same view the sidebar uses, so the two stay in step). Wrapped
        // in a Loader so it arms the service (its own refcount) only while
        // the lyrics page is actually shown.
        Item {
            anchors.fill: parent
            opacity: root.viewLyrics ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: root.crossfadeDuration; easing.type: Easing.InOutQuad } }
            Loader {
                anchors.fill: parent
                anchors.margins: Appearance.spacing.space100
                // Kept mounted (not active: viewLyrics) so the lyrics are
                // already fetched and rendered when the crossfade begins -
                // creating it on toggle left page 1 blank mid-fade while the
                // fetch ran, the "pops in and out" gap. Gated on showLyrics
                // so a widget with the feature off pays nothing.
                active: true
                sourceComponent: Lyrics {
                    player: MprisController.activePlayer
                    textAlignment: Text.AlignHCenter
                    textColor: Appearance.colors.colOnLayer0
                    activeColor: Appearance.colors.colPrimary
                    dimColor: Functions.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.4)
                }
            }
        }
    }

}
