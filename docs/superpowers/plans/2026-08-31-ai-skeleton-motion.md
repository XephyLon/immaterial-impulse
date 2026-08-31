# AI Chat Skeleton & Motion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Intelligence tab becomes the fork's three-surface instrument - chip tools bar, chat area, composer - with entrance choreography, transcript reveal, a rolled greeting and an EmptyStateKey rail, on imi tokens.

**Architecture:** `AiChat.qml` restructures into three `colLayer1` surfaces; a new `ChatControlBar` absorbs the floating status pill as chips that pre-fill commands (the popover canvas deliberately waits for sub-project 2); one `entranceTrigger` drives the composer rise/blur and a `transcriptRevealToken` staggers in-view messages, consumed by `AiMessage`. Spec: `docs/superpowers/specs/2026-08-31-ai-skeleton-motion-design.md`.

**Tech Stack:** QML (Quickshell), python contract tests (`contract_runner`), qmllint. Paths relative to `dots/.config/quickshell/imi/` unless starting with `docs/`.

**Conventions that bind every task:** commit with `git commit --only -F - -- <paths>` (new files need `git add -N` first); no Claude/agent attribution; comments explain *why*; run only the named tests, never `run_tests.sh` (suite is parked).

**Facts verified at plan time:** imi's `PagePlaceholder` has `shown/icon/title/description/shape` only (no entranceTrigger - the glyph-grow already lives in AiChat and stays); `StyledText` has `animateChange`; the commands row's `ApiInputBoxIndicator`s (model/tool) STAY - only the floating `statusBg` pill and its root-level `StatusItem`/`StatusSeparator` components dissolve into the bar; `Config.qml` `sidebar` > `JsonObject ai` (~line 1496, holding `textFadeIn`) takes the `greeting` key; fork composer entrance numbers: pause 320, fade 320 OutCubic, blur 20→0 350 OutCubic, rise 40→0 450 OutExpo; fork message arrival rise is `Appearance.rounding.verysmall`.

**Structural pins land in Task 4** (after the structure exists): the surfaces are not unit-testable headless, so the pins are the regression net, not the TDD driver - stated rather than pretended otherwise.

---

### Task 1: the components

**Files:**
- Create: `modules/imi/sidebarLeft/aiChat/ChatControlBar.qml`
- Create: `modules/imi/sidebarLeft/aiChat/EmptyStateKey.qml`

- [ ] **Step 1: Write `ChatControlBar.qml`**

```qml
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The AI pane's tools bar (spec 2026-08-31): the fork's ControlChip grammar
 * on imi tokens. The floating status pill's content lives here now.
 *
 * THE BRIDGE, stated: no popover views in this sub-project. A chip
 * pre-fills its command into the input field and the existing suggestion
 * flow answers; the caret and this file's seams are what the sessions
 * drawer (sub-project 2) fills with the slide-in canvas. This is a module
 * component beside AiMessage, not a shared widget - reading Ai directly
 * is its job.
 */
Item {
    id: root

    property var inputField: null
    property string commandPrefix: "/"

    /** Below this the chips drop their labels and keep icons and values. */
    readonly property bool compact: root.width < 340

    implicitHeight: 32

    function prefill(command) {
        if (!root.inputField) return;
        root.inputField.text = command;
        root.inputField.cursorPosition = root.inputField.text.length;
        root.inputField.forceActiveFocus();
    }

    component ControlChip: RippleButton {
        id: chip
        property string chipIcon: ""
        property string label: ""
        property string value: ""
        property string hint: ""
        property bool caret: false
        property bool alwaysLabel: false
        /** An informational chip: keeps its ink and tooltip, drops the ripple. */
        property bool inert: false
        property color chipInk: Appearance.colors.colOnLayer1
        readonly property bool showLabel: (chip.alwaysLabel || !root.compact) && chip.label.length > 0

        Layout.alignment: Qt.AlignVCenter
        implicitHeight: 32
        implicitWidth: chipContent.implicitWidth + Appearance.spacing.space200 * 2
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: chip.inert ? Appearance.colors.colLayer2 : Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        rippleEnabled: !chip.inert

        contentItem: RowLayout {
            id: chipContent
            anchors.centerIn: parent
            spacing: Appearance.spacing.space50

            MaterialSymbol {
                text: chip.chipIcon
                iconSize: Appearance.font.pixelSize.larger
                color: chip.chipInk
            }
            StyledText {
                visible: chip.showLabel
                text: chip.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: chip.chipInk
                animateChange: true
            }
            StyledText {
                visible: chip.value.length > 0
                text: chip.value
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: chip.chipInk
                animateChange: true
            }
            MaterialSymbol {
                visible: chip.caret
                text: "keyboard_arrow_down"
                iconSize: Appearance.font.pixelSize.normal
                color: chip.chipInk
                // Reserved: the sessions-drawer sub-project rotates this
                // when its view opens; the Behavior waits here so the
                // motion lands with the feature, not as a second pass.
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }

        StyledToolTip {
            text: chip.hint
            extraVisibleCondition: chip.hint.length > 0 && chip.hovered
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: Appearance.spacing.space50

        ControlChip { // Model: the name is a value, so compact keeps it.
            chipIcon: "network_intelligence"
            value: Ai.getModel()?.name ?? Translation.tr("Model")
            caret: true
            hint: Translation.tr("Current model\nSet it with %1model MODEL").arg(root.commandPrefix)
            onClicked: root.prefill(root.commandPrefix + "model ")
        }
        ControlChip {
            chipIcon: "device_thermostat"
            value: Ai.temperature.toFixed(1)
            hint: Translation.tr("Temperature\nChange with %1temp VALUE").arg(root.commandPrefix)
            onClicked: root.prefill(root.commandPrefix + "temp ")
        }
        ControlChip {
            chipIcon: Ai.currentModelHasApiKey ? "key" : "key_off"
            chipInk: Ai.currentModelHasApiKey ? Appearance.colors.colOnLayer1
                                              : Appearance.m3colors.m3error
            hint: Ai.currentModelHasApiKey
                ? Translation.tr("API key is set\nChange with %1key YOUR_API_KEY").arg(root.commandPrefix)
                : Translation.tr("No API key\nSet it with %1key YOUR_API_KEY").arg(root.commandPrefix)
            onClicked: root.prefill(root.commandPrefix + "key ")
        }
        ControlChip {
            visible: Ai.tokenCount.total > 0
            inert: true
            chipIcon: "token"
            value: `${Ai.tokenCount.total}`
            hint: Translation.tr("Total token count\nInput: %1\nOutput: %2").arg(Ai.tokenCount.input).arg(Ai.tokenCount.output)
        }

        Item { Layout.fillWidth: true }

        ControlChip {
            chipIcon: "edit_square"
            hint: Translation.tr("New chat")
            onClicked: Ai.clearMessages()
        }
    }
}
```

- [ ] **Step 2: Write `EmptyStateKey.qml`** (the fork's file on imi spacing tokens)

```qml
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * One line of the empty state: what the key is, and what it does - keycap
 * chips and a label. The fork's EmptyStateKey, its hand-typed
 * rounding-as-spacing swapped for imi's spacing scale.
 */
Rectangle {
    id: root

    property var keys: []
    property string label: ""
    /** Set when pressing the row does the same thing the key does. */
    property bool actionable: false

    signal triggered

    implicitHeight: Math.round(Appearance.font.pixelSize.huge * 1.6)
    radius: Appearance.rounding.full
    color: rowMouse.containsMouse && root.actionable ? Appearance.colors.colLayer2Hover : "transparent"

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.actionable
        cursorShape: root.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.triggered()
    }

    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Appearance.spacing.space100
        anchors.rightMargin: Appearance.spacing.space150
        spacing: Appearance.spacing.space100

        Repeater {
            model: ScriptModel {
                values: root.keys
            }

            delegate: Rectangle {
                id: keyCap
                required property var modelData

                implicitWidth: Math.max(keyCapLabel.implicitWidth + Appearance.spacing.space150,
                    root.implicitHeight * 0.66)
                implicitHeight: Math.round(root.implicitHeight * 0.66)
                radius: Appearance.rounding.verysmall
                color: Appearance.colors.colLayer2

                StyledText {
                    id: keyCapLabel
                    anchors.centerIn: parent
                    text: keyCap.modelData
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer2
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: root.label
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
}
```

- [ ] **Step 3: qmllint both** (import-path noise excluded):

```
/usr/lib/qt6/bin/qmllint -I . -I /usr/lib/qt6/qml modules/imi/sidebarLeft/aiChat/ChatControlBar.qml modules/imi/sidebarLeft/aiChat/EmptyStateKey.qml 2>&1 | grep -viE "import|was not found|unqualified|unresolved-type"
```

- [ ] **Step 4: Commit**

```bash
cd ~/dev/imi-unify
git add -N dots/.config/quickshell/imi/modules/imi/sidebarLeft/aiChat/ChatControlBar.qml \
  dots/.config/quickshell/imi/modules/imi/sidebarLeft/aiChat/EmptyStateKey.qml
git commit --only -F - -- \
  dots/.config/quickshell/imi/modules/imi/sidebarLeft/aiChat/ChatControlBar.qml \
  dots/.config/quickshell/imi/modules/imi/sidebarLeft/aiChat/EmptyStateKey.qml <<'MSG'
feat(ai): the tools bar chips and the empty state's keycap rows

The fork's ControlChip and EmptyStateKey grammar on imi tokens. Chips
pre-fill their commands into the input - the popover canvas
deliberately waits for the sessions drawer, and the caret's Behavior
waits with it so the motion lands with the feature.
MSG
```

---

### Task 2: the skeleton and the choreography

**Files:**
- Modify: `modules/imi/sidebarLeft/AiChat.qml`
- Modify: `modules/common/Config.qml` (`sidebar` > `JsonObject ai`, ~line 1496)

- [ ] **Step 1: Config key** - inside the SIDEBAR `ai` JsonObject (the one holding `textFadeIn`, NOT the top-level ai provider block):

```qml
                property JsonObject ai: JsonObject {
                    property bool textFadeIn: false
                    // Empty rolls a fresh hello per opening; set to pin one.
                    property string greeting: ""
                }
```

- [ ] **Step 2: Root additions in `AiChat.qml`** - after `property string commandPrefix: "/"`:

```qml
    // One number the opening choreography hangs off: the composer's
    // rise/blur and the transcript reveal both fire when it bumps.
    property int entranceTrigger: -1

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
    Component.onCompleted: root.refreshGreeting()
```

- [ ] **Step 3: The opening arm** - extend the existing `onSidebarLeftOpenChanged` Connections body (keep the wave + glyph-grow lines) with:

```qml
                root.entranceTrigger++;
                root.revealTranscript();
                if (emptyStatePlaceholder.shown)
                    root.refreshGreeting();
```

- [ ] **Step 4: Tools bar surface** - first child of `columnLayout`, before the messages item:

```qml
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
            }
        }
```

- [ ] **Step 5: Chat area surface** - the messages `Item` becomes a Rectangle surface and sheds the status pill:

- Change `Item {` (the one with `// Messages` and the OpacityMask) to `Rectangle {` with `id: chatAreaSurface`, `color: Appearance.colors.colLayer1`, `radius: Appearance.rounding.large`, and the mask source's `radius: Appearance.rounding.large`.
- DELETE: the `StyledRectangularShadow { target: statusBg ... }` block, the whole `Rectangle { id: statusBg ... }` block, and the root-level `component StatusItem` / `component StatusSeparator` definitions (their content lives in the control bar now).
- The list's `topMargin: statusBg.implicitHeight + ...` becomes `topMargin: Appearance.spacing.space100`; give it `bottomMargin: Appearance.spacing.space100` and `leftMargin`/`rightMargin` `Appearance.spacing.space100` so messages sit inside the surface.
- The `PagePlaceholder` empty state changes: `title: root.emptyStateGreeting`, `description: Translation.tr("Ask anything")` (the key hints move to the rail below).
- After `ScrollToBottomButton`, add the rail:

```qml
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
                        Layout.fillWidth: true
                        keys: ["/key"]
                        label: Translation.tr("Set an API key to get started")
                        actionable: true
                        onTriggered: controlBar.prefill(root.commandPrefix + "key ")
                    }
                    EmptyStateKey { Layout.fillWidth: true; keys: ["Ctrl", "O"]; label: Translation.tr("Expand the sidebar") }
                    EmptyStateKey { Layout.fillWidth: true; keys: ["Ctrl", "P"]; label: Translation.tr("Pin it open") }
                    EmptyStateKey { Layout.fillWidth: true; keys: ["Ctrl", "D"]; label: Translation.tr("Detach it into its own window") }
                }
            }
```

- [ ] **Step 6: Composer entrance** - on `Rectangle { id: inputWrapper ... }`:

- DELETE its `property real appear: 1` line (it leaves the wave; the entrance below is its one owner - two writers on opacity is the doubling the quick-toggle history warns about).
- Add, inside `inputWrapper`:

```qml
            // The fork's composer rise: fade + de-blur + rise as the
            // choreography's last rank, after the pane's wave has landed.
            // One writer per channel: this owns opacity, blur and the
            // transform; the wave no longer dresses this surface.
            opacity: 1
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
```

(`Appearance.animation.scale()` is the same scaler the glyph-grow above already uses; if a `FastBlur` layer effect needs the `Qt5Compat.GraphicalEffects` import, it is already at the top of this file.)

- [ ] **Step 7: Delegate wiring** - the message list's `delegate: AiMessage { ... }` gains:

```qml
                    transcriptRevealToken: root.transcriptRevealToken
                    transcriptRevealDelay: index * 40
```

- [ ] **Step 8: qmllint + compile sanity**

```
/usr/lib/qt6/bin/qmllint -I . -I /usr/lib/qt6/qml modules/imi/sidebarLeft/AiChat.qml 2>&1 | grep -viE "import|was not found|unqualified|unresolved-type"
```

- [ ] **Step 9: Commit**

```bash
git commit --only -F - -- \
  dots/.config/quickshell/imi/modules/imi/sidebarLeft/AiChat.qml \
  dots/.config/quickshell/imi/modules/common/Config.qml <<'MSG'
feat(ai): the three-surface skeleton and its opening choreography

Tools bar pill (the status pill's content as chips), a chat-area
surface owning transcript, greeting and the keycap rail, and the
composer leaving the wave for the fork's rise - fade, de-blur, lift -
as the choreography's last rank, one writer per channel. A greeting
rolls per opening, overridable by sidebar.ai.greeting.
MSG
```

---

### Task 3: the transcript arrival

**Files:**
- Modify: `modules/imi/sidebarLeft/aiChat/AiMessage.qml` (root Rectangle)

- [ ] **Step 1: Add the reveal consumption** - after `property bool editing: false`:

```qml
    // The opening reveal (spec 2026-08-31): the sidebar bumps the token on
    // arrival and each delegate in view runs one short entrance, ordered by
    // its visible index. handledRevealToken is what keeps a recycled
    // delegate from replaying it, and -1 outside the reveal window keeps
    // scroll-created delegates settled.
    property int transcriptRevealToken: -1
    property int transcriptRevealDelay: 0
    property int handledRevealToken: -1

    transform: Translate { id: arrivalRise }
    onTranscriptRevealTokenChanged: {
        if (root.transcriptRevealToken < 0) return;
        if (root.transcriptRevealToken === root.handledRevealToken) return;
        root.handledRevealToken = root.transcriptRevealToken;
        arrivalAnimation.stop();
        root.opacity = 0;
        arrivalRise.y = Appearance.rounding.verysmall;
        arrivalAnimation.start();
    }
    SequentialAnimation {
        id: arrivalAnimation
        PauseAnimation { duration: root.transcriptRevealDelay }
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; to: 1; duration: Appearance.animation.elementMoveEnter.duration; easing.type: Easing.OutCubic }
            NumberAnimation { target: arrivalRise; property: "y"; to: 0; duration: Appearance.animation.elementMoveEnter.duration; easing.type: Easing.OutExpo }
        }
    }
```

- [ ] **Step 2: qmllint** (same filter) and rerun the message contract if one names this file: `grep -rln "AiMessage" tests/ | head` - adapt only if a pin greps structure that moved (none known at plan time).

- [ ] **Step 3: Commit**

```bash
git commit --only -F - -- \
  dots/.config/quickshell/imi/modules/imi/sidebarLeft/aiChat/AiMessage.qml <<'MSG'
feat(ai): messages arrive with the reveal token

Each delegate in view when the sidebar's reveal token bumps runs one
fade-and-rise ordered by its visible index; a handled token keeps
recycled delegates from replaying it and -1 outside the window keeps
scroll-created rows settled.
MSG
```

---

### Task 4: pins, receipts, deploy, eyes

**Files:**
- Create: `tests/test_ai_skeleton_contract.py`
- Modify: `CHANGELOG.md` (top of `### Added`), `docs/tests-README.md`

- [ ] **Step 1: Write the pins**

`tests/test_ai_skeleton_contract.py`:

```python
#!/usr/bin/env python3
"""Source contract: the AI pane's three-surface skeleton stays composed.

The surfaces are not unit-testable headless, so these pins are the
regression net for the shapes that fail silently: a status pill quietly
reintroduced beside the chips, a second writer on the composer's entrance
channels, a chip that lost the command hint that replaced its pill.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
CHAT = ROOT / "modules/imi/sidebarLeft/AiChat.qml"
BAR = ROOT / "modules/imi/sidebarLeft/aiChat/ChatControlBar.qml"
CONFIG = ROOT / "modules/common/Config.qml"


def test_the_three_surfaces_stand_and_the_pill_is_gone():
    body = CHAT.read_text(encoding="utf-8")
    for marker in ("id: toolsBarSurface", "id: chatAreaSurface", "id: inputWrapper",
                   "ChatControlBar", "EmptyStateKey"):
        assert marker in body, f"the skeleton lost {marker}"
    for gone in ("statusBg", "component StatusItem", "component StatusSeparator"):
        assert gone not in body, f"the floating status pill crept back: {gone}"


def test_the_composer_has_one_entrance_writer():
    """The wave dressing and the rise animation both write opacity; a
    composer that is both a wave member and its own entrance doubles the
    channel - the quick-toggle grid's two-writers bug, one surface over."""
    body = CHAT.read_text(encoding="utf-8")
    wrapper = re.search(r'id: inputWrapper[\s\S]{0,600}', body).group(0)
    assert "property real appear" not in wrapper, (
        "inputWrapper is a wave member again while carrying its own entrance")
    assert "onEntranceTriggerChanged" in body, "the composer entrance is gone"


def test_the_chips_carry_the_pills_command_hints():
    body = BAR.read_text(encoding="utf-8")
    for command in ("model", "temp", "key"):
        assert f'"{command} "' in body or f"{command} MODEL" in body or f"{command} VALUE" in body or f"{command} YOUR_API_KEY" in body, (
            f"the {command} chip lost its command hint")
    assert "StyledToolTip" in body
    assert "clearMessages" in body, "the new-chat chip lost its action"


def test_the_greeting_key_exists_and_rolls():
    config = CONFIG.read_text(encoding="utf-8")
    assert re.search(r'JsonObject ai: JsonObject \{[^}]*greeting', config, re.DOTALL), (
        "sidebar.ai.greeting is gone from the schema")
    chat = CHAT.read_text(encoding="utf-8")
    assert "refreshGreeting" in chat and "greetingLines" in chat


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from contract_runner import run
    sys.exit(run(globals()))
```

- [ ] **Step 2: Run** - `python3 tests/test_ai_skeleton_contract.py` → `4/4 contract checks passed`.

- [ ] **Step 3: CHANGELOG entry (top of `### Added`)**

```markdown
- **The Intelligence tab reads as an instrument.** Three surfaces - a
  chip tools bar (model, temperature, key, tokens, new chat), the chat
  area, the composer - with an opening choreography: the pane waves in,
  the composer rises last through a de-blur, and reopening a
  conversation staggers the visible messages back onto the stage. The
  empty state greets you with a rolled hello (pin one with
  sidebar.ai.greeting) over a keycap rail of the keys worth knowing.
```

- [ ] **Step 4: docs/tests-README.md entry**

```markdown
* **AI skeleton contract (`test_ai_skeleton_contract.py`)**: the Intelligence tab's three surfaces stand (tools bar, chat area, composer), the floating status pill stays dissolved into the chips, the composer keeps exactly one entrance writer (wave membership and the rise animation may not share opacity), and the greeting key stays in the schema.
```

- [ ] **Step 5: Commit, deploy, restart**

```bash
git add -N dots/.config/quickshell/imi/tests/test_ai_skeleton_contract.py
git commit --only -F - -- dots/.config/quickshell/imi/tests/test_ai_skeleton_contract.py \
  CHANGELOG.md docs/tests-README.md <<'MSG'
docs: receipts and pins for the AI skeleton and motion
MSG
cd ~/dev/imi-unify && ./deploy-shell
qs kill -c imi; sleep 1; setsid -f qs -c imi
```

(Full restart: two new module files.)

- [ ] **Step 6: Maintainer visual pass.** Open the left sidebar's Intelligence tab: bar and chat surfaces wave in, composer rises last through the de-blur; empty state greets with a rolled line and the keycap rail; chips show model/temp/key (key chip error-inked without a key), compact on a narrow sidebar; clicking a chip pre-fills its command; with messages present, close and reopen - the visible messages stagger in; send a message mid-generation and reopen - no reveal replays. The maintainer drives; no captures without asking.

---

## Self-review notes

- Spec coverage: skeleton three surfaces (T2 S4-5), control bar + bridge + compact + tooltips (T1), status pill dissolution (T2 S5), composer entrance + one-writer (T2 S6), transcript reveal + guards (T2 S2/S7, T3), greeting + config key (T2 S1-3), EmptyStateKey rail (T1 S2, T2 S5), error states (key chip ink T1; stale model name falls to "Model" label T1), pins (T4), receipts (T4).
- Type consistency: `entranceTrigger`/`transcriptRevealToken`/`transcriptRevealDelay`/`handledRevealToken`/`refreshGreeting`/`prefill(command)` spelled identically across tasks; `controlBar.prefill` used by the rail matches T1's function.
- Verify-before-trust, inline: `Appearance.animation.scale()` existence (the glyph-grow already calls it in this same file); `FastBlur` import already present via `Qt5Compat.GraphicalEffects`; `StyledToolTip.extraVisibleCondition` spelling (used in this same file's StatusItem today). If `RippleButton` lacks `hovered` in the tooltip condition context, drop `&& chip.hovered` - StyledToolTip already gates on hover.
- Known accepted: the commands row keeps its model/tool `ApiInputBoxIndicator`s - the model appears in both bar and row this sub-project; the sessions drawer pass decides which one survives.
