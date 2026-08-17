import QtQuick
import QtTest

// `Behavior on <non-animatable>` with a trailing bare `PropertyAction {}`.
//
// A `url` cannot be interpolated, so a Behavior on one does not animate it -
// it DEFERS the write, and the bare PropertyAction is what says where the
// write lands. With no `target`, no `property` and no `value`, inside a
// Behavior it means "apply the pending write here", which is how the OSD's
// indicator Loader (modules/imi/onScreenDisplay/OnScreenDisplay.qml) lets the
// outgoing indicator leave before its replacement is built - with no pending
// value field, no state machine, and no pair of Timers whose intervals have to
// keep agreeing with two animations' durations.
//
// This is Qt semantics rather than our code, and that is exactly why it is
// pinned: the construct is load-bearing and its failure mode is silent in the
// wrong direction. If a Qt release stopped honouring the bare form, the
// pending write would simply never be applied and the OSD would keep showing
// the indicator the user has just navigated away from, with nothing in any
// log. tests/test_osd_indicator_swap.py holds the other half - that our call
// site still uses it.
TestCase {
    name: "DeferredPropertySwapTest"
    when: windowShown

    Item {
        id: host
        property url wanted: "fixtures/deferredSwap/Outgoing.qml"
        // Read through a binding, not through `loader.item`: tryCompare
        // captures its target once, and the outgoing item is destroyed by the
        // swap this is waiting for.
        readonly property string shownTag: loader.item ? loader.item.tag : ""

        Loader {
            id: loader
            source: host.wanted
            Behavior on source {
                SequentialAnimation {
                    NumberAnimation {
                        target: loader; property: "opacity"; to: 0
                        duration: 120
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: [0.3, 0, 0.8, 0.15, 1, 1]
                    }
                    PropertyAction {}
                    NumberAnimation {
                        target: loader; property: "opacity"; to: 1
                        duration: 120
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: [0.05, 0.7, 0.1, 1, 1, 1]
                    }
                }
            }
        }
    }

    // The OSD is built when it opens, and it must show its first indicator on
    // the frame it appears rather than fading in from nothing. A Behavior does
    // not fire before its component is finalized, which is what makes the same
    // construct free at construction and deferred afterwards.
    function test_the_first_value_is_applied_without_waiting() {
        compare(host.shownTag, "outgoing");
        compare(loader.opacity, 1);
    }

    function test_the_swap_waits_for_the_outgoing_content_to_leave() {
        host.wanted = "fixtures/deferredSwap/Incoming.qml";
        compare(host.shownTag, "outgoing",
                "the write must not land in the frame it was made");
        wait(60);
        compare(host.shownTag, "outgoing",
                "and must still be pending while the exit is running");
        verify(loader.opacity < 1, "which is only meaningful if the exit is animating");

        tryCompare(host, "shownTag", "incoming", 1000);
        tryCompare(loader, "opacity", 1, 1000);
    }
}
