import QtTest
import "../modules/imi/bar/bar_popup_unroll.js" as BarPopupUnroll

// The bar popup card's height, which is the whole of what its one driver
// scalar produces. Nothing about the card itself is reachable from here - it
// lives on a wlr-layer-shell surface qmltestrunner cannot build - so the
// arithmetic is what the checks reach.
TestCase {
    name: "BarPopupUnrollTest"

    readonly property real padding: 8
    readonly property real parkedSize: 20

    function sections(spec) {
        // Enough of an Item for the measurement: the module reads `visible`
        // and `height` and must read nothing else, because a section is any
        // item a popup happens to declare first.
        return spec.map(entry => ({ visible: entry[0], height: entry[1] }));
    }

    function test_the_hero_is_the_first_drawn_section_plus_the_card_inset() {
        compare(BarPopupUnroll.heroSectionHeight(
            sections([[true, 125], [true, 80], [true, 40]]), padding),
            125 + padding * 2);
    }

    function test_an_undrawn_or_empty_leading_section_is_not_the_hero() {
        // A spacer or a hidden row spending the first slot would open the card
        // at the height of nothing, which is the same failure as ranking a
        // stagger by position in `children`.
        compare(BarPopupUnroll.heroSectionHeight(
            sections([[false, 125], [true, 0], [true, 80]]), padding),
            80 + padding * 2);
    }

    function test_content_with_no_measurable_section_reports_no_hero() {
        compare(BarPopupUnroll.heroSectionHeight(sections([]), padding), 0);
        compare(BarPopupUnroll.heroSectionHeight(
            sections([[false, 125], [true, 0]]), padding), 0);
        compare(BarPopupUnroll.heroSectionHeight(undefined, padding), 0);
    }

    function test_the_card_opens_at_the_hero_and_unrolls_to_the_full_height() {
        const open = 400;
        const hero = 141;
        compare(BarPopupUnroll.cardHeight(open, hero, parkedSize, false, 0), hero);
        compare(BarPopupUnroll.cardHeight(open, hero, parkedSize, false, 1), open);
        // The unroll is exactly the progress: half way is half the distance,
        // which is what lets the fade ride the same scalar.
        compare(BarPopupUnroll.cardHeight(open, hero, parkedSize, false, 0.5),
                hero + (open - hero) / 2);
    }

    function test_the_start_height_is_the_hero_rather_than_the_parked_square() {
        // The check that reddens if the unroll is rewritten against a literal
        // or against the floor: two different heroes must give two different
        // starts, and neither may be the parked square.
        const first = BarPopupUnroll.cardHeight(400, 141, parkedSize, false, 0);
        const second = BarPopupUnroll.cardHeight(400, 232, parkedSize, false, 0);
        compare(first, 141);
        compare(second, 232);
        verify(first !== parkedSize);
        verify(second !== parkedSize);
    }

    function test_a_hero_taller_than_the_content_is_no_unroll_at_all() {
        // A one-section popup: the hero IS the content, so rest and open
        // coincide and the card simply has no unroll rather than a case.
        compare(BarPopupUnroll.cardHeight(200, 260, parkedSize, false, 0), 200);
        compare(BarPopupUnroll.cardHeight(200, 200, parkedSize, false, 0.4), 200);
    }

    function test_without_a_hero_the_card_still_grows_out_of_the_bar() {
        compare(BarPopupUnroll.cardHeight(400, 0, parkedSize, false, 0), parkedSize);
        compare(BarPopupUnroll.cardHeight(400, 0, parkedSize, false, 1), 400);
    }

    function test_leaving_collapses_toward_the_parked_square_not_the_hero() {
        compare(BarPopupUnroll.cardHeight(400, 141, parkedSize, true, 0), parkedSize);
        // The moment the exit begins the card has not moved: at a settled
        // progress the rest height is not in the answer at all, so flipping to
        // the exit's rest cannot make the card jump.
        compare(BarPopupUnroll.cardHeight(400, 141, parkedSize, true, 1), 400);
        compare(BarPopupUnroll.cardHeight(400, 141, parkedSize, false, 1), 400);
    }

    function test_an_idle_card_is_zero_tall_at_every_progress() {
        // Load-bearing, not cosmetic: an `opacity: 0` card still publishes a
        // full-size input region, and the overlay's surface is screen-sized and
        // on the Overlay layer. A zero-height region is what makes Qt mark the
        // whole surface transparent for input.
        for (const progress of [0, 0.5, 1, -0.3, 1.2]) {
            compare(BarPopupUnroll.cardHeight(0, 0, parkedSize, false, progress), 0);
            compare(BarPopupUnroll.cardHeight(0, 141, parkedSize, true, progress), 0);
        }
    }

    function test_the_exit_curve_undershooting_below_zero_does_not_invert_the_card() {
        // expressiveDefaultSpatial overshoots past its target, so a 1 -> 0 ramp
        // passes below 0 before settling. A negative height is a card that
        // vanishes and comes back at the end of every exit.
        verify(BarPopupUnroll.cardHeight(400, 141, parkedSize, true, -0.21) >= 0);
        compare(BarPopupUnroll.cardHeight(400, 141, parkedSize, true, -0.21), parkedSize);
    }

    function test_the_overshoot_past_one_is_kept() {
        // The other half of the same curve, and it is deliberate: the card
        // overshooting its content and settling back is the tier's own
        // expressiveness, and it is what the height Behavior this replaced did.
        verify(BarPopupUnroll.cardHeight(400, 141, parkedSize, false, 1.21) > 400);
    }

    // ---- the section entrance's three channels ------------------------------
    //
    // A below-the-fold section arrives on one `appear` scalar driving opacity,
    // a slight scale and a small rise together (the measured survey's §3
    // three-property entrance). The scale's excursion is DERIVED from the rise
    // over the section's own width, floored at the survey's measured 0.85 -
    // EditModeDrawer.qml derives it the same way and says why: a fixed factor
    // is a settle on a compact card and a zoom on a wide row.

    readonly property real rise: 20

    function test_a_settled_member_is_not_dressed_at_all() {
        compare(BarPopupUnroll.entranceScale(1, rise, 300), 1);
        compare(BarPopupUnroll.entranceOffset(1, rise), 0);
    }

    function test_the_entrance_starts_scaled_down_by_the_rise_over_the_width() {
        compare(BarPopupUnroll.entranceScale(0, rise, 400), 1 - rise / 400);
    }

    function test_the_scale_floor_is_the_surveys_measured_085() {
        // A narrow section would otherwise invert the derivation into a zoom:
        // 20 of rise over 100 of width is a 0.8 start, below what was measured
        // on the sibling fork's own compact popup cards.
        compare(BarPopupUnroll.entranceScale(0, rise, 100), 0.85);
    }

    function test_a_section_with_no_width_yet_takes_the_floor_not_NaN() {
        // Sections are measured before their first layout pass; a width of 0
        // divided into the rise is -Infinity waiting to happen, and NaN
        // geometry is a relayout that never converges.
        compare(BarPopupUnroll.entranceScale(0, rise, 0), 0.85);
        compare(BarPopupUnroll.entranceScale(0, rise, undefined), 0.85);
    }

    function test_the_rise_is_spent_linearly_with_appear() {
        compare(BarPopupUnroll.entranceOffset(0, rise), rise);
        compare(BarPopupUnroll.entranceOffset(0.5, rise), rise / 2);
    }

    function test_scale_and_rise_land_together_because_both_are_linear_in_appear() {
        // Half the appear is half the excursion on BOTH channels - the whole
        // point of one scalar is that the three cannot finish on different
        // schedules.
        const from = BarPopupUnroll.entranceScale(0, rise, 400);
        compare(BarPopupUnroll.entranceScale(0.5, rise, 400), from + (1 - from) / 2);
    }
}
