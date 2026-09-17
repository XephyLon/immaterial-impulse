import QtQuick
import QtTest

// The dock's lift latch (modules/imi/dock/Dock.qml `liftFromTab`): whether a
// lift under way began as the TAB - neck at the seam, tab look until landed
// apart - or as a pill that was never fused (a floating dock being pinned)
// and rises as it is. The real dock is a PanelWindow inside a Variants, which
// the suite cannot build, so this rebuilds the latch's exact shape out of a
// plain Item: the same two plain properties, the same two handlers, and
// `attached` / `splitTarget` as bindings on the same inputs Dock.qml reads
// (the option, the pin, the frame). What the model pins is the ORDER: the
// edge handler reads last turn's `attached`, refreshed a turn late by
// Qt.callLater, so the answer does not depend on which of this turn's
// bindings re-evaluated first. Two earlier spellings passed the source-text
// contract and were wrong on sequences it cannot express - reading the look
// at the edge, and reading "what changed since the last edge" - so the
// sequences that broke them are driven here, one per test.
TestCase {
    id: testCase
    name: "DockSplitLatchTest"

    Component {
        id: latchModel
        Item {
            id: dock
            // The inputs, in the shape Dock.qml sees them.
            property bool frameEnabled: true
            property bool pinned: true
            property bool optionAttached: true
            // DockReservation.attached: the option, while pinned; an unpinned
            // dock never reserves, and on the default band it keeps the tab.
            readonly property bool reservationAttached: optionAttached
            readonly property bool attached: reservationAttached
            readonly property real splitTarget: frameEnabled && pinned && !reservationAttached ? 1 : 0
            // The latch, verbatim from Dock.qml.
            property bool liftFromTab: true
            property bool attachedBefore: false
            Component.onCompleted: dock.attachedBefore = dock.attached
            onAttachedChanged: Qt.callLater(() => { dock.attachedBefore = dock.attached; })
            onSplitTargetChanged: if (dock.splitTarget === 1) dock.liftFromTab = dock.attachedBefore
        }
    }

    function settle() {
        // Let the deferred refresh run: one pass of the event loop.
        wait(0);
    }

    function test_a_pinned_tab_going_floating_lifts_as_the_tab() {
        var d = createTemporaryObject(latchModel, testCase, { optionAttached: false });
        // Seeded from the settled state before any change.
        d.optionAttached = true; settle();
        compare(d.attachedBefore, true);
        d.optionAttached = false;
        compare(d.splitTarget, 1);
        compare(d.liftFromTab, true, "the edge reads last turn's attached, not this turn's");
        settle();
        compare(d.attachedBefore, false, "the refresh lands a turn late");
        compare(d.liftFromTab, true, "and does not rewrite the latch");
    }

    function test_pinning_a_floating_dock_lifts_as_the_pill() {
        var d = createTemporaryObject(latchModel, testCase, { optionAttached: false, pinned: false });
        settle();
        compare(d.attachedBefore, false);
        d.pinned = true;
        compare(d.splitTarget, 1);
        compare(d.liftFromTab, false);
    }

    function test_the_option_flipped_while_unpinned_then_pinned_lifts_as_the_pill() {
        // The sequence "what changed since the last edge" missed: the change
        // happens between edges, so nothing changed AT the edge.
        var d = createTemporaryObject(latchModel, testCase);
        settle();
        d.pinned = false; settle();
        compare(d.splitTarget, 0);
        d.optionAttached = false; settle();
        compare(d.splitTarget, 0, "no target while unpinned");
        compare(d.attachedBefore, false);
        d.pinned = true;
        compare(d.splitTarget, 1);
        compare(d.liftFromTab, false, "the pill on screen rises as a pill");
    }

    function test_the_frame_switched_on_under_a_floating_pinned_dock_lifts_as_the_pill() {
        var d = createTemporaryObject(latchModel, testCase, { frameEnabled: false, optionAttached: false });
        settle();
        d.frameEnabled = true;
        compare(d.splitTarget, 1);
        compare(d.liftFromTab, false);
    }

    function test_a_landing_then_a_second_lift_reads_the_landed_state() {
        var d = createTemporaryObject(latchModel, testCase);
        settle();
        d.optionAttached = false; settle();
        compare(d.liftFromTab, true);
        d.optionAttached = true; settle();
        compare(d.attachedBefore, true);
        d.optionAttached = false;
        compare(d.liftFromTab, true, "the second lift is the tab's again");
    }
}
