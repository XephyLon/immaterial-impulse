import QtQuick
import Quickshell
import qs.modules.common.widgets
import qs.services

/**
 * Pins the contract the notification popup's compositor blur rests on: the
 * cards `NotificationListView` publishes are the ones currently on screen.
 *
 * `NotificationPopup` hands that list to a `WindowBlurRegion`, which builds one
 * `Region` per card. A `Region` whose item has been destroyed reports itself
 * empty, so a stale list is not a slightly wrong blur - it is no blur at all,
 * silently, with the region still published and nothing in any log.
 *
 * The case that broke it is the ordinary one: a popup times out, the window
 * hides, another notification arrives from the same app. The app-name list ends
 * that cycle exactly where it started, so the model count reads 1 throughout
 * while the delegate is torn down and rebuilt - and `count`'s signal is raised
 * from the view's layout pass, which does not run while the window is
 * unmapped, so even the 1 -> 0 -> 1 in between is never announced. Every
 * notification after the first was unblurred for the whole life of the feature.
 *
 * The window here is a `FloatingWindow` rather than the real layer surface, so
 * this runs under headless weston: what has to be reproduced is the window
 * going down and coming back, not wlr-layer-shell. Nothing about the published
 * region itself is reachable from a test - Quickshell's plugin does not load in
 * qmltestrunner and weston implements no ext-background-effect - which is what
 * `tests/run_notification_blur_probe.sh` is for.
 *
 * Driven by tests/test_notification_cards_runtime.py; run it against throwaway
 * XDG dirs and an isolated bus, never a real session.
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int checksRun: 0
    property int elapsed: 0
    property var firstCard: null
    property int seenPopups: 0
    property bool wentDown: false

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[NotifCards] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function finish() {
        console.log(`[NotifCards] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }

    // Walks up from the card instead of re-reading the list's own children, so
    // the assertion is not the function under test spelled a second time.
    function isOnScreen(card) {
        if (!card)
            return false;
        let node = card;
        while (node) {
            if (node === listview.contentItem)
                return true;
            node = node.parent;
        }
        return false;
    }

    FloatingWindow {
        id: window
        // The real popup window is bound exactly this way, and the binding is
        // what takes the surface down between notifications.
        visible: Notifications.popupList.length > 0
        implicitWidth: 460
        implicitHeight: 420
        color: "black"

        NotificationListView {
            id: listview
            anchors.fill: parent
            popup: true
        }
    }

    Timer {
        interval: 200
        repeat: true
        running: true
        onTriggered: {
            harness.elapsed += 200;

            if (harness.seenPopups === 0 && Notifications.popupList.length > 0) {
                harness.seenPopups = 1;
                settle.restart();
                return;
            }

            if (harness.seenPopups === 1 && Notifications.popupList.length === 0)
                harness.wentDown = true;

            if (harness.wentDown && Notifications.popupList.length > 0) {
                harness.seenPopups = 2;
                settle.restart();
                running = false;
                return;
            }

            if (harness.elapsed >= 60000) {
                harness.check("two notifications arrive with the popup down in between", false);
                harness.finish();
            }
        }
    }

    Timer {
        id: settle
        interval: 600
        onTriggered: {
            const cards = listview.cardItems;
            if (harness.seenPopups === 1) {
                harness.check("the first popup publishes one card", cards.length === 1);
                harness.check("the first card is on screen", harness.isOnScreen(cards[0] ?? null));
                harness.firstCard = cards[0] ?? null;
                return;
            }

            // Without this the rest is vacuous: if the delegate had survived
            // the cycle, a list that never refreshed would still be right.
            harness.check("the first popup's card left the screen",
                !harness.isOnScreen(harness.firstCard));
            harness.check("the second popup publishes one card", cards.length === 1);
            harness.check("the second popup's card is on screen",
                harness.isOnScreen(cards[0] ?? null));
            harness.finish();
        }
    }
}
