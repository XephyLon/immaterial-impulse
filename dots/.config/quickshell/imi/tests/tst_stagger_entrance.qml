import QtQuick
import QtTest
import qs.modules.common
import qs.modules.common.widgets
import "../modules/common/motion_policy.js" as Motion

// `StaggerEntrance`: the one spelling of how a wave member arrives - opacity,
// a scale from a derived near-1 start, and a small rise, all riding the same
// `appear` scalar the StaggerWave animates. It dresses a CONTAINER's members,
// which is what keeps a tenth row added next year from being the fourth
// hand-copied dressing that drifts by a channel.
//
// The two refusals are as load-bearing as the dressing: a member that does not
// declare `appear` is not a wave member and is left alone, and a member that
// owns an `interactionMotion` already folds `appear` into the opacity that
// carries its disabled dim and owns `scale` through the model - a second
// writer of either REPLACES the control's binding rather than composing with
// it (the doubling lint_interaction_motion_double.py and
// lint_disabled_opacity.py exist to fail on).
TestCase {
    name: "StaggerEntranceTest"
    when: windowShown
    width: 500
    height: 400
    visible: true

    Column {
        id: column
        width: 400

        Item {
            id: plainMember
            property real appear: 1
            width: 400
            height: 40
        }

        // The RippleButton shape, duck-typed the way the dresser sees it: a
        // control that declares its own driver and folds its dim (and its own
        // `appear`) into its opacity binding.
        Item {
            id: controlMember
            property real appear: 1
            property var interactionMotion: ({ scale: 1 })
            property bool controlEnabled: true
            opacity: controlMember.controlEnabled ? 1 : 0.4
            width: 400
            height: 40
        }

        Item {
            id: bystander
            width: 400
            height: 40
        }
    }

    StaggerEntrance {
        id: entrance
        target: column
        reference: 380
    }

    readonly property real rise: Appearance.animation.entranceRise
    readonly property real scaleFrom: Motion.entranceScaleFrom(rise, 380)

    function liftsOf(item) {
        const lifts = [];
        for (let i = 0; i < item.transform.length; i++)
            if (item.transform[i]?.objectName === "staggerEntranceLift")
                lifts.push(item.transform[i]);
        return lifts;
    }

    function test_a_member_arrives_on_all_three_channels() {
        plainMember.appear = 0.25;
        fuzzyCompare(plainMember.opacity, 0.25, 1e-6);
        fuzzyCompare(plainMember.scale,
                     scaleFrom + (1 - scaleFrom) * 0.25, 1e-6);
        const lifts = liftsOf(plainMember);
        compare(lifts.length, 1, "one rise transform, exactly");
        fuzzyCompare(lifts[0].y, (1 - 0.25) * rise, 1e-6);

        plainMember.appear = 1;
        fuzzyCompare(plainMember.opacity, 1, 1e-6);
        fuzzyCompare(plainMember.scale, 1, 1e-6);
        fuzzyCompare(liftsOf(plainMember)[0].y, 0, 1e-6);
    }

    function test_a_control_keeps_its_own_channels() {
        compare(liftsOf(controlMember).length, 0,
                "a control's rise is its own 6px fold, not the dressing's");
        controlMember.appear = 0.25;
        fuzzyCompare(controlMember.scale, 1, 1e-6);
        // The proof the opacity BINDING survived, not just its current value:
        // flip the state it reads and watch it answer. A dresser that wrote
        // `opacity` here would have destroyed it - the control would read
        // enabled for the rest of the session.
        controlMember.controlEnabled = false;
        fuzzyCompare(controlMember.opacity, 0.4, 1e-6);
        controlMember.controlEnabled = true;
        controlMember.appear = 1;
    }

    function test_a_child_without_appear_is_not_a_member() {
        compare(liftsOf(bystander).length, 0);
        fuzzyCompare(bystander.opacity, 1, 1e-6);
        fuzzyCompare(bystander.scale, 1, 1e-6);
    }

    // The scale start is the policy's derivation against the declared
    // reference width - the drawer's own arithmetic, now in one place.
    function test_the_scale_start_is_derived_from_the_reference() {
        fuzzyCompare(scaleFrom, 1 - rise / 380, 1e-9);
        plainMember.appear = 0;
        fuzzyCompare(plainMember.scale, scaleFrom, 1e-6);
        plainMember.appear = 1;
    }

    // A Repeater fills its container after the dresser completed, so arrival
    // has to dress too - and re-dressing must not stack a second rise onto a
    // member that already has one.
    function test_a_member_arriving_later_is_dressed_once() {
        const late = Qt.createQmlObject(
            "import QtQuick; Item { property real appear: 1; width: 400; height: 40 }",
            column, "lateMember");
        // The dress hangs off onChildrenChanged, same turn as the add.
        compare(liftsOf(late).length, 1, "the late member was dressed");
        compare(liftsOf(plainMember).length, 1,
                "the resident member was not dressed a second time");
        late.appear = 0.5;
        fuzzyCompare(late.opacity, 0.5, 1e-6);
        late.destroy();
    }
}
