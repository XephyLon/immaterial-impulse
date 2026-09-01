import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.panels.lock
import qs.modules.imi.bar as Bar
import Quickshell
import Quickshell.Services.SystemTray
import "../../common/functions/lock_islands.js" as LockIslands
import "../../common/functions/media_art.js" as MediaArt

MouseArea {
    id: root
    required property QtObject context
    property bool active: false
    // The one switch between the real lock screen and Edit Mode's preview of
    // it (spec §4.3). While false, nothing on this surface may take a
    // keystroke or dispatch a session action: forceFieldFocus returns before
    // reaching the field, the field itself is disabled and readOnly, the root
    // area stops taking presses, and every click handler returns first thing.
    // The guards are uniform on purpose - every handler starts with the same
    // line - so tests/test_lock_preview_contract.py can hold ALL of them to it
    // rather than an allowlist of the ones somebody remembered.
    //
    // `context` is typed QtObject rather than LockContext for the same reason:
    // the preview hands in LockPreviewContext, a separate component with the
    // same property surface that cannot authenticate, instead of the real
    // context with a flag on it.
    property bool interactive: true
    property bool showInputField: active || context.currentText.length > 0
    readonly property bool requirePasswordToPower: Config.options.lock.security.requirePasswordToPower
    readonly property MprisPlayer activePlayer: MprisController.activePlayer

    property var    artUrl:      MediaArt.resolve(activePlayer?.trackArtUrl ?? "", activePlayer?.metadata)

    // ---- the islands' contents, as data --------------------------------
    //
    // Spec §14, answered "reorder": each island renders its stored order
    // through the one resolver, so a list written by an older shell still
    // shows a later version's items at their default positions, and a list
    // written by a newer shell loses nothing on the way through this one.
    // The Repeaters below model these, never the stored lists directly.
    readonly property var mainOrder: LockIslands.orderedItems(
        Config.options.lock.islands.main, LockIslands.MAIN_DEFAULT)
    readonly property var leftOrder: LockIslands.orderedItems(
        Config.options.lock.islands.left, LockIslands.LEFT_DEFAULT)
    readonly property var rightOrder: LockIslands.orderedItems(
        Config.options.lock.islands.right, LockIslands.RIGHT_DEFAULT)

    // One filter, shared by the fcitx slot's visibility and the component
    // that draws it, so the two cannot disagree about what counts as present.
    readonly property var fcitxItems: SystemTray.items.values.filter(i => i.id == "Fcitx")

    // Which component draws each id. An id missing here would render as an
    // empty slot - the Loader resolves null and draws nothing - which is why
    // tests/test_lock_islands_contract.py holds this map to the module's
    // whole default vocabulary.
    readonly property var islandComponents: ({
        fingerprint: fingerprintComponent,
        password: passwordComponent,
        confirm: confirmComponent,
        username: usernameComponent,
        media: mediaComponent,
        keyboardLayout: keyboardLayoutComponent,
        fcitx: fcitxComponent,
        battery: batteryComponent,
        sleep: sleepComponent,
        power: powerComponent,
        reboot: rebootComponent
    })

    // Each item's Layout facts, which used to live as attached properties on
    // the hand-placed children. They move to the slot Loader because a Layout
    // only honours attached properties on its DIRECT children, and the slot
    // is the direct child now. Held to the same vocabulary as the components
    // by the contract, since a missing entry is not an error - it is a margin
    // of 0 that reads as a design choice.
    readonly property var islandItemMeta: ({
        fingerprint: { leftMargin: Appearance.spacing.space150, rightMargin: Appearance.spacing.space100 },
        password: { fillHeight: true },
        confirm: { fillHeight: true },
        username: { leftMargin: Appearance.spacing.space100, rightMargin: Appearance.spacing.space150, fillHeight: true },
        media: { leftMargin: Appearance.spacing.space25, rightMargin: Appearance.spacing.space25 },
        keyboardLayout: { rightMargin: Appearance.spacing.space100, fillHeight: true },
        fcitx: { rightMargin: Appearance.spacing.space150 },
        battery: { leftMargin: Appearance.spacing.space150, rightMargin: Appearance.spacing.space150, fillHeight: true },
        sleep: { fillHeight: true },
        power: { fillHeight: true },
        reboot: { fillHeight: true }
    })

    // The per-item visibility the hand-placed children carried, unchanged in
    // meaning: visibility stays per item, order is the list - the lists and
    // the lock.show* booleans divide the work rather than fighting over it.
    function islandItemActive(id) {
        if (id === "fingerprint") return root.context.fingerprintsConfigured === true;
        if (id === "media") return MprisController.activePlayer !== null;
        return true;
    }

    function islandItemVisible(id) {
        if (id === "username" || id === "keyboardLayout")
            return !Config.options.lock.showMedia || MprisController.activePlayer === null;
        if (id === "media") return Config.options.lock.showMedia;
        if (id === "fcitx") return root.fcitxItems.length > 0;
        if (id === "battery") return Battery.available;
        return true;
    }

    // One slot shape for all three islands: the Loader is the layout's direct
    // child, so it carries the Layout facts, the active/visible gates and the
    // component resolution; the loaded item keeps drawing exactly what the
    // hand-placed child drew. In the preview, in the mode, a movable slot
    // additionally hosts the reorder overlay - never the password field,
    // which is the module's rule rather than this file's.
    component IslandSlot: Loader {
        id: slot
        required property int index
        required property string modelData
        objectName: "islandSlot_" + slot.modelData
        property string island: ""
        property var reorder: null
        readonly property var meta: root.islandItemMeta[slot.modelData] ?? ({})
        Layout.alignment: Qt.AlignVCenter
        Layout.leftMargin: slot.meta.leftMargin ?? 0
        Layout.rightMargin: slot.meta.rightMargin ?? 0
        Layout.fillHeight: slot.meta.fillHeight === true
        active: root.islandItemActive(slot.modelData)
        visible: slot.active && root.islandItemVisible(slot.modelData)
        sourceComponent: root.islandComponents[slot.modelData] ?? null
        // The gesture's dim: "this one is moving", on the slot rather than on
        // a ghost - island items carry no catalogued display name to put on a
        // chip, and the dim plus the indicator says everything a chip would.
        opacity: (editOverlay.item?.dragging ?? false) ? 0.4 : 1

        Loader {
            id: editOverlay
            anchors.fill: parent
            z: 2
            active: !root.interactive && GlobalStates.editMode
                && LockIslands.reorderable(slot.island, slot.modelData)
            sourceComponent: LockIslandEditItem {
                controller: slot.reorder
                renderedIndex: slot.index
            }
        }
    }

    // The field lives inside a delegate component now, so the surface reaches
    // it through this property rather than an id that no longer resolves at
    // file scope. Null while the main island has not built (or is rebuilt by
    // a reorder), which forceFieldFocus already tolerates.
    property Item passwordField: null

    // Force focus on entry
    function forceFieldFocus() {
        if (!root.interactive) return;
        root.passwordField?.forceActiveFocus();
    }
    Connections {
        target: context
        function onShouldReFocus() {
            forceFieldFocus();
        }
    }
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    // MouseArea's own `enabled`, which stops this area alone: the preview must
    // not focus-chase the pointer or swallow clicks over the whole screen -
    // the desktop being edited is underneath. The islands' own controls keep
    // their input and are gated handler by handler instead, because disabling
    // the whole subtree would run every control's disabled dim at once and the
    // preview would stop looking like the lock screen it previews.
    enabled: root.interactive
    onPressed: mouse => {
        forceFieldFocus();
    }
    onPositionChanged: mouse => {
        forceFieldFocus();
    }

    // Toolbar appearing animation
    property real toolbarScale: 0.9
    property real toolbarOpacity: 0
    Behavior on toolbarScale {
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
        }
    }
    Behavior on toolbarOpacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    // Init
    Component.onCompleted: {
        forceFieldFocus();
        toolbarScale = 1;
        toolbarOpacity = 1;
    }

    // Key presses
    property bool ctrlHeld: false
    Keys.onPressed: event => {
        if (!root.interactive) return;
        root.context.resetClearTimer();
        if (event.key === Qt.Key_Control) {
            root.ctrlHeld = true;
        }
        if (event.key === Qt.Key_Escape) { // Esc to clear
            root.context.currentText = "";
        }
        forceFieldFocus();
    }
    Keys.onReleased: event => {
        if (!root.interactive) return;
        if (event.key === Qt.Key_Control) {
            root.ctrlHeld = false;
        }
        forceFieldFocus();
    }

    // Main toolbar: password box
    Toolbar {
        id: mainIsland
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: Appearance.spacing.space250
        }
        Behavior on anchors.bottomMargin {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        scale: root.toolbarScale
        opacity: root.toolbarOpacity

        Repeater {
            id: mainRepeater
            model: root.mainOrder
            delegate: IslandSlot {
                island: "main"
                reorder: mainReorder
            }
        }
    }

    // Left toolbar
    Toolbar {
        id: leftIsland
        visible: Config.options.lock.showToolbars
        anchors {
            right: mainIsland.left
            top: mainIsland.top
            bottom: mainIsland.bottom
            rightMargin: Appearance.spacing.space150
        }
        scale: root.toolbarScale
        opacity: root.toolbarOpacity

        Repeater {
            id: leftRepeater
            model: root.leftOrder
            delegate: IslandSlot {
                island: "left"
                reorder: leftReorder
            }
        }
    }

    // Right toolbar
    Toolbar {
        id: rightIsland
        visible: Config.options.lock.showToolbars
        anchors {
            left: mainIsland.right
            top: mainIsland.top
            bottom: mainIsland.bottom
            leftMargin: Appearance.spacing.space150
        }

        scale: root.toolbarScale
        opacity: root.toolbarOpacity

        Repeater {
            id: rightRepeater
            model: root.rightOrder
            delegate: IslandSlot {
                island: "right"
                reorder: rightReorder
            }
        }
    }

    // ---- the reorder coordinators, one per island ------------------------
    //
    // Full-surface siblings of the islands so their drop indicators can be
    // drawn in surface coordinates over any slot. One per island rather than
    // one with three buckets, deliberately: each island's vocabulary is its
    // own defaults, and a cross-island move would write an id the receiving
    // island's resolver (correctly) skips as unknown - the item would vanish
    // from both. See LockIslandReorder for the rest of the reasoning.
    LockIslandReorder {
        id: mainReorder
        anchors.fill: parent
        island: "main"
        orderedIds: root.mainOrder
        repeater: mainRepeater
        islandItem: mainIsland
    }
    LockIslandReorder {
        id: leftReorder
        anchors.fill: parent
        island: "left"
        orderedIds: root.leftOrder
        repeater: leftRepeater
        islandItem: leftIsland
    }
    LockIslandReorder {
        id: rightReorder
        anchors.fill: parent
        island: "right"
        orderedIds: root.rightOrder
        repeater: rightRepeater
        islandItem: rightIsland
    }

    // ---- the items, one component per id --------------------------------

    Component {
        id: fingerprintComponent
        MaterialSymbol {
            fill: 1
            text: "fingerprint"
            iconSize: Appearance.font.pixelSize.hugeass
            color: Appearance.colors.colOnSurfaceVariant
        }
    }

    Component {
        id: passwordComponent
        PasswordField {
            id: passwordBox
            materialShapeChars: passwordBox.masked && Config.options.lock.materialShapeChars
            placeholderText: GlobalStates.screenUnlockFailed ? Translation.tr("Incorrect password") : Translation.tr("Enter password")

            // The pull as well as the publication: a slot rebuild (a reorder
            // committing, an external write to the main list) creates a
            // fresh field, and one that only followed onCurrentTextChanged
            // would show empty over a context still holding text - then
            // overwrite that text with the next keystroke alone.
            Component.onCompleted: {
                root.passwordField = passwordBox;
                passwordBox.text = root.context.currentText;
            }
            Component.onDestruction: if (root.passwordField === passwordBox) root.passwordField = null

            // Style
            font.pixelSize: Appearance.font.pixelSize.small

            // Password. Both halves of the preview gate on purpose: `enabled`
            // stops pointer and key input, `readOnly` closes the programmatic
            // paths a disabled field still leaves open.
            enabled: !root.context.unlockInProgress && root.interactive
            readOnly: !root.interactive

            // Synchronizing (across monitors) and unlocking
            onTextChanged: root.context.currentText = this.text
            // Guarded like every other dispatch even though `enabled: false`
            // already keeps key events out of a preview field: `accepted()`
            // is raised from Return handling, which `readOnly` does NOT close
            // (readOnly stops text mutation, not the signal), so this is the
            // one belt the disabled field wears alone - and the contract's
            // action-anchored sweep holds it to the guard by the dispatch
            // rather than by the handler's name.
            onAccepted: {
                if (!root.interactive) return;
                root.context.tryUnlock(ctrlHeld);
            }
            Connections {
                target: root.context
                function onCurrentTextChanged() {
                    passwordBox.text = root.context.currentText;
                }
            }

            Keys.onPressed: event => {
                if (!root.interactive) return;
                root.context.resetClearTimer();
            }

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: passwordBox.width - 8
                    height: passwordBox.height
                    radius: height / 2
                }
            }

            // Shake when wrong password
            ErrorShakeAnimation {
                id: wrongPasswordShakeAnim
                target: passwordBox
            }
            Connections {
                target: GlobalStates
                function onScreenUnlockFailedChanged() {
                    if (GlobalStates.screenUnlockFailed) wrongPasswordShakeAnim.restart();
                }
            }
        }
    }

    Component {
        id: confirmComponent
        ToolbarButton {
            id: confirmButton
            implicitWidth: height
            toggled: true
            enabled: !root.context.unlockInProgress
            colBackgroundToggled: Appearance.colors.colPrimary

            onClicked: {
                if (!root.interactive) return;
                root.context.tryUnlock();
            }

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                iconSize: 24
                text: {
                    if (root.context.targetAction === LockContext.ActionEnum.Unlock) {
                        return root.ctrlHeld ? "coffee" : "arrow_right_alt";
                    } else if (root.context.targetAction === LockContext.ActionEnum.Poweroff) {
                        return "power_settings_new";
                    } else if (root.context.targetAction === LockContext.ActionEnum.Reboot) {
                        return "restart_alt";
                    }
                }
                color: confirmButton.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
            }
        }
    }

    Component {
        id: usernameComponent
        IconAndTextPair {
            icon: "account_circle"
            text: SystemInfo.username
        }
    }

    Component {
        id: mediaComponent
        Item {
            implicitWidth: mediaRow.implicitWidth
            implicitHeight: mediaRow.implicitHeight

            readonly property MprisPlayer activePlayer: MprisController.activePlayer
            readonly property string cleanedTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle) || ""

            Timer {
                running: activePlayer?.playbackState == MprisPlaybackState.Playing
                interval: Config.options.resources.updateInterval
                repeat: true
                onTriggered: activePlayer.positionChanged()
            }

            // Compact playback controls for the lock-screen media widget.
            component LockMediaButton: MouseArea {
                property string icon
                property bool ctlEnabled: true
                implicitWidth: 28
                implicitHeight: 28
                enabled: ctlEnabled
                opacity: ctlEnabled ? 1 : 0.4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                Layout.alignment: Qt.AlignVCenter
                MaterialSymbol {
                    anchors.centerIn: parent
                    fill: 1
                    text: parent.icon
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }

            RowLayout {
                id: mediaRow
                spacing: Appearance.spacing.space100
                anchors.centerIn: parent

                Rectangle {
                    id: artRect
                    implicitWidth: 40
                    implicitHeight: 40
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colPrimaryContainer
                    Layout.alignment: Qt.AlignVCenter
                    clip: true

                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: artRect.width
                            height: artRect.height
                            radius: artRect.radius
                        }
                    }

                    StyledImage {
                        anchors.centerIn: parent
                        width: artRect.width
                        height: artRect.height
                        source: root.artUrl
                        fillMode: Image.PreserveAspectCrop
                        cache: false
                        antialiasing: true
                        sourceSize.width: artRect.width * 2
                        sourceSize.height: artRect.height * 2
                        visible: root.artUrl !== ""
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        fill: 1
                        text: "music_note"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnSecondaryContainer
                        visible: root.artUrl === ""
                    }
                }

                Column {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: -Appearance.spacing.space25

                    StyledText {
                        horizontalAlignment: Text.AlignLeft
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        width: Math.min(implicitWidth, 180)
                        color: Appearance.colors.colOnSurfaceVariant
                        text: {
                            var artist = activePlayer?.trackArtist || " ";
                            return artist.length > 25 ? artist.substring(0, 25) + "..." : artist;
                        }
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }

                    StyledText {
                        horizontalAlignment: Text.AlignLeft
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        width: Math.min(implicitWidth, 180)
                        color: Appearance.colors.colOnSurfaceVariant
                        text: {
                            var title = cleanedTitle;
                            return title.length > 30 ? title.substring(0, 30) + "..." : title;
                        }
                        font.weight: Font.Medium
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Appearance.spacing.space25

                    LockMediaButton {
                        icon: "skip_previous"
                        ctlEnabled: MprisController.canGoPrevious
                        onClicked: {
                            if (!root.interactive) return;
                            MprisController.previous();
                        }
                    }
                    LockMediaButton {
                        icon: activePlayer?.isPlaying ? "pause" : "play_arrow"
                        onClicked: {
                            if (!root.interactive) return;
                            MprisController.togglePlaying();
                        }
                    }
                    LockMediaButton {
                        icon: "skip_next"
                        ctlEnabled: MprisController.canGoNext
                        onClicked: {
                            if (!root.interactive) return;
                            MprisController.next();
                        }
                    }
                }

                ClippedFilledCircularProgress {
                    id: mediaCircProg
                    Layout.alignment: Qt.AlignVCenter
                    lineWidth: Appearance.rounding.unsharpen
                    value: activePlayer?.position / activePlayer?.length
                    implicitSize: 24
                    colPrimary: Appearance.colors.colOnSurfaceVariant
                    enableAnimation: false

                    Item {
                        anchors.centerIn: parent
                        width: mediaCircProg.implicitSize
                        height: mediaCircProg.implicitSize

                        MaterialSymbol {
                            anchors.centerIn: parent
                            fill: 1
                            text: "music_note"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }
            }
        }
    }

    Component {
        id: keyboardLayoutComponent
        Row {
            spacing: Appearance.spacing.space100

            MaterialSymbol {
                id: keyboardIcon
                anchors.verticalCenter: parent.verticalCenter
                fill: 1
                text: "keyboard_alt"
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colOnSurfaceVariant
            }
            Loader {
                anchors.verticalCenter: parent.verticalCenter
                sourceComponent: StyledText {
                    text: HyprlandXkb.currentLayoutCode
                    color: Appearance.colors.colOnSurfaceVariant
                    animateChange: true
                }
            }
        }
    }

    Component {
        id: fcitxComponent
        // `enabled` cascades from SysTray's plain Item root, so the preview's
        // copy cannot activate the real SNI item - the one interactive element
        // in the islands that reaches outside the shell.
        Bar.SysTray {
            enabled: root.interactive
            showSeparator: false
            showOverflowMenu: false
            pinnedItems: root.fcitxItems
        }
    }

    Component {
        id: batteryComponent
        IconAndTextPair {
            icon: Battery.isCharging ? "bolt" : "battery_android_full"
            text: Math.round(Battery.percentage * 100)
            color: (Battery.isLow && !Battery.isCharging) ? Appearance.colors.colError : Appearance.colors.colOnSurfaceVariant
        }
    }

    Component {
        id: sleepComponent
        IconToolbarButton {
            onClicked: {
                if (!root.interactive) return;
                Session.suspend();
            }
            text: "dark_mode"
        }
    }

    Component {
        id: powerComponent
        PasswordGuardedIconToolbarButton {
            text: "power_settings_new"
            targetAction: LockContext.ActionEnum.Poweroff
        }
    }

    Component {
        id: rebootComponent
        PasswordGuardedIconToolbarButton {
            text: "restart_alt"
            targetAction: LockContext.ActionEnum.Reboot
        }
    }

    component PasswordGuardedIconToolbarButton: IconToolbarButton {
        id: guardedBtn
        required property var targetAction

        toggled: root.context.targetAction === guardedBtn.targetAction

        onClicked: {
            if (!root.interactive) return;
            if (!root.requirePasswordToPower) {
                root.context.unlocked(guardedBtn.targetAction);
                return;
            }
            if (root.context.targetAction === guardedBtn.targetAction) {
                root.context.resetTargetAction();
            } else {
                root.context.targetAction = guardedBtn.targetAction;
                root.context.shouldReFocus();
            }
        }
    }

    component IconAndTextPair: Row {
        id: pair
        required property string icon
        required property string text
        property color color: Appearance.colors.colOnSurfaceVariant

        spacing: Appearance.spacing.space50

        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            fill: 1
            text: pair.icon
            iconSize: Appearance.font.pixelSize.huge
            animateChange: true
            color: pair.color
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: pair.text
            color: pair.color
        }
    }
}
