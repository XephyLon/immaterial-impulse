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
    // A line is right-to-left if it carries Hebrew/Arabic-block
    // glyphs; its words must then lay out right to left.
    function isRtl(s) { return /[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]/.test(s || "") }
    // One duration for every size change - delegate height, word
    // font, word scale, and the list's own resize - so a line growing
    // as it becomes active reads as a single coordinated motion.
    readonly property int growDuration: 320
    // Romanization/translation toggles, persisted. Shown as footer buttons
    // only when the fetched source actually carries them.
    property bool showRomanization: Config.options.appearance.lyrics.showRomanization
    property bool showTranslation: Config.options.appearance.lyrics.showTranslation

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
                    : lyricSlot.karaokeWords ? wordColumn.implicitHeight : slotText.implicitHeight)
                    + (lyricSlot.hasExtras ? extrasColumn.implicitHeight + Appearance.spacing.space50 : 0)
                    + Appearance.spacing.space50
                // The size changes are transformations too: an active line
                // growing a tier, or swapping to the word flow, eases the
                // rows around it instead of shoving them.
                Behavior on implicitHeight { NumberAnimation { duration: root.growDuration; easing.type: Easing.OutCubic } }

                readonly property int dist: Math.abs(index - LyricsService.activeIndex)
                readonly property bool isActive: index === LyricsService.activeIndex
                readonly property string rowRomanized: root.showRomanization ? LyricsService.lineRomanized(index) : ""
                readonly property string rowTranslated: root.showTranslation ? LyricsService.lineTranslated(index) : ""
                readonly property bool hasExtras: isActive && (rowRomanized.length > 0 || rowTranslated.length > 0)
                readonly property bool filler: lyricSlot.modelData.filler === true
                // Word stamps from the source drive the animated word flow;
                // a line-level source gets the glyph-masked comet sweep.
                readonly property var wordModel: LyricsService.wordTimeline(lyricSlot.modelData)
                // The line just passed keeps its word flow while its tail is
                // still singing - the active-line switch (and the half-second
                // anticipation) must not kill a word mid-glow when lines
                // overlap.
                // The previous line stays lit while its tail is still singing.
                // Word-timed: until the last word's sung end (cross-line
                // overlap). Line-level (no word data - Glassy's line-synced
                // lyrics): until the ACTIVE line actually starts, bridging the
                // half-second activeIndex anticipation so a still-singing line
                // is not dropped early. The old `wordModel.length > 0` gate left
                // line-level lines with no keep-alive at all.
                readonly property bool tailSinging: index === LyricsService.activeIndex - 1
                    && ((wordModel.length > 0
                            && LyricsService.sungEnd(lyricSlot.modelData) > root.sweepPosition)
                        || (LyricsService.activeLineSpan !== null
                            && root.sweepPosition < LyricsService.activeLineSpan.start))
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
                // closer than its neighbours. Keyed on lineHot, not
                // isActive/dist: the moment the next line activated, a
                // still-singing tail line was dimmed to 0.6 and shrunk -
                // whole-line demotion that read as the line being dropped,
                // burying every word-level keep-alive underneath it.
                scale: lineHot ? 1 : 0.94
                transformOrigin: Item.Center
                Behavior on scale {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                opacity: {
                    if (lineHot) return 1.0
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
                    font.pixelSize: lyricSlot.lineHot
                        ? Appearance.font.pixelSize.larger
                        : (lyricSlot.dist === 1 ? Appearance.font.pixelSize.large : Appearance.font.pixelSize.normal)
                    Behavior on font.pixelSize { NumberAnimation { duration: root.growDuration; easing.type: Easing.OutCubic } }
                    // font.weight is numeric and the shell fonts are variable,
                    // so the Bold<->Normal step can tween - without this the
                    // ink-coverage jump reads as an instant colour change.
                    font.weight: lyricSlot.lineHot ? Font.Bold : Font.Normal
                    Behavior on font.weight { NumberAnimation { duration: root.growDuration; easing.type: Easing.OutCubic } }
                    color: lyricSlot.lineSweep ? root.dimColor
                        : (lyricSlot.lineHot ? root.activeColor : root.textColor)
                    // Ease the base colour when a line starts/ends its turn
                    // instead of snapping between active and rest.
                    Behavior on color {
                        ColorAnimation { duration: root.growDuration; easing.type: Easing.OutCubic }
                    }

                    // The line-level sweep: the active colour crossing the
                    // line's own glyphs, paced by the interpolated clock.
                    Item {
                        id: sweepState
                        anchors.fill: parent
                        // Fade the bright overlay in/out rather than toggling
                        // it: a hard flip made the active colour vanish in one
                        // frame when a line ended, which the base-colour
                        // Behavior above could not smooth (the overlay sits on
                        // top of it).
                        opacity: lyricSlot.lineSweep ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity {
                            NumberAnimation { duration: root.growDuration; easing.type: Easing.OutCubic }
                        }
                        readonly property real sweepProgress: {
                            const span = LyricsService.activeLineSpan
                            if (!span) return 0
                            return Math.max(0, Math.min(1,
                                (root.sweepPosition - span.start) / (span.end - span.start)))
                        }
                        // A line with no per-word timing gets a single sweep
                        // at a FIXED speed, not one paced to the line's
                        // duration - restarted each time this becomes the
                        // active swept line. (sweepProgress stays defined for
                        // reference but no longer drives the paint.)
                        property real shownProgress: 0
                        onVisibleChanged: if (visible) fixedSweep.restart()
                        NumberAnimation on shownProgress {
                            id: fixedSweep
                            running: false
                            from: 0; to: 1
                            duration: 2200
                            easing.type: Easing.Linear
                        }

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
                            // Track the overlay's visibility (not lineSweep) so
                            // the glyph mask survives the fade-out.
                            text: sweepState.visible ? slotText.text : ""
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
                            // RTL lines pack their words right-to-left.
                            layoutDirection: root.isRtl(lyricSlot.modelData.text)
                                ? Qt.RightToLeft : Qt.LeftToRight
                            // Anchor to the stable column id, never `parent`
                            // (null for a frame at create/destroy - the source
                            // of the horizontalCenter-of-null warnings).
                            anchors.horizontalCenter: root.textAlignment === Text.AlignHCenter
                                ? wordColumn.horizontalCenter : undefined
                            anchors.left: root.textAlignment === Text.AlignHCenter
                                ? undefined : wordColumn.left
                            spacing: Appearance.spacing.space50

                            Repeater {
                                model: wordRow.modelData
                                delegate: ShimmerLabel {
                                    id: wordText
                                    required property var modelData
                                    readonly property int wordIndex: modelData
                                    readonly property var word: lyricSlot?.wordModel[wordIndex] ?? ({ time: 0, text: "" })
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
                                    // Keyed on lineHot, not isActive: a line whose tail is
                                    // still singing (activeIndex moved on, but it isn't done)
                                    // keeps its full size instead of shrinking away - the
                                    // "previous line still being sung gets ignored" bug.
                                    font.pixelSize: (lyricSlot?.lineHot ?? false)
                                        ? Appearance.font.pixelSize.larger
                                        : ((lyricSlot?.dist ?? 9) === 1 ? Appearance.font.pixelSize.large : Appearance.font.pixelSize.normal)
                                    Behavior on font.pixelSize { NumberAnimation { duration: root.growDuration; easing.type: Easing.OutCubic } }
                                    font.weight: (lyricSlot?.lineHot ?? false) ? Font.DemiBold : Font.Medium
                                    Behavior on font.weight { NumberAnimation { duration: root.growDuration; easing.type: Easing.OutCubic } }
                                    running: (lyricSlot?.lineHot ?? false) && current
                                    phase: current ? Math.max(0, Math.min(1, syllablePhase(root.sweepPosition))) : 0
                                    baseColor: root.activeColor
                                    glowColor: Qt.lighter(root.activeColor, 1.6)
                                    restColor: (lyricSlot?.lineHot ?? false) ? (sung ? root.activeColor : root.dimColor) : root.textColor
                                    // Ease the word colour over the same clock as the size/scale
                                    // so a line's activation and hand-off read as one motion, not
                                    // a fast colour flick.
                                    colorDuration: root.growDuration

                                    property real appearOpacity: 0
                                    transform: Translate { id: wordRise; y: 8 }
                                    Component.onCompleted: wordAppear.start()
                                    SequentialAnimation {
                                        id: wordAppear
                                        PauseAnimation { duration: Appearance.animation.staggerDelay(wordText.wordIndex, 30, 0) }
                                        ParallelAnimation {
                                            NumberAnimation { target: wordText; property: "appearOpacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
                                            NumberAnimation { target: wordRise; property: "y"; from: 8; to: 0; duration: 240; easing.type: Easing.OutCubic }
                                        }
                                    }
                                    opacity: ((lyricSlot?.lineHot ?? false) ? (sung ? 1 : 0.55) : 1) * appearOpacity
                                    scale: (lyricSlot?.lineHot ?? false) && current ? 1.06 : 1.0
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

                // Romanization / translation under the active line, when the
                // matching toggle is on and the source carried them.
                Column {
                    id: extrasColumn
                    visible: lyricSlot.hasExtras
                    width: lyricSlot.width - root.sidePadding * 2
                    y: (lyricSlot.karaokeWords ? wordColumn.implicitHeight : slotText.implicitHeight)
                        + Appearance.spacing.space50
                    anchors.horizontalCenter: root.textAlignment === Text.AlignHCenter ? parent.horizontalCenter : undefined
                    anchors.left: root.textAlignment === Text.AlignHCenter ? undefined : parent.left
                    anchors.leftMargin: root.textAlignment === Text.AlignHCenter ? 0 : root.sidePadding
                    spacing: 0
                    StyledText {
                        visible: lyricSlot.rowRomanized.length > 0
                        width: parent.width
                        horizontalAlignment: root.textAlignment
                        wrapMode: Text.WordWrap
                        text: lyricSlot.rowRomanized
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: root.dimColor
                    }
                    StyledText {
                        visible: lyricSlot.rowTranslated.length > 0
                        width: parent.width
                        horizontalAlignment: root.textAlignment
                        wrapMode: Text.WordWrap
                        text: lyricSlot.rowTranslated
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.italic: true
                        color: root.dimColor
                    }
                }
            }
        }

        // Footer: which source answered, and the romanize/translate toggles -
        // shown only where the source carried each.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: root.sidePadding
            Layout.rightMargin: root.sidePadding
            Layout.bottomMargin: Appearance.spacing.space50
            spacing: Appearance.spacing.space100
            visible: LyricsService.status === "ok"

            StyledText {
                visible: LyricsService.source.length > 0
                text: Translation.tr("via %1").arg(LyricsService.source)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.dimColor
                opacity: 0.7
            }
            Item { Layout.fillWidth: true }
            RippleButton {
                visible: LyricsService.hasRomanization
                implicitWidth: 28; implicitHeight: 28
                buttonRadius: Appearance.rounding.full
                toggled: root.showRomanization
                onClicked: {
                    root.showRomanization = !root.showRomanization
                    Config.options.appearance.lyrics.showRomanization = root.showRomanization
                }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "translate"
                    iconSize: Appearance.font.pixelSize.normal
                    color: root.showRomanization ? root.activeColor : root.dimColor
                }
            }
            RippleButton {
                visible: LyricsService.hasTranslation
                implicitWidth: 28; implicitHeight: 28
                buttonRadius: Appearance.rounding.full
                toggled: root.showTranslation
                onClicked: {
                    root.showTranslation = !root.showTranslation
                    Config.options.appearance.lyrics.showTranslation = root.showTranslation
                }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "language"
                    iconSize: Appearance.font.pixelSize.normal
                    color: root.showTranslation ? root.activeColor : root.dimColor
                }
            }
        }
    }
}