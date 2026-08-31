pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

ColumnLayout {
    id: root
    // These are needed on the parent loader
    property bool editing: false
    property bool renderMarkdown: true
    property bool enableMouseSelection: false
    property var segmentContent: ({})
    property var messageData: {}
    property bool done: true
    property bool forceDisableChunkSplitting: false

    property list<string> renderedLatexHashes: []
    property string renderedSegmentContent: ""
    property string shownText: ""
    property bool fadeChunkSplitting: !forceDisableChunkSplitting && !editing && !/\n\|/.test(shownText) && Config.options.sidebar.ai.textFadeIn

    Layout.fillWidth: true

    Timer {
        id: renderTimer
        interval: 1000
        repeat: false
        onTriggered: {
            renderLatex()
            for (const hash of renderedLatexHashes) {
                handleRenderedLatex(hash, true);
            }
        }
    }

    function renderLatex() {
        // Regex for $...$, $$...$$, \[...\]
        // Note: This is a simple approach and may need refinement for edge cases
        let regex = /(\$\$([\s\S]+?)\$\$)|(\$([^\$]+?)\$)|(\\\[((?:.|\n)+?)\\\])|(\\\(([\s\S]+?)\\\))/g;
        let match;
        while ((match = regex.exec(segmentContent)) !== null) {
            let expression = match[1] || match[2] || match[3] || match[4] || match[5] || match[6] || match[7] || match[8];
            if (expression) {
                Qt.callLater(() => {
                    const [renderHash, isNew] = LatexRenderer.requestRender(expression.trim());
                    if (!renderedLatexHashes.includes(renderHash)) {
                        renderedLatexHashes.push(renderHash);
                    }
                });
            }
        }
    }

    function handleRenderedLatex(hash, force = false) {
        if (renderedLatexHashes.includes(hash) || force) {
            const imagePath = LatexRenderer.renderedImagePaths[hash];
            const markdownImage = `![latex](${imagePath})`;

            const expression = LatexRenderer.processedExpressions[hash];
            renderedSegmentContent = renderedSegmentContent.replace(expression, markdownImage);
        }
    }

    onDoneChanged: {
        renderTimer.restart();
    }
    onEditingChanged: {
        if (!editing) {
            // Leaving edit mode: fold the edits back into the display path
            // the guards above kept frozen while typing.
            renderedSegmentContent = segmentContent;
            root.shownText = segmentContent;
            renderLatex()
        } else {
            // console.log("Editing mode enabled", segmentContent)
            root.shownText = segmentContent
        }
    }

    onSegmentContentChanged: {
        // While EDITING, the TextArea is the source of truth and its own
        // keystrokes land here - echoing them back into shownText replaced
        // the Repeater's values and rebuilt the very delegate being typed
        // in, killing the cursor after one keystroke. The echo resumes
        // when editing ends (onEditingChanged reseeds shownText).
        if (root.editing) return;
        renderedSegmentContent = segmentContent;
        if (segmentContent) {
            root.renderLatex();
        }
    }

    onRenderedSegmentContentChanged: {
        if (root.editing) return; // see onSegmentContentChanged
        if (renderedSegmentContent) {
            root.shownText = renderedSegmentContent;
        }
    }

    // When something finishes rendering
    // 1. Check if the hash is in the list
    // 2. If it is, replace the expression with the image path
    Connections {
        target: LatexRenderer
        function onRenderFinished(hash, imagePath) {
            const expression = LatexRenderer.processedExpressions[hash];
            // console.log("Render finished: " + hash + " " + expression);
            handleRenderedLatex(hash);
        }
    }

    spacing: 0
    Repeater {
        id: textLinesRepeater
        model: ScriptModel {
            // Split by either double newlines or single newlines in a list
            values: root.fadeChunkSplitting ? root.shownText.split(/\n\n(?= {0,2})|\n(?= {0,2}[-\*])/g).filter(line => line.trim() !== "") : [root.shownText]
        }
        delegate: TextArea {
            id: textArea
            required property int index
            required property string modelData

            // The append fade, as a ROTATING ring of snapshots. One ghost
            // restarted per flush never finished its fade before the next
            // flush reset it - text hung near-invisible and popped on
            // pauses. Now each flush claims the oldest of four stacked
            // twins: its previous snapshot (fade long done) commits into
            // the base, and it fades its new full-text snapshot in over
            // its own 200ms, overlapping the other ghosts' fades.
            // Identical glyphs overlap invisibly at every layer, so only
            // appended words read as fading.
            readonly property bool liveTail: !root.done && index === textLinesRepeater.count - 1 && !root.editing
            property string committedText: ""
            property int ghostHead: 0
            onModelDataChanged: {
                if (!liveTail) return;
                const g = ghostRepeater.itemAt(ghostHead % 4);
                if (!g) return;
                if (g.text.length > committedText.length) committedText = g.text;
                g.launch(modelData);
                ghostHead++;
            }

            // A NEW paragraph fades in the moment it is born. The previous
            // scheme held each line at opacity 0 until the NEXT one arrived,
            // so the stream rendered one paragraph behind and landed in
            // pops; a delegate created mid-stream now announces itself and
            // an updated one just keeps its text.
            opacity: 1
            Component.onCompleted: {
                committedText = modelData;
                if (root.fadeChunkSplitting && !(root.messageData?.done ?? true)) {
                    opacity = 0;
                    Qt.callLater(() => textArea.opacity = 1);
                }
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            Layout.fillWidth: true
            readOnly: !editing
            selectByMouse: enableMouseSelection || editing
            renderType: Text.NativeRendering
            font.family: Appearance.font.family.reading
            font.hintingPreference: Font.PreferNoHinting // Prevent weird bold text
            font.pixelSize: Appearance.font.pixelSize.small
            selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
            selectionColor: Appearance.colors.colSecondaryContainer
            wrapMode: TextEdit.Wrap
            color: root.messageData?.thinking ? Appearance.colors.colSubtext
                : root.messageData?.role === 'user' ? Appearance.m3colors.m3onSecondaryContainer
                : Appearance.colors.colOnLayer1
            textFormat: renderMarkdown ? TextEdit.MarkdownText : TextEdit.PlainText
            text: liveTail ? committedText : modelData

            onTextChanged: {
                if (!root.editing) return
                segmentContent = text
            }

            onLinkActivated: (link) => {
                Qt.openUrlExternally(link)
                GlobalStates.sidebarLeftOpen = false
            }

            MouseArea { // Pointing hand for links
                anchors.fill: parent
                acceptedButtons: Qt.NoButton // Only for hover
                hoverEnabled: true
                cursorShape: parent.hoveredLink !== "" ? Qt.PointingHandCursor : 
                    (enableMouseSelection || editing) ? Qt.IBeamCursor : Qt.ArrowCursor
            }

            Repeater {
                id: ghostRepeater
                model: 4
                delegate: TextArea {
                    id: ghost
                    anchors.fill: parent
                    visible: textArea.liveTail && opacity > 0 && text.length > 0
                    opacity: 0
                    enabled: false
                    readOnly: true
                    background: null
                    renderType: Text.NativeRendering
                    font: textArea.font
                    wrapMode: textArea.wrapMode
                    color: textArea.color
                    textFormat: textArea.textFormat
                    text: ""
                    function launch(snapshot) {
                        ghostAnim.stop();
                        text = snapshot;
                        opacity = 0;
                        ghostAnim.start();
                    }
                    NumberAnimation {
                        id: ghostAnim
                        target: ghost
                        property: "opacity"
                        to: 1
                        duration: 200
                        easing.type: Easing.OutQuad
                    }
                }
            }

            Rectangle {
                // The soft leading edge: while this is the growing line of a
                // streaming message, its last stretch sits under a gradient
                // of the message surface, so appended text EMERGES as it
                // pushes past the veil instead of popping in fully formed.
                // Done (or losing last place) fades the veil away, which is
                // also what reveals the final words.
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Appearance.font.pixelSize.small * 2.4
                opacity: (!root.done && textArea.index === textLinesRepeater.count - 1
                    && !root.editing) ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                gradient: Gradient {
                    GradientStop { position: 0.0; color: ColorUtils.transparentize(Appearance.colors.colLayer1, 1) }
                    GradientStop { position: 1.0; color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.08) }
                }
            }

            // Rectangle {
            //     anchors.fill: parent
            //     color: "#22786378"
            //     border.width: 1
            //     border.color: "#7E7E7E"
            // }
        }
    }
}
