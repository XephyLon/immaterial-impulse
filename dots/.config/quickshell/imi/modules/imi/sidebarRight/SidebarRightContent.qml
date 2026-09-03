import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.imi.mediaControls
import qs.modules.common.functions
import qs.modules.common.plugins.designsystem.services
import Quickshell.Services.Mpris
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland

import qs.modules.imi.sidebarRight.quickToggles
import qs.modules.imi.sidebarRight.quickToggles.classicStyle
import qs.modules.imi.sidebarRight.bluetoothDevices
import qs.modules.imi.sidebarRight.nightLight
import qs.modules.imi.sidebarRight.volumeMixer
import qs.modules.imi.sidebarRight.wifiNetworks
import qs.modules.imi.sidebarRight.tailscale
import qs.modules.imi.sidebarRight.iconPicker

Item {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidth
    property int sidebarPadding: Appearance.spacing.space125
    property string settingsQmlPath: Quickshell.shellPath("settings.qml")
    property bool showAudioOutputDialog: false
    property bool showAudioInputDialog: false
    property bool showBluetoothDialog: false
    property bool showNightLightDialog: false
    property bool showWifiDialog: false
    property bool showTailscaleDialog: false
    property bool editMode: false
    property bool showIconPickerDialog: false

    readonly property bool sidebarOpen: GlobalStates.sidebarRightOpen

    // The opaque panel body, exposed so the hosting window can scope its
    // compositor blur region to it (see WindowBlurRegion in SidebarRight.qml).
    readonly property Item backgroundItem: sidebarRightBackground

    // One counter drives every bespoke widget entrance, the fork's own
    // architecture: sliders sweep their fill, the calendar ripples
    // diagonally, the notification bar's halves converge - each widget owns
    // its choreography and this only says "an open happened". The generic
    // wave stays for the sections with no character of their own.
    property int entranceTrigger: -1

    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property var meaningfulPlayers: MprisController.meaningfulPlayers

    // The entrance runs UNDER the slide, not after it. This surface's wave
    // shipped twice wrong before landing here, and both wrong versions are
    // worth naming. The original (00efe588's revert) guessed a leadIn and
    // landed content ~200ms after the slide. The second gated on the slide's
    // progress like the popup card - correct-sounding, and measured as
    // ruined: the panel arrived EMPTY and then visibly built itself, because
    // parked-at-zero content plus a 60% gate puts the whole construction ON
    // STAGE. The fork's sidebars, re-recorded and read object by object, do
    // the opposite: the surface's own fade carries the panel already
    // composed - the per-element entrances run underneath it, and only the
    // last-ranked one or two elements visibly pop after the panel lands.
    // So: park and enter on the open's rising edge, with no gate - the slide
    // masks the wave's early frames, and the tail is the grammar.
    // With keepRightSidebarLoaded off, this whole tree is created INSIDE the
    // sidebarRightOpenChanged emission (the loader's `active` follows
    // `slide.shown` synchronously) - and a connection made during an
    // emission does not receive that emission. The Connections below then
    // misses every open, because the tree is torn down on close: no wave, no
    // trigger, ever. So a tree born with the panel already open runs the
    // entrance itself, one turn later - after the children (and the
    // calendar's own creation-edge arming) have finished coming up.
    Component.onCompleted: {
        if (GlobalStates.sidebarRightOpen)
            Qt.callLater(() => {
                if (GlobalStates.sidebarRightOpen)
                    root.runEntrance();
            });
        // The content is built on the open edge, after onSidebarRightOpenChanged
        // has already fired without it - so a deep link written before the
        // panel existed is honoured here.
        root.consumeDialogRequest();
    }

    // GlobalStates.sidebarRightDialog names a dialog to open ("bluetooth");
    // consume it and clear it, the way SidebarLeftContent consumes its tab.
    function consumeDialogRequest() {
        if (GlobalStates.sidebarRightDialog === "") return;
        if (GlobalStates.sidebarRightDialog === "bluetooth")
            root.showBluetoothDialog = true;
        GlobalStates.sidebarRightDialog = "";
    }

    function runEntrance() {
        sectionEntrance.park();
        sectionEntrance.enter();
        root.entranceTrigger++;
    }

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (GlobalStates.sidebarRightOpen) {
                root.runEntrance();
                root.consumeDialogRequest();
                return;
            }
            if (!GlobalStates.sidebarRightOpen) {
                root.showWifiDialog = false;
                root.showTailscaleDialog = false;
                root.showBluetoothDialog = false;
                root.showAudioOutputDialog = false;
                root.showAudioInputDialog = false;
            }
        }
        // A request written while the panel is already open has no open
        // edge behind it, so it is honoured on the write as well.
        function onSidebarRightDialogChanged() {
            if (GlobalStates.sidebarRightOpen)
                root.consumeDialogRequest();
        }
    }

    Process {
        id: fileChooser
        command: ["kdialog", "--getopenfilename", Quickshell.env("HOME") + "/Pictures", "image/png image/jpg image/jpeg image/webp"]
        
        stdout: StdioCollector {
            id: fileChooserOutput
        }
        
        onExited: (code) => {
            if (code === 0) {
                const path = fileChooserOutput.text.trim()
                if (path !== "") {
                    Config.options.sidebar.bannerImage = path
                }
            }
        }
    }

    implicitHeight: sidebarRightBackground.implicitHeight
    implicitWidth: sidebarRightBackground.implicitWidth

    StyledRectangularShadow {
        target: sidebarRightBackground
    }
    Rectangle {
        id: sidebarRightBackground

        anchors.fill: parent
        implicitHeight: parent.height - Appearance.sizes.hyprlandGapsOut * 2
        implicitWidth: sidebarWidth - Appearance.sizes.hyprlandGapsOut * 2
        color: Appearance.colors.colLayer0
        border.width: Appearance.borderWidth.standard
        border.color: Appearance.colors.colLayer0Border
        radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 5

        ColumnLayout {
            id: sidebarColumn
            anchors.fill: parent
            anchors.margins: sidebarPadding
            spacing: sidebarPadding

            // The sections arrive in sequence once the slide has essentially
            // landed. Ranking by VISIBLE position earns its place here: only
            // one quick-panel style is ever active and the media player is
            // absent with nothing playing, so unranked slots would leave
            // holes mid-wave. No exit wave - the sections ride the slide out
            // rigid, the same asymmetry the popup card keeps.
            StaggerWave {
                id: sectionEntrance
                target: sidebarColumn
            }
            StaggerEntrance {
                target: sidebarColumn
                reference: root.sidebarWidth
                // Deliberately UNIFORM at the section level. The convergent
                // mode was tried here and read as ruined on screen: a section
                // translating in from above or below WHILE its own interior
                // converges (the toggle grid's tiles) is two directional
                // motions stacked, and the fork this grammar was measured off
                // never does that - its sections hold still and their PIECES
                // converge. Sections keep the calm fade-scale-rise; the
                // directional language lives one level down.
            }

            // Banner
            Loader {
                property real appear: 1
                Layout.fillWidth: true
                Layout.fillHeight: false
                sourceComponent: Config.options.sidebar.banner ? bannerComponent : normalComponent

                Component {
                    id: bannerComponent
                    Item {
                        implicitHeight: 180
                        implicitWidth: parent?.width ?? 0

                        Rectangle {
                            id: sysRect
                            anchors.fill: parent
                            radius: Config.options.hyprland.decoration.rounding - 2
                            color: Appearance.colors.colLayer1

                            Rectangle {
                                id: wallpaperRect
                                anchors {
                                    top: parent.top
                                    left: parent.left
                                    right: parent.right
                                    topMargin: Appearance.spacing.space25
                                    leftMargin: Appearance.spacing.space25
                                    rightMargin: Appearance.spacing.space25
                                }
                                height: 120
                                radius: sysRect.radius
                                color: "transparent"

                                StyledImage {
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectCrop
                                    source: Config.options.sidebar.bannerImage !== "" 
                                        ? Config.options.sidebar.bannerImage 
                                        : Config.options.wallpaperSelector.wallpaperEngine.activePreview !== ""
                                            ? Config.options.wallpaperSelector.wallpaperEngine.activePreview
                                            : Config.options.background.wallpaperPath
                                    cache: false
                                    antialiasing: true
                                    sourceSize.width: wallpaperRect.width * 2
                                    sourceSize.height: wallpaperRect.height * 2
                                    layer.enabled: true
                                    layer.effect: OpacityMask {
                                        maskSource: Rectangle {
                                            width: wallpaperRect.width
                                            height: wallpaperRect.height
                                            radius: wallpaperRect.radius
                                        }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: (event) => {
                                        if (event.button === Qt.LeftButton) {
                                            fileChooser.running = true
                                            GlobalStates.sidebarRightOpen = false
                                        } else if (event.button === Qt.RightButton) {
                                            Config.options.sidebar.bannerImage = ""
                                        }
                                    }
                                }
                            }

                            Column {
                                anchors {
                                    left: parent.left
                                    bottom: parent.bottom
                                    leftMargin: 13
                                    bottomMargin: Appearance.spacing.space100
                                }
                                spacing: Appearance.spacing.space25

                                Rectangle {
                                    id: avatarRect
                                    width: 48; height: 48; radius: width / 2
                                    color: Appearance.colors.colPrimaryContainer

                                    Image {
                                        id: avatarImage
                                        anchors.fill: parent
                                        source: Config.options.profile.avatarPath !== "" 
                                            ? "file://" + Config.options.profile.avatarPicture 
                                            : "file:///home/" + (Quickshell.env("USER") ?? "user") + "/.face"
                                        sourceSize.width: avatarImage.width * 2
                                        sourceSize.height: avatarImage.height * 2
                                        fillMode: Image.PreserveAspectCrop
                                        layer.enabled: true
                                        layer.effect: OpacityMask {
                                            maskSource: Rectangle {
                                                width: avatarRect.width
                                                height: avatarRect.height
                                                radius: avatarRect.radius
                                            }
                                        }
                                        onStatusChanged: {
                                            if (status === Image.Error) visible = false
                                        }
                                    }

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "account_circle"
                                        iconSize: 32
                                        color: Appearance.colors.colOnPrimaryContainer
                                        visible: avatarImage.status === Image.Error
                                    }
                                }

                                StyledText {
                                    text: (Config.options.profile.displayName === "" ? SystemInfo.username : Config.options.profile.displayName) + "@" + SystemInfo.hostname
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnLayer1
                                }

                                StyledText {
                                    text: Translation.tr("Up • %1").arg(DateTime.uptime)
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer1
                                    opacity: 0.6
                                }
                            }

                            ButtonGroup {
                                anchors {
                                    right: parent.right
                                    bottom: parent.bottom
                                    margins: Appearance.spacing.space50
                                }
                                color: "transparent"
                                padding: Appearance.spacing.space50

                                QuickToggleButton {
                                    toggled: root.editMode
                                    visible: Config.options.sidebar.quickToggles.style === "android"
                                    buttonIcon: "edit"
                                    onClicked: root.editMode = !root.editMode
                                    StyledToolTip {
                                        text: Translation.tr("Edit quick toggles") + (root.editMode ? Translation.tr("\nLMB to enable/disable\nRMB to toggle size\nScroll to swap position") : "")
                                    }
                                }
                                QuickToggleButton {
                                    toggled: false
                                    buttonIcon: "restart_alt"
                                    onClicked: {
                                        Quickshell.execDetached(["hyprctl", "reload"])
                                        Quickshell.reload(true);
                                    }
                                    StyledToolTip {
                                        text: Translation.tr("Reload Hyprland & Quickshell")
                                    }
                                }
                                QuickToggleButton {
                                    toggled: GlobalStates.settingsOpen
                                    buttonIcon: "settings"
                                    onClicked: {
                                        GlobalStates.sidebarRightOpen = false;
                                        GlobalStates.settingsOpen = !GlobalStates.settingsOpen
                                    }
                                    StyledToolTip {
                                        text: Translation.tr("Settings")
                                    }
                                }
                                QuickToggleButton {
                                    toggled: false
                                    buttonIcon: "mode_off_on"
                                    onClicked: GlobalStates.sessionOpen = true
                                    StyledToolTip {
                                        text: Translation.tr("Session")
                                    }
                                }
                            }
                        }
                    }
                }

                Component {
                    id: normalComponent
                    SystemButtonRow {}
                }
            }

            LoaderedQuickPanelImplementation {
                styleName: "classic"
                sourceComponent: ClassicQuickPanel {}
            }

            LoaderedQuickPanelImplementation {
                styleName: "android"
                sourceComponent: AndroidQuickPanel {
                    editMode: root.editMode
                }
            }

            Loader {
                id: slidersLoader
                // Not a wave member: the sliders own their entrance - the
                // fill sweep, and a card wave of their own inside
                // (QuickSliders.qml), the toggle grid's shape. A fading
                // section over fading cards is the compound that grid
                // already paid for.
                Layout.fillWidth: true
                visible: active
                active: {
                    const configQuickSliders = Config.options.sidebar.quickSliders
                    if (!configQuickSliders.enable) return false
                    if (!configQuickSliders.showMic && !configQuickSliders.showVolume && !configQuickSliders.showBrightness) return false;
                    return true;
                }
                sourceComponent: QuickSliders { entranceTrigger: root.entranceTrigger }
            }

            Loader {
                id: mediaPlayerLoader
                property real appear: 1
                active: root.activePlayer !== null && GlobalStates.sidebarRightOpen && Config.options.sidebar.mediaPlayer
                visible: active
                Layout.fillWidth: true
                Layout.topMargin: -Appearance.spacing.space150
                Layout.bottomMargin: -Appearance.spacing.space150
                Layout.leftMargin: -Appearance.spacing.space150
                Layout.rightMargin: -Appearance.spacing.space150
                sourceComponent: Player {
                    player: root.activePlayer
                    visualizerPoints: CavaService.values
                    maxVisualizerValue: CavaService.maxValue
                    implicitHeight: 160
                    radius: Appearance.rounding.normal
                }
            }

            // The sidebar's claim on cava. Narrower than the "sidebar is open"
            // term it replaces: with the media player row switched off, or no
            // player at all, this panel shows no bands and does not ask for
            // any.
            CavaRef {
                active: mediaPlayerLoader.active
            }

            CenterWidgetGroup {
                entranceTrigger: root.entranceTrigger
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: true
                Layout.fillWidth: true
            }

            BottomWidgetGroup {
                id: bottomWidgetGroup
                entranceTrigger: root.entranceTrigger
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: false
                Layout.fillWidth: true
            }
        }
    }

    ToggleDialog {
        shownPropertyString: "showAudioOutputDialog"
        dialog: VolumeDialog {
            isSink: true
        }
    }

    ToggleDialog {
        shownPropertyString: "showAudioInputDialog"
        dialog: VolumeDialog {
            isSink: false
        }
    }

    ToggleDialog {
        shownPropertyString: "showBluetoothDialog"
        dialog: BluetoothDialog {}
        onShownChanged: {
            if (!shown) {
                Bluetooth.defaultAdapter.discovering = false;
            } else {
                Bluetooth.defaultAdapter.enabled = true;
                Bluetooth.defaultAdapter.discovering = true;
            }
        }
    }

    ToggleDialog {
        shownPropertyString: "showNightLightDialog"
        dialog: NightLightDialog {}
    }

    ToggleDialog {
        shownPropertyString: "showWifiDialog"
        dialog: WifiDialog {}
        onShownChanged: {
            if (!shown) return;
            Network.enableWifi();
            Network.rescanWifi();
        }
    }

    ToggleDialog {
        shownPropertyString: "showTailscaleDialog"
        dialog: TailscaleDialog {}
        onShownChanged: {
            if (shown) Tailscale.refresh();
        }
    }

    ToggleDialog {
        shownPropertyString: "showIconPickerDialog"
        dialog: IconPickerDialog {}
    }

    component ToggleDialog: Loader {
        id: toggleDialogLoader
        required property string shownPropertyString
        property alias dialog: toggleDialogLoader.sourceComponent
        readonly property bool shown: root[shownPropertyString]
        anchors.fill: parent

        onShownChanged: if (shown) toggleDialogLoader.active = true;
        active: shown
        onActiveChanged: {
            if (active) {
                item.show = true;
                item.forceActiveFocus();
            }
        }
        Connections {
            target: toggleDialogLoader.item
            function onDismiss() {
                toggleDialogLoader.item.show = false
                root[toggleDialogLoader.shownPropertyString] = false;
            }
            function onVisibleChanged() {
                if (toggleDialogLoader.item && !toggleDialogLoader.item.visible && !root[toggleDialogLoader.shownPropertyString])
                    toggleDialogLoader.active = false;
            }
        }
    }

    component LoaderedQuickPanelImplementation: Loader {
        id: quickPanelImplLoader
        // Deliberately NOT a wave member (no `appear`): the android panel's
        // tiles run their own entrance, and a fading section times a fading
        // tile is two opacities MULTIPLIED - measured at full resolution as
        // a ~250ms mushy tail of half-visible tiles, which is what read as
        // broken. One fade per pixel: the section stands still, the pieces
        // move - the fork's own rule, finally applied where it bites.
        required property string styleName
        Layout.alignment: item?.Layout.alignment ?? Qt.AlignHCenter
        Layout.fillWidth: item?.Layout.fillWidth ?? false
        visible: active
        active: Config.options.sidebar.quickToggles.style === styleName
        Connections {
            target: quickPanelImplLoader.item
            function onOpenAudioOutputDialog() { root.showAudioOutputDialog = true; }
            function onOpenAudioInputDialog() { root.showAudioInputDialog = true; }
            function onOpenBluetoothDialog() { root.showBluetoothDialog = true; }
            function onOpenNightLightDialog() { root.showNightLightDialog = true; }
            function onOpenWifiDialog() { root.showWifiDialog = true; }
            function onOpenTailscaleDialog() { root.showTailscaleDialog = true; }
            // The phone lives in the LEFT sidebar now: this toggle names
            // the tab and opens that panel, where it used to raise a dialog
            // of its own. The refresh goes with the open, as the dialog's
            // did - a tile the user just pressed should not show the sweep
            // before last.
            function onOpenPhoneTab() {
                PhoneConnect.refresh();
                GlobalStates.sidebarLeftTab = "phone";
                GlobalStates.sidebarLeftOpen = true;
                GlobalStates.sidebarRightOpen = false;
            }
        }
    }

    component SystemButtonRow: Item {
        implicitHeight: Math.max(uptimeContainer.implicitHeight, systemButtonsRow.implicitHeight)

        Rectangle {
            id: uptimeContainer
            anchors {
                top: parent.top
                bottom: parent.bottom
                left: parent.left
            }
            color: Appearance.colors.colLayer1
            radius: Appearance.rounding.normal
            implicitWidth: uptimeRow.implicitWidth + 24
            implicitHeight: uptimeRow.implicitHeight + 8

            Row {
                id: uptimeRow
                anchors.centerIn: parent
                spacing: Appearance.spacing.space100
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 25
                    height: 25

                    CustomIcon {
                        id: distroIcon
                        anchors.fill: parent
                        source: Config.options.custom.distroIcon || SystemInfo.distroIcon
                        colorize: Config.options.custom.colorizeIcon
                        color: Appearance.colors.colOnLayer0
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showIconPickerDialog = true
                    }
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer0
                    text: Translation.tr("Up • %1").arg(DateTime.uptime)
                    textFormat: Text.MarkdownText
                }
            }
        }

        ButtonGroup {
            id: systemButtonsRow
            anchors {
                top: parent.top
                bottom: parent.bottom
                right: parent.right
            }
            color: Appearance.colors.colLayer1
            padding: Appearance.spacing.space50

            QuickToggleButton {
                toggled: root.editMode
                visible: Config.options.sidebar.quickToggles.style === "android"
                buttonIcon: "edit"
                onClicked: root.editMode = !root.editMode
                StyledToolTip {
                    text: Translation.tr("Edit quick toggles") + (root.editMode ? Translation.tr("\nLMB to enable/disable\nRMB to toggle size\nScroll to swap position") : "")
                }
            }
            QuickToggleButton {
                toggled: false
                buttonIcon: "restart_alt"
                onClicked: {
                    Quickshell.execDetached(["hyprctl", "reload"]);
                    Quickshell.reload(true);
                }
                StyledToolTip {
                    text: Translation.tr("Reload Hyprland & Quickshell")
                }
            }
            QuickToggleButton {
                toggled: GlobalStates.settingsOpen
                buttonIcon: "settings"
                onClicked: {
                    GlobalStates.sidebarRightOpen = false;
                    GlobalStates.settingsOpen = !GlobalStates.settingsOpen
                }
                StyledToolTip {
                    text: Translation.tr("Settings")
                }
            }
            QuickToggleButton {
                toggled: false
                buttonIcon: "mode_off_on"
                onClicked: GlobalStates.sessionOpen = true
                StyledToolTip {
                    text: Translation.tr("Session")
                }
            }
        }
    }
}
