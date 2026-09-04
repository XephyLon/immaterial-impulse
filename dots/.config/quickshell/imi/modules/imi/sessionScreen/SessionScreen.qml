import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    // The window is persistent now - one per screen, mapped at boot - because
    // creating it per open blocked the shell's one GUI thread ~61ms while the
    // new window got its render thread, GL context and scene graph (the
    // sidebars' measured number, and this is a screen-sized surface). Closed,
    // each window is a Top-layer surface with a null input mask, keyboard
    // focus None and nothing drawn - the bar's own idle shape. The layer is
    // promoted to Overlay only while open over a true fullscreen window
    // (the overview's #339 rule): a permanently-mapped Overlay surface would
    // hold the compositor's fullscreen fast path shut for every game.
    //
    // One surface PER SCREEN, with the open edge latching the focused
    // monitor - the overview's #297 shape, checked by
    // tests/test_persistent_surface_screen.py's SURFACES registry.
    property string targetScreen: ""
    property PanelWindow activeWindow: null

    function latchTarget() {
        root.targetScreen = WM.focusedMonitor?.name ?? "";
    }

    function windowForFocusedMonitor() {
        root.latchTarget();
        const windows = sessionWindows.instances;
        return windows.find(w => w.modelData.name === root.targetScreen)
            ?? windows[0] ?? null;
    }

    // One dispatcher at the scope: the latch is written, THEN the one target
    // opens. Per-window handlers would each read the latch with nothing
    // ordering them against it being written.
    Connections {
        target: GlobalStates
        function onSessionOpenChanged() {
            if (GlobalStates.sessionOpen) {
                SessionWarnings.refresh();
                root.activeWindow = root.windowForFocusedMonitor();
                root.activeWindow?.open();
            } else {
                root.activeWindow?.close();
            }
        }
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) {
                GlobalStates.sessionOpen = false;
            }
        }
    }

    Variants {
        id: sessionWindows
        model: Quickshell.screens

        PanelWindow { // Session menu
            id: sessionRoot
            required property ShellScreen modelData
            screen: modelData
            readonly property bool isTarget: root.activeWindow === sessionRoot
            // The content outlives the flag by exactly one exit animation -
            // the wallpaper selector's `reallyOpen` rule. The exit's
            // `finished` is what clears it.
            property bool reallyOpen: false
            property string subtitle
            property bool rebootPickerOpen: false

            function open() {
                sessionRoot.reallyOpen = true;
                sessionRoot.rebootPickerOpen = false;
                sessionRoot.subtitle = "";
                EfiBoot.refresh();
                // A persistent window is created once, at boot, without
                // keyboard focus - an open has to say where keys go, or the
                // window activates with no focus item and every key is
                // dropped (the sidebars' lesson).
                sessionLock.forceActiveFocus();
                // Park-then-enter, not enter alone: the grid is persistent
                // now, so after the first open every member is already at
                // full strength and a bare enter() would have nothing to
                // animate.
                sessionEntrance.park();
                sessionEntrance.enter();
                enterAnim.stop();
                exitAnim.stop();
                enterAnim.start();
            }

            function close() {
                enterAnim.stop();
                exitAnim.start();
            }

            function hide() {
                GlobalStates.sessionOpen = false;
            }

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:session"
            // Overlay only while open over a true fullscreen window on this
            // monitor: fullscreen windows composite above Top, so the menu
            // opened behind a game - but a mapped Overlay surface holds the
            // fullscreen fast path shut, which a session menu that is closed
            // all day may not do.
            readonly property bool monitorHasFullscreen:
                HyprlandData.fullscreenByMonitorName[sessionRoot.screen?.name ?? ""] ?? false
            WlrLayershell.layer: (GlobalStates.sessionOpen && sessionRoot.isTarget && sessionRoot.monitorHasFullscreen)
                ? WlrLayer.Overlay : WlrLayer.Top
            // Gated on being the target as well as the flag: every sibling
            // would otherwise go Exclusive on the same open and the
            // compositor would pick which surface swallows the keyboard.
            WlrLayershell.keyboardFocus: (GlobalStates.sessionOpen && sessionRoot.isTarget)
                ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            // A literal, with the scrim painted by a child (scrimRect): a
            // window colour bound to a theme token is the #143 latch, and on
            // a persistent surface there is no rebuild to recover it.
            color: "transparent"

            // The whole surface takes input while open (a click anywhere
            // cancels), and none of it while closed - a persistent surface
            // with an ungated mask eats every click on the screen.
            Item {
                id: inputRegionProxy
                anchors.fill: parent
            }
            mask: Region {
                item: (GlobalStates.sessionOpen && sessionRoot.isTarget) ? inputRegionProxy : null
            }

            anchors {
                top: true
                left: true
                right: true
            }

            implicitWidth: sessionRoot.modelData?.width ?? 0
            implicitHeight: sessionRoot.modelData?.height ?? 0

            // One scalar drives the scrim and the content together, started
            // rather than a Behavior because the exit's `finished` owns
            // `reallyOpen` and a Behavior never raises it.
            property real openProgress: 0

            NumberAnimation {
                id: enterAnim
                target: sessionRoot
                property: "openProgress"
                to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }

            NumberAnimation {
                id: exitAnim
                target: sessionRoot
                property: "openProgress"
                to: 0
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                onFinished: sessionRoot.reallyOpen = false
            }

            Rectangle {
                id: scrimRect
                anchors.fill: parent
                visible: sessionRoot.reallyOpen
                opacity: sessionRoot.openProgress
                color: ColorUtils.transparentize(Appearance.m3colors.m3background,
                    Appearance.m3colors.darkmode ? 0.05 : 0.12)
            }

            MouseArea {
                id: sessionMouseArea
                anchors.fill: parent
                enabled: sessionRoot.reallyOpen
                onClicked: {
                    sessionRoot.hide();
                }
            }

            ColumnLayout { // Content column
                id: contentColumn
                anchors.centerIn: parent
                spacing: Appearance.spacing.space200
                visible: sessionRoot.reallyOpen
                opacity: sessionRoot.openProgress

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        sessionRoot.hide();
                    }
                }

                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 0
                    StyledText {
                        // Title
                        Layout.alignment: Qt.AlignHCenter
                        horizontalAlignment: Text.AlignHCenter
                        font {
                            family: Appearance.font.family.title
                            pixelSize: Appearance.font.pixelSize.title
                            variableAxes: Appearance.font.variableAxes.title
                        }
                        text: Translation.tr("Session")
                    }

                    StyledText {
                        // Small instruction
                        Layout.alignment: Qt.AlignHCenter
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.normal
                        text: Translation.tr("Arrow keys to navigate, Enter to select\nEsc or click anywhere to cancel")
                    }
                }

                GridLayout {
                    id: sessionGrid
                    // 3x3: session actions on the top rows, power actions on
                    // the bottom row, so "Reboot into..." sits beside Reboot
                    // instead of orphaned on its own row.
                    columns: 3

                    // Nine buttons that used to appear in one frame. The
                    // screen is opened deliberately and read before anything
                    // is pressed, so a cascade costs nothing the user is
                    // waiting on - and the button that already holds the
                    // keyboard cursor is rank 0, so it is never the one kept
                    // waiting. No lead-in: this window has no motion of its
                    // own to give the members a head start on.
                    //
                    // Ranking by VISIBLE position is load-bearing here rather
                    // than theoretical: "Reboot into..." is hidden unless the
                    // machine offers more than one firmware entry.
                    StaggerWave {
                        id: sessionEntrance
                        target: sessionGrid
                        step: Appearance.animation.staggerStep
                    }
                    columnSpacing: Appearance.spacing.space200
                    rowSpacing: Appearance.spacing.space200

                    SessionActionButton {
                        id: sessionLock
                        buttonIcon: "lock"
                        buttonText: Translation.tr("Lock")
                        onClicked: {
                            Session.lock();
                            sessionRoot.hide();
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.right: sessionSleep
                        KeyNavigation.down: sessionHibernate
                    }
                    SessionActionButton {
                        id: sessionSleep
                        buttonIcon: "dark_mode"
                        buttonText: Translation.tr("Sleep")
                        onClicked: {
                            Session.suspend();
                            sessionRoot.hide();
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.left: sessionLock
                        KeyNavigation.right: sessionLogout
                        KeyNavigation.down: sessionTaskManager
                    }
                    SessionActionButton {
                        id: sessionLogout
                        buttonIcon: "logout"
                        buttonText: Translation.tr("Logout")
                        onClicked: {
                            Session.logout();
                            sessionRoot.hide();
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.left: sessionSleep
                        KeyNavigation.down: sessionFirmwareReboot
                    }

                    SessionActionButton {
                        id: sessionHibernate
                        buttonIcon: "downloading"
                        buttonText: Translation.tr("Hibernate")
                        onClicked: {
                            Session.hibernate();
                            sessionRoot.hide();
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.up: sessionLock
                        KeyNavigation.right: sessionTaskManager
                        KeyNavigation.down: sessionShutdown
                    }
                    SessionActionButton {
                        id: sessionTaskManager
                        buttonIcon: "browse_activity"
                        buttonText: Translation.tr("Task Manager")
                        onClicked: {
                            Session.launchTaskManager();
                            sessionRoot.hide();
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.left: sessionHibernate
                        KeyNavigation.up: sessionSleep
                        KeyNavigation.right: sessionFirmwareReboot
                        KeyNavigation.down: sessionReboot
                    }
                    SessionActionButton {
                        id: sessionFirmwareReboot
                        buttonIcon: "settings_applications"
                        buttonText: Translation.tr("Reboot to firmware settings")
                        onClicked: {
                            Session.rebootToFirmware();
                            sessionRoot.hide();
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.left: sessionTaskManager
                        KeyNavigation.up: sessionLogout
                        KeyNavigation.down: sessionRebootInto
                    }

                    SessionActionButton {
                        id: sessionShutdown
                        buttonIcon: "power_settings_new"
                        buttonText: Translation.tr("Shutdown")
                        onClicked: {
                            Session.poweroff();
                            sessionRoot.hide();
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.up: sessionHibernate
                        KeyNavigation.right: sessionReboot
                    }
                    SessionActionButton {
                        id: sessionReboot
                        buttonIcon: "restart_alt"
                        buttonText: Translation.tr("Reboot")
                        onClicked: {
                            Session.reboot();
                            sessionRoot.hide();
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.left: sessionShutdown
                        KeyNavigation.up: sessionTaskManager
                        KeyNavigation.right: sessionRebootInto
                    }
                    SessionActionButton {
                        id: sessionRebootInto
                        // Only meaningful with an actual choice of firmware entries.
                        visible: EfiBoot.entries.length > 1
                        buttonIcon: "alt_route"
                        buttonText: Translation.tr("Reboot into...")
                        toggled: sessionRoot.rebootPickerOpen
                        onClicked: {
                            sessionRoot.rebootPickerOpen = !sessionRoot.rebootPickerOpen;
                        }
                        onFocusChanged: {
                            if (focus)
                                sessionRoot.subtitle = buttonText;
                        }
                        KeyNavigation.left: sessionReboot
                        KeyNavigation.up: sessionFirmwareReboot
                        KeyNavigation.down: sessionRoot.rebootPickerOpen ? efiEntryRepeater.itemAt(0) : null
                    }
                }

                // Firmware boot entries (BootNext + reboot). Separate from the
                // plain Reboot button on purpose: picking an entry authenticates
                // via polkit first, then reboots straight into that OS.
                ColumnLayout {
                    // Stacked and clamped to the grid's width so the picker
                    // never overflows the button block sideways.
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: sessionGrid.width
                    Layout.maximumWidth: sessionGrid.width
                    visible: sessionRoot.rebootPickerOpen
                    spacing: Appearance.spacing.space100

                    Repeater {
                        id: efiEntryRepeater
                        model: EfiBoot.entries
                        delegate: RippleButton {
                            id: efiEntryButton
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            implicitHeight: 44
                            buttonRadius: height / 2
                            // Focus wins (filled primary pill, matching the grid
                            // buttons' focus style); the current OS is tonal.
                            readonly property color colContent: efiEntryButton.activeFocus
                                ? Appearance.colors.colOnPrimary
                                : modelData.current
                                    ? Appearance.colors.colOnSecondaryContainer
                                    : Appearance.colors.colOnLayer2
                            colBackground: efiEntryButton.activeFocus
                                ? Appearance.colors.colPrimary
                                : modelData.current
                                    ? Appearance.colors.colSecondaryContainer
                                    : Appearance.colors.colLayer2
                            colBackgroundHover: efiEntryButton.activeFocus
                                ? Appearance.colors.colPrimaryHover
                                : Appearance.colors.colLayer2Hover

                            function activate() {
                                sessionRoot.hide();
                                EfiBoot.rebootInto(efiEntryButton.modelData.num, efiEntryButton.modelData.label);
                            }
                            onClicked: activate()
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    efiEntryButton.activate();
                                    event.accepted = true;
                                }
                            }
                            KeyNavigation.up: efiEntryButton.index > 0
                                ? efiEntryRepeater.itemAt(efiEntryButton.index - 1) : sessionRebootInto
                            KeyNavigation.down: efiEntryRepeater.itemAt(efiEntryButton.index + 1)
                            onFocusChanged: {
                                if (focus)
                                    sessionRoot.subtitle = Translation.tr("Reboot into %1").arg(efiEntryButton.modelData.label);
                            }
                            contentItem: RowLayout {
                                anchors.fill: parent
                                spacing: Appearance.spacing.space75
                                MaterialSymbol {
                                    Layout.leftMargin: Appearance.spacing.space150
                                    text: efiEntryButton.modelData.current ? "radio_button_checked" : "restart_alt"
                                    iconSize: Appearance.font.pixelSize.large
                                    color: efiEntryButton.colContent
                                    Behavior on color {
                                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                    }
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: efiEntryButton.modelData.label
                                        + (efiEntryButton.modelData.current ? " " + Translation.tr("(current)") : "")
                                    color: efiEntryButton.colContent
                                    Behavior on color {
                                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                    }
                                }
                                StyledText {
                                    Layout.rightMargin: Appearance.spacing.space150
                                    text: efiEntryButton.modelData.num
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    opacity: 0.6
                                    color: efiEntryButton.colContent
                                }
                            }
                            StyledToolTip {
                                text: Translation.tr("Set BootNext to %1 and reboot").arg(efiEntryButton.modelData.num)
                            }
                        }
                    }
                }

                DescriptionLabel {
                    Layout.alignment: Qt.AlignHCenter
                    text: sessionRoot.subtitle
                }
            }

            ColumnLayout {
                anchors {
                    top: contentColumn.bottom
                    topMargin: Appearance.spacing.space150
                    horizontalCenter: contentColumn.horizontalCenter
                }
                spacing: Appearance.spacing.space150
                visible: sessionRoot.reallyOpen
                opacity: sessionRoot.openProgress

                Loader {
                    Layout.alignment: Qt.AlignHCenter
                    active: sessionRoot.reallyOpen && SessionWarnings.downloadRunning
                    visible: active
                    sourceComponent: DescriptionLabel {
                        text: Translation.tr("There might be a download in progress. Check your Downloads folder.")
                        textColor: Appearance.m3colors.m3onErrorContainer
                        color: Appearance.m3colors.m3errorContainer
                    }
                }

                Loader {
                    Layout.alignment: Qt.AlignHCenter
                    active: sessionRoot.reallyOpen && SessionWarnings.packageManagerRunning
                    visible: active
                    sourceComponent: DescriptionLabel {
                        text: Translation.tr("Your package manager is running")
                        textColor: Appearance.m3colors.m3onErrorContainer
                        color: Appearance.m3colors.m3errorContainer
                    }
                }
            }
        }
    }

    component DescriptionLabel: Rectangle {
        id: descriptionLabel
        property string text
        property color textColor: Appearance.colors.colOnTooltip
        color: Appearance.colors.colTooltip
        clip: true
        radius: Appearance.rounding.normal
        implicitHeight: descriptionLabelText.implicitHeight + 10 * 2
        implicitWidth: descriptionLabelText.implicitWidth + 15 * 2

        Behavior on implicitWidth {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        StyledText {
            id: descriptionLabelText
            anchors.centerIn: parent
            color: descriptionLabel.textColor
            text: descriptionLabel.text
        }
    }

    IpcHandler {
        target: "session"

        function toggle(): void {
            GlobalStates.sessionOpen = !GlobalStates.sessionOpen;
        }

        function close(): void {
            GlobalStates.sessionOpen = false;
        }

        function open(): void {
            GlobalStates.sessionOpen = true;
        }

        // Which screen's window the last open landed on - what the
        // persistent-surface focus probe reads. Empty until the first open.
        function activeScreen(): string {
            return root.activeWindow?.modelData.name ?? "";
        }
    }

    GlobalShortcut {
        name: "sessionToggle"
        description: "Toggles session screen on press"

        onPressed: {
            GlobalStates.sessionOpen = !GlobalStates.sessionOpen;
        }
    }

    GlobalShortcut {
        name: "sessionOpen"
        description: "Opens session screen on press"

        onPressed: {
            GlobalStates.sessionOpen = true;
        }
    }

    GlobalShortcut {
        name: "sessionClose"
        description: "Closes session screen on press"

        onPressed: {
            GlobalStates.sessionOpen = false;
        }
    }
}
