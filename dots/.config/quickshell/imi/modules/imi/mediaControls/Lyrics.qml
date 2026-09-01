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

        ColumnLayout {
            id: lyricsRoll
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: LyricsService.status === "ok"
            spacing: Appearance.spacing.space100

            // The advance: when the active line moves on, the column arrives
            // shifted one line-height toward the reader and settles - the
            // roles (size, opacity) already cross-fade through their own
            // Behaviors, this is the travel that makes it read as motion
            // instead of a swap.
            readonly property real lineAdvance: Appearance.font.pixelSize.small + Appearance.spacing.space100
            transform: Translate { id: lineShiftTransform; y: 0 }
            NumberAnimation {
                id: lineShiftSettle
                target: lineShiftTransform
                property: "y"
                to: 0
                duration: 350
                easing.type: Easing.OutCubic
            }
            Connections {
                target: LyricsService
                function onActiveIndexChanged() {
                    if (LyricsService.activeIndex < 0)
                        return;
                    lineShiftSettle.stop();
                    // Named, not `parent`: inside a Connections handler an
                    // unqualified parent resolves past the column entirely,
                    // and the assignment of undefined aborted the handler -
                    // which is exactly the snap this animation exists to end.
                    lineShiftTransform.y = lyricsRoll.lineAdvance;
                    lineShiftSettle.start();
                }
            }

            Repeater {
                model: 7
                delegate: Item {
                    id: lyricSlot
                    required property int index
                    Layout.fillWidth: true
                    implicitHeight: lyricSlot.karaokeWords ? wordFlow.implicitHeight : slotText.implicitHeight

                    readonly property int dist: Math.abs(index - LyricsService.before)
                    // Word stamps from the source drive the animated word
                    // flow; a line-level source gets the glyph-masked comet
                    // sweep on the plain text instead.
                    readonly property bool karaokeWords: dist === 0 && LyricsService.activeWordTimeline.length > 0
                    readonly property bool lineSweep: dist === 0 && !karaokeWords && LyricsService.activeLineSpan !== null

                    // The fork's polish, kept: the active line stands a step
                    // closer than its neighbours.
                    scale: dist === 0 ? 1 : 0.94
                    transformOrigin: Item.Center
                    Behavior on scale {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    opacity: {
                        if (dist === 0) return 1.0
                        if (dist === 1) return 0.6
                        if (dist === 2) return 0.35
                        return 0.15
                    }
                    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

                    // A line is a place in the song: click seeks there.
                    MouseArea {
                        anchors.fill: parent
                        enabled: (LyricsService.activePlayer?.canSeek ?? false)
                            && (lyricSlot.karaokeWords || slotText.text.length > 0)
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            const lineIndex = LyricsService.activeIndex - LyricsService.before + lyricSlot.index
                            if (lineIndex < 0 || lineIndex >= LyricsService.lyricsLines.length)
                                return
                            LyricsService.activePlayer.position = LyricsService.lyricsLines[lineIndex].time
                        }
                    }

                    // Plain and line-sweep rendering.
                    StyledText {
                        id: slotText
                        anchors.left: parent.left
                        anchors.right: parent.right
                        visible: !lyricSlot.karaokeWords
                        horizontalAlignment: root.textAlignment
                        wrapMode: Text.WordWrap
                        text: lyricSlot.karaokeWords ? "" : (LyricsService.slots[lyricSlot.index] ?? "")
                        font.pixelSize: {
                            if (lyricSlot.dist === 0) return Appearance.font.pixelSize.normal
                            if (lyricSlot.dist === 1) return Appearance.font.pixelSize.small
                            return Appearance.font.pixelSize.smaller
                        }
                        Behavior on font.pixelSize { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        font.weight: lyricSlot.dist === 0 ? Font.Bold : Font.Normal
                        color: lyricSlot.lineSweep ? root.dimColor
                            : (lyricSlot.dist === 0 ? root.activeColor : root.textColor)

                        // The line-level sweep: the active colour crossing the
                        // line's own glyphs (an invisible twin is the mask),
                        // paced by the interpolated clock over the line's span.
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

                    // Word-mode: every word is its own element, so becoming
                    // sung is MOTION - colour and opacity ease in, and the
                    // word under the clock pops a step forward - instead of
                    // a rich-text rebuild's hard flip.
                    Flow {
                        id: wordFlow
                        visible: lyricSlot.karaokeWords
                        spacing: Appearance.spacing.space50

                        // Centred like every other line when the view centres.
                        // The width comes from the words' own implicitWidths,
                        // never from the Flow's - a positioner feeds its
                        // implicitWidth from its children's WIDTH, and that
                        // circle is the cheatsheet's collapsed-sheet bug.
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
                            // The AI "Thinking" shimmer, synced to the word:
                            // the current word carries the traveling glow with
                            // its band at exactly the word's progress, then
                            // rests in the sung colour.
                            delegate: ShimmerLabel {
                                id: wordText
                                required property var modelData
                                required property int index
                                readonly property bool sung: modelData.time <= root.sweepPosition
                                readonly property real nextTime: {
                                    const timeline = LyricsService.activeWordTimeline
                                    return index + 1 < timeline.length ? timeline[index + 1].time : Infinity
                                }
                                readonly property bool current: sung && root.sweepPosition < nextTime

                                text: modelData.text
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: sung ? Font.Bold : Font.Medium
                                running: current
                                phase: current && nextTime !== Infinity
                                    ? (root.sweepPosition - modelData.time) / Math.max(0.05, nextTime - modelData.time)
                                    : -1
                                baseColor: root.activeColor
                                glowColor: Qt.lighter(root.activeColor, 1.6)
                                restColor: sung ? root.activeColor : root.dimColor
                                opacity: sung ? 1 : 0.55
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
}