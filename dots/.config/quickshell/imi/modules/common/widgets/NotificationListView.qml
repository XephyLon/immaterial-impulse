pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell

StyledListView { // Scrollable window
    id: root
    property bool popup: false
    // See NotificationGroup. Handed to every card this view builds.
    property NotificationController controller: NotificationController {}

    spacing: Appearance.spacing.space50

    // Entrance transitions only while the view is on screen. A delegate built
    // while the sidebar's content was hidden (a notification arriving with
    // the panel closed, the list restored from file at startup) started its
    // add transition - opacity and scale from 0 - and the transition never
    // advanced: measured in a nested Hyprland, cards sat at 0.65/0.87/0.96
    // after sixteen arrivals with the panel closed, and at exactly 0 after a
    // restart, and stayed there when the panel opened. Only a card that took
    // a new notification while open was drawn again - the list read as blank
    // under a footer counting sixteen. So a view that is not visible adds
    // its cards at rest, and coming on screen settles anything a transition
    // left half way.
    animateAppearance: root.visible
    onVisibleChanged: {
        if (root.visible)
            Qt.callLater(root.settleDelegates);
    }
    function settleDelegates(): void {
        const children = root.contentItem?.children ?? [];
        for (let i = 0; i < children.length; i++) {
            const card = children[i];
            if (!card?.blurItem)
                continue;
            if (card.opacity < 1)
                card.opacity = 1;
            if (card.scale !== 1)
                card.scale = 1;
        }
    }

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

    // Observe the delegates, not the model count. The set of realized delegates
    // changes for reasons `count` cannot report, and the popup's ordinary life
    // is one of them: a notification times out, the popup window hides, another
    // arrives from the same app, and the app-name list ends the cycle exactly
    // where it started - so the delegate is torn down and rebuilt while `count`
    // reads 1 throughout. `count`'s signal is raised from the view's layout
    // pass as well, which does not run while the popup window's surface is
    // down, so even the 1 -> 0 -> 1 in between is never announced.
    // Qt.callLater coalesces a burst and defers the read until the pass that
    // built the delegates has finished.
    Connections {
        target: root.contentItem
        function onChildrenChanged() {
            Qt.callLater(root.refreshCardItems);
        }
    }
    Component.onCompleted: Qt.callLater(root.refreshCardItems)

    model: ScriptModel {
        values: root.controller.appNames(root.popup)
    }
    delegate: NotificationGroup {
        required property int index
        required property var modelData
        popup: root.popup
        controller: root.controller
        width: ListView.view.width // https://doc.qt.io/qt-6/qml-qtquick-listview.html
        notificationGroup: root.controller.groupForApp(modelData, root.popup)
    }
}
