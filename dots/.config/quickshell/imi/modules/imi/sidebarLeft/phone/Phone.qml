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

        // The outgoing half of the transition. The tab does not sit still
        // behind the page sliding over it: it fades AND recedes, so what the
        // eye reads is the tab going back a layer rather than being covered
        // up. Both channels ride `subPageProgress` - the ONE scalar, with the
        // one Behavior on it - because a second Behavior is two numbers that
        // have to agree, agreeing at rest (where nobody looks) and
        // disagreeing on exactly the frames the transition is made of.
        //
        // The scale's destination is derived, never picked:
        // `entranceScaleFrom` matches the excursion to the shell's entrance
        // rise at this panel's own width, floored at the survey's measured
        // 0.85, which is the same derivation every StaggerEntrance member
        // arrives on. A hand-picked 0.85 on a full-width column is a zoom.
        readonly property real recedeTo: Appearance.animation.entranceScaleFrom(root.width)
        opacity: 1 - root.subPageProgress
        scale: 1 - (1 - phoneColumn.recedeTo) * root.subPageProgress
        transformOrigin: Item.Center
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

        // The roster behind the chip's arrow: every device the daemon knows,
        // one selectable row each. Drawn by the component the Wi-Fi and the
        // Bluetooth dialogs already draw their device lists with - a
        // `StyledListView` of `DialogListItem` rows, which is exactly what
        // `PhoneDeviceItem` is - rather than by a `Repeater` of its own. What
        // that buys past one shape for three lists is the view's own
        // add/remove transitions on the shared tier: a device joining or
        // leaving the network becomes a row that arrives or leaves instead of
        // a column that jumps.
        //
        // Not a wave member: it is folded at every open, and a member that is
        // off screen when the wave runs takes no slot anyway.
        Item {
            id: rosterReveal
            Layout.fillWidth: true
            Layout.preferredHeight: rosterList.height
            visible: root.rosterOpen

            // The list stands at its OWN content height whatever this wrapper
            // is doing. A `ListView` told it is zero pixels tall builds no
            // delegates, so it reports a content height of zero and can never
            // grow out of it - the height that folds has to be a box around
            // the list rather than the list's own.
            StyledListView {
                id: rosterList
                width: rosterReveal.width
                height: rosterList.contentHeight
                interactive: false
                spacing: 0

                model: ScriptModel {
                    values: PhoneConnect.devices
                }
                delegate: PhoneDeviceItem {
                    required property var modelData
                    device: modelData
                    anchors {
                        left: parent?.left
                        right: parent?.right
                    }
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

        // What the toast may not cross. Any service's error string can reach
        // here - "DroidCam did not start - is the DroidCam app open on the
        // phone?" is a real one - and with the width taken from the row's own
        // implicit width and nothing above it, a long message drew a
        // full-width bar clipped at the panel edge with its text running off
        // the end. The bound comes from the panel and the spacing tokens
        // rather than from a guess about the longest string: the tab's own
        // column is inset by space125 on each side, and the toast sits inside
        // the same margin.
        readonly property real maxWidth: root.width - Appearance.spacing.space125 * 2
        readonly property real horizontalPadding: Appearance.spacing.space300

        implicitWidth: Math.min(toastRow.implicitWidth + toast.horizontalPadding, toast.maxWidth)
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
                id: toastGlyph
                Layout.alignment: Qt.AlignVCenter
                text: toast.ok ? "check_circle" : "error"
                iconSize: Appearance.font.pixelSize.larger
                color: toast.ok ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnErrorContainer
            }
            StyledText {
                id: toastLabel
                Layout.alignment: Qt.AlignVCenter
                // Measured off the PANEL, not off the toast: the toast's own
                // width is derived from this row's implicit width, so binding
                // the label to it closes that circle. Wrapping first and
                // eliding after keeps a two-line sentence readable and still
                // refuses to grow a third line into the tab's content.
                Layout.maximumWidth: toast.maxWidth - toast.horizontalPadding
                    - toastGlyph.implicitWidth - toastRow.spacing
                text: toast.message
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                color: toast.ok ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnErrorContainer
            }
        }
    }

    // Every service that can fail a gesture the user made on this tab reports
    // it here. PhoneConnect was the only one connected, so a scrcpy that could
    // not attach, a webcam that never connected and a microphone whose routing
    // failed all raised a signal nothing listened to - three services carrying
    // a "tell the user" channel with no listener, which is what a card that
    // "does nothing when clicked" looked like from outside. The cards' own
    // subtitles say the same thing once the state settles; the toast is what
    // says it at the moment of the click.
    function showToast(message: string, ok: bool): void {
        if (!message)
            return;
        toast.message = message;
        toast.ok = ok;
        toastTimer.restart();
    }

    Connections {
        target: PhoneConnect
        function onActionFeedback(message: string, ok: bool): void {
            root.showToast(message, ok);
        }
    }

    Connections {
        target: PhoneScrcpy
        function onFeedback(message: string, ok: bool): void {
            root.showToast(message, ok);
        }
    }

    Connections {
        target: PhoneCamera
        function onErrorOccurred(message: string): void {
            root.showToast(message, false);
        }
    }

    Connections {
        target: PhoneMic
        function onErrorOccurred(message: string): void {
            root.showToast(message, false);
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
