import QtTest
import "../modules/common/functions/placeholderFit.js" as PlaceholderFit

// The empty-state placeholder's shape is dropped rather than drawn outside a
// page too short to hold it (#87). The widget itself cannot be instantiated
// here - it reaches StyledText, whose `font.variableAxes` needs Qt 6.7 while
// the suite runs against the distribution Qt - so the decision lives in a
// library function and this is where it is exercised.
TestCase {
    name: "PlaceholderFitTest"

    readonly property real iconHeight: 80   // 56px symbol + space150 padding
    readonly property real lineHeight: 20
    readonly property real spacing: 8       // space100, the column's own

    function fits(availableHeight, textHeights) {
        return PlaceholderFit.iconFits(availableHeight, iconHeight,
                                       textHeights, spacing);
    }

    function test_aPageWithRoomKeepsItsShape() {
        verify(fits(400, [lineHeight]));
        verify(fits(400, []));
    }

    // The whole point: a page shorter than the column does not clip it, so
    // there is no such thing as "it overflows a little".
    function test_aPageTooShortDropsTheShape() {
        verify(!fits(60, []));
        verify(!fits(100, [lineHeight]));
    }

    // 80 + 8 + 20 = 108 exactly. Off by one either way is a shape drawn one
    // pixel outside the container, or dropped with a pixel to spare.
    function test_theBoundaryIsExactFit() {
        compare(fits(108, [lineHeight]), true, "an exact fit still fits");
        compare(fits(107, [lineHeight]), false, "one pixel short does not");
    }

    // The spacing above each label is part of what the shape has to leave
    // behind, so a title *and* a description cost more than either alone.
    function test_everyVisibleLabelCostsItsOwnSpacing() {
        const one = [lineHeight];
        const two = [lineHeight, lineHeight];
        verify(fits(108, one));
        verify(!fits(108, two));
        verify(fits(136, two), "80 + 2 * (8 + 20) = 136");
    }

    // A placeholder built before its first layout pass has height 0, which is
    // "not measured yet", not "too short". Reading it as too short would drop
    // the shape on construction and pop it back in a frame later.
    function test_anUnlaidOutPageIsNotTreatedAsTooShort() {
        verify(fits(0, [lineHeight]));
        verify(fits(-1, [lineHeight]));
        verify(fits(NaN, [lineHeight]));
        verify(fits(undefined, [lineHeight]));
    }

    function test_noLabelsIsJustTheShape() {
        compare(fits(80, []), true);
        compare(fits(79, []), false);
        compare(fits(80, undefined), true, "an absent list reads as no labels");
    }
}
