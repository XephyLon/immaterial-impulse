pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

Item {
    id: root

    // The player this view is showing - forwarded to the service so the
    // fetch follows the dropdown, not the global active player.
    property var player: null
    Binding {
        target: LyricsService
        property: "overridePlayer"
        value: root.player
        when: root.player !== null && root.player !== undefined
    }

    // The sweep clock the active line's words follow.
    property real sweepPosition: 0
    Timer {
        interval: 90
        repeat: true
        running: root.visible && LyricsService.status === "ok"
        onTriggered: root.sweepPosition = LyricsService.estimatedPosition()
    }


    property color textColor: "white"
    property color activeColor: "white"
    property color dimColor: Qt.rgba(1, 1, 1, 0.35)
    property color indicatorColor: Appearance.colors.colPrimaryContainer
    property color indicatorShapeColor: Appearance.colors.colOnPrimaryContainer
    property int textAlignment: Text.AlignLeft

    implicitWidth: 200
    implicitHeight: 200

    // This view existing IS the demand: it is created when the player flips
    // to lyrics and destroyed when it flips back, so its lifetime is the
    // refcount's.
    Component.onCompleted: LyricsService.sidebarLyricsRefs++
    Component.onDestruction: LyricsService.sidebarLyricsRefs--

    ColumnLayout {
        anchors.fill: parent
        spacing: Appearance.spacing.space50

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: LyricsService.status !== "ok"

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Appearance.spacing.space150

                MaterialLoadingIndicator {
                    Layout.alignment: Qt.AlignHCenter
                    loading: LyricsService.status === "loading"
                    colBg: root.indicatorColor
                    colShape: root.indicatorShapeColor
                    implicitSize: 48
                }
            }
        }

        ListView {
            id: lyricsList
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: LyricsService.status === "ok"
            clip: true
            interactive: false
            spacing: Appearance.spacing.space100

            // Lines are STABLE elements that travel - the seven fixed slots
            // swapped their text per advance, and no translate can make a
            // content teleport read as motion. The highlight-follow scroll
            // is the glide: the list eases the active line into the centre
            // band over its own 450ms.
            model: LyricsService.lyricsLines
            currentIndex: LyricsService.activeIndex
            highlightFollowsCurrentItem: true
            highlightRangeMode: ListView.StrictlyEnforceRange
            preferredHighlightBegin: Math.max(0, height / 2 - 40)
            preferredHighlightEnd: height / 2 + 40
            highlightMoveDuration: 450
            highlightMoveVelocity: -1
            highlightResizeDuration: 0

            delegate: Item {
                id: lyricSlot
                required property var modelData
                required property int index
                width: lyricsList.width
                implicitHeight: (lyricSlot.filler ? fillerNote.implicitHeight
                    : lyricSlot.karaokeWords ? wordFlow.implicitHeight : slotText.implicitHeight)
                    + Appearance.spacing.space50
                // The size changes are transformations too: an active line
                // growing a tier, or swapping to the word flow, eases the
                // rows around it instead of shoving them.
                Behavior on implicitHeight { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                readonly property int dist: Math.abs(index - LyricsService.activeIndex)
                readonly property bool isActive: index === LyricsService.activeIndex
                readonly property bool filler: lyricSlot.modelData.filler === true
                // Word stamps from the source drive the animated word flow;
                // a line-level source gets the glyph-masked comet sweep.
                readonly property bool karaokeWords: !filler && isActive && LyricsService.activeWordTimeline.length > 0
                readonly property bool lineSweep: !filler && isActive && !karaokeWords && LyricsService.activeLineSpan !== null

                // The fork's polish, kept: the active line stands a step
                // closer than its neighbours.
                scale: isActive ? 1 : 0.94
                transformOrigin: Item.Center
                Behavior on scale {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                opacity: {
                    if (dist === 0) return 1.0
                    if (dist === 1) return 0.6
                    if (dist === 2) return 0.35
                    if (dist === 3) return 0.15
                    return 0.05
                }
                Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                // A line is a place in the song: click seeks there.
                MouseArea {
                    anchors.fill: parent
                    enabled: (LyricsService.activePlayer?.canSeek ?? false)
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: LyricsService.activePlayer.position = lyricSlot.modelData.time
                }

                // Plain and line-sweep rendering.
                // The instrumental filler: a note that breathes while its
                // gap is the active line, and sits quiet otherwise. The loop
                // runs only while ON - the hidden-panels lesson.
                MaterialSymbol {
                    id: fillerNote
                    visible: lyricSlot.filler
                    anchors.horizontalCenter: root.textAlignment === Text.AlignHCenter
                        ? parent.horizontalCenter : undefined
                    anchors.left: root.textAlignment === Text.AlignHCenter
                        ? undefined : parent.left
                    text: "music_note"
                    iconSize: Appearance.font.pixelSize.large
                    color: lyricSlot.isActive ? root.activeColor : root.dimColor
                    transformOrigin: Item.Center
                    SequentialAnimation on scale {
                        running: lyricSlot.filler && lyricSlot.isActive && lyricSlot.visible
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 1.18; duration: 600; easing.type: Easing.InOutQuad }
                        NumberAnimation { from: 1.18; to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
                    }
                }

                StyledText {
                    id: slotText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    visible: !lyricSlot.karaokeWords && !lyricSlot.filler
                    horizontalAlignment: root.textAlignment
                    wrapMode: Text.WordWrap
                    text: lyricSlot.karaokeWords ? "" : (lyricSlot.modelData.text ?? "")
                    font.pixelSize: lyricSlot.isActive
                        ? Appearance.font.pixelSize.large
                        : (lyricSlot.dist === 1 ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.small)
                    Behavior on font.pixelSize { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    font.weight: lyricSlot.isActive ? Font.Bold : Font.Normal
                    color: lyricSlot.lineSweep ? root.dimColor
                        : (lyricSlot.isActive ? root.activeColor : root.textColor)

                    // The line-level sweep: the active colour crossing the
                    // line's own glyphs, paced by the interpolated clock.
                    Item {
                        id: sweepState
                        anchors.fill: parent
                        visible: lyricSlot.lineSweep
                        readonly property real sweepProgress: {
                            const span = LyricsService.activeLineSpan
                            if (!span) return 0
                            return Math.max(0, Math.min(1,
                                (root.sweepPosition - span.start) / (span.end - span.start)))
                        }
                        property real shownProgress: sweepProgress
                        Behavior on shownProgress { NumberAnimation { duration: 140 } }

                        LinearGradient {
                            id: sweepSource
                            anchors.fill: parent
                            visible: false
                            start: Qt.point(0, 0)
                            end: Qt.point(width, 0)
                            gradient: Gradient {
                                GradientStop { position: 0 ; color: root.activeColor }
                                GradientStop { position: sweepState.shownProgress; color: root.activeColor }
                                // The comet head: a brighter tip at the
                                // clock's exact position.
                                GradientStop { position: Math.min(1, sweepState.shownProgress + 0.05); color: Qt.lighter(root.activeColor, 1.55) }
                                GradientStop { position: Math.min(1, sweepState.shownProgress + 0.16); color: "transparent" }
                            }
                        }
                        StyledText {
                            id: sweepMask
                            anchors.fill: parent
                            visible: false
                            text: lyricSlot.lineSweep ? slotText.text : ""
                            font: slotText.font
                            horizontalAlignment: slotText.horizontalAlignment
                            wrapMode: slotText.wrapMode
                        }
                        OpacityMask {
                            anchors.fill: parent
                            source: sweepSource
                            maskSource: sweepMask
                        }
                    }
                }

                // Word-mode: every word its own element; becoming sung is
                // motion, and the current word carries the synced shimmer.
                Flow {
                    id: wordFlow
                    visible: lyricSlot.karaokeWords
                    spacing: Appearance.spacing.space50

                    readonly property real naturalWidth: {
                        let total = 0, count = 0;
                        for (let i = 0; i < children.length; i++) {
                            const w = children[i].implicitWidth ?? 0;
                            if (w > 0) { total += w; count++; }
                        }
                        return total + Math.max(0, count - 1) * wordFlow.spacing;
                    }
                    width: Math.min(wordFlow.naturalWidth, lyricSlot.width)
                    anchors.horizontalCenter: root.textAlignment === Text.AlignHCenter
                        ? parent.horizontalCenter : undefined
                    anchors.left: root.textAlignment === Text.AlignHCenter
                        ? undefined : parent.left

                    Repeater {
                        model: lyricSlot.karaokeWords ? LyricsService.activeWordTimeline : []
                        delegate: ShimmerLabel {
                            id: wordText
                            required property var modelData
                            required property int index
                            readonly property bool sung: modelData.time <= root.sweepPosition
                            readonly property real nextTime: {
                                const timeline = LyricsService.activeWordTimeline
                                return index + 1 < timeline.length ? timeline[index + 1].time : Infinity
                            }
                            readonly property real windowEnd: {
                                if (modelData.end !== undefined) return modelData.end
                                if (nextTime !== Infinity) return nextTime
                                return modelData.time + 1.2
                            }
                            // The word's OWN window, not "until the next word
                            // starts": backing vocals land a word in the
                            // middle of another, and both must carry their
                            // shimmer for their own sung spans.
                            readonly property bool current: sung && root.sweepPosition < windowEnd
                            function syllablePhase(position) {
                                const syls = modelData.syllables
                                if (!syls || syls.length < 2) {
                                    return (position - modelData.time)
                                        / Math.max(0.05, windowEnd - modelData.time)
                                }
                                const total = syls.reduce((sum, s) => sum + s.text.length, 0)
                                let covered = 0
                                for (let i = 0; i < syls.length; i++) {
                                    const sylEnd = i + 1 < syls.length ? syls[i + 1].time : windowEnd
                                    if (position < sylEnd || i === syls.length - 1) {
                                        const inside = Math.max(0, Math.min(1,
                                            (position - syls[i].time) / Math.max(0.05, sylEnd - syls[i].time)))
                                        return (covered + inside * syls[i].text.length) / Math.max(1, total)
                                    }
                                    covered += syls[i].text.length
                                }
                                return 1
                            }

                            text: modelData.text
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: sung ? Font.Bold : Font.Medium
                            running: current
                            phase: current ? Math.max(0, Math.min(1, syllablePhase(root.sweepPosition))) : 0
                            baseColor: root.activeColor
                            glowColor: Qt.lighter(root.activeColor, 1.6)
                            restColor: sung ? root.activeColor : root.dimColor

                            // The entrance: a new line's words rise in with a
                            // small per-word stagger instead of popping as a
                            // block. Explicit from-values; the entrance
                            // opacity MULTIPLIES the sung state so the two
                            // channels compose.
                            property real appearOpacity: 0
                            transform: Translate { id: wordRise; y: 8 }
                            Component.onCompleted: wordAppear.start()
                            SequentialAnimation {
                                id: wordAppear
                                PauseAnimation { duration: Math.min(240, wordText.index * 30) }
                                ParallelAnimation {
                                    NumberAnimation { target: wordText; property: "appearOpacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: wordRise; property: "y"; from: 8; to: 0; duration: 240; easing.type: Easing.OutCubic }
                                }
                            }

                            opacity: (sung ? 1 : 0.55) * appearOpacity
                            scale: current ? 1.06 : 1.0
                            transformOrigin: Item.Center
                            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            Behavior on scale {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                        }
                    }
                }
            }
        }
    }
}