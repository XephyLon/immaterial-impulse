pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell

StyledListView { // Scrollable window
    id: root
    property bool popup: false

    spacing: Appearance.spacing.space50

    // The painted card of every realized delegate, for a caller that needs the
    // list's painted area rather than its bounding box - the popup window's
    // blur region (see NotificationPopup.qml). The bounding box would swallow
    // the gaps between cards, and blurring a gap frosts bare wallpaper exactly
    // where the card's shadow falls.
    //
    // Recomputed on membership changes only: a Region tracks its item's
    // geometry itself, so cards resizing or sliding need no rebuild.
    property var cardItems: []

    function refreshCardItems(): void {
        let items = [];
        const children = root.contentItem?.children ?? [];
        for (let i = 0; i < children.length; i++) {
            // contentItem also holds children that are not delegates (the
            // highlight items a ListView makes), which have no card.
            const card = children[i]?.blurItem ?? null;
            if (card)
                items.push(card);
        }
        root.cardItems = items;
    }

    // Delegates are built a beat after the count changes, so read the children
    // once the current pass of the event loop has created them.
    onCountChanged: Qt.callLater(root.refreshCardItems)
    Component.onCompleted: Qt.callLater(root.refreshCardItems)

    model: ScriptModel {
        values: root.popup ? Notifications.popupAppNameList : Notifications.appNameList
    }
    delegate: NotificationGroup {
        required property int index
        required property var modelData
        popup: root.popup
        width: ListView.view.width // https://doc.qt.io/qt-6/qml-qtquick-listview.html
        notificationGroup: popup ? 
            Notifications.popupGroupsByAppName[modelData] :
            Notifications.groupsByAppName[modelData]
    }
}
