import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.imi.phone
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * The Phone tab: the paired phone on a chip with its state as pills, one
 * row of six actions, two navigation cards, the notification list owning
 * whatever height is left, a footer toolbar, and the secondary features
 * stacked at the bottom.
 *
 * Design: docs/superpowers/specs/2026-08-27-phone-tab-design.md. It
 * replaces the right sidebar's Phone Connect dialog; that toggle's menu
 * opens this tab now.
 *
 * ---- The interface this file is one half of -------------------------------
 *
 * The tab is built by two workstreams and this is the seam between them.
 * Written down here rather than agreed in a conversation, because the two
 * halves are edited independently and an interface nobody can read drifts.
 *
 *  - SUB-PAGES are `PhoneSubPage`-rooted Items with `signal back()`. This
 *    file hosts exactly ONE at a time in `subPageLoader`, selected by a
 *    string id - "contacts" | "apps" | "webcam" | "mic" - resolved to a
 *    FILE NAME through `subPageSource()`, so a page that has not landed
 *    yet leaves the Loader in error with a null item rather than failing
 *    this file's compile. `PhoneContactsPage.qml`, `PhoneAppsPage.qml`,
 *    `PhoneWebcamPage.qml` and `PhoneMicPage.qml` are the other half's.
 *    The page is popped by its own `back()` and by Escape; nothing else
 *    may write `subPage`.
 *
 *  - THE BOTTOM CARD STACK is `PhoneFeatureCards.qml` - the other half's
 *    too, along with `PhoneFeatureCard.qml` and `InstallGuidePopup.qml`.
 *    It is loaded last in the column with `Layout.fillWidth: true`, and
 *    its `signal openPage(string id)` opens "webcam" / "mic" through the
 *    same loader the nav cards' "contacts" / "apps" go through. Absent, the
 *    Loader draws nothing and the column simply ends at the footer.
 *
 *  - PAIRING CARDS are drawn HERE, above that Loader, rather than in the
 *    feature stack the spec groups them with: answering a pairing request
 *    is the only way into the shell for a phone that is not paired yet,
 *    and the dialog that used to carry it is gone - hanging it off a file
 *    that may not exist would make pairing unreachable.
 */
Item {
    id: root

    // Which device the chip, the pills and the actions are about: the
    // roster row the user picked, else whatever the service considers
    // active, else the first one there is. The pick is session state as
    // well as persisted, because a roster row for an UNPAIRED device is
    // exactly what the user clicks to see its pairing card - and
    // PhoneConnect.activeDevice will never answer with one.
    property string pickedDeviceId: ""
    readonly property var device: PhoneConnect.devices.find(d => d.id === root.pickedDeviceId)
        ?? PhoneConnect.activeDevice
        ?? (PhoneConnect.devices[0] ?? null)
    readonly property bool online: root.device !== null
        && root.device.paired && root.device.reachable

    property bool rosterOpen: false

    // "" | "contacts" | "apps" | "webcam" | "mic"
    property string subPage: ""
    // What the loader is holding, which outlives `subPage` for the length
    // of the exit - clearing it with the request would destroy the page on
    // frame one and leave nothing to animate out.
    property string shownSubPage: ""
    property real subPageProgress: root.subPage !== "" ? 1 : 0

    // One tier for both directions, deliberately: Qt refuses a second write
    // to a Behavior's animation, so a directional pair would have to be a
    // duration and a curve written onto a bare NumberAnimation - half a
    // tier, and silently Easing.Linear the day someone drops the curve.
    Behavior on subPageProgress {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    onSubPageChanged: {
        if (root.subPage !== "")
            root.shownSubPage = root.subPage;
    }
    onSubPageProgressChanged: {
        if (root.subPageProgress === 0)
            root.shownSubPage = "";
    }

    function openSubPage(id: string): void {
        root.subPage = id;
    }

    function popSubPage(): void {
        root.subPage = "";
    }

    // A file name, never a type: the other half's pages are resolved by
    // URL so a missing one is a Loader error rather than this file failing
    // to compile.
    function subPageSource(id: string): string {
        switch (id) {
        case "contacts": return "PhoneContactsPage.qml";
        case "apps": return "PhoneAppsPage.qml";
        case "webcam": return "PhoneWebcamPage.qml";
        case "mic": return "PhoneMicPage.qml";
        default: return "";
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape && root.subPage !== "") {
            root.popSubPage();
            event.accepted = true;
        }
    }

    // ---- the tab itself ---------------------------------------------------

    ColumnLayout {
        id: phoneColumn
        anchors.fill: parent
        anchors.margins: Appearance.spacing.space125
        spacing: Appearance.spacing.space125

        opacity: 1 - root.subPageProgress
        // A page on top is a picture, not a control: a click landing on the
        // tab mid-slide is aimed at the page the pointer moved toward.
        enabled: root.subPage === ""

        StaggerWave {
            id: entrance
            target: phoneColumn
        }
        StaggerEntrance {
            target: phoneColumn
            reference: root.width
        }

        PhoneHeader {
            id: header
            Layout.fillWidth: true
            device: root.device
            rosterOpen: root.rosterOpen
            onToggleRoster: root.rosterOpen = !root.rosterOpen
        }

        // The roster behind the chip's arrow. Not a wave member: it is
        // folded at every open, and a member that is off screen when the
        // wave runs takes no slot anyway.
        ColumnLayout {
            id: roster
            Layout.fillWidth: true
            visible: root.rosterOpen
            spacing: 0

            Repeater {
                model: ScriptModel {
                    values: PhoneConnect.devices
                }
                delegate: PhoneDeviceItem {
                    required property var modelData
                    device: modelData
                    Layout.fillWidth: true
                    active: root.device !== null && root.device.id === modelData.id
                    onClicked: {
                        root.pickedDeviceId = modelData.id;
                        PhoneConnect.selectDevice(modelData.id);
                        root.rosterOpen = false;
                    }
                }
            }
        }

        PhoneActionsRow {
            id: actionsRow
            Layout.fillWidth: true
            device: root.device
        }

        PhoneNavCards {
            id: navCards
            Layout.fillWidth: true
            onOpenPage: pageId => root.openSubPage(pageId)
        }

        PhoneNotificationList {
            id: notificationList
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        PhoneFooterBar {
            id: footerBar
            Layout.fillWidth: true
            online: root.online
        }

        Repeater {
            model: ScriptModel {
                values: PhoneConnect.pairingRequests
            }
            delegate: PhonePairingCard {
                required property var modelData
                device: modelData
                Layout.fillWidth: true
            }
        }

        Loader {
            id: featureCardsLoader
            property real appear: 1
            Layout.fillWidth: true
            source: Qt.resolvedUrl("PhoneFeatureCards.qml")

            onLoaded: {
                if (featureCardsLoader.item?.openPage !== undefined)
                    featureCardsLoader.item.openPage.connect(root.openSubPage);
            }
        }
    }

    // ---- files dropped on the tab go to the phone -------------------------

    DropArea {
        id: shareDrop
        anchors.fill: parent
        enabled: root.online && PhoneConnect.canShare && root.subPage === ""

        onDropped: drop => {
            const urls = (drop.urls ?? []).map(url => String(url));
            if (urls.length === 0) return;
            PhoneConnect.shareUrls(root.device, urls);
            drop.accept(Qt.CopyAction);
        }

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.normal
            color: Appearance.colors.colPrimaryContainer
            opacity: shareDrop.containsDrag ? 0.9 : 0
            visible: opacity > 0

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Appearance.spacing.space100

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "upload_file"
                    iconSize: 56
                    color: Appearance.colors.colOnPrimaryContainer
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Drop the file here")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnPrimaryContainer
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Ready to send to %1").arg(root.device?.name ?? "")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
        }
    }

    // ---- the one sub-page, sliding over the tab ---------------------------

    Item {
        id: subPageHost
        anchors.fill: parent
        anchors.margins: Appearance.spacing.space125
        opacity: root.subPageProgress
        visible: opacity > 0

        Loader {
            id: subPageLoader
            width: parent.width
            height: parent.height
            // Explicit size rather than anchors, so the travel is free to
            // write x - an anchored Loader owns that coordinate.
            x: (1 - root.subPageProgress) * root.width
            active: root.shownSubPage !== ""
            source: root.shownSubPage !== ""
                ? Qt.resolvedUrl(root.subPageSource(root.shownSubPage))
                : ""

            onLoaded: {
                if (subPageLoader.item?.back !== undefined)
                    subPageLoader.item.back.connect(root.popSubPage);
            }
        }
    }

    // ---- what the last action had to say ----------------------------------

    Rectangle {
        id: toast
        z: 9999
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: Appearance.spacing.space150

        property string message: ""
        property bool ok: true

        implicitWidth: toastRow.implicitWidth + Appearance.spacing.space300
        implicitHeight: toastRow.implicitHeight + Appearance.spacing.space150
        radius: Appearance.rounding.full
        color: toast.ok ? Appearance.colors.colPrimaryContainer : Appearance.colors.colErrorContainer
        opacity: toastTimer.running ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Timer {
            id: toastTimer
            interval: 2800
        }

        RowLayout {
            id: toastRow
            anchors.centerIn: parent
            spacing: Appearance.spacing.space100

            MaterialSymbol {
                text: toast.ok ? "check_circle" : "error"
                iconSize: Appearance.font.pixelSize.larger
                color: toast.ok ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnErrorContainer
            }
            StyledText {
                text: toast.message
                font.pixelSize: Appearance.font.pixelSize.small
                color: toast.ok ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnErrorContainer
            }
        }
    }

    Connections {
        target: PhoneConnect
        function onActionFeedback(message: string, ok: bool): void {
            toast.message = message;
            toast.ok = ok;
            toastTimer.restart();
        }
    }

    // The entrance rides the sidebar's open flag, the way
    // SidebarLeftContent's own does - and the wave holds itself until this
    // page is the one on screen, since a SwipeView page that is not current
    // reports every member off screen (StaggerWave's pendingEnter).
    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            if (GlobalStates.sidebarLeftOpen) {
                entrance.park();
                entrance.enter();
            }
        }
    }
}
