import QtQuick
import QtTest
import qs.modules.common
import qs.modules.common.widgets

// A `GroupedList` row that is not drawn must take no room.
//
// The plates are built by a `Repeater` over the declared items and each sizes
// itself from its item's `implicitHeight`; nothing asked whether the item was
// drawn, so a hidden row kept a row-height band of `bgcolor` with nothing in
// it. Two call sites had it - the desktop menu's Edit layout row, which
// disappears while Edit Mode is on, and Settings > Services > Weather's
// OWM-only API-key field.
//
// The mechanism the fix could NOT use has its own case below: `Item.visible`
// reads back EFFECTIVE visibility, so a plate that hid itself from its own
// child's `visible` would hide the child and then read false for ever. That is
// the one regression a reviewer would introduce while "simplifying" this.
TestCase {
    name: "GroupedListTest"
    when: windowShown
    width: 400
    height: 400
    visible: true

    Component {
        id: groupComponent
        GroupedList {
            id: group
            width: 300
            property alias firstRow: first
            property alias middleRow: middle
            property alias lastRow: last
            Item {
                id: first
                implicitHeight: 40
                property bool rowVisible: true
            }
            Item {
                id: middle
                implicitHeight: 40
                property bool rowVisible: true
            }
            // Declares nothing, which is what almost every row in the shell
            // does - it must still be drawn, and it must still be able to hold
            // the group's bottom corner.
            Item { id: last; implicitHeight: 40 }
        }
    }

    function plates(group) {
        // The plates are the Repeater's delegates: the children of the
        // ColumnLayout the group builds, which is its only child item.
        const column = group.children[0];
        const out = [];
        for (let i = 0; i < column.children.length; i++) {
            const child = column.children[i];
            if (child.hasOwnProperty("topLeftRadius"))
                out.push(child);
        }
        return out;
    }

    function test_a_hidden_row_takes_no_height_and_no_spacing() {
        const group = createTemporaryObject(groupComponent, this);
        verify(group);
        waitForRendering(group);
        const full = group.implicitHeight;
        verify(full > 0);

        group.middleRow.rowVisible = false;
        waitForRendering(group);
        // One plate and one spacing gone: the plate is the row plus the group's
        // vertical padding, and a ColumnLayout leaves an invisible child out of
        // the spacing too. Both terms, because collapsing only the height
        // leaves a doubled gap where the row was - which is the other half of
        // "an empty row-height gap between Widgets and DropShelf".
        const expected = full - (40 + group.itemVerticalPadding)
            - Appearance.spacing.space25;
        fuzzyCompare(group.implicitHeight, expected, 0.5);
    }

    function test_the_rows_either_side_of_it_close_up() {
        const group = createTemporaryObject(groupComponent, this);
        verify(group);
        waitForRendering(group);
        group.middleRow.rowVisible = false;
        waitForRendering(group);

        const drawn = plates(group).filter(plate => plate.visible);
        compare(drawn.length, 2);
        fuzzyCompare(drawn[1].y, drawn[0].y + drawn[0].height + Appearance.spacing.space25, 0.5);
    }

    function test_the_groups_corners_follow_the_rows_that_are_drawn() {
        const group = createTemporaryObject(groupComponent, this);
        verify(group);
        waitForRendering(group);
        const all = plates(group);
        compare(all.length, 3);
        compare(all[0].topLeftRadius, group.bigRadius);
        compare(all[1].topLeftRadius, group.smallRadius);

        // Hiding the FIRST row must move the group's outer corner onto the new
        // first, or the group is drawn with a square top on a hidden plate's
        // behalf. `isFirst` read off the declared index does exactly that.
        group.firstRow.rowVisible = false;
        waitForRendering(group);
        compare(all[1].topLeftRadius, group.bigRadius);
        compare(all[1].bottomLeftRadius, group.smallRadius);
        compare(all[2].bottomLeftRadius, group.bigRadius);
    }

    function test_a_row_that_declares_nothing_is_drawn() {
        // The last row declares no `rowVisible` at all, which is what almost
        // every row in the shell does. An undeclared property reads
        // `undefined`, and the group must take the `?? true` rather than
        // reading it as hidden - which is what a plain truthiness test on the
        // wrong side of the `??` would do, silently, to every group.
        const group = createTemporaryObject(groupComponent, this);
        verify(group);
        waitForRendering(group);
        const drawn = plates(group).filter(plate => plate.visible);
        compare(drawn.length, 3);
    }

    function test_a_row_that_comes_back_is_drawn_again() {
        // The case that rules out the obvious fix. `Item.visible` is EFFECTIVE
        // visibility, so a plate bound to its own child's `visible` hides the
        // child, then reads false, then never lets it back - probed with
        // `qml6` against a control row, the mirrored one stayed false through
        // four more toggles while the control followed every one. The Edit
        // layout row toggles on every entry to and exit from the mode, so the
        // latch would cost the menu that row permanently after the first edit.
        const group = createTemporaryObject(groupComponent, this);
        verify(group);
        waitForRendering(group);
        const full = group.implicitHeight;

        group.middleRow.rowVisible = false;
        waitForRendering(group);
        verify(group.implicitHeight < full);

        group.middleRow.rowVisible = true;
        waitForRendering(group);
        fuzzyCompare(group.implicitHeight, full, 0.5);
        compare(plates(group).filter(plate => plate.visible).length, 3);
    }
}
