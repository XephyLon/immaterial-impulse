import QtQuick
import QtTest
import qs.modules.common
import qs.modules.common.widgets

// `StaggerWave.items`: the members, when they are not one container's
// children. `GroupedList` reparents each declared row into its own plate, so
// a wave over its rows has no container whose `children` are the group - the
// rows' shared origin is the declared list. The desktop menu is the adopter
// that needs this; the drawer keeps the children walk.
//
// What is pinned: the list REPLACES the children walk (a member the target
// does not contain is still parked and still enters), rank comes from the
// list's order with a hidden member spending no slot but SETTLED rather than
// left parked (a member hidden at the open that becomes visible later must
// arrive at rest, not at the 0 the park wrote), and park/enter still meet in
// the middle - a parked member ends at 1 after an entrance.
TestCase {
    name: "StaggerWaveItemsTest"
    when: windowShown
    width: 300
    height: 300
    visible: true

    Item {
        id: host
        width: 300
        height: 200

        Item {
            id: resident
            property real appear: 1
            width: 10
            height: 10
        }
    }

    // A member living OUTSIDE the wave's target, the way a GroupedList row
    // lives inside its plate rather than beside its siblings.
    Item {
        id: elsewhere
        width: 300
        height: 50

        Item {
            id: reparented
            property real appear: 1
            width: 10
            height: 10
        }

        Item {
            id: hiddenMember
            visible: false
            property real appear: 1
            width: 10
            height: 10
        }
    }

    // A child of the target that the LIST does not name: the list must
    // replace the children walk, not add to it.
    Item {
        id: unlisted
        parent: host
        property real appear: 1
        width: 10
        height: 10
    }

    StaggerWave {
        id: wave
        target: host
        items: [resident, reparented, hiddenMember]
    }

    function test_the_list_is_the_membership() {
        wave.park();
        compare(resident.appear, 0, "a listed child parks");
        compare(reparented.appear, 0,
                "a listed member outside the target parks too");
        compare(hiddenMember.appear, 0);
        compare(unlisted.appear, 1,
                "an unlisted child of the target is not a member");

        wave.enter();
        tryCompare(resident, "appear", 1);
        tryCompare(reparented, "appear", 1);
        compare(unlisted.appear, 1);
        compare(hiddenMember.appear, 1,
                "a hidden member spends no slot and is settled, so it "
                + "arrives at rest if something shows it mid-open");
        wave.settle();
    }
}
