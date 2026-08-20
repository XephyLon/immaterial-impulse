import QtTest
import QtQuick
import "../modules/common/functions/widget_nudge.js" as Nudge

// Arrow-key nudging of a selected desktop widget. Three decisions live in the
// module: which keys are a direction at all, where one press lands (a whole
// lattice cell along, snapped back ONTO the lattice, because a widget can sit
// off it), and what a multi-widget selection does when one member reaches a
// wall. Nothing about the rendered canvas or the key delivery is reachable
// from qmltestrunner, so the arithmetic is the half a test can hold.
TestCase {
    name: "WidgetNudge"

    readonly property var keys: ({
        left: Qt.Key_Left, right: Qt.Key_Right,
        up: Qt.Key_Up, down: Qt.Key_Down
    })

    function test_each_arrow_is_one_direction() {
        compare(Nudge.direction(Qt.Key_Left, keys), { dx: -1, dy: 0 });
        compare(Nudge.direction(Qt.Key_Right, keys), { dx: 1, dy: 0 });
        compare(Nudge.direction(Qt.Key_Up, keys), { dx: 0, dy: -1 });
        compare(Nudge.direction(Qt.Key_Down, keys), { dx: 0, dy: 1 });
    }

    function test_a_key_that_is_not_an_arrow_is_not_a_direction() {
        // The handler leaves such a key unaccepted, so Escape still reaches
        // the ladder and Ctrl+Z still reaches undo.
        compare(Nudge.direction(Qt.Key_Escape, keys), null);
        compare(Nudge.direction(Qt.Key_Z, keys), null);
        compare(Nudge.direction(Qt.Key_Left, {}), null);
    }

    function test_a_press_from_the_lattice_moves_exactly_one_cell() {
        compare(Nudge.step(96, 12, 12, 0), 108);
        compare(Nudge.step(96, -12, 12, 0), 84);
    }

    function test_a_press_from_off_the_lattice_lands_on_it() {
        // 465 is a measured edge-snap landing: one gap off a neighbour's edge,
        // which the lattice cannot produce. The first press gets it onto the
        // grid, so it travels 15 rather than 12 - and the next one is clean.
        compare(Nudge.step(465, 12, 12, 0), 480);
        compare(Nudge.step(480, 12, 12, 0), 492);
    }

    function test_the_lattice_can_be_offset() {
        // A subclass whose coordinate is not the one it stores moves the
        // lattice into its own frame (AbstractWidget's snapOffsetX/Y).
        compare(Nudge.step(101, 12, 12, 5), 113);
        compare(Nudge.step(100, 12, 12, 4), 112);
    }

    function test_a_lattice_of_zero_still_moves_by_the_delta() {
        // Rather than dividing by it and answering NaN, which is a legal
        // double nothing downstream rejects.
        compare(Nudge.step(50, 12, 0, 0), 62);
        compare(Nudge.step(50, 12, -12, 0), 62);
    }

    function test_a_lone_widget_travels_the_whole_delta() {
        const members = [{ x: 96, y: 96, minX: 0, maxX: 500, minY: 0, maxY: 500 }];
        compare(Nudge.groupDelta(members, 12, 0), { dx: 12, dy: 0 });
    }

    function test_the_group_stops_when_its_first_member_reaches_the_wall() {
        // The group-drag rule: the cluster stops rather than deforming, so
        // the member with the least headroom decides for all of them.
        const members = [
            { x: 96, y: 0, minX: 0, maxX: 500, minY: 0, maxY: 500 },
            { x: 494, y: 0, minX: 0, maxX: 500, minY: 0, maxY: 500 }
        ];
        compare(Nudge.groupDelta(members, 12, 0), { dx: 6, dy: 0 });
    }

    function test_a_selection_already_against_the_wall_does_not_move() {
        // Which is what keeps a nudge into a wall from committing every
        // member's unchanged position and filling the undo stack.
        const members = [{ x: 500, y: 0, minX: 0, maxX: 500, minY: 0, maxY: 500 }];
        compare(Nudge.groupDelta(members, 12, 0), { dx: 0, dy: 0 });
        compare(Nudge.groupDelta(members, -12, 0), { dx: -12, dy: 0 });
    }

    function test_each_axis_is_shrunk_on_its_own() {
        const members = [
            { x: 500, y: 96, minX: 0, maxX: 500, minY: 0, maxY: 500 },
            { x: 96, y: 96, minX: 0, maxX: 500, minY: 0, maxY: 500 }
        ];
        // Blocked rightward, free downward: a diagonal is not a thing the
        // keys produce, but the shrink must not leak between axes.
        compare(Nudge.groupDelta(members, 12, 12), { dx: 0, dy: 12 });
    }

    function test_an_empty_or_unbranded_selection_answers_zero() {
        // A list that has crossed a QML property boundary keeps its length
        // and loses Array.isArray, so the module tests for likeness.
        compare(Nudge.groupDelta([], 12, 0), { dx: 0, dy: 0 });
        compare(Nudge.groupDelta(null, 12, 0), { dx: 0, dy: 0 });
        compare(Nudge.groupDelta({ length: 1, 0: { x: 0, y: 0, minX: 0, maxX: 96, minY: 0, maxY: 96 } },
                                 12, 0), { dx: 12, dy: 0 });
    }

    function test_a_member_with_no_bounds_is_unclamped_rather_than_frozen() {
        const members = [{ x: 96, y: 96 }];
        compare(Nudge.groupDelta(members, 12, 0), { dx: 12, dy: 0 });
    }
}
