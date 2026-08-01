import QtQuick
import QtTest
import qs.modules.common.functions

TestCase {
    name: "ColorUtilsTest"


    function test_transparentize() {
        // Test transparentize default percentage (1 = fully transparent)
        var col1 = ColorUtils.transparentize("#ffffff")
        compare(col1.a, 0.0)

        // Test transparentize 50%
        var col2 = ColorUtils.transparentize("#ffffff", 0.5)
        compare(col2.r, 1.0)
        compare(col2.g, 1.0)
        compare(col2.b, 1.0)
        compare(col2.a, 0.5)

        // Test transparentize 25% on a color that already has alpha
        // Qt.rgba(1, 0, 0, 0.5) (red at 0.5 alpha) transparentized by 25% should be red at 0.5 * 0.75 = 0.375 alpha
        var col3 = ColorUtils.transparentize(Qt.rgba(1, 0, 0, 0.5), 0.25)
        compare(col3.r, 1.0)
        compare(col3.g, 0.0)
        compare(col3.b, 0.0)
        verify(Math.abs(col3.a - 96 / 255) < 1e-6)
    }

    function test_applyAlpha() {
        // Test normal alpha application
        var col1 = ColorUtils.applyAlpha("#00ff00", 0.6)
        compare(col1.r, 0.0)
        compare(col1.g, 1.0)
        compare(col1.b, 0.0)
        compare(col1.a, 0.6)

        // Test clamping alpha below 0
        var col2 = ColorUtils.applyAlpha("#0000ff", -0.5)
        compare(col2.a, 0.0)

        // Test clamping alpha above 1
        var col3 = ColorUtils.applyAlpha("#0000ff", 1.5)
        compare(col3.a, 1.0)
    }

    function test_solveOverlayColor() {
        // base = black, target = gray (0.5, 0.5, 0.5), overlayOpacity = 0.5
        // (tc - bc * invA) / opacity => (0.5 - 0 * 0.5) / 0.5 = 1.0
        // So overlay should be white (1.0, 1.0, 1.0) at opacity 0.5
        var base = Qt.rgba(0, 0, 0, 1)
        var target = Qt.rgba(0.5, 0.5, 0.5, 1)
        var solved = ColorUtils.solveOverlayColor(base, target, 0.5)

        compare(solved.r, 1.0)
        compare(solved.g, 1.0)
        compare(solved.b, 1.0)
        compare(solved.a, 0.5)

        // Test with clamping (target requires more intensity than possible)
        // target is fully bright, but opacity is 0.1 and base is black
        // (1.0 - 0 * 0.9) / 0.1 = 10.0, which clamps to 1.0
        var solvedClamped = ColorUtils.solveOverlayColor(Qt.rgba(0,0,0,1), Qt.rgba(1,1,1,1), 0.1)
        compare(solvedClamped.r, 1.0)
        compare(solvedClamped.g, 1.0)
        compare(solvedClamped.b, 1.0)
    }
}
