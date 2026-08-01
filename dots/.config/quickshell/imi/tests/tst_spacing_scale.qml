import QtQuick
import QtTest
import qs.modules.common

TestCase {
    name: "SpacingScaleTest"

    // Guards Material 3's system spacing scale. space100 (8dp) is the base
    // unit; the other names are percentages of that base.
    function test_scaleValues() {
        const actual = [Appearance.spacing.space0, Appearance.spacing.space25,
                        Appearance.spacing.space50, Appearance.spacing.space75,
                        Appearance.spacing.space100, Appearance.spacing.space125,
                        Appearance.spacing.space150, Appearance.spacing.space175,
                        Appearance.spacing.space200, Appearance.spacing.space250,
                        Appearance.spacing.space300, Appearance.spacing.space400,
                        Appearance.spacing.space450, Appearance.spacing.space500,
                        Appearance.spacing.space600, Appearance.spacing.space700,
                        Appearance.spacing.space800, Appearance.spacing.space900];
        const expected = [0, 2, 4, 6, 8, 10, 12, 14, 16, 20, 24, 32, 36, 40, 48, 56, 64, 72];
        compare(actual.length, expected.length);
        for (let i = 0; i < expected.length; ++i)
            compare(actual[i], expected[i], "space token at index " + i);
    }

    function test_borderWidthTokens() {
        compare(Appearance.borderWidth.standard, 1, "border standard");
        compare(Appearance.borderWidth.emphasis, 2, "border emphasis");
        compare(Appearance.borderWidth.heavy, 4, "border heavy");
    }
}
