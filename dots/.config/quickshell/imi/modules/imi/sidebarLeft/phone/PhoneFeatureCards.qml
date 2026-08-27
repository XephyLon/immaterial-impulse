pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.imi.phone
import "phone_cards.js" as PhoneCards

/**
 * The Phone tab's bottom card stack: the scrcpy mirror, the phone webcam, the
 * phone microphone, and one pairing card per peer that has asked to pair.
 *
 * This is the ONE place a card's click becomes a service call, which is what
 * makes "a button whose call no service answers is a fake action" checkable:
 * tests/test_phone_tab_surface_contract.py resolves every `PhoneX.member` in
 * this directory against what the services declare. Two of the sibling fork's
 * chips are deliberately absent for that reason - it offers "phone
 * screenshot", "toggle phone power" and "hear yourself", and PhoneScrcpy and
 * PhoneMic answer none of the three.
 *
 * The stack is one Item the tab places last in its column. It reads nothing
 * from the tab and announces what it cannot do itself: `openPage(id)` with
 * "webcam" or "mic".
 *
 * `showPeripheralCards` hides the three FEATURE cards only. A pairing request
 * is a question a peer asked, not a peripheral, and dropping it because the
 * cards are off would leave no way to answer it.
 */
Item {
    id: root

    signal openPage(string id)

    implicitHeight: stack.implicitHeight

    readonly property bool showCards: Config.options.phone?.showPeripheralCards ?? true
    readonly property var activeDevice: PhoneConnect.activeDevice
    readonly property bool deviceReachable: PhoneConnect.activeDevice?.reachable === true

    // The elapsed clock for whichever cards are running. A Timer rather than
    // DateTime's own: that clock ticks per MINUTE unless the user asked for
    // seconds, and this line counts in them. It runs only while something is
    // active, so an idle tab costs no frames.
    property real nowMs: Date.now()
    readonly property bool anyActive: PhoneScrcpy.mirrorRunning || PhoneCamera.active || PhoneMic.active

    Timer {
        interval: 1000
        repeat: true
        running: root.anyActive && root.visible
        onTriggered: root.nowMs = Date.now()
    }

    onAnyActiveChanged: root.nowMs = Date.now()

    // PhoneScrcpy's session rows carry `startedAt` in milliseconds (Date.now()
    // at the moment the supervisor reported the window), where PhoneCamera and
    // PhoneMic carry whole UNIX seconds off their session script's state file.
    // The two are converted at their own call sites rather than by pretending
    // one of them is the other.
    readonly property real mirrorStartedAtMs: {
        // sessionCount is read to make this a binding: a ListModel is not a
        // property, so nothing here would re-evaluate on an append without it.
        const count = PhoneScrcpy.sessionCount;
        if (count === 0)
            return 0;
        const index = PhoneScrcpy.sessionIndex("mirror");
        return index >= 0 ? Number(PhoneScrcpy.sessions.get(index).startedAt) : 0;
    }

    function openInstallGuide(feature: string, title: string): void {
        installGuide.feature = feature;
        installGuide.headerTitle = title;
        installGuide.shown = true;
    }

    ColumnLayout {
        id: stack
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        spacing: Appearance.spacing.space100

        // ---- 1. the scrcpy mirror ----
        PhoneFeatureCard {
            id: mirrorCard
            Layout.fillWidth: true
            visible: root.showCards

            readonly property var flags: ({
                available: PhoneScrcpy.available,
                reachable: root.deviceReachable,
                running: PhoneScrcpy.mirrorRunning,
                launching: PhoneScrcpy.mirrorLaunching,
                error: PhoneScrcpy.lastError
            })

            iconName: "smart_display"
            iconShape: MaterialShape.Shape.Cookie9Sided
            cardState: PhoneCards.mirrorState(mirrorCard.flags)
            title: {
                switch (PhoneCards.mirrorTitleKey(mirrorCard.flags)) {
                case "install":
                    return Translation.tr("Install scrcpy");
                case "running":
                    return Translation.tr("scrcpy Mirror");
                case "connecting":
                    return Translation.tr("Connecting scrcpy…");
                default:
                    return Translation.tr("Open scrcpy Mirror");
                }
            }
            subtitle: {
                switch (PhoneCards.mirrorSubtitleKey(mirrorCard.flags)) {
                case "install":
                    return Translation.tr("Click to see missing dependencies and install guide");
                case "offline":
                    return Translation.tr("Pair a reachable device to mirror its screen");
                case "error":
                    return PhoneCards.errorHeadline(PhoneScrcpy.lastError);
                case "running":
                    return Translation.tr("Mirror is running · click to focus its window");
                case "launching":
                    return Translation.tr("Launching scrcpy…");
                default:
                    return Translation.tr("Opens a floating window for the active phone");
                }
            }
            detailLine: PhoneScrcpy.mirrorRunning && root.mirrorStartedAtMs > 0
                ? Translation.tr("Active for %1").arg(PhoneCards.formatElapsed(root.nowMs - root.mirrorStartedAtMs))
                : ""
            // A running mirror's own launch error is over; what is in
            // `lastError` by then belongs to some other session (see
            // phone_cards.js on why the subtitle asks running first).
            lastError: ""
            inlineActions: [
                {
                    icon: "center_focus_strong",
                    label: Translation.tr("Focus the mirror window"),
                    action: () => PhoneScrcpy.focusMirror()
                }
            ]
            // Sharing a file with the phone is KDE Connect's, not scrcpy's -
            // the mirror card is simply where a file dropped on a running
            // phone session naturally lands.
            dropEnabled: root.deviceReachable && PhoneConnect.canShare
            onFilesDropped: urls => PhoneConnect.shareUrls(root.activeDevice, urls)

            onClicked: {
                if (!PhoneScrcpy.available) {
                    root.openInstallGuide("mirror", Translation.tr("scrcpy Mirror — missing dependencies"));
                    return;
                }
                if (PhoneScrcpy.mirrorLaunching)
                    return;
                // launchMirror() focuses an already-running mirror itself, so
                // there is one call here rather than a second copy of that
                // decision.
                PhoneScrcpy.launchMirror();
            }
            onStopClicked: PhoneScrcpy.stopMirror()
        }

        // ---- 2. the phone as a webcam ----
        PhoneFeatureCard {
            id: webcamCard
            Layout.fillWidth: true
            visible: root.showCards

            readonly property var flags: ({
                available: PhoneCamera.available,
                reachable: root.deviceReachable,
                connecting: PhoneCamera.connecting,
                active: PhoneCamera.active,
                device: PhoneCamera.device
            })

            iconName: "videocam"
            iconShape: MaterialShape.Shape.Cookie7Sided
            hasSettings: true
            cardState: PhoneCamera.state
            title: PhoneCards.webcamTitleKey(PhoneCamera.available) === "install"
                ? Translation.tr("Install DroidCam")
                : Translation.tr("Phone Webcam")
            subtitle: {
                switch (PhoneCards.webcamSubtitleKey(webcamCard.flags)) {
                case "install":
                    return Translation.tr("Click to see missing dependencies and install guide");
                case "offline":
                    return Translation.tr("Pair a reachable device to use its camera");
                case "connecting":
                    return Translation.tr("Connecting to the phone's camera…");
                case "device":
                    return PhoneCamera.device;
                case "running":
                    return Translation.tr("Streaming from the phone's camera");
                default:
                    return Translation.tr("Tap to start · settings to configure");
                }
            }
            detailLine: {
                if (!PhoneCamera.active)
                    return "";
                const elapsed = PhoneCards.formatElapsed(PhoneCards.elapsedMs(PhoneCamera.startedAt, root.nowMs));
                const target = (PhoneCamera.activeIp || Translation.tr("usb")) + ":" + PhoneCamera.activePort;
                return Translation.tr("Active for %1 · %2 · %3")
                    .arg(elapsed).arg(target).arg(PhoneCamera.device || "—");
            }
            lastError: PhoneCamera.lastError
            inlineActions: [
                {
                    icon: "preview",
                    label: Translation.tr("Open a preview window"),
                    action: () => PhoneCamera.openPreview()
                },
                {
                    icon: "cameraswitch",
                    label: Translation.tr("Switch the camera the app uses"),
                    action: () => PhoneCamera.flip()
                }
            ]

            onClicked: {
                if (!PhoneCamera.available) {
                    root.openInstallGuide("webcam", Translation.tr("Phone Webcam — missing dependencies"));
                    return;
                }
                PhoneCamera.toggle();
            }
            onSettingsClicked: root.openPage("webcam")
            onStopClicked: PhoneCamera.stop()
        }

        // ---- 3. the phone as a microphone ----
        PhoneFeatureCard {
            id: micCard
            Layout.fillWidth: true
            visible: root.showCards

            readonly property var flags: ({
                available: PhoneMic.available,
                reachable: root.deviceReachable,
                connecting: PhoneMic.connecting,
                active: PhoneMic.active,
                muted: PhoneMic.muted
            })

            iconName: "mic"
            iconShape: MaterialShape.Shape.Sunny
            hasSettings: true
            cardState: PhoneMic.state
            title: PhoneCards.micTitleKey(PhoneMic.available) === "install"
                ? Translation.tr("Install scrcpy or DroidCam")
                : Translation.tr("Phone Microphone")
            subtitle: {
                switch (PhoneCards.micSubtitleKey(micCard.flags)) {
                case "install":
                    return Translation.tr("Click to see missing dependencies and install guide");
                case "offline":
                    return Translation.tr("Pair a reachable device to use its microphone");
                case "connecting":
                    return Translation.tr("Setting up audio routing…");
                case "muted":
                    return Translation.tr("Muted · click to unmute");
                case "active":
                    return Translation.tr("Active · click to mute");
                default:
                    return Translation.tr("Tap to start · uses scrcpy or DroidCam");
                }
            }
            detailLine: {
                if (!PhoneMic.active)
                    return "";
                const elapsed = PhoneCards.formatElapsed(PhoneCards.elapsedMs(PhoneMic.startedAt, root.nowMs));
                const suffix = PhoneMic.isDefaultInput ? Translation.tr("default input") : PhoneMic.backend;
                return Translation.tr("Active for %1 · %2% · %3")
                    .arg(elapsed).arg(PhoneMic.gain).arg(suffix);
            }
            lastError: PhoneMic.lastError
            inlineActions: [
                {
                    icon: PhoneMic.muted ? "mic_off" : "mic",
                    label: PhoneMic.muted ? Translation.tr("Unmute") : Translation.tr("Mute"),
                    action: () => PhoneMic.toggleMute()
                },
                {
                    icon: "tune",
                    // The gain cycle is the sibling fork's: 100 -> 150 -> 200
                    // -> 50 -> 100, so one chip reaches every useful level
                    // without a slider on a 68px card.
                    label: Translation.tr("Gain: %1%").arg(PhoneMic.gain),
                    action: () => {
                        const gain = PhoneMic.gain;
                        PhoneMic.setGain(gain < 100 ? 100 : gain < 150 ? 150 : gain < 200 ? 200 : 50);
                    }
                },
                {
                    icon: PhoneMic.isDefaultInput ? "star" : "star_border",
                    label: PhoneMic.isDefaultInput
                        ? Translation.tr("Restore the previous default input")
                        : Translation.tr("Set as the default input"),
                    action: () => {
                        if (PhoneMic.isDefaultInput)
                            PhoneMic.restoreDefaultInput();
                        else
                            PhoneMic.setAsDefaultInput();
                    }
                }
            ]

            onClicked: {
                if (!PhoneMic.available) {
                    root.openInstallGuide("microphone", Translation.tr("Phone Microphone — missing dependencies"));
                    return;
                }
                // A running microphone's primary click mutes rather than
                // stops: muting is the thing wanted in a hurry, and the Stop
                // button is right there for the other one.
                if (PhoneMic.active) {
                    PhoneMic.toggleMute();
                    return;
                }
                PhoneMic.toggle();
            }
            onSettingsClicked: root.openPage("mic")
            onStopClicked: PhoneMic.stop()
        }

        // ---- 4. a card per peer asking to pair ----
        Repeater {
            model: PhoneConnect.pairingRequests

            delegate: PhoneConnectPairingCard {
                required property var modelData
                Layout.fillWidth: true
                device: modelData
            }
        }
    }

    // The guide covers the phone panel rather than the three cards it was
    // opened from: a per-distro command block does not fit in 200px. It is
    // reparented onto the window's own content item, which is the only thing
    // reachable from here that spans the panel - this component may not read
    // anything off the tab that hosts it.
    InstallGuidePopup {
        id: installGuide
        property bool shown: false
        // Which feature the guide was opened for, so a re-check that resolves
        // it can close it. Declared here rather than on the component: the
        // popup itself is handed a dependency list and knows nothing about
        // scrcpy, DroidCam or the microphone.
        property string feature: ""

        parent: root.Window.contentItem ?? root
        anchors.fill: parent
        visible: installGuide.shown
        z: 9999
        // A binding, not an assignment: missingFor() reads every one of
        // PhoneDeps' presence flags, so a Re-check that installs something
        // empties this list on its own - and the popup dismisses itself when
        // it does. Assigning the list once instead left the guide showing
        // dependencies the probes had just stopped reporting.
        dependencies: installGuide.feature.length > 0
            ? PhoneDeps.missingFor(installGuide.feature)
            : []
        detectedDistro: PhoneDeps.distro
        onCloseRequested: installGuide.shown = false
        onRecheckRequested: PhoneDeps.recheck()
    }
}
