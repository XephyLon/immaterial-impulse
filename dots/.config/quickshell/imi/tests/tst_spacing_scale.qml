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

    // The rounding ladder docs/M3_GUIDELINES.md documents. Pinned here for the
    // same reason the spacing scale is: the guidelines assign a meaning to each
    // rung ("small: standard buttons", "normal: standard cards"), and a rung
    // that quietly moves takes every one of its call sites with it.
    function test_roundingLadder() {
        compare(Appearance.rounding.unsharpen, 2, "unsharpen");
        compare(Appearance.rounding.unsharpenslight, 4, "unsharpenslight");
        compare(Appearance.rounding.unsharpenmore, 6, "unsharpenmore");
        compare(Appearance.rounding.verysmall, 8, "verysmall");
        compare(Appearance.rounding.small, 12, "small");
        compare(Appearance.rounding.normal, 17, "normal");
        compare(Appearance.rounding.large, 23, "large");
        compare(Appearance.rounding.verylarge, 30, "verylarge");
        compare(Appearance.rounding.windowRounding, 18, "windowRounding");
        compare(Appearance.rounding.full, 9999, "full is the round-me-completely sentinel");
    }

    // The three M3-named tokens the design system reads. They were undeclared
    // for the whole life of the port, and `radius: undefined` renders 0 - a
    // square corner that reads as a design choice rather than as a bug.
    //
    // Asserted as ALIASES rather than as numbers on purpose. The lint
    // (tests/lint_appearance_tokens.py) already guarantees they exist; what
    // this pins is that each one is still the tier it claims, so giving `card`
    // a fourth independent number fails here instead of shipping two subtly
    // different card radii. The literals above are what make that a real
    // assertion rather than a tautology.
    function test_theM3NamedTokensAreTheTiersTheyName() {
        compare(Appearance.rounding.button, Appearance.rounding.small,
                "button is the standard-button tier");
        compare(Appearance.rounding.card, Appearance.rounding.normal,
                "card is the standard-card tier");
        compare(Appearance.rounding.extraLarge, Appearance.rounding.verylarge,
                "extraLarge is M3's name for this ladder's verylarge");
    }

    // The failure that made the tokens worth a test of their own: `Carousel`
    // did arithmetic on one, and arithmetic on `undefined` is NaN. NaN is a
    // legal double, so nothing rejects it, nothing logs it, and `Math.max(0, x)`
    // does not repair it - which is why the guard at the call site is a
    // comparison. A token that is merely absent costs one warning; this costs
    // none.
    function test_aRoundingTokenSurvivesArithmetic() {
        const nested = Appearance.rounding.extraLarge - 10;
        verify(!isNaN(nested), "a radius derived from a token must be a number");
        compare(nested, 20, "a child inset by 10 from a 30px parent nests at 20");
    }
}
