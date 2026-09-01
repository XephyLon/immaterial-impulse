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
    // Lines breathe in from the panel edges; a long line wraps inside this
    // column instead of running to the side.
    property real sidePadding: Appearance.spacing.space300
    // One duration for every size change - delegate height, word
    // font, word scale, and the list's own resize - so a line growing
    // as it becomes active reads as a single coordinated motion.
    readonly property int growDuration: 320

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
            highlightMoveDuration: root.growDuration
            highlightMoveVelocity: -1
            highlightResizeDuration: root.growDuration

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
                Behavior on implicitHeight { NumberAnimation { duration: root.growDuration; easing.type: Easing.OutCubic } }

                readonly property int dist: Math.abs(index - LyricsService.activeIndex)
                readonly property bool isActive: index === LyricsService.activeIndex
                readonly property bool filler: lyricSlot.modelData.filler === true
                // Word stamps from the source drive the animated word flow;
                // a line-level source gets the glyph-masked comet sweep.
                readonly property var wordModel: LyricsService.wordTimeline(lyricSlot.modelData)
                // The line just passed keeps its word flow while its tail is
                // still singing - the active-line switch (and the half-second
                // anticipation) must not kill a word mid-glow when lines
                // overlap.
                readonly property bool tailSinging: index === LyricsService.activeIndex - 1
                    && wordModel.length > 0
                    && LyricsService.sungEnd(lyricSlot.modelData) > root.sweepPosition
                // A line with word data is a word flow ALWAYS - swapping
                // to plain text while inactive made activation a twin swap,
                // and the fresh words' entrance left a visible gap ("words
                // disappear for a moment"). One element per purpose:
                // activation restyles the same words through Behaviors.
                readonly property bool karaokeWords: !filler && wordModel.length > 0
                readonly property bool lineHot: isActive || tailSinging
                readonly property bool lineSweep: !filler && isActive
                    && LyricsService.activeWordTimeline.length === 0
                    && LyricsService.activeLineSpan !== null

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
                    anchors.leftMargin: root.sidePadding
                    anchors.rightMargin: root.sidePadding
                    visible: !lyricSlot.karaokeWords && !lyricSlot.filler
                    horizontalAlignment: root.textAlignment
                    wrapMode: Text.WordWrap
                    text: lyricSlot.karaokeWords ? "" : (lyricSlot.modelData.text ?? "")
                    font.pixelSize: lyricSlot.isActive
                        ? Appearance.font.pixelSize.large
                        : (lyricSlot.dist === 1 ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.small)
                    Behavior on font.pixelSize { NumberAnimation { duration: root.growDuration; easing.type: Easing.OutCubic } }
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

// Word-mode: every word its own element, laid out in manually
                // centred rows - a Flow left-packs its wrapped rows, which a
                // centred view cannot have. FontMetrics measures the packing;
                // each row is a Row centred in the column.
                Column {
                    id: wordColumn
                    visible: lyricSlot.karaokeWords
                    width: lyricSlot.width - root.sidePadding * 2
                    anchors.horizontalCenter: root.textAlignment === Text.AlignHCenter
                        ? parent.horizontalCenter : undefined
                    anchors.left: root.textAlignment === Text.AlignHCenter
                        ? undefined : parent.left
                    anchors.leftMargin: root.textAlignment === Text.AlignHCenter
                        ? 0 : root.sidePadding
                    spacing: Appearance.spacing.space25

                    FontMetrics {
                        id: wordMetrics
                        font.family: Appearance.font.family.reading
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Bold
                    }
                    // Greedy packing of the word timeline into rows that fit
                    // the column - arrays of indices into wordModel.
                    readonly property var rows: {
                        const timeline = lyricSlot.wordModel
                        const avail = wordColumn.width
                        const gap = Appearance.spacing.space50
                        const out = []
                        let cur = [], used = 0
                        for (let i = 0; i < timeline.length; i++) {
                            const w = wordMetrics.advanceWidth(timeline[i].text)
                            const add = (cur.length ? gap : 0) + w
                            if (cur.length && used + add > avail) { out.push(cur); cur = []; used = 0 }
                            cur.push(i); used += (cur.length > 1 ? gap : 0) + w
                        }
                        if (cur.length) out.push(cur)
                        return out
                    }

                    Repeater {
                        model: wordColumn.rows
                        delegate: Row {
                            id: wordRow
                            required property var modelData
                            anchors.horizontalCenter: root.textAlignment === Text.AlignHCenter
                                ? parent.horizontalCenter : undefined
                            anchors.left: root.textAlignment === Text.AlignHCenter
                                ? undefined : parent.left
                            spacing: Appearance.spacing.space50

                            Repeater {
                                model: wordRow.modelData
                                delegate: ShimmerLabel {
                                    id: wordText
                                    required property var modelData
                                    readonly property int wordIndex: modelData
                                    readonly property var word: lyricSlot.wordModel[wordIndex]
                                    readonly property bool sung: word.time <= root.sweepPosition
                                    readonly property real nextTime: {
                                        const tl = lyricSlot.wordModel
                                        return wordIndex + 1 < tl.length ? tl[wordIndex + 1].time : Infinity
                                    }
                                    readonly property real windowEnd: {
                                        if (word.end !== undefined) return word.end
                                        if (nextTime !== Infinity) return nextTime
                                        return word.time + 1.2
                                    }
                                    readonly property bool current: sung && root.sweepPosition < windowEnd
                                    function syllablePhase(position) {
                                        const syls = word.syllables
                                        if (!syls || syls.length < 2)
                                            return (position - word.time) / Math.max(0.05, windowEnd - word.time)
                                        const total = syls.reduce((s, x) => s + x.text.length, 0)
                                        let covered = 0
                                        for (let i = 0; i < syls.length; i++) {
                                            const e = i + 1 < syls.length ? syls[i + 1].time : windowEnd
                                            if (position < e || i === syls.length - 1) {
                                                const inside = Math.max(0, Math.min(1,
                                                    (position - syls[i].time) / Math.max(0.05, e - syls[i].time)))
                                                return (covered + inside * syls[i].text.length) / Math.max(1, total)
                                            }
                                            covered += syls[i].text.length
                                        }
                                        return 1
                                    }

                                    text: word.text
                                    font.pixelSize: lyricSlot.isActive
                                        ? Appearance.font.pixelSize.large
                                        : (lyricSlot.dist === 1 ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.small)
                                    Behavior on font.pixelSize { NumberAnimation { duration: root.growDuration; easing.type: Easing.OutCubic } }
                                    font.weight: lyricSlot.lineHot && sung ? Font.Bold : Font.Medium
                                    running: lyricSlot.lineHot && current
                                    phase: current ? Math.max(0, Math.min(1, syllablePhase(root.sweepPosition))) : 0
                                    baseColor: root.activeColor
                                    glowColor: Qt.lighter(root.activeColor, 1.6)
                                    restColor: lyricSlot.lineHot ? (sung ? root.activeColor : root.dimColor) : root.textColor

                                    property real appearOpacity: 0
                                    transform: Translate { id: wordRise; y: 8 }
                                    Component.onCompleted: wordAppear.start()
                                    SequentialAnimation {
                                        id: wordAppear
                                        PauseAnimation { duration: Math.min(240, wordText.wordIndex * 30) }
                                        ParallelAnimation {
                                            NumberAnimation { target: wordText; property: "appearOpacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
                                            NumberAnimation { target: wordRise; property: "y"; from: 8; to: 0; duration: 240; easing.type: Easing.OutCubic }
                                        }
                                    }
                                    opacity: (lyricSlot.lineHot ? (sung ? 1 : 0.55) : 1) * appearOpacity
                                    scale: lyricSlot.lineHot && current ? 1.06 : 1.0
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
    }
}