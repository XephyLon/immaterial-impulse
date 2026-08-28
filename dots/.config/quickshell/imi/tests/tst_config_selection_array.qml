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


    // Built from a URL rather than declared inline, the way
    // tst_bar_group_collapse.qml does it: this row draws through RippleButton
    // and the per-corner radii Qt below 6.7 does not have, and declared inline
    // the whole FILE fails to compile there rather than this one check. Through
    // createComponent the version dependency is a status the test can read.
    property Component rowComponent: null
    property var incubated: null

    function initTestCase() {
        rowComponent = Qt.createComponent("fixtures/ConfigSelectionArrayRow.qml");
        // A skip on ANY load error is a check that cannot fail. This one hid a
        // real one: `GroupButton` moved onto `RippleButton`, the test import
        // tree had no `InteractionMotion` to resolve, and the row stopped
        // building - the suite reported two more skips, zero failures and
        // exit 0. The only reason this file may skip is a Qt too old for the
        // per-corner radii, exactly as `tst_grouped_list` says it.
        if (rowComponent.status === Component.Error) {
            const reason = rowComponent.errorString();
            // The row reaches `StyledText`, which sets `font.variableAxes` -
            // Qt 6.7 and up. That, and not the per-corner radii this file
            // first guessed at, is why the row cannot build on the CI Qt: the
            // guess was never checked because a skip on ANY error printed the
            // same green either way.
            verify(/variableAxes|(top|bottom)(Left|Right)Radius/.test(reason),
                "the row failed to build for a reason that is not Qt's version: " + reason);
        }
    }

    function ensureComponent() {
        if (rowComponent.status === Component.Error)
            skip("Qt is older than 6.7, so the variable font axes this row's text sets do not exist here");
        compare(rowComponent.status, Component.Ready, rowComponent.errorString());
    }

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
        ensureComponent();
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
        ensureComponent();
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
