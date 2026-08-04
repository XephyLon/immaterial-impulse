import QtQuick
import QtTest
import qs.modules.common

// Bar geometry that only exists as arithmetic between Appearance tokens, and
// so is the one part of the bar a unit test can actually reach.
TestCase {
    name: "BarGeometryTest"

    readonly property var cornerStyles: [0, 1, 2, 3]
    readonly property int m3CornerStyle: 3

    property int savedCornerStyle: 0
    property bool savedBottom: false
    property bool savedDeadPixel: false

    function initTestCase() {
        savedCornerStyle = Config.options.bar.cornerStyle;
        savedBottom = Config.options.bar.bottom;
        savedDeadPixel = Config.options.interactions.deadPixelWorkaround.enable;
    }

    function cleanupTestCase() {
        Config.options.bar.cornerStyle = savedCornerStyle;
        Config.options.bar.bottom = savedBottom;
        Config.options.interactions.deadPixelWorkaround.enable = savedDeadPixel;
    }

    // Bar.qml's `margins.bottom` used to read
    //     (enable && anchors.bottom) * -1 || cornerStyle === 3 ? 5 : 0
    // where `||` binds tighter than `?:`, so the whole left-hand side was only
    // the ternary's *condition*. A live workaround made that condition truthy
    // and the margin came out +5 for every corner style - pushing the bar away
    // from the very edge it was meant to overhang, and making Hyprland reserve
    // 5px more with it (exclusive + margin).
    function test_deadPixelOverhangBeatsTheM3DetachMargin() {
        Config.options.bar.bottom = true;
        Config.options.interactions.deadPixelWorkaround.enable = true;
        for (const style of cornerStyles) {
            Config.options.bar.cornerStyle = style;
            compare(Appearance.sizes.barBottomMargin,
                    Appearance.sizes.barDeadPixelOverhang,
                    "the workaround must pull the surface past the edge, "
                    + "cornerStyle " + style);
            verify(Appearance.sizes.barBottomMargin < 0,
                   "a positive bottom margin is the bug: it moves the bar off "
                   + "the dead row instead of over it, cornerStyle " + style);
        }
    }

    // The dead row Hyprland leaves is on the right and bottom screen edges, so
    // a top-anchored bar has nothing to overhang and keeps the detach margin.
    function test_aTopBarIsUnaffectedByTheWorkaround() {
        Config.options.bar.bottom = false;
        Config.options.interactions.deadPixelWorkaround.enable = true;
        for (const style of cornerStyles) {
            Config.options.bar.cornerStyle = style;
            compare(Appearance.sizes.barBottomMargin,
                    Appearance.sizes.barDetachMargin,
                    "a top bar must not overhang, cornerStyle " + style);
        }
    }

    function test_withTheWorkaroundOffOnlyM3DetachesFromTheEdge() {
        Config.options.interactions.deadPixelWorkaround.enable = false;
        compare(Appearance.sizes.barDeadPixelOverhang, 0,
                "no overhang while the workaround is off");
        for (let b = 0; b < 2; ++b) {
            Config.options.bar.bottom = b === 1;
            for (const style of cornerStyles) {
                Config.options.bar.cornerStyle = style;
                const expected = style === m3CornerStyle
                    ? Appearance.sizes.hyprlandGapsOut : 0;
                compare(Appearance.sizes.barDetachMargin, expected,
                        "detach margin, cornerStyle " + style);
                compare(Appearance.sizes.barBottomMargin, expected,
                        "bottom margin, cornerStyle " + style
                        + ", bottom " + (b === 1));
            }
        }
    }
}
