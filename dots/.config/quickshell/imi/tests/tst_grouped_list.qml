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

    // Built from a URL rather than declared inline. `GroupedList` uses
    // per-corner `Rectangle` radii, which arrived in Qt 6.7 - and an inline
    // component is compiled with this file, so on an older Qt the whole
    // TestCase goes unavailable and all five cases are lost with it. CI runs
    // Ubuntu's Qt and that is exactly what happened the first time this landed:
    // one FAIL reading `Type GroupedList unavailable`, with the real cause
    // ("Cannot assign to non-existent property bottomRightRadius") one line
    // further down.
    //
    // Through `createComponent` the version dependency is a STATUS, so the
    // skip is specific: an error naming a per-corner radius is a Qt too old for
    // the widget the shell ships, and any other error is still a failure.
    property Component groupComponent: null

    function initTestCase() {
        groupComponent = Qt.createComponent("fixtures/GroupedListRows.qml");
        if (groupComponent.status === Component.Error) {
            const reason = groupComponent.errorString();
            verify(/(top|bottom)(Left|Right)Radius/.test(reason),
                "GroupedList failed to build for a reason that is not Qt's version: " + reason);
        }
    }

    function ensureComponent() {
        if (groupComponent.status === Component.Error)
            skip("Qt is older than 6.7, so the per-corner radii GroupedList "
                + "draws its group with do not exist here");
        compare(groupComponent.status, Component.Ready, groupComponent.errorString());
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
        ensureComponent();
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
        ensureComponent();
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
        ensureComponent();
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
        ensureComponent();
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
        ensureComponent();
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
