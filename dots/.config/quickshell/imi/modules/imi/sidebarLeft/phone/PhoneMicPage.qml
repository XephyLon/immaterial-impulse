pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "phone_cards.js" as PhoneCards

/**
 * The Phone tab's Phone Microphone sub-page: the stream's toggle, its level,
 * and where it is routed.
 *
 * Rooted on `PhoneSubPage` (W5a's; the interface is pinned by the stub at
 * tests/imports/qs/modules/imi/sidebarLeft/phone/PhoneSubPage.qml), with a
 * `ContentPage` inside it so the sections scroll.
 *
 * Two rows the sibling fork's page has are deliberately not here, and both
 * for the same reason: PhoneMic answers neither call.
 *
 *   - "Hear yourself" is a `pactl load-module module-loopback` on the null
 *     sink's monitor. PhoneMic only ever UNLOADS loopbacks (it clears one a
 *     previous session left behind); nothing loads one. Drawing the toggle
 *     would be a button whose call no service answers.
 *   - Noise suppression, echo cancellation and auto gain are three config
 *     keys in that fork that nothing reads - `Config.qml` declares none of
 *     them here, and a control bound to an undeclared key reads `undefined`,
 *     takes its fallback for ever, and is destroyed by the JsonAdapter's
 *     first write.
 */
PhoneSubPage {
    id: root

    title: Translation.tr("Phone Microphone")

    readonly property var micConfig: Config.options.phone?.microphone
    readonly property bool deviceReachable: PhoneConnect.activeDevice?.reachable === true
    readonly property bool canStart: PhoneMic.available && root.deviceReachable

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
        // the panel has - 495px for a failed launch's own message in a 440px
        // page, which is what `Math.max(baseWidth, implicitWidth)` above was
        // widening on. Capped, the banner wraps inside itself instead of
        // moving the page.
        NoticeBox {
            Layout.fillWidth: true
            Layout.maximumWidth: page.baseWidth
            visible: !PhoneMic.available
            materialIcon: "download"
            text: Translation.tr("The phone microphone is not set up on this machine. %1 is missing.")
                .arg(PhoneDeps.missingFor("microphone").map(dependency => dependency.name).join(", "))

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
            visible: PhoneMic.available && !root.deviceReachable
            materialIcon: "phonelink_off"
            text: Translation.tr("No phone is reachable. Pair one in KDE Connect and bring it onto the network.")
        }

        NoticeBox {
            Layout.fillWidth: true
            Layout.maximumWidth: page.baseWidth
            visible: PhoneMic.lastError.length > 0
            materialIcon: "error"
            text: PhoneMic.lastError
        }

        ContentSection {
            icon: "mic"
            shape: MaterialShape.Shape.Sunny
            title: Translation.tr("Microphone")

            RippleButton {
                Layout.fillWidth: true
                Layout.preferredHeight: Appearance.font.pixelSize.huge * 2 + Appearance.spacing.space150
                enabled: root.canStart || PhoneMic.active || PhoneMic.connecting
                buttonRadius: Appearance.rounding.normal
                colBackground: PhoneMic.active ? Appearance.colors.colErrorContainer : Appearance.colors.colPrimaryContainer
                colBackgroundHover: PhoneMic.active ? Appearance.colors.colErrorContainerHover : Appearance.colors.colPrimaryContainerHover
                colRipple: PhoneMic.active ? Appearance.colors.colErrorContainerActive : Appearance.colors.colPrimaryContainerActive
                onClicked: PhoneMic.toggle()

                contentItem: RowLayout {
                    spacing: Appearance.spacing.space125

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: PhoneMic.active ? "stop_circle" : "play_circle"
                        fill: PhoneMic.active ? 1 : 0
                        iconSize: Appearance.font.pixelSize.hugeass
                        color: PhoneMic.active ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimaryContainer
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: PhoneMic.connecting ? Translation.tr("Setting up audio routing…")
                            : PhoneMic.active ? Translation.tr("Stop the microphone")
                            : Translation.tr("Start the microphone")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: PhoneMic.active ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimaryContainer
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: Appearance.spacing.space100
                visible: PhoneMic.active
                // The source name is what a recording application will be
                // looking for in its own input list, so it is said in full.
                text: Translation.tr("Running for %1 · %2 · recording source %3")
                    .arg(PhoneCards.formatElapsed(PhoneCards.elapsedMs(PhoneMic.startedAt, clock.nowMs)))
                    .arg(PhoneMic.backend)
                    .arg(PhoneMic.pulseSource)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
            }

            RippleButton {
                Layout.fillWidth: true
                Layout.preferredHeight: Appearance.font.pixelSize.huge + Appearance.spacing.space250
                enabled: PhoneMic.active
                buttonRadius: Appearance.rounding.normal
                colBackground: PhoneMic.muted ? Appearance.colors.colTertiaryContainer : Appearance.colors.colLayer2
                colBackgroundHover: PhoneMic.muted ? Appearance.colors.colTertiaryContainerHover : Appearance.colors.colLayer2Hover
                colRipple: PhoneMic.muted ? Appearance.colors.colTertiaryContainerActive : Appearance.colors.colLayer2Active
                onClicked: PhoneMic.toggleMute()

                contentItem: RowLayout {
                    spacing: Appearance.spacing.space100

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: PhoneMic.muted ? "mic_off" : "mic"
                        fill: PhoneMic.muted ? 1 : 0
                        iconSize: Appearance.font.pixelSize.larger
                        color: PhoneMic.muted ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnLayer2
                        animateChange: true
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: PhoneMic.muted ? Translation.tr("Unmute") : Translation.tr("Mute")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: PhoneMic.muted ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnLayer2
                    }
                }
            }
        }

        ContentSection {
            icon: "tune"
            shape: MaterialShape.Shape.Clover4Leaf
            title: Translation.tr("Level and routing")

            GroupedList {
                ConfigSlider {
                    text: Translation.tr("Input gain")
                    buttonIcon: "volume_up"
                    from: 0
                    to: 200
                    value: root.micConfig?.micGain ?? 100
                    usePercentTooltip: false
                    // setGain() writes the config at its source and applies the
                    // level to the live source, so there is one writer.
                    onValueModified: PhoneMic.setGain(newValue)
                }

                ConfigSwitch {
                    iconChip: true
                    buttonIcon: "star"
                    text: Translation.tr("Use as the default input now")
                    infoText: Translation.tr("Points every application that records at the phone until it stops, then puts the previous source back.")
                    enabled: PhoneMic.active
                    // The source of truth is the service's own record of
                    // whether it made the swap - the config key below is the
                    // separate question of what to do at the NEXT start.
                    checked: PhoneMic.isDefaultInput
                    onToggleRequested: {
                        if (PhoneMic.isDefaultInput)
                            PhoneMic.restoreDefaultInput();
                        else
                            PhoneMic.setAsDefaultInput();
                    }
                }

                ConfigSwitch {
                    iconChip: true
                    buttonIcon: "star_border"
                    text: Translation.tr("Make it the default input every time it starts")
                    checked: root.micConfig?.setAsDefault ?? false
                    onToggleRequested: Config.options.phone.microphone.setAsDefault = !(root.micConfig?.setAsDefault ?? false)
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
                    infoText: Translation.tr("Only the DroidCam backend uses this. The scrcpy backend reaches the phone through adb, which prefers USB on its own.")
                    currentValue: root.micConfig?.connection ?? "wifi"
                    onSelected: value => Config.options.phone.microphone.connection = value
                    options: [
                        { displayName: Translation.tr("Automatic"), value: "wifi", icon: "auto_mode" },
                        { displayName: Translation.tr("USB"), value: "usb", icon: "usb" }
                    ]
                }

                ConfigTextArea {
                    id: micIpField
                    // `rowVisible`, never `visible`: a GroupedList row hidden
                    // with `visible` keeps a full-height empty plate.
                    property bool rowVisible: (root.micConfig?.connection ?? "wifi") !== "usb"
                    Layout.fillWidth: true
                    floatingLabel: true
                    buttonIcon: "lan"
                    text: Translation.tr("Phone address (empty = ask KDE Connect)")
                    value: root.micConfig?.wifiIp ?? ""
                    onValueChanged: micIpDebounce.restart()

                    Timer {
                        id: micIpDebounce
                        interval: 600
                        onTriggered: Config.options.phone.microphone.wifiIp = micIpField.value
                    }
                }

                ConfigSpinBox {
                    icon: "tag"
                    text: Translation.tr("DroidCam audio port")
                    infoText: Translation.tr("The port the DroidCam app shows for audio. 4748 is its default; the scrcpy backend ignores it.")
                    value: root.micConfig?.port ?? 4748
                    from: 1024
                    to: 65535
                    stepSize: 1
                    onValueModified: Config.options.phone.microphone.port = newValue
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
        running: PhoneMic.active && root.visible
        onTriggered: clock.nowMs = Date.now()
    }

    // The same guide the feature card opens, filled to the panel rather than
    // to this page. Reparented onto the window's own content item, the only
    // thing spanning the panel that this page may reach.
    InstallGuidePopup {
        id: installGuide
        property bool shown: false

        parent: root.Window.contentItem ?? root
        anchors.fill: parent
        visible: installGuide.shown
        z: 9999
        dependencies: PhoneDeps.missingFor("microphone")
        detectedDistro: PhoneDeps.distro
        headerTitle: Translation.tr("Phone Microphone — missing dependencies")
        onCloseRequested: installGuide.shown = false
        onRecheckRequested: PhoneDeps.recheck()
    }
}
