import QtQuick
import QtQuick.Layouts
import QtTest
import qs.modules.common
import qs.modules.common.widgets

// A segmented row's chips wrap on the width the row really has, not on the
// width the Flow inferred from itself while it was still being built.
//
// The defect this pins: a Flow with no width of its own takes its
// implicitWidth, and computes that from the width it currently has. Built in
// one pass it settles on one line; INCUBATED across frames - which is how a
// settings page has been built since the page host stopped blocking on
// construction - it latched at the narrow intermediate width and wrapped every
// chip onto its own line, permanently. Measured at 628px: 43px synchronous,
// 154px asynchronous. Every segmented row on every settings page looked like
// that, and no check could see it, because a synchronous build is correct.
TestCase {
    id: tc
    name: "ConfigSelectionArrayTest"
    visible: true
    when: windowShown
    width: 700
    height: 500

    Component {
        id: rowComponent
        Item {
            id: host
            property alias row: sel
            property int hostWidth: 660
            width: hostWidth
            ColumnLayout {
                width: parent.width
                GroupedList {
                    Layout.fillWidth: true
                    ConfigSelectionArray {
                        id: sel
                        Layout.fillWidth: true
                        // The host's width is only a constraint if the row is
                        // told it cannot exceed it: a QQuickLayout hands a child
                        // its implicit width when nothing caps it, so without
                        // this the "narrow" case is not narrow at all.
                        Layout.maximumWidth: host.hostWidth - Appearance.spacing.space400
                        text: "Bar position"
                        icon: "swap_vert"
                        currentValue: "top"
                        options: [
                            {"displayName": "Top", "icon": "arrow_upward", "value": "top"},
                            {"displayName": "Left", "icon": "arrow_back", "value": "left"},
                            {"displayName": "Bottom", "icon": "arrow_downward", "value": "bottom"},
                            {"displayName": "Right", "icon": "arrow_forward", "value": "right"}
                        ]
                    }
                }
            }
        }
    }

    property var incubated: null

    function buildAsync(props) {
        tc.incubated = null;
        const incubator = rowComponent.incubateObject(tc, props ?? {}, Qt.Asynchronous);
        incubator.onStatusChanged = function (status) {
            if (status === Component.Ready)
                tc.incubated = incubator.object;
        };
        if (incubator.status === Component.Ready)
            tc.incubated = incubator.object;
        tryVerify(function () { return tc.incubated !== null; }, 5000, "the row never finished incubating");
        wait(400);
        return tc.incubated;
    }

    // The measurement that matters: the same row, built both ways, is the same
    // height. Asserting a literal height instead would pin the font metrics of
    // whichever machine ran it last.
    function test_an_incubated_row_lays_its_chips_out_like_a_built_one() {
        const built = rowComponent.createObject(tc);
        wait(400);
        const syncHeight = built.row.height;
        verify(syncHeight > 0, "the synchronous row has no height at all");

        const incubatedRow = buildAsync(null);
        compare(incubatedRow.row.height, syncHeight,
                "an incubated row is taller than the same row built in one pass, which is the Flow "
                + "wrapping on a width it inferred from itself mid-construction");

        built.destroy();
        incubatedRow.destroy();
    }

    // The other half: the same agreement at a width where the chips genuinely
    // do not fit on one line. Comparing only the roomy case would pass just as
    // well on a row that had stopped wrapping altogether.
    function test_the_two_builds_agree_when_the_row_is_cramped() {
        const built = rowComponent.createObject(tc, {hostWidth: 320});
        wait(400);
        const syncHeight = built.row.height;

        const incubatedRow = buildAsync({hostWidth: 320});
        compare(incubatedRow.row.height, syncHeight,
                "at 320px an incubated row and a built one disagree about how many lines the chips take");

        built.destroy();
        incubatedRow.destroy();
    }
}
