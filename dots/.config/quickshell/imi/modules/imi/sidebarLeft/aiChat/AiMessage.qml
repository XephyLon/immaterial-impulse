import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Rectangle {
    id: root
    property int messageIndex
    property var messageData
    property var messageInputField

    property real messagePadding: Appearance.spacing.space100
    property real contentSpacing: Appearance.spacing.space50

    property bool enableMouseSelection: false
    property bool renderMarkdown: true
    property bool editing: false

    /** Asks the composer to take this question back for another go. */
    signal editResendRequested(int messageIndex, string content)

    // The opening reveal (spec 2026-08-31): the sidebar bumps the token on
    // arrival and each delegate in view runs one short entrance, ordered by
    // its visible index. handledRevealToken is what keeps a recycled
    // delegate from replaying it, and -1 outside the reveal window keeps
    // scroll-created delegates settled.
    property int transcriptRevealToken: -1
    property int transcriptRevealDelay: 0
    property int handledRevealToken: -1
    /** Open while the chat is receiving: a delegate CREATED inside the
        window is a fresh message and arrives instead of snapping in. */
    property bool arrivalWindow: false

    transform: Translate { id: arrivalRise }
    function startArrival(delay) {
        arrivalAnimation.stop();
        arrivalPause.duration = delay;
        root.opacity = 0;
        arrivalRise.y = Appearance.rounding.verysmall;
        arrivalAnimation.start();
    }
    Component.onCompleted: {
        if (root.arrivalWindow) root.startArrival(0);
    }
    onTranscriptRevealTokenChanged: {
        if (root.transcriptRevealToken < 0) return;
        if (root.transcriptRevealToken === root.handledRevealToken) return;
        root.handledRevealToken = root.transcriptRevealToken;
        root.startArrival(root.transcriptRevealDelay);
    }
    SequentialAnimation {
        id: arrivalAnimation
        PauseAnimation { id: arrivalPause; duration: 0 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; to: 1; duration: Appearance.animation.elementMoveEnter.duration; easing.type: Easing.OutCubic }
            NumberAnimation { target: arrivalRise; property: "y"; to: 0; duration: Appearance.animation.elementMoveEnter.duration; easing.type: Easing.OutExpo }
        }
    }

    property list<var> messageBlocks: StringUtils.splitMarkdownBlocks(root.messageData?.content)
    // The streaming tail re-parses on every chunk, and a Repeater over the
    // whole split rebuilt EVERY block's delegate each time - settled
    // paragraphs flashed and the trailing heading morphed between shapes
    // (the recorded flicker). The PREFIX only changes when a new block is
    // born, so it freezes per block-count and only the last segment renders
    // live.
    property var stablePrefix: []
    property int stableForCount: -1
    readonly property var tailBlock: root.messageBlocks.length > 0
        ? root.messageBlocks[root.messageBlocks.length - 1] : null
    onMessageBlocksChanged: {
        if (root.messageBlocks.length !== root.stableForCount) {
            root.stableForCount = root.messageBlocks.length;
            root.stablePrefix = root.messageBlocks.slice(0, -1);
        }
    }

    anchors.left: parent?.left
    anchors.right: parent?.right
    implicitHeight: columnLayout.implicitHeight + root.messagePadding * 2

    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    function saveMessage() {
        if (!root.editing) return;
        // Get all Loader children (each represents a segment)
        const segments = messageContentColumnLayout.children
            .map(child => child.segment)
            .filter(segment => (segment));

        // Reconstruct markdown
        const newContent = segments.map(segment => {
            if (segment.type === "code") {
                const lang = segment.lang ? segment.lang : "";
                // Remove trailing newlines
                const code = segment.content.replace(/\n+$/, "");
                return "```" + lang + "\n" + code + "\n```";
            } else {
                return segment.content;
            }
        }).join("");

        root.editing = false
        root.messageData.content = newContent;
    }

    Keys.onPressed: (event) => {
        if ( // Prevent de-select
            event.key === Qt.Key_Control || 
            event.key == Qt.Key_Shift || 
            event.key == Qt.Key_Alt || 
            event.key == Qt.Key_Meta
        ) {
            event.accepted = true
        }
        // Ctrl + S to save
        if ((event.key === Qt.Key_S) && event.modifiers == Qt.ControlModifier) {
            root.saveMessage();
            event.accepted = true;
        }
    }

    ColumnLayout { // Main layout of the whole thing
        id: columnLayout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: messagePadding
        spacing: root.contentSpacing

        Rectangle {
            Layout.fillWidth: true
            implicitWidth: headerRowLayout.implicitWidth + 4 * 2
            implicitHeight: headerRowLayout.implicitHeight + 4 * 2
            color: Appearance.colors.colSecondaryContainer
            radius: Appearance.rounding.small
        
            RowLayout { // Header
                id: headerRowLayout
                anchors {
                    fill: parent
                    margins: Appearance.spacing.space50
                }
                spacing: Appearance.spacing.space250

                Item { // Name
                    id: nameWrapper
                    implicitHeight: Math.max(nameRowLayout.implicitHeight + 5 * 2, 30)
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter

                    RowLayout {
                        id: nameRowLayout
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Appearance.spacing.space150
                        anchors.rightMargin: Appearance.spacing.space150
                        spacing: Appearance.spacing.space150

                        Item {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillHeight: true
                            implicitWidth: messageData?.role == 'assistant' ? modelIcon.width : roleIcon.implicitWidth
                            implicitHeight: messageData?.role == 'assistant' ? modelIcon.height : roleIcon.implicitHeight

                            CustomIcon {
                                id: modelIcon
                                anchors.centerIn: parent
                                visible: messageData?.role == 'assistant' && Ai.models[messageData?.model].icon
                                width: Appearance.font.pixelSize.large
                                height: Appearance.font.pixelSize.large
                                source: messageData?.role == 'assistant' ? Ai.models[messageData?.model].icon :
                                    messageData?.role == 'user' ? 'arch-symbolic' : 'desktop-symbolic'

                                colorize: true
                                color: Appearance.m3colors.m3onSecondaryContainer
                            }

                            MaterialSymbol {
                                id: roleIcon
                                anchors.centerIn: parent
                                visible: !modelIcon.visible
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.m3colors.m3onSecondaryContainer
                                text: messageData?.role == 'user' ? 'person' : 
                                    messageData?.role == 'interface' ? 'settings' : 
                                    messageData?.role == 'assistant' ? 'neurology' : 
                                    'computer'
                            }
                        }

                        ShimmerLabel {
                            id: providerName
                            Layout.alignment: Qt.AlignVCenter
                            // The glow IS the generating signal, for every
                            // model - reasoning or not.
                            running: messageData?.role == 'assistant' && !(messageData?.done ?? true)
                            baseColor: Appearance.colors.colSubtext
                            glowColor: Appearance.m3colors.m3onSecondaryContainer
                            font.pixelSize: Appearance.font.pixelSize.normal
                            text: messageData?.role == 'assistant' ? (Ai.models[messageData?.model]?.name ?? messageData?.model ?? "") :
                                (messageData?.role == 'user' && SystemInfo.username) ? SystemInfo.username :
                                Translation.tr("Interface")
                        }
                        Item { Layout.fillWidth: true }
                    }
                }

                Button { // Not visible to model
                    id: modelVisibilityIndicator
                    visible: messageData?.role == 'interface'
                    implicitWidth: 16
                    implicitHeight: 30
                    Layout.alignment: Qt.AlignVCenter

                    background: Item

                    MaterialSymbol {
                        id: notVisibleToModelText
                        anchors.centerIn: parent
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        text: "visibility_off"
                    }
                    StyledToolTip {
                        text: Translation.tr("Not visible to model")
                    }
                }

                ButtonGroup {
                    spacing: Appearance.spacing.space100

                    AiMessageControlButton {
                        id: editResendButton
                        visible: messageData?.role === 'user'
                        enabled: messageData?.done ?? false
                        buttonIcon: "edit_note"
                        onClicked: root.editResendRequested(root.messageIndex,
                            String(root.messageData?.rawContent ?? root.messageData?.content ?? ""))
                        StyledToolTip {
                            text: Translation.tr("Edit & resend")
                        }
                    }

                    AiMessageControlButton {
                        id: regenButton
                        buttonIcon: "refresh"
                        visible: messageData?.role === 'assistant'

                        onClicked: {
                            Ai.regenerate(root.messageIndex)
                        }
                        
                        StyledToolTip {
                            text: Translation.tr("Regenerate")
                        }
                    }

                    AiMessageControlButton {
                        id: copyButton
                        buttonIcon: activated ? "inventory" : "content_copy"

                        onClicked: {
                            Quickshell.clipboardText = root.messageData?.content
                            copyButton.activated = true
                            copyIconTimer.restart()
                        }

                        Timer {
                            id: copyIconTimer
                            interval: 1500
                            repeat: false
                            onTriggered: {
                                copyButton.activated = false
                            }
                        }
                        
                        StyledToolTip {
                            text: Translation.tr("Copy")
                        }
                    }
                    AiMessageControlButton {
                        id: editButton
                        activated: root.editing
                        enabled: root.messageData?.done ?? false
                        buttonIcon: "edit"
                        onClicked: {
                            root.editing = !root.editing
                            if (!root.editing) { // Save changes
                                root.saveMessage()
                            }
                        }
                        StyledToolTip {
                            text: root.editing ? Translation.tr("Save") : Translation.tr("Edit")
                        }
                    }
                    AiMessageControlButton {
                        id: toggleMarkdownButton
                        activated: !root.renderMarkdown
                        buttonIcon: "code"
                        onClicked: {
                            root.renderMarkdown = !root.renderMarkdown
                        }
                        StyledToolTip {
                            text: Translation.tr("View Markdown source")
                        }
                    }
                }
            }
        }

        Loader {
            Layout.fillWidth: true
            active: root.messageData?.localFilePath && root.messageData?.localFilePath.length > 0
            sourceComponent: AttachedFileIndicator {
                filePath: root.messageData?.localFilePath
                canRemove: false
            }
        }

        ColumnLayout { // Message content
            id: messageContentColumnLayout
            spacing: 0

            Item {
                Layout.fillWidth: true
                implicitHeight: loadingIndicatorLoader.shown ? loadingIndicatorLoader.implicitHeight : 0
                implicitWidth: loadingIndicatorLoader.implicitWidth
                visible: implicitHeight > 0

                Behavior on implicitHeight {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                FadeLoader {
                    id: loadingIndicatorLoader
                    anchors.centerIn: parent
                    shown: (root.messageBlocks.length < 1) && (!root.messageData.done)
                    sourceComponent: MaterialLoadingIndicator {
                        loading: true
                    }
                }
            }
            Repeater {
                model: ScriptModel {
                    values: root.stablePrefix
                }
                delegate: blockChooser
            }
            // The live tail: one delegate re-rendering per chunk instead of
            // all of them. Declared after the Repeater so saveMessage still
            // walks the segments in order.
            Repeater {
                model: ScriptModel {
                    values: root.tailBlock !== null ? [root.tailBlock] : []
                }
                delegate: blockChooser
            }
            DelegateChooser {
                    id: blockChooser
                    role: "type"

                    DelegateChoice { roleValue: "code"; MessageCodeBlock {
                        editing: root.editing
                        renderMarkdown: root.renderMarkdown
                        enableMouseSelection: root.enableMouseSelection
                        segmentContent: modelData.content
                        segmentLang: modelData.lang
                        messageData: root.messageData
                    } }
                    DelegateChoice { roleValue: "think"; MessageThinkBlock {
                        editing: root.editing
                        renderMarkdown: root.renderMarkdown
                        enableMouseSelection: root.enableMouseSelection
                        segmentContent: modelData.content
                        messageData: root.messageData
                        done: root.messageData?.done ?? false
                        completed: modelData.completed ?? false
                    } }
                    DelegateChoice { roleValue: "text"; MessageTextBlock {
                        editing: root.editing
                        renderMarkdown: root.renderMarkdown
                        enableMouseSelection: root.enableMouseSelection
                        segmentContent: modelData.content
                        messageData: root.messageData
                        done: root.messageData?.done ?? false
                        forceDisableChunkSplitting: root.messageData?.content.includes("```") ?? true
                    } }
            }
        }

        Flow { // Annotations
            visible: root.messageData?.annotationSources?.length > 0
            spacing: Appearance.spacing.space100
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignLeft

            Repeater {
                model: ScriptModel {
                    values: root.messageData?.annotationSources || []
                }
                delegate: AnnotationSourceButton {
                    id: sourceChip
                    required property var modelData
                    displayText: modelData.text
                    url: modelData.url
                    faviconPath: Favicons.pathFor(modelData.url, modelData.text)
                    faviconReady: Favicons.ready[sourceChip.faviconPath] === true
                    Component.onCompleted: Favicons.request(modelData.url, modelData.text)
                    onFollowed: url => {
                        Qt.openUrlExternally(url);
                        GlobalStates.sidebarLeftOpen = false;
                    }
                }
            }
        }

        Flow { // Search queries
            visible: root.messageData?.searchQueries?.length > 0
            spacing: Appearance.spacing.space100
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignLeft

            Repeater {
                model: ScriptModel {
                    values: root.messageData?.searchQueries || []
                }
                delegate: SearchQueryButton {
                    required property var modelData
                    query: modelData
                    onSearched: query => {
                        let url = Config.options.search.engineBaseUrl + query;
                        for (const site of (Config.options.search.excludedSites ?? []))
                            url += ` -site:${site}`;
                        Qt.openUrlExternally(url);
                        GlobalStates.sidebarLeftOpen = false;
                    }
                }
            }
        }

    }
}

