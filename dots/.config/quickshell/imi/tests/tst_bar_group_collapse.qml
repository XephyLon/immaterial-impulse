import QtQuick
import QtQuick.Layouts
import QtTest
import qs
import qs.modules.common
import qs.modules.imi.bar

// A BarGroup whose content has collapsed paints nothing, and the ends of a
// row follow which neighbours are showing.
//
// The standalone pills (timer, submap, privacy) animate their implicitWidth
// to 0 when idle and hide themselves; the group around one kept its padding,
// so every layout ending in a pill carried a small empty stub beside its last
// widget (user-reported, 2026-08-26). What is pinned: a group with a
// zero-width child is collapsed and invisible, it comes back when the child
// grows, edit mode keeps it on the bar regardless, and the group beside a
// collapsed one gets the full end radius its index alone would not give it.
TestCase {
    name: "BarGroupCollapseTest"
    when: windowShown

    property bool savedEditMode: false
    function initTestCase() { savedEditMode = GlobalStates.editMode; }
    function cleanupTestCase() { GlobalStates.editMode = savedEditMode; }

    // Enough of the edit controller for BarWidgetEditItem to bind against
    // when edit mode instantiates it; no test here drags anything.
    QtObject {
        id: fakeController
        property var bucketNames: ["left"]
        function dropBuckets() { return []; }
        function beginDrag() {}
        function dragMoved() {}
        function commitReorder() {}
        function endDrag() {}
        function removeAt() {}
    }

    Component {
        id: rowComponent
        RowLayout {
            spacing: 4
            property alias first: first
            property alias second: second
            property alias secondContent: secondContent
            BarGroup {
                id: first
                currentIndex: 0
                totalCount: 2
                widgetId: "activeWindow"
                Item { implicitWidth: 40; implicitHeight: 10 }
            }
            BarGroup {
                id: second
                currentIndex: 1
                totalCount: 2
                widgetId: "timerPill"
                editController: fakeController
                // The pills' own shape: 0 wide when idle, and hidden with it.
                Item { id: secondContent; implicitWidth: 0; implicitHeight: 10; visible: implicitWidth > 0 }
            }
        }
    }

    function test_a_group_with_nothing_in_it_is_collapsed_and_invisible() {
        GlobalStates.editMode = false;
        const row = createTemporaryObject(rowComponent, this);
        verify(row.second.contentEmpty, "a zero-width child is not read as empty");
        verify(row.second.collapsed, "an empty group is not collapsed");
        verify(!row.first.collapsed, "a group with content collapsed");
        // The layout is the evidence: a collapsed group takes no width and
        // no spacing, so the row is exactly its one showing member.
        compare(row.implicitWidth, row.first.implicitWidth,
                "the collapsed group still takes room in the row");
    }

    function test_the_group_comes_back_when_its_content_does() {
        GlobalStates.editMode = false;
        const row = createTemporaryObject(rowComponent, this);
        verify(row.second.collapsed);
        row.secondContent.implicitWidth = 36;
        tryVerify(() => !row.second.collapsed, 500, "the group stayed collapsed after its content grew");
        tryCompare(row, "implicitWidth",
                   row.first.implicitWidth + row.spacing + row.second.implicitWidth, 500);
        row.secondContent.implicitWidth = 0;
        tryVerify(() => row.second.collapsed, 500, "the group did not collapse again");
        tryCompare(row, "implicitWidth", row.first.implicitWidth, 500);
    }

    function test_edit_mode_keeps_an_empty_group_on_the_bar() {
        GlobalStates.editMode = true;
        const row = createTemporaryObject(rowComponent, this);
        verify(row.second.contentEmpty, "still empty");
        verify(!row.second.collapsed, "edit mode collapsed a slot the user has to be able to drag");
        // Empty, but on the bar: its padding is its width, and it takes spacing.
        compare(row.second.implicitWidth, row.second.padding * 2);
        compare(row.implicitWidth, row.first.implicitWidth + row.spacing + row.second.implicitWidth);
        GlobalStates.editMode = false;
        tryVerify(() => row.second.collapsed, 500, "leaving edit mode did not collapse the empty group");
    }

    function test_the_row_end_follows_the_showing_neighbour_not_the_index() {
        GlobalStates.editMode = false;
        const row = createTemporaryObject(rowComponent, this);
        // Index says first is not last; its only neighbour is collapsed, so it is.
        verify(!row.first.showingAfter, "a collapsed neighbour counts as showing");
        compare(row.first.endRadius, row.first.fullRadius,
                "the group beside a collapsed one did not get the full end radius");
        compare(row.first.startRadius, row.first.fullRadius);
        row.secondContent.implicitWidth = 36;
        tryVerify(() => row.first.showingAfter, 500, "a neighbour that came back is not seen");
        compare(row.first.endRadius, row.first.midRadius,
                "with a showing neighbour the shared edge is not the mid radius");
        compare(row.second.startRadius, row.second.midRadius);
        compare(row.second.endRadius, row.second.fullRadius);
    }
}
