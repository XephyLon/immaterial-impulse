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

    property string focusedScreenName: Hyprland.focusedMonitor?.name ?? ""

    property var focusedScreen: Quickshell.screens.find(s => s.name === root.focusedScreenName)
        ?? Quickshell.screens[0]

    Loader {
        id: sessionLoader
        active: GlobalStates.sessionOpen
        onActiveChanged: {
            if (sessionLoader.active)
                SessionWarnings.refresh();
        }

        Connections {
            target: GlobalStates
            function onScreenLockedChanged() {
                if (GlobalStates.screenLocked) {
                    GlobalStates.sessionOpen = false;
                }
            }
        }

        sourceComponent: PanelWindow { // Session menu
            id: sessionRoot
            screen: root.focusedScreen
            visible: sessionLoader.active
            property string subtitle
            property bool rebootPickerOpen: false
            onVisibleChanged: {
                rebootPickerOpen = false;
                if (visible) EfiBoot.refresh();
            }

            function hide() {
                GlobalStates.sessionOpen = false;
            }

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:session"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: ColorUtils.transparentize(Appearance.m3colors.m3background, Appearance.m3colors.darkmode ? 0.05 : 0.12)

            anchors {
                top: true
                left: true
                right: true
            }

            implicitWidth: root.focusedScreen?.width ?? 0
            implicitHeight: root.focusedScreen?.height ?? 0

            MouseArea {
                id: sessionMouseArea
                anchors.fill: parent
                onClicked: {
                    sessionRoot.hide();
                }
            }

            ColumnLayout { // Content column
                id: contentColumn
                anchors.centerIn: parent
                spacing: Appearance.spacing.space200

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
                    columnSpacing: Appearance.spacing.space200
                    rowSpacing: Appearance.spacing.space200

                    SessionActionButton {
                        id: sessionLock
                        focus: sessionRoot.visible
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
                                        ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                                    }
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: efiEntryButton.modelData.label
                                        + (efiEntryButton.modelData.current ? " " + Translation.tr("(current)") : "")
                                    color: efiEntryButton.colContent
                                    Behavior on color {
                                        ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
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

                Loader {
                    Layout.alignment: Qt.AlignHCenter
                    active: SessionWarnings.downloadRunning
                    visible: active
                    sourceComponent: DescriptionLabel {
                        text: Translation.tr("There might be a download in progress. Check your Downloads folder.")
                        textColor: Appearance.m3colors.m3onErrorContainer
                        color: Appearance.m3colors.m3errorContainer
                    }
                }

                Loader {
                    Layout.alignment: Qt.AlignHCenter
                    active: SessionWarnings.packageManagerRunning
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
