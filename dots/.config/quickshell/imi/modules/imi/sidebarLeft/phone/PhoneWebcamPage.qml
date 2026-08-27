pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "phone_cards.js" as PhoneCards

/**
 * The Phone tab's Phone Webcam sub-page: the DroidCam stream's toggle and its
 * settings.
 *
 * Rooted on `PhoneSubPage` (W5a's; the interface is pinned by the stub at
 * tests/imports/qs/modules/imi/sidebarLeft/phone/PhoneSubPage.qml), with a
 * `ContentPage` inside it so the sections scroll and read as the rest of the
 * shell's settings do.
 *
 * Every row here writes a key `Config.qml` already declares under
 * `phone.webcam`, read with optional chaining. The sibling fork's page also
 * offers a frame rate and a bitrate; neither key exists in this schema and
 * `droidcam-cli` takes no flag for either, so neither row is here - a control
 * bound to an undeclared key reads `undefined`, takes its fallback for ever
 * and is destroyed by the JsonAdapter's first write.
 */
PhoneSubPage {
    id: root

    title: Translation.tr("Phone Webcam")

    readonly property var webcamConfig: Config.options.phone?.webcam
    readonly property bool deviceReachable: PhoneConnect.activeDevice?.reachable === true
    readonly property bool canStart: PhoneCamera.available && root.deviceReachable

    ContentPage {
        id: page

        Layout.fillWidth: true
        Layout.fillHeight: true
        // ContentPage centres its content column at
        // `Math.max(baseWidth, implicitWidth)`, and `baseWidth` defaults to
        // 600 - the settings window's number. The panel hands this page 440,
        // so the column was drawn from -80 to 520 and every row was clipped
        // at the panel's left edge while the page rendered perfectly and
        // logged nothing (measured in PhoneSubPageWidthRuntimeTest.qml). The
        // column takes the width it is really given, less the lane the scroll
        // bar overlays.
        forceWidth: true
        baseWidth: Math.max(0, page.width - Appearance.spacing.space200)
        bottomContentPadding: Appearance.spacing.space400

        // A NoticeBox reports its string's UNWRAPPED width as its implicit
        // width, so one long service error asks the column for more room than
        // the panel has - 495px for PhoneCamera's own "DroidCam did not start
        // - is the DroidCam app open on the phone?" in a 440px page, which is
        // what `Math.max(baseWidth, implicitWidth)` above was widening on.
        // Capped, the banner wraps inside itself instead of moving the page.
        NoticeBox {
            Layout.fillWidth: true
            Layout.maximumWidth: page.baseWidth
            visible: !PhoneCamera.available
            materialIcon: "download"
            text: Translation.tr("DroidCam is not set up on this machine. %1 is missing.")
                .arg(PhoneDeps.missingFor("webcam").map(dependency => dependency.name).join(", "))

            RippleButton {
                Layout.alignment: Qt.AlignRight
                Layout.preferredHeight: Appearance.font.pixelSize.huge + Appearance.spacing.space150
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: installGuide.shown = true

                contentItem: StyledText {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: Translation.tr("How to install")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimary
                }
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            Layout.maximumWidth: page.baseWidth
            visible: PhoneCamera.available && !root.deviceReachable
            materialIcon: "phonelink_off"
            text: Translation.tr("No phone is reachable. Pair one in KDE Connect and bring it onto the network.")
        }

        NoticeBox {
            Layout.fillWidth: true
            Layout.maximumWidth: page.baseWidth
            visible: PhoneCamera.lastError.length > 0
            materialIcon: "error"
            text: PhoneCamera.lastError
        }

        ContentSection {
            icon: "videocam"
            shape: MaterialShape.Shape.Cookie7Sided
            title: Translation.tr("Camera")

            RippleButton {
                Layout.fillWidth: true
                Layout.preferredHeight: Appearance.font.pixelSize.huge * 2 + Appearance.spacing.space150
                enabled: root.canStart || PhoneCamera.active || PhoneCamera.connecting
                buttonRadius: Appearance.rounding.normal
                colBackground: PhoneCamera.active ? Appearance.colors.colErrorContainer : Appearance.colors.colPrimaryContainer
                colBackgroundHover: PhoneCamera.active ? Appearance.colors.colErrorContainerHover : Appearance.colors.colPrimaryContainerHover
                colRipple: PhoneCamera.active ? Appearance.colors.colErrorContainerActive : Appearance.colors.colPrimaryContainerActive
                onClicked: PhoneCamera.toggle()

                contentItem: RowLayout {
                    spacing: Appearance.spacing.space125

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: PhoneCamera.active ? "stop_circle" : "play_circle"
                        fill: PhoneCamera.active ? 1 : 0
                        iconSize: Appearance.font.pixelSize.hugeass
                        color: PhoneCamera.active ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimaryContainer
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: PhoneCamera.connecting ? Translation.tr("Connecting…")
                            : PhoneCamera.active ? Translation.tr("Stop the camera")
                            : Translation.tr("Start the camera")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: PhoneCamera.active ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimaryContainer
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        visible: PhoneCamera.active && PhoneCamera.device.length > 0
                        text: PhoneCamera.device
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: Appearance.font.family.monospace
                        color: Appearance.colors.colOnErrorContainer
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: Appearance.spacing.space100
                visible: PhoneCamera.active
                text: Translation.tr("Running for %1 · %2:%3")
                    .arg(PhoneCards.formatElapsed(PhoneCards.elapsedMs(PhoneCamera.startedAt, clock.nowMs)))
                    .arg(PhoneCamera.activeIp || Translation.tr("usb"))
                    .arg(PhoneCamera.activePort)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.space100

                RippleButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Appearance.font.pixelSize.huge + Appearance.spacing.space250
                    buttonRadius: Appearance.rounding.normal
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    // DroidCam has no flag for which camera it opens - the app
                    // on the phone decides - so this records the preference
                    // the next fresh start uses.
                    onClicked: PhoneCamera.flip()

                    contentItem: RowLayout {
                        spacing: Appearance.spacing.space75

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "cameraswitch"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            text: Translation.tr("Flip camera")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer2
                        }
                    }
                }

                RippleButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Appearance.font.pixelSize.huge + Appearance.spacing.space250
                    enabled: PhoneCamera.active && PhoneCamera.device.length > 0
                    buttonRadius: Appearance.rounding.normal
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: PhoneCamera.openPreview()

                    contentItem: RowLayout {
                        spacing: Appearance.spacing.space75

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "preview"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            text: Translation.tr("Preview")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer2
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "video_settings"
            shape: MaterialShape.Shape.Clover4Leaf
            title: Translation.tr("Camera settings")

            GroupedList {
                ConfigSelectionArray {
                    text: Translation.tr("Camera")
                    icon: "photo_camera"
                    infoText: Translation.tr("DroidCam has no flag for this - the app on the phone picks the lens. The choice is recorded and applies from the next start.")
                    currentValue: root.webcamConfig?.cameraFacing ?? "front"
                    onSelected: value => Config.options.phone.webcam.cameraFacing = value
                    options: [
                        { displayName: Translation.tr("Front"), value: "front", icon: "camera_front" },
                        { displayName: Translation.tr("Back"), value: "back", icon: "camera_rear" }
                    ]
                }

                ConfigSelectionArray {
                    text: Translation.tr("Resolution")
                    icon: "aspect_ratio"
                    currentValue: root.webcamConfig?.resolution ?? "1280x720"
                    onSelected: value => Config.options.phone.webcam.resolution = value
                    options: [
                        { displayName: Translation.tr("480p"), value: "640x480", icon: "sd" },
                        { displayName: Translation.tr("720p"), value: "1280x720", icon: "hd" },
                        { displayName: Translation.tr("1080p"), value: "1920x1080", icon: "high_quality" }
                    ]
                }

                ConfigSelectionArray {
                    text: Translation.tr("Rotation")
                    icon: "screen_rotation"
                    infoText: Translation.tr("180° is the only turn droidcam-cli can make - it is both flips at once. 90° and 270° would need a filter this stream does not run through.")
                    currentValue: root.webcamConfig?.rotateDegrees ?? 0
                    onSelected: value => Config.options.phone.webcam.rotateDegrees = value
                    options: [
                        { displayName: Translation.tr("None"), value: 0, icon: "crop_din" },
                        { displayName: Translation.tr("180°"), value: 180, icon: "flip" }
                    ]
                }

                ConfigSwitch {
                    iconChip: true
                    buttonIcon: "flip"
                    text: Translation.tr("Mirror horizontally")
                    // Through the service, not straight into the config: a
                    // running stream is re-flipped live with v4l2-ctl, and the
                    // service is the only thing that knows the device node.
                    checked: root.webcamConfig?.mirrorHorizontally ?? false
                    onToggleRequested: PhoneCamera.mirror(!(root.webcamConfig?.mirrorHorizontally ?? false))
                }
            }
        }

        ContentSection {
            icon: "cable"
            shape: MaterialShape.Shape.Slanted
            title: Translation.tr("Connection")

            GroupedList {
                ConfigSelectionArray {
                    text: Translation.tr("Connect over")
                    icon: "settings_ethernet"
                    infoText: Translation.tr("Automatic prefers USB whenever adb can reach the phone, then the address KDE Connect reports for it.")
                    currentValue: root.webcamConfig?.connection ?? "wifi"
                    onSelected: value => Config.options.phone.webcam.connection = value
                    options: [
                        { displayName: Translation.tr("Automatic"), value: "wifi", icon: "auto_mode" },
                        { displayName: Translation.tr("USB"), value: "usb", icon: "usb" }
                    ]
                }

                ConfigTextArea {
                    id: webcamIpField
                    // `rowVisible`, never `visible`: a GroupedList row hidden
                    // with `visible` keeps a full-height empty plate.
                    property bool rowVisible: (root.webcamConfig?.connection ?? "wifi") !== "usb"
                    Layout.fillWidth: true
                    floatingLabel: true
                    buttonIcon: "lan"
                    text: Translation.tr("Phone address (empty = ask KDE Connect)")
                    value: root.webcamConfig?.wifiIp ?? ""
                    // Debounced: every keystroke otherwise re-evaluates the
                    // connection plan the camera service builds from it.
                    onValueChanged: webcamIpDebounce.restart()

                    Timer {
                        id: webcamIpDebounce
                        interval: 600
                        onTriggered: Config.options.phone.webcam.wifiIp = webcamIpField.value
                    }
                }

                ConfigSpinBox {
                    icon: "tag"
                    text: Translation.tr("DroidCam port")
                    infoText: Translation.tr("The port the DroidCam app shows on the phone. 4747 is its default.")
                    value: root.webcamConfig?.port ?? 4747
                    from: 1024
                    to: 65535
                    stepSize: 1
                    onValueModified: Config.options.phone.webcam.port = newValue
                }
            }
        }
    }

    // The elapsed clock, running only while the stream is up.
    QtObject {
        id: clock
        property real nowMs: Date.now()
    }

    Timer {
        interval: 1000
        repeat: true
        running: PhoneCamera.active && root.visible
        onTriggered: clock.nowMs = Date.now()
    }

    // The same guide the feature card opens, filled to the panel rather than
    // to this page: the per-distro command blocks do not fit in a column. It
    // is reparented onto the window's own content item, which is the only
    // thing spanning the panel that this page may reach.
    InstallGuidePopup {
        id: installGuide
        property bool shown: false

        parent: root.Window.contentItem ?? root
        anchors.fill: parent
        visible: installGuide.shown
        z: 9999
        dependencies: PhoneDeps.missingFor("webcam")
        detectedDistro: PhoneDeps.distro
        headerTitle: Translation.tr("Phone Webcam — missing dependencies")
        onCloseRequested: installGuide.shown = false
        onRecheckRequested: PhoneDeps.recheck()
    }
}
