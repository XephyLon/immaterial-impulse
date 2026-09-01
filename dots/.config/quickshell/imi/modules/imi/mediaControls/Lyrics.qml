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

    function escapeMarkup(text) {
        return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }
    // Qt's rich-text HTML subset takes #rrggbb only; a QML color stringifies
    // with its alpha in front (#aarrggbb) and the 8-digit form is ignored -
    // which painted every word the same and hid the sweep entirely.
    function cssColor(value) {
        const s = String(value)
        return s.length === 9 ? "#" + s.slice(3) : s
    }
    // The active line as rich text: sung words in the active colour, the
    // rest dimmed - the word flips as the clock crosses its stamp.
    function karaokeMarkup(timeline, position) {
        let parts = []
        for (let i = 0; i < timeline.length; i++) {
            const word = timeline[i]
            const tone = word.time <= position
                ? root.cssColor(root.activeColor)
                : root.cssColor(Qt.darker(root.textColor, 2.2))
            parts.push(`<font color="${tone}">${root.escapeMarkup(word.text)}</font>`)
        }
        return parts.join(" ")
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
                delegate: StyledText {
                    id: lyricSlot
                    required property int index
                    Layout.fillWidth: true
                    horizontalAlignment: root.textAlignment
                    wrapMode: Text.WordWrap
                    readonly property int dist: Math.abs(index - LyricsService.before)
                    // Word stamps from the source drive per-word flips; a
                    // line-level source gets the glyph-masked sweep below
                    // instead of a synthesized word fake.
                    readonly property bool karaokeWords: dist === 0 && LyricsService.activeWordTimeline.length > 0
                    readonly property bool lineSweep: dist === 0 && !karaokeWords && LyricsService.activeLineSpan !== null

                    // The fork's polish, kept: the active line stands a step
                    // closer than its neighbours.
                    scale: dist === 0 ? 1 : 0.94
                    transformOrigin: Item.Center
                    Behavior on scale {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    // A line is a place in the song: click seeks there.
                    MouseArea {
                        anchors.fill: parent
                        enabled: (LyricsService.activePlayer?.canSeek ?? false)
                            && lyricSlot.text.length > 0
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            const lineIndex = LyricsService.activeIndex - LyricsService.before + lyricSlot.index
                            if (lineIndex < 0 || lineIndex >= LyricsService.lyricsLines.length)
                                return
                            LyricsService.activePlayer.position = LyricsService.lyricsLines[lineIndex].time
                        }
                    }

                    // The line-level sweep: the active colour crossing the
                    // line's own glyphs (an invisible twin is the mask), paced
                    // by the interpolated clock over the line's span - honest
                    // motion without invented word stamps, and seek-proof
                    // where the fork's fire-and-forget animation drifts.
                    Item {
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
                                GradientStop { position: parent.parent.shownProgress; color: root.activeColor }
                                GradientStop { position: Math.min(1, parent.parent.shownProgress + 0.12); color: "transparent" }
                            }
                        }
                        StyledText {
                            id: sweepMask
                            anchors.fill: parent
                            visible: false
                            text: lyricSlot.lineSweep ? lyricSlot.text : ""
                            font: lyricSlot.font
                            horizontalAlignment: lyricSlot.horizontalAlignment
                            wrapMode: lyricSlot.wrapMode
                        }
                        OpacityMask {
                            anchors.fill: parent
                            source: sweepSource
                            maskSource: sweepMask
                        }
                    }

                    textFormat: karaokeWords ? Text.RichText : Text.PlainText
                    text: {
                        if (lyricSlot.karaokeWords)
                            return root.karaokeMarkup(LyricsService.activeWordTimeline, root.sweepPosition)
                        return LyricsService.slots[index] ?? ""
                    }
                    font.pixelSize: {
                        if (dist === 0) return Appearance.font.pixelSize.normal
                        if (dist === 1) return Appearance.font.pixelSize.small
                        return Appearance.font.pixelSize.smaller
                    }
                    opacity: {
                        if (dist === 0) return 1.0
                        if (dist === 1) return 0.6
                        if (dist === 2) return 0.35
                        return 0.15
                    }
                    color: lyricSlot.lineSweep ? root.dimColor
                        : (dist === 0 ? root.activeColor : root.textColor)
                    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    Behavior on font.pixelSize { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                }
            }
        }
    }
}