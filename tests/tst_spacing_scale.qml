import QtQuick
import QtTest
import qs.modules.common

TestCase {
    name: "SpacingScaleTest"

    // Guards the spacing token scale: fine control at the bottom (1, 2), then a
    // strict multiple-of-4 rhythm (4, 8, 12, 16, 20, 24). Changing a value here
    // shifts spacing shell-wide, so it should be a deliberate, tested edit.
    function test_scaleValues() {
        compare(Appearance.spacing.hairline, 1, "hairline");
        compare(Appearance.spacing.unsharpen, 2, "unsharpen");
        compare(Appearance.spacing.verysmall, 4, "verysmall");
        compare(Appearance.spacing.small, 8, "small");
        compare(Appearance.spacing.normal, 12, "normal");
        compare(Appearance.spacing.large, 16, "large");
        compare(Appearance.spacing.verylarge, 20, "verylarge");
        compare(Appearance.spacing.huge, 24, "huge");
    }

    function test_multipleOfFourFromVerysmallUp() {
        const steps = [Appearance.spacing.verysmall, Appearance.spacing.small,
                       Appearance.spacing.normal, Appearance.spacing.large,
                       Appearance.spacing.verylarge, Appearance.spacing.huge];
        for (let i = 0; i < steps.length; i++)
            verify(steps[i] % 4 === 0, "step " + steps[i] + " is a multiple of 4");
        // strictly ascending
        for (let i = 1; i < steps.length; i++)
            verify(steps[i] > steps[i - 1], "ascending at " + i);
    }

    function test_borderWidthTokens() {
        compare(Appearance.borderWidth.standard, 1, "border standard");
        compare(Appearance.borderWidth.emphasis, 2, "border emphasis");
        compare(Appearance.borderWidth.heavy, 4, "border heavy");
    }
}
