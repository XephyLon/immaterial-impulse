import QtQuick
import QtTest
import qs.modules.common

// Bar geometry that only exists as arithmetic between Appearance tokens, and
// so is the one part of the bar a unit test can actually reach. Both bugs
// pinned here were invisible in review because each individual token still
// looked right on its own.
TestCase {
    name: "BarGeometryTest"

    readonly property var cornerStyles: [0, 1, 2, 3, 4]
    readonly property int m3CornerStyle: 3

    property int savedCornerStyle: 0
    property bool savedBottom: false
    property bool savedDeadPixel: false
    property bool savedAutoHide: false

    function initTestCase() {
        savedCornerStyle = Config.options.bar.cornerStyle;
        savedBottom = Config.options.bar.bottom;
        savedDeadPixel = Config.options.interactions.deadPixelWorkaround.enable;
        savedAutoHide = Config.options.bar.autoHide.enable;
    }

    function cleanupTestCase() {
        Config.options.bar.cornerStyle = savedCornerStyle;
        Config.options.bar.bottom = savedBottom;
        Config.options.interactions.deadPixelWorkaround.enable = savedDeadPixel;
        Config.options.bar.autoHide.enable = savedAutoHide;
    }

    // BarGroup.qml paints its background inset by the edge-side margin at the
    // monitor edge and the window-side margin opposite it, inside a box that is
    // always baseBarHeight along the bar's thickness. `bar.bottom` names the far
    // edge for both orientations, so it swaps which margin lands where.
    function groupPillSpan(barBottom) {
        const nearInset = barBottom ? Appearance.sizes.barMarginBottom
                                    : Appearance.sizes.barMarginTop;
        const farInset = barBottom ? Appearance.sizes.barMarginTop
                                   : Appearance.sizes.barMarginBottom;
        return { start: nearInset, end: Appearance.sizes.baseBarHeight - farInset };
    }

    // TimerPill/PrivacyIndicator/SubmapIndicator each centre their pill in that
    // same box, offset by barStandalonePillOffset, at barStandalonePillHeight.
    function standaloneBadgeSpan() {
        const centre = Appearance.sizes.baseBarHeight / 2
            + Appearance.sizes.barStandalonePillOffset;
        const half = Appearance.sizes.barStandalonePillHeight / 2;
        return { start: centre - half, end: centre + half };
    }

    // A standalone badge reads as a compact dynamic-island pill sitting inside
    // the group pill it belongs to, so it has to be inset from that pill by the
    // same amount on both sides. Centring it in the whole bar produced that
    // only while the group pill's own two margins matched; Hug dropped its
    // edge-side margin (131ce1165) and the badge went flush against the pill's
    // window-side edge with all 4px of slack on the other, which is exactly the
    // configuration most users see - Hug is the default cornerStyle.
    function test_standaloneBadgeIsConcentricInsideItsGroupPill() {
        for (let b = 0; b < 2; ++b) {
            const barBottom = b === 1;
            Config.options.bar.bottom = barBottom;
            for (const style of cornerStyles) {
                Config.options.bar.cornerStyle = style;
                const pill = groupPillSpan(barBottom);
                const badge = standaloneBadgeSpan();
                const where = "cornerStyle " + style + ", bottom " + barBottom;

                const nearInset = badge.start - pill.start;
                const farInset = pill.end - badge.end;
                compare(nearInset, farInset,
                        "badge is not concentric in its group pill (" + where + ")");
                compare(nearInset, Appearance.sizes.barStandalonePillMargin,
                        "badge inset is not barStandalonePillMargin (" + where + ")");
                verify(badge.start >= pill.start && badge.end <= pill.end,
                       "badge escapes its group pill (" + where + ")");
            }
        }
    }

    // The offset has to be a real shift, not a constant zero that happens to be
    // right for three of the four styles.
    function test_hugIsTheStyleThatNeedsTheOffset() {
        Config.options.bar.bottom = false;
        Config.options.bar.cornerStyle = 0;
        compare(Appearance.sizes.barMarginTop, 0,
                "Hug should still sit flush against the monitor edge");
        verify(Appearance.sizes.barStandalonePillOffset !== 0,
               "Hug's group pill is off-centre in the bar, so the badge must be "
               + "shifted to match it");

        Config.options.bar.cornerStyle = 1;
        compare(Appearance.sizes.barStandalonePillOffset, 0,
                "a symmetric group pill needs no shift");
    }

    // `bar.bottom` moves the edge-side margin to the other side, so the shift
    // has to mirror with it rather than always pointing the same way.
    function test_theOffsetMirrorsWithTheBarsEdge() {
        Config.options.bar.cornerStyle = 0;
        Config.options.bar.bottom = false;
        const top = Appearance.sizes.barStandalonePillOffset;
        Config.options.bar.bottom = true;
        compare(Appearance.sizes.barStandalonePillOffset, -top,
                "the shift must follow the bar to the other monitor edge");
    }

    // A detached bar style holds the surface off the screen edge. With auto-hide
    // on that gap is not a gap - it is a band of the screen the bar's surface
    // does not cover, and the reveal strip lives inside the surface. Hovering it
    // reached whatever was behind the bar, so an auto-hidden detached bar could
    // not be brought back from the very edge at all; and hiding looked wrong,
    // because the bar slid up inside a surface that already began below the
    // edge, leaving the band above it untouched.
    //
    // The gap has to survive - it is the style - so it moves from the surface's
    // margin to an inset on the content. These two therefore always sum to the
    // gap, whichever side is carrying it.
    function test_autoHideMovesTheDetachGapOffTheSurface() {
        Config.options.bar.bottom = false;
        Config.options.interactions.deadPixelWorkaround.enable = false;
        for (const style of cornerStyles) {
            Config.options.bar.cornerStyle = style;
            const gap = Appearance.sizes.barDetachGap;

            Config.options.bar.autoHide.enable = false;
            compare(Appearance.sizes.barDetachInset, 0,
                    "nothing is inset while the surface keeps the gap, cornerStyle " + style);
            compare(Appearance.sizes.barDetachMargin, gap,
                    "the surface carries the whole gap, cornerStyle " + style);

            Config.options.bar.autoHide.enable = true;
            compare(Appearance.sizes.barDetachMargin, 0,
                    "an auto-hidden bar's surface must reach the edge, cornerStyle " + style);
            compare(Appearance.sizes.barDetachInset, gap,
                    "the content must take on the gap the surface gave up, cornerStyle " + style);
            compare(Appearance.sizes.barDetachMargin + Appearance.sizes.barDetachInset, gap,
                    "the gap changed size instead of moving, cornerStyle " + style);

            // Every later test in this case reads these same tokens, and
            // auto-hide changes what they mean.
            Config.options.bar.autoHide.enable = false;
        }
    }

    // The bottom margin falls through to the detach margin on a top bar, so it
    // inherits the move rather than needing its own rule - and must not go
    // negative doing it.
    function test_theBottomMarginFollowsTheDetachMargin() {
        Config.options.bar.bottom = false;
        Config.options.interactions.deadPixelWorkaround.enable = false;
        Config.options.bar.cornerStyle = m3CornerStyle;
        Config.options.bar.autoHide.enable = true;
        compare(Appearance.sizes.barBottomMargin, Appearance.sizes.barDetachMargin,
                "a top bar's bottom margin must still track the detach margin");
        verify(Appearance.sizes.barBottomMargin >= 0,
               "the surface must not be pulled off the opposite edge");
        Config.options.bar.autoHide.enable = false;
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
