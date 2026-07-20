import QtQuick
import QtTest
import qs.modules.common

TestCase {
    name: "SpacingScaleTest"

    // Guards the spacing scale: the two fine values 2 and 4, then multiples
    // of 4 only. M3's nested 6/10/14 steps are deliberately not offered.
    function test_scaleValues() {
        const actual = [Appearance.spacing.space0, Appearance.spacing.space25,
                        Appearance.spacing.space50, Appearance.spacing.space100,
                        Appearance.spacing.space150, Appearance.spacing.space200,
                        Appearance.spacing.space250,
                        Appearance.spacing.space300, Appearance.spacing.space400,
                        Appearance.spacing.space450, Appearance.spacing.space500,
                        Appearance.spacing.space600, Appearance.spacing.space700,
                        Appearance.spacing.space800, Appearance.spacing.space900];
        const expected = [0, 2, 4, 8, 12, 16, 20, 24, 32, 36, 40, 48, 56, 64, 72];
        compare(actual.length, expected.length);
        for (let i = 0; i < expected.length; ++i)
            compare(actual[i], expected[i], "space token at index " + i);

        // Every step above the two fine values must be a multiple of 4.
        for (const value of expected.slice(2))
            compare(value % 4, 0, "step " + value + " is not a multiple of 4");
    }

    function test_borderWidthTokens() {
        compare(Appearance.borderWidth.standard, 1, "border standard");
        compare(Appearance.borderWidth.emphasis, 2, "border emphasis");
        compare(Appearance.borderWidth.heavy, 4, "border heavy");
    }
}
