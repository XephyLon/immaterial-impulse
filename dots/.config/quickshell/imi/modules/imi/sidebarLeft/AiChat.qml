import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.imi.sidebarLeft.aiChat
import qs.modules.imi.aiProviders
import "../../../services/ai/prompt_history.js" as PromptHistory
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

Item {
    id: root
    property real padding: Appearance.spacing.space50
    property var inputField: messageInputField
    property string commandPrefix: "/"

    // Prompt recall (the tested fold) and the edit takeback. Reset on every
    // send so a recalled prompt does not leak into the next stepping run.
    property var promptHistoryState: PromptHistory.idle()
    property int editingMessageIndex: -1

    function stepPromptHistory(delta) {
        const r = PromptHistory.step(root.promptHistoryState,
            Ai.ownPromptHistory, messageInputField.text, delta);
        if (!r.handled) return false;
        root.promptHistoryState = { index: r.index, backup: r.backup };
        if (r.text !== null) {
            messageInputField.text = r.text;
            messageInputField.cursorPosition = messageInputField.text.length;
        }
        return true;
    }

    function beginEdit(messageIndex, content) {
        root.editingMessageIndex = messageIndex;
        messageInputField.text = String(content ?? "");
        messageInputField.cursorPosition = messageInputField.text.length;
        messageInputField.forceActiveFocus();
    }

    function regenerateLastAnswer() {
        for (let at = Ai.messageIDs.length - 1; at >= 0; at--) {
            if (Ai.messageByID[Ai.messageIDs[at]]?.role === "assistant") {
                Ai.regenerate(at);
                return;
            }
        }
    }

    function editLastQuestion() {
        for (let at = Ai.messageIDs.length - 1; at >= 0; at--) {
            const m = Ai.messageByID[Ai.messageIDs[at]];
            if (m?.role === "user" && m.visibleToUser !== false) {
                root.beginEdit(at, String(m.rawContent ?? m.content ?? ""));
                return;
            }
        }
    }

    function cancelEdit() {
        if (root.editingMessageIndex < 0) return;
        root.editingMessageIndex = -1;
        messageInputField.clear();
    }

    function acceptComposer(inputText) {
        AiDrafts.clear(AiSessions.currentId);
        root.promptHistoryState = PromptHistory.idle();
        if (root.editingMessageIndex >= 0) {
            const at = root.editingMessageIndex;
            root.editingMessageIndex = -1;
            Ai.editAndResend(at, inputText);
            return;
        }
        root.handleInput(inputText);
    }

    // One number the opening choreography hangs off: the composer's
    // rise/blur and the transcript reveal both fire when it bumps.
    property int entranceTrigger: -1

    // The keys view: the chat area renders the shared providers editor in
    // place - the maintainer's call over a jump to Settings. Closing it is
    // an arrival, so the transcript reveals again.
    // One view over the transcript at a time: "" (the chat), "keys", or
    // "sessions". Closing any of them is an arrival, so the transcript
    // reveals; the step-back below reads the same emptiness.
    property string activeView: ""
    // Where the open view's back arrow RETURNS to: the view it was opened
    // from (the fork's viewReturnTo), not always the chat - browse opened
    // from Providers & keys goes back there.
    property string viewReturnTo: ""
    function toggleView(name) {
        root.viewReturnTo = "";
        root.activeView = (root.activeView === name) ? "" : name;
    }
    function openView(name, from) {
        root.viewReturnTo = from ?? "";
        root.activeView = name;
    }
    function closeView() {
        const back = root.viewReturnTo;
        root.viewReturnTo = "";
        root.activeView = back;
    }
    onActiveViewChanged: if (root.activeView === "") root.revealTranscript()

    // ---- transcript reveal ------------------------------------------------
    // Delegates in view when this bumps run a short arrival; offscreen rows
    // are created settled. Never mid-answer: a reveal is an opening
    // transition, and replaying it over a turn still being written asks
    // every settled turn to enter again around it.
    property int transcriptRevealToken: -1
    function revealTranscript() {
        if (Ai.isGenerating) return;
        root.transcriptRevealToken = Math.max(0, root.transcriptRevealToken + 1);
        transcriptRevealWindow.restart();
    }
    // A message added while the pane is on screen arrives - the delegates
    // created inside this short window play the same fade-and-rise the
    // reveal uses, so a fresh answer lands the way one does in a chat app
    // instead of snapping into existence.
    property bool messageArrivalWindow: false
    Timer {
        id: messageArrivalTimer
        interval: 400
        onTriggered: root.messageArrivalWindow = false
    }
    Connections {
        // The SOURCE list, not the view's count: the view creates the new
        // delegate before its own countChanged fires, so a window opened
        // there is a window opened one message late. The service's property
        // change precedes the model propagation.
        target: Ai
        function onMessageIDsChanged() {
            if (!GlobalStates.sidebarLeftOpen) return;
            root.messageArrivalWindow = true;
            messageArrivalTimer.restart();
        }
    }

    Timer {
        id: transcriptRevealWindow
        // Covers the stagger while keeping delegates later created by
        // scrolling settled - an opening transition, never a list-populate
        // one.
        interval: Appearance.animation.elementMoveEnter.duration
            + Appearance.animation.elementMoveSmall.duration * 2
        onTriggered: root.transcriptRevealToken = -1
    }

    // ---- the empty state's hello -------------------------------------------
    property string emptyStateGreeting: ""
    readonly property var greetingLines: [
        Translation.tr("Hello"),
        Translation.tr("What's on your mind?"),
        Translation.tr("Ready when you are"),
        Translation.tr("Ask away"),
        Translation.tr("Where were we?")
    ]
    function refreshGreeting() {
        const configured = String(Config.options.sidebar.ai.greeting ?? "").trim();
        root.emptyStateGreeting = configured.length > 0 ? configured
            : root.greetingLines[Math.floor(Math.random() * root.greetingLines.length)];
    }
    Component.onCompleted: {
        root.refreshGreeting();
        if (messageInputField.text.length === 0)
            messageInputField.text = AiDrafts.take(AiSessions.currentId);
    }

    Connections {
        target: AiSessions
        function onSessionOpened(id) {
            // Only an EMPTY composer takes the stored draft - a half-typed
            // thought is never clobbered by a stale one.
            if (messageInputField.text.length === 0)
                messageInputField.text = AiDrafts.take(id);
        }
        function onCurrentIdChanged() {
            if (AiSessions.currentId === "" && messageInputField.text.length === 0)
                messageInputField.text = AiDrafts.take("");
        }
    }

    property var suggestionQuery: ""
    property var suggestionList: []

    // Inline message editing: the vacuum below yanked focus back to the
    // composer after the first keystroke in a message's edit field.
    property bool transcriptEditActive: false

    // The vacuum stands down whenever ANY other editable text item holds
    // focus - the temp chip's inline editor was armed and instantly
    // disarmed by it, which read as the chip not responding at all.
    function composerMayVacuum() {
        const afi = root.Window.activeFocusItem;
        return !(afi && afi !== messageInputField
            && afi.cursorPosition !== undefined && afi.readOnly === false);
    }

    onFocusChanged: focus => {
        // Never while a canvas view covers the composer: stealing focus to
        // a hidden input routed the browse view's search typing into the
        // chat box. And never while a message is being edited in place,
        // nor while any other editor owns the keys.
        if (focus && root.activeView === "" && !root.transcriptEditActive
                && root.composerMayVacuum()) {
            root.inputField.forceActiveFocus();
        }
    }

    Keys.onPressed: event => {
        // Same guard as onFocusChanged: with a view open, the composer is
        // under an overlay and must not vacuum the keys - nor while a
        // message edit field owns them.
        if (root.activeView !== "" || root.transcriptEditActive || !root.composerMayVacuum()) return;
        messageInputField.forceActiveFocus();
        if (event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageUp) {
                messageListView.contentY = Math.max(0, messageListView.contentY - messageListView.height / 2);
                event.accepted = true;
            } else if (event.key === Qt.Key_PageDown) {
                messageListView.contentY = Math.min(messageListView.contentHeight - messageListView.height / 2, messageListView.contentY + messageListView.height / 2);
                event.accepted = true;
            }
        }
        if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_O) {
            AiSessions.newSession();
        }
    }

    property var allCommands: [
        {
            name: "attach",
            description: Translation.tr("Attach a file. Works with Gemini and vision-capable OpenAI-compatible models."),
            execute: args => {
                Ai.attachFile(args.join(" ").trim());
            }
        },
        {
            name: "model",
            description: Translation.tr("Choose model"),
            execute: args => {
                Ai.setModel(args[0]);
            }
        },
        {
            name: "tool",
            description: Translation.tr("Set the tool to use for the model."),
            execute: args => {
                // console.log(args)
                if (args.length == 0 || args[0] == "get") {
                    Ai.addMessage(Translation.tr("Usage: %1tool TOOL_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                } else {
                    const tool = args[0];
                    const switched = Ai.setTool(tool);
                    if (switched) {
                        Ai.addMessage(Translation.tr("Tool set to: %1").arg(tool), Ai.interfaceRole);
                    }
                }
            }
        },
        {
            name: "prompt",
            description: Translation.tr("Set the system prompt for the model."),
            execute: args => {
                if (args.length === 0 || args[0] === "get") {
                    Ai.printPrompt();
                    return;
                }
                Ai.loadPrompt(args.join(" ").trim());
            }
        },
        {
            name: "key",
            description: Translation.tr("Set API key"),
            execute: args => {
                if (args[0] == "get") {
                    Ai.printApiKey();
                } else {
                    Ai.setApiKey(args[0]);
                }
            }
        },
        {
            name: "save",
            description: Translation.tr("Save chat"),
            execute: args => {
                const joinedArgs = args.join(" ");
                if (joinedArgs.trim().length == 0) {
                    Ai.addMessage(Translation.tr("Usage: %1save CHAT_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                Ai.saveChat(joinedArgs);
            }
        },
        {
            name: "load",
            description: Translation.tr("Load chat"),
            execute: args => {
                const joinedArgs = args.join(" ");
                if (joinedArgs.trim().length == 0) {
                    Ai.addMessage(Translation.tr("Usage: %1load CHAT_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                Ai.loadChat(joinedArgs);
            }
        },
        {
            name: "clear",
            description: Translation.tr("Clear chat history"),
            execute: () => {
                Ai.clearMessages();
            }
        },
        {
            name: "temp",
            description: Translation.tr("Set temperature (randomness) of the model. Values range between 0 to 2 for Gemini, 0 to 1 for other models. Default is 0.5."),
            execute: args => {
                // console.log(args)
                if (args.length == 0 || args[0] == "get") {
                    Ai.printTemperature();
                } else {
                    const temp = parseFloat(args[0]);
                    Ai.setTemperature(temp);
                }
            }
        },
        {
            name: "test",
            description: Translation.tr("Markdown test"),
            execute: () => {
                Ai.simulateStream(Ai.testStreamText);
            }
        },
    ]

    function handleInput(inputText) {
        if (inputText.startsWith(root.commandPrefix)) {
            // Handle special commands
            const command = inputText.split(" ")[0].substring(1);
            const args = inputText.split(" ").slice(1);
            const commandObj = root.allCommands.find(cmd => cmd.name === `${command}`);
            if (commandObj) {
                commandObj.execute(args);
            } else {
                Ai.addMessage(Translation.tr("Unknown command: ") + command, Ai.interfaceRole);
            }
        } else {
            Ai.sendUserMessage(inputText);
        }

        // Always scroll to bottom when user sends a message
        messageListView.positionViewAtEnd();
    }

    Process {
        id: decodeImageAndAttachProc
        property string imageDecodePath: Directories.cliphistDecode
        property string imageDecodeFileName: "image"
        property string imageDecodeFilePath: `${imageDecodePath}/${imageDecodeFileName}`
        function handleEntry(entry: string) {
            imageDecodeFileName = parseInt(entry.match(/^(\d+)\t/)[1]);
            decodeImageAndAttachProc.exec(["bash", "-c", `[ -f ${imageDecodeFilePath} ] || echo '${StringUtils.shellSingleQuoteEscape(entry)}' | ${Cliphist.cliphistBinary} decode > '${imageDecodeFilePath}'`]);
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                Ai.attachFile(imageDecodeFilePath);
            } else {
                console.error("[AiChat] Failed to decode image in clipboard content");
            }
        }
    }

    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            if (GlobalStates.sidebarLeftOpen) {
                paneEntrance.park();
                paneEntrance.enter();
                if (emptyStatePlaceholder.shown) {
                    glyphGrow.stop();
                    emptyStatePlaceholder.scale = 0.85;
                    glyphGrow.start();
                }
                root.entranceTrigger++;
                root.revealTranscript();
                if (emptyStatePlaceholder.shown)
                    root.refreshGreeting();
            }
        }
    }

    // The empty state's glyph GROWS into place while the pane's members
    // fade - the fork's left-pane look, where the brain mark visibly
    // arrives rather than being faded in as furniture. Scale only, on its
    // own item: the fade is the wave member's (the messages area above it)
    // and the placeholder's own opacity Behavior belongs to its shown
    // fade - three channels, three owners, no doubling.
    SequentialAnimation {
        id: glyphGrow
        PauseAnimation { duration: Appearance.animation.scale(120) }
        NumberAnimation {
            target: emptyStatePlaceholder
            property: "scale"
            to: 1
            duration: Appearance.animation.scale(380)
            easing.type: Easing.OutBack
            easing.overshoot: 1.2
        }
    }

    ColumnLayout {
        id: columnLayout
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: root.padding

        StaggerWave {
            id: paneEntrance
            target: columnLayout
            // The right sidebar's twice-learned cadence: a modest head start
            // so no member is mid-fade while the panel edge is arriving,
            // then the fork's tight per-member step. The composer is the
            // last rank - the visible tail after the landing, which is the
            // fork's own left-pane signature.
            leadIn: 80
            step: 25
        }
        StaggerEntrance {
            target: columnLayout
            reference: root.width
        }

        Rectangle { // Tools bar
            id: toolsBarSurface
            property real appear: 1   // wave member, first rank
            Layout.fillWidth: true
            implicitHeight: controlBar.implicitHeight + Appearance.spacing.space150
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer1
            clip: true

            ChatControlBar {
                id: controlBar
                anchors.fill: parent
                anchors.leftMargin: Appearance.spacing.space100
                anchors.rightMargin: Appearance.spacing.space100
                inputField: messageInputField
                commandPrefix: root.commandPrefix
                onKeysRequested: root.toggleView("keys")
                onSessionsRequested: root.toggleView("sessions")
            }
        }

        Rectangle {
            id: chatAreaSurface
            property real appear: 1
            color: Appearance.colors.colLayer1
            // Messages
            Layout.fillWidth: true
            Layout.fillHeight: true
            layer.enabled: true
            radius: Appearance.rounding.large
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: swipeView.width
                    height: swipeView.height
                    radius: Appearance.rounding.large
                }
            }

            // The page under the providers view: it fades and zooms INWARD as
            // the view arrives - the M3 container step-back - and gives its
            // input up while covered. One wrapper drives every transcript-side
            // child; the keys view stays a sibling above it. (The children
            // keep their original indentation: re-indenting them all would
            // bury this change's actual diff.)
            Item {
                id: transcriptPage
                anchors.fill: parent
                scale: root.activeView === "" ? 1 : 0.95
                opacity: root.activeView === "" ? 1 : 0
                visible: opacity > 0.01
                enabled: root.activeView === ""
                Behavior on scale {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

            ScrollEdgeFade {
                z: 1
                target: messageListView
                vertical: true
            }

            StyledListView { // Message list
                id: messageListView
                // An unclipped ListView renders off-screen delegates OVER
                // the tools bar above it, and their readOnly TextAreas ate
                // every click on the chips whenever the transcript was
                // scrolled anywhere but the top.
                clip: true
                z: 0
                anchors.fill: parent
                spacing: Appearance.spacing.space150
                popin: false
                topMargin: Appearance.spacing.space100
                bottomMargin: Appearance.spacing.space100
                leftMargin: Appearance.spacing.space100
                rightMargin: Appearance.spacing.space100

                touchpadScrollFactor: Config.options.interactions.scrolling.touchpadScrollFactor * 1.4
                mouseScrollFactor: Config.options.interactions.scrolling.mouseScrollFactor * 1.4

                property int lastResponseLength: 0
                // FOLLOW is a state, not a per-chunk atYEnd check: every
                // chunk grows the content past the viewport, so atYEnd
                // flickers false mid-stream, the scroll pill strobed and the
                // late reposition yanked the view (the recorded jitter).
                // Only the USER breaks follow - contentY moving UP, which
                // growth and positionViewAtEnd never do - and reaching the
                // bottom re-arms it.
                property bool following: true
                // Follow breaks on EXPLICIT user input only. The old
                // contentY-decrease detector also fired on the ListView's
                // own layout adjustments mid-stream, silently killing the
                // follow partway through every long answer (both recorded
                // runs show it dead in their late windows).
                Connections {
                    target: messageListView
                    function onUserWheeled(delta) {
                        if (delta > 0) {
                            messageListView.following = false;
                            messageListView.chasing = false;
                            messageListView.followVel = 0;
                        }
                    }
                }
                onMovingChanged: if (moving) { following = false; chasing = false; followVel = 0; }
                onAtYEndChanged: if (atYEnd) following = true

                // The chase, not the snap: positionViewAtEnd() per chunk
                // repainted the whole viewport in bursts - the recorded
                // stutter. Growth now retargets one short animation from
                // wherever the view is, so the follow reads as continuous
                // motion; the detector above still stops it the moment the
                // user scrolls up, because an upward wheel is the one thing
                // that moves contentY down mid-chase.
                // The chase is a per-frame exponential approach: every
                // frame closes a fixed fraction of the remaining gap, so
                // velocity is proportional to distance and there is no
                // easing cycle to restart. The recorded SmoothedAnimation
                // version ran its short hop to completion, stopped, and
                // re-eased on the next chunk - scroll advanced on every
                // other frame in bursts, which was the remaining stutter.
                property bool chasing: false
                property real followVel: 0
                function followToEnd() { chasing = true; }
                FrameAnimation {
                    id: followTick
                    running: messageListView.chasing && messageListView.following
                    onTriggered: {
                        // SmoothDamp: velocity is STATE, so it stays
                        // continuous while the target jumps with every
                        // chunk. The previous gap-proportional step made
                        // speed track the gap directly - measured on video
                        // as a 0..79px/frame sawtooth (decay, stall, jump).
                        const end = messageListView.originY + messageListView.contentHeight
                            + messageListView.bottomMargin - messageListView.height;
                        const y = messageListView.contentY;
                        const gap = end - y;
                        if (gap <= 0.5 && Math.abs(messageListView.followVel) < 8) {
                            messageListView.chasing = false;
                            messageListView.followVel = 0;
                            return;
                        }
                        const dt = Math.min(frameTime, 0.05);
                        const omega = 2 / 0.35;   // smoothTime 350ms
                        const x = omega * dt;
                        const damp = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x);
                        const change = y - end;
                        const temp = (messageListView.followVel + omega * change) * dt;
                        messageListView.followVel = (messageListView.followVel - omega * temp) * damp;
                        let next = end + (change + temp) * damp;
                        if (next > end) { next = end; messageListView.followVel = 0; }
                        // Written past the wheel Behavior: smoothed writes
                        // queue behind alwaysRunToEnd and the chase freezes.
                        messageListView.setContentYImmediate(next);
                    }
                }
                onContentHeightChanged: if (following) followToEnd()
                onCountChanged: if (following) followToEnd()

                add: null // Prevent function calls from being janky

                model: ScriptModel {
                    values: Ai.messageIDs.filter(id => {
                        const message = Ai.messageByID[id];
                        return message?.visibleToUser ?? true;
                    })
                }
                delegate: AiMessage {
                    required property var modelData
                    required property int index
                    transcriptRevealToken: root.transcriptRevealToken
                    transcriptRevealDelay: index * 40
                    arrivalWindow: root.messageArrivalWindow
                    onEditResendRequested: (messageIndex, content) => root.beginEdit(messageIndex, content)
                    onEditingChanged: root.transcriptEditActive = editing
                    messageIndex: index
                    messageData: {
                        Ai.messageByID[modelData];
                    }
                    messageInputField: root.inputField
                }
            }

            PagePlaceholder {
                id: emptyStatePlaceholder
                z: 2
                shown: Ai.messageIDs.length === 0
                icon: "neurology"
                title: root.emptyStateGreeting
                description: Translation.tr("Ask anything")
                shape: MaterialShape.Shape.PixelCircle
            }

            ScrollToBottomButton {
                z: 3
                target: messageListView
            }

            Loader {
                // The keys worth knowing before the first message.
                z: 3
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    bottom: parent.bottom
                    bottomMargin: Appearance.spacing.space200
                }
                width: Math.min(parent.width - Appearance.spacing.space200 * 2,
                    Appearance.font.pixelSize.huge * 18)
                active: Ai.messageIDs.length === 0
                opacity: active ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                sourceComponent: ColumnLayout {
                    spacing: Appearance.spacing.space25
                    EmptyStateKey {
                        // No providers, no models: the one row that matters
                        // leads, and it opens the door it names.
                        visible: Ai.modelList.length === 0
                        Layout.fillWidth: true
                        keys: ["+"]
                        label: Translation.tr("No providers yet - add one to start chatting")
                        actionable: true
                        onTriggered: root.activeView = "keys"
                    }
                    EmptyStateKey {
                        visible: Ai.modelList.length > 0
                        Layout.fillWidth: true
                        keys: ["/key"]
                        label: Translation.tr("Manage providers & keys")
                        actionable: true
                        onTriggered: root.activeView = "keys"
                    }
                    EmptyStateKey { Layout.fillWidth: true; keys: ["Ctrl", "O"]; label: Translation.tr("Expand the sidebar") }
                    EmptyStateKey { Layout.fillWidth: true; keys: ["Ctrl", "P"]; label: Translation.tr("Pin it open") }
                    EmptyStateKey { Layout.fillWidth: true; keys: ["Ctrl", "D"]; label: Translation.tr("Detach it into its own window") }
                }
            }
            }

            Loader {
                // Providers & keys, rendered in place over the transcript.
                id: overlayViewLoader
                z: 10
                anchors.fill: parent
                // LATCHED, never bound to activeView directly: a row's click
                // closes the view, and a binding that unloads on close
                // destroys the very MouseArea still holding the pointer
                // grab - the next click then misdelivered until the pointer
                // state reset (the "can't click Chats until I scroll" bug).
                // The view now outlives the close through its fade and
                // unloads only once invisible, the SettingsContent dialog
                // hosts' shape.
                readonly property bool wanted: root.activeView.length > 0
                property string shownView: ""
                active: false
                Connections {
                    target: root
                    function onActiveViewChanged() {
                        if (root.activeView.length === 0) return;
                        if (overlayViewLoader.active) {
                            // View-to-view (keys -> browse): the click that
                            // asked lives in the OLD view - swap next turn,
                            // never under the pressed surface. `wanted`
                            // alone never fired here: it stays true across
                            // the switch, which left shownView stale and
                            // both in-view doors dead.
                            Qt.callLater(() => {
                                if (root.activeView.length > 0)
                                    overlayViewLoader.shownView = root.activeView;
                            });
                            return;
                        }
                        overlayViewLoader.shownView = root.activeView;
                        overlayViewLoader.active = true;
                    }
                }
                onLoaded: if (overlayViewLoader.shownView === "keys" && !KeyringStorage.loaded) KeyringStorage.fetchKeyringData()
                opacity: wanted ? 1 : 0
                visible: opacity > 0.01
                onVisibleChanged: if (!visible && !wanted) overlayViewLoader.active = false
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                sourceComponent: overlayViewLoader.shownView === "keys" ? keysViewComponent
                    : overlayViewLoader.shownView === "sessions" ? sessionsViewComponent
                    : overlayViewLoader.shownView === "browse" ? browseViewComponent : null

                Component {
                    id: browseViewComponent
                    BrowseModelsView {
                        onClosed: root.closeView()
                    }
                }

                Component {
                    id: sessionsViewComponent
                    SessionListView {
                        onClosed: root.closeView()
                    }
                }

                Component {
                    id: keysViewComponent
                Rectangle {
                    color: Appearance.colors.colLayer1
                    radius: Appearance.rounding.large

                    // Arrives from the right, the fork's going-deeper
                    // direction; the back arrow is the way out.
                    transform: Translate { id: keysViewSlide; y: 0 }
                    Component.onCompleted: {
                        keysViewSlide.x = 24;
                        keysSlideAnim.start();
                    }
                    NumberAnimation {
                        id: keysSlideAnim
                        target: keysViewSlide
                        property: "x"
                        to: 0
                        duration: Appearance.animation.elementMoveEnter.duration
                        easing.type: Easing.OutExpo
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Appearance.spacing.space150
                        spacing: Appearance.spacing.space100

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Appearance.spacing.space100
                            RippleButton {
                                implicitWidth: 32
                                implicitHeight: 32
                                buttonRadius: Appearance.rounding.full
                                colBackground: "transparent"
                                colRipple: Appearance.colors.colLayer2Active
                                onClicked: root.closeView()
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "arrow_back"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colOnLayer1
                                }
                            }
                            StyledText {
                                text: Translation.tr("Providers & keys")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                            }
                            Item { Layout.fillWidth: true }
                            RippleButton {
                                // The fetch: a flat primary-inked icon in
                                // the header (was a text button lost at the
                                // bottom; the filled FAB read too heavy).
                                implicitWidth: 36
                                implicitHeight: 36
                                buttonRadius: Appearance.rounding.full
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                colRipple: Appearance.colors.colLayer2Active
                                onClicked: Ai.fetchCustomModels()
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "sync"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colPrimary
                                }
                                StyledToolTip { text: Translation.tr("Fetch models") }
                            }
                        }

                        StyledFlickable {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentHeight: keysColumn.implicitHeight

                            ColumnLayout {
                                id: keysColumn
                                width: parent.width
                                spacing: Appearance.spacing.space150

                                AiProvidersEditor {
                                    Layout.fillWidth: true
                                }

                                RippleButton {
                                    Layout.fillWidth: true
                                    implicitHeight: 40
                                    buttonRadius: Appearance.rounding.normal
                                    colBackground: "transparent"
                                    colBackgroundHover: Appearance.colors.colLayer2Hover
                                    colRipple: Appearance.colors.colLayer2Active
                                    onClicked: root.openView("browse", "keys")
                                    contentItem: RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Appearance.spacing.space100
                                        spacing: Appearance.spacing.space100
                                        MaterialSymbol {
                                            text: "travel_explore"
                                            iconSize: Appearance.font.pixelSize.larger
                                            color: Appearance.colors.colPrimary
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: (Config.options.ai.customProviders ?? []).length > 0
                                                ? Translation.tr("Browse models")
                                                : Translation.tr("Browse OpenRouter models")
                                            color: Appearance.colors.colOnLayer1
                                            font.pixelSize: Appearance.font.pixelSize.small
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

        DescriptionBox {
            property real appear: 1
            text: root.suggestionList[suggestions.selectedIndex]?.description ?? ""
            showArrows: root.suggestionList.length > 1
        }

        FlowButtonGroup { // Suggestions
            property real appear: 1
            id: suggestions
            visible: root.suggestionList.length > 0 && messageInputField.text.length > 0
            property int selectedIndex: 0
            Layout.fillWidth: true
            spacing: Appearance.spacing.space100

            Repeater {
                id: suggestionRepeater
                model: {
                    suggestions.selectedIndex = 0;
                    return root.suggestionList.slice(0, 10);
                }
                delegate: ApiCommandButton {
                    id: commandButton
                    colBackground: suggestions.selectedIndex === index ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer
                    bounce: false
                    contentItem: StyledText {
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.m3colors.m3onSurface
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData.displayName ?? modelData.name
                    }

                    onHoveredChanged: {
                        if (commandButton.hovered) {
                            suggestions.selectedIndex = index;
                        }
                    }
                    onClicked: {
                        suggestions.acceptSuggestion(modelData.name);
                    }
                }
            }

            function acceptSuggestion(word) {
                const words = messageInputField.text.trim().split(/\s+/);
                if (words.length > 0) {
                    words[words.length - 1] = word;
                } else {
                    words.push(word);
                }
                const updatedText = words.join(" ") + " ";
                messageInputField.text = updatedText;
                messageInputField.cursorPosition = messageInputField.text.length;
                messageInputField.forceActiveFocus();
            }

            function acceptSelectedWord() {
                if (suggestions.selectedIndex >= 0 && suggestions.selectedIndex < suggestionRepeater.count) {
                    const word = root.suggestionList[suggestions.selectedIndex].name;
                    suggestions.acceptSuggestion(word);
                }
            }
        }

        Rectangle { // Input area
            id: inputWrapper
            property real spacing: Appearance.spacing.space100
            Layout.fillWidth: true
            radius: Appearance.rounding.normal - root.padding
            color: Appearance.colors.colLayer2
            implicitHeight: Math.max(inputFieldRowLayout.implicitHeight + inputFieldRowLayout.anchors.topMargin + commandButtonsRow.implicitHeight + commandButtonsRow.anchors.bottomMargin + spacing, 45) + (attachedFileIndicator.implicitHeight + spacing + attachedFileIndicator.anchors.topMargin)
                + (editBanner.visible ? editBanner.implicitHeight + spacing : 0)
            clip: true

            Behavior on implicitHeight {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            // The fork's composer rise: fade + de-blur + rise as the
            // choreography's last rank, after the pane's wave has landed.
            // One writer per channel: this owns opacity, blur and the
            // transform; the wave no longer dresses this surface.
            transform: Translate { id: inputWrapperRise }
            layer.enabled: inputBlur.radius > 0
            layer.effect: FastBlur { radius: inputBlur.radius }
            QtObject { id: inputBlur; property real radius: 0 }

            Connections {
                target: root
                function onEntranceTriggerChanged() {
                    if (root.entranceTrigger < 0) return;
                    inputWrapperAnim.stop();
                    inputWrapper.opacity = 0;
                    inputBlur.radius = 20;
                    inputWrapperRise.y = 40;
                    inputWrapperAnim.start();
                }
            }
            SequentialAnimation {
                id: inputWrapperAnim
                PauseAnimation { duration: Appearance.animation.scale(320) }
                ParallelAnimation {
                    NumberAnimation { target: inputWrapper; property: "opacity"; to: 1; duration: Appearance.animation.scale(320); easing.type: Easing.OutCubic }
                    NumberAnimation { target: inputBlur; property: "radius"; to: 0; duration: Appearance.animation.scale(350); easing.type: Easing.OutCubic }
                    NumberAnimation { target: inputWrapperRise; property: "y"; to: 0; duration: Appearance.animation.scale(450); easing.type: Easing.OutExpo }
                }
            }

            RowLayout { // The takeback banner: says the mode, names the exit.
                id: editBanner
                visible: root.editingMessageIndex >= 0
                anchors {
                    top: attachedFileIndicator.bottom
                    left: parent.left
                    right: parent.right
                    topMargin: visible ? Appearance.spacing.space50 : 0
                    leftMargin: Appearance.spacing.space150
                    rightMargin: Appearance.spacing.space150
                }
                spacing: Appearance.spacing.space50
                MaterialSymbol {
                    text: "edit_note"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: Translation.tr("Editing a question - Enter resends as a new chat, Esc cancels")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }

            AttachedFileIndicator {
                id: attachedFileIndicator
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    margins: visible ? 5 : 0
                }
                filePath: Ai.pendingFilePath
                onRemove: Ai.attachFile("")
            }

            RowLayout { // Input field and send button
                id: inputFieldRowLayout
                anchors {
                    bottom: commandButtonsRow.top
                    left: parent.left
                    right: parent.right
                    bottomMargin: Appearance.spacing.space100
                }
                spacing: 0

                ScrollView {
                    id: inputScrollView
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(root.height * 3/5, messageInputField.height)
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded

                    StyledTextArea { // The actual TextArea (inside ScrollView to enable scrolling)
                        id: messageInputField
                        anchors.fill: parent
                        wrapMode: TextArea.Wrap
                        padding: Appearance.spacing.space150
                        color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                        placeholderText: Translation.tr('Message the model... "%1" for commands').arg(root.commandPrefix)

                        background: null

                        onTextChanged: {
                            // The draft survives (spec 2026-08-31); the
                            // takeback edit records nothing while active.
                            if (root.editingMessageIndex < 0)
                                AiDrafts.record(AiSessions.currentId, messageInputField.text);
                            // Handle suggestions
                            if (messageInputField.text.length === 0) {
                                root.suggestionQuery = "";
                                root.suggestionList = [];
                                return;
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}model`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const modelResults = Fuzzy.go(root.suggestionQuery, Ai.modelList.map(model => {
                                    return {
                                        name: Fuzzy.prepare(model),
                                        obj: model
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = modelResults.map(model => {
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "model ") : ""}${model.target}`,
                                        displayName: `${Ai.models[model.target].name}`,
                                        description: `${Ai.models[model.target].description}`
                                    };
                                });
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}prompt`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const promptFileResults = Fuzzy.go(root.suggestionQuery, Ai.promptFiles.map(file => {
                                    return {
                                        name: Fuzzy.prepare(file),
                                        obj: file
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = promptFileResults.map(file => {
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "prompt ") : ""}${file.target}`,
                                        displayName: `${FileUtils.trimFileExt(FileUtils.fileNameForPath(file.target))}`,
                                        description: Translation.tr("Load prompt from %1").arg(file.target)
                                    };
                                });
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}save`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const promptFileResults = Fuzzy.go(root.suggestionQuery, Ai.savedChats.map(file => {
                                    return {
                                        name: Fuzzy.prepare(file),
                                        obj: file
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = promptFileResults.map(file => {
                                    const chatName = FileUtils.trimFileExt(FileUtils.fileNameForPath(file.target)).trim();
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "save ") : ""}${chatName}`,
                                        displayName: `${chatName}`,
                                        description: Translation.tr("Save chat to %1").arg(chatName)
                                    };
                                });
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}load`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const promptFileResults = Fuzzy.go(root.suggestionQuery, Ai.savedChats.map(file => {
                                    return {
                                        name: Fuzzy.prepare(file),
                                        obj: file
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = promptFileResults.map(file => {
                                    const chatName = FileUtils.trimFileExt(FileUtils.fileNameForPath(file.target)).trim();
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "load ") : ""}${chatName}`,
                                        displayName: `${chatName}`,
                                        description: Translation.tr(`Load chat from %1`).arg(file.target)
                                    };
                                });
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}tool`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const toolResults = Fuzzy.go(root.suggestionQuery, Ai.availableTools.map(tool => {
                                    return {
                                        name: Fuzzy.prepare(tool),
                                        obj: tool
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = toolResults.map(tool => {
                                    const toolName = tool.target;
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "tool ") : ""}${tool.target}`,
                                        displayName: toolName,
                                        description: Ai.toolDescriptions[toolName]
                                    };
                                });
                            } else if (messageInputField.text.startsWith(root.commandPrefix)) {
                                root.suggestionQuery = messageInputField.text;
                                root.suggestionList = root.allCommands.filter(cmd => cmd.name.startsWith(messageInputField.text.substring(1))).map(cmd => {
                                    return {
                                        name: `${root.commandPrefix}${cmd.name}`,
                                        description: `${cmd.description}`
                                    };
                                });
                            }
                        }

                        function accept() {
                            root.acceptComposer(text);
                            text = "";
                        }

                        Keys.onPressed: event => {
                            // These live HERE, not on the pane root: the
                            // TextArea holds focus and consumes modified
                            // arrows internally, so root arms never fire.
                            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_R) {
                                root.regenerateLastAnswer();
                                event.accepted = true;
                                return;
                            }
                            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Up
                                    && messageInputField.text.length === 0) {
                                root.editLastQuestion();
                                event.accepted = true;
                                return;
                            }
                            if (event.key === Qt.Key_Tab) {
                                suggestions.acceptSelectedWord();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Up && suggestions.visible) {
                                suggestions.selectedIndex = Math.max(0, suggestions.selectedIndex - 1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Down && suggestions.visible) {
                                suggestions.selectedIndex = Math.min(root.suggestionList.length - 1, suggestions.selectedIndex + 1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Up && event.modifiers === Qt.NoModifier
                                    && root.editingMessageIndex < 0
                                    && (messageInputField.text.length === 0 || root.promptHistoryState.index !== -1)) {
                                // Shell-style recall - only from an empty
                                // draft, so cursor movement in a real
                                // multi-line message is never hijacked.
                                if (root.stepPromptHistory(-1)) event.accepted = true;
                            } else if (event.key === Qt.Key_Down && event.modifiers === Qt.NoModifier
                                    && root.editingMessageIndex < 0
                                    && root.promptHistoryState.index !== -1) {
                                if (root.stepPromptHistory(1)) event.accepted = true;
                            } else if ((event.key === Qt.Key_Enter || event.key === Qt.Key_Return)) {
                                if (event.modifiers & Qt.ShiftModifier) {
                                    // Insert newline
                                    messageInputField.insert(messageInputField.cursorPosition, "\n");
                                    event.accepted = true;
                                } else {
                                    // Accept text
                                    const inputText = messageInputField.text;
                                    messageInputField.clear();
                                    root.acceptComposer(inputText);
                                    event.accepted = true;
                                }
                            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                                // Intercept Ctrl+V to handle image/file pasting
                                if (event.modifiers & Qt.ShiftModifier) {
                                    // Let Shift+Ctrl+V = plain paste
                                    messageInputField.text += Quickshell.clipboardText;
                                    event.accepted = true;
                                    return;
                                }
                                // Try image paste first
                                const currentClipboardEntry = Cliphist.entries[0];
                                const cleanCliphistEntry = StringUtils.cleanCliphistEntry(currentClipboardEntry);
                                if (/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(currentClipboardEntry)) {
                                    // First entry = currently copied entry = image?
                                    decodeImageAndAttachProc.handleEntry(currentClipboardEntry);
                                    event.accepted = true;
                                    return;
                                } else if (cleanCliphistEntry.startsWith("file://")) {
                                    // First entry = currently copied entry = image?
                                    const fileName = decodeURIComponent(cleanCliphistEntry);
                                    Ai.attachFile(fileName);
                                    event.accepted = true;
                                    return;
                                }
                                event.accepted = false; // No image, let text pasting proceed
                            } else if (event.key === Qt.Key_Escape) {
                                if (root.editingMessageIndex >= 0) {
                                    // Cancel the takeback before Escape can
                                    // mean detach-file.
                                    root.cancelEdit();
                                    event.accepted = true;
                                } else if (Ai.pendingFilePath.length > 0) {
                                    Ai.attachFile("");
                                    event.accepted = true;
                                } else {
                                    event.accepted = false;
                                }
                            }
                        }
                    }
                }
                RippleButton { // Send button
                    id: sendButton
                    Layout.alignment: Qt.AlignBottom
                    Layout.rightMargin: Appearance.spacing.space100
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.small
                    // While generating this is the STOP control (M3's send
                    // morph) - the one way to end a runaway answer.
                    enabled: messageInputField.text.length > 0 || Ai.isGenerating
                    toggled: enabled

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: sendButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (Ai.isGenerating) {
                                Ai.stopGeneration();
                                return;
                            }
                            const inputText = messageInputField.text;
                            root.acceptComposer(inputText);
                            messageInputField.clear();
                        }
                    }

                    contentItem: MaterialSymbol {
                        verticalAlignment: Text.AlignVCenter
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: 22
                        color: sendButton.enabled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2Disabled
                        text: Ai.isGenerating ? "stop" : "arrow_upward"
                    }
                }
            }

            RowLayout { // Controls
                id: commandButtonsRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Appearance.spacing.space100
                anchors.leftMargin: Appearance.spacing.space150
                anchors.rightMargin: Appearance.spacing.space100
                spacing: Appearance.spacing.space50

                StyledComboBox { // The model picker lives at the composer now.
                    id: modelPicker
                    Layout.fillWidth: false
                    Layout.preferredWidth: Math.min(implicitWidth, 190)
                    Layout.minimumWidth: 0
                    implicitHeight: 28
                    // Model names are long; the menu opens wider than the
                    // compact button so they read whole.
                    popupWidth: 260
                    buttonIcon: "network_intelligence"
                    textRole: "name"
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colBackgroundActive: Appearance.colors.colLayer2Active
                    model: Ai.pickerModelList.map(id => ({ name: Ai.models[id]?.name ?? id, value: id }))
                        .concat([{ name: Translation.tr("Browse models…"), value: "__browse__" }])
                    currentIndex: Ai.pickerModelList.indexOf(Ai.currentModelId)
                    // First use / a stale persisted id: nothing selected, and
                    // a blank button reads as broken.
                    displayText: modelPicker.currentIndex < 0
                        ? Translation.tr("Select model")
                        : (modelPicker.model[modelPicker.currentIndex]?.name ?? "")
                    onActivated: index => {
                        const chosen = modelPicker.model[index];
                        if (!chosen) return;
                        if (chosen.value === "__browse__") {
                            root.openView("browse", "");
                            modelPicker.currentIndex = Ai.pickerModelList.indexOf(Ai.currentModelId);
                            return;
                        }
                        Ai.setModel(chosen.value);
                    }
                    // A pick writes currentIndex and destroys the binding, so
                    // the /model command path resyncs it here.
                    Connections {
                        target: Ai
                        function onCurrentModelIdChanged() {
                            modelPicker.currentIndex = Ai.pickerModelList.indexOf(Ai.currentModelId);
                        }
                    }
                }

                ApiInputBoxIndicator {
                    // Tool indicator
                    icon: "service_toolbox"
                    text: Ai.currentTool.charAt(0).toUpperCase() + Ai.currentTool.slice(1)
                    tooltipText: Translation.tr("Current tool: %1\nSet it with %2tool TOOL").arg(Ai.currentTool).arg(root.commandPrefix)
                }

                Item {
                    Layout.fillWidth: true
                }
            }
        }
    }
}
