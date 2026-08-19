import QtTest
import "../modules/imi/bar/bar_flip.js" as BarFlip

// The invert and the play offsets a bar slot's reposition is built out of.
// Nothing about the rendered bar is reachable from qmltestrunner, so this is
// the half that can be pinned; BarFlipRuntimeTest.qml is the one that can tell
// the animation from the snap it replaces.
TestCase {
    name: "BarFlipTest"

    function test_a_chain_of_ancestors_sums_to_one_origin() {
        const origin = BarFlip.chainOrigin([{ x: 4, y: 5 }, { x: 100, y: 0 }, { x: 20, y: 3 }]);
        compare(origin.x, 124);
        compare(origin.y, 8);
    }

    function test_an_empty_or_absent_chain_is_the_frames_own_origin() {
        compare(BarFlip.chainOrigin([]).x, 0);
        compare(BarFlip.chainOrigin([]).y, 0);
        compare(BarFlip.chainOrigin(undefined).x, 0);
        compare(BarFlip.chainOrigin(null).y, 0);
    }

    // A slot destroyed mid-walk reads as null from JS; skipping it is right,
    // because the alternative is NaN propagating into the translate, which is
    // a legal double no boundary rejects.
    function test_a_hole_in_the_chain_is_skipped_rather_than_poisoning_it() {
        const origin = BarFlip.chainOrigin([{ x: 10, y: 1 }, null, { x: 5, y: 2 }]);
        compare(origin.x, 15);
        compare(origin.y, 3);
    }

    function test_the_invert_is_the_offset_back_to_where_the_slot_was_drawn() {
        const offset = BarFlip.invert({ x: 600, y: 5 }, { x: 720, y: 5 });
        compare(offset.x, -120);
        compare(offset.y, 0);
        const back = BarFlip.invert({ x: 720, y: 5 }, { x: 600, y: 5 });
        compare(back.x, 120);
    }

    function test_a_missing_record_inverts_to_nothing_rather_than_to_zero() {
        // Zero would be a legal offset - "it did not move" - and would let a
        // slot with no first position play a zero-length animation. NaN is the
        // honest answer and repositionTravel refuses it below.
        verify(isNaN(BarFlip.invert(null, { x: 10, y: 0 }).x));
        verify(isNaN(BarFlip.invert({ x: 10, y: 0 }, null).x));
    }

    function test_only_the_axis_the_bar_runs_along_travels() {
        const offset = { x: -120, y: 7 };
        compare(BarFlip.alongAxis(offset, false), -120);
        compare(BarFlip.alongAxis(offset, true), 7);
    }

    function test_a_reposition_along_the_bar_plays_from_the_inverted_offset() {
        const step = BarFlip.repositionTravel(0, { x: 600, y: 5 }, { x: 720, y: 5 },
                                              false, BarFlip.MIN_TRAVEL);
        verify(step.play);
        compare(step.travel, -120);
    }

    function test_a_reposition_across_the_bar_alone_does_not_play() {
        // A horizontal bar growing taller moves every slot down by the same
        // amount; animating that reads as the bar resizing, not as its
        // contents rearranging.
        const step = BarFlip.repositionTravel(0, { x: 600, y: 5 }, { x: 600, y: 21 },
                                              false, BarFlip.MIN_TRAVEL);
        verify(!step.play);
        compare(step.travel, 0);
    }

    function test_a_sub_pixel_settle_is_not_worth_a_frame_of_motion() {
        const step = BarFlip.repositionTravel(0, { x: 600, y: 0 }, { x: 600.4, y: 0 },
                                              false, BarFlip.MIN_TRAVEL);
        verify(!step.play);
        compare(step.travel, 0);
    }

    function test_a_slot_with_no_record_refuses_instead_of_jumping_from_nowhere() {
        const step = BarFlip.repositionTravel(0, null, { x: 720, y: 5 },
                                              false, BarFlip.MIN_TRAVEL);
        verify(!step.play);
        compare(step.travel, 0);
    }

    // The half a settled check cannot see: a second reflow arriving while the
    // first is still running has to continue from where the slot is DRAWN.
    function test_a_reposition_mid_flight_accumulates_onto_the_travel_in_force() {
        const step = BarFlip.repositionTravel(-80, { x: 720, y: 0 }, { x: 760, y: 0 },
                                              false, BarFlip.MIN_TRAVEL);
        verify(step.play);
        compare(step.travel, -120);
    }

    // Two writes inside one layout pass - the slot's own x, then its section's
    // - must telescope to `recorded - final` whatever order they arrive in, or
    // a caller would have to know how many times the layout touched it.
    function test_two_writes_in_one_pass_telescope_to_the_same_travel() {
        const recorded = { x: 800, y: 0 };
        const first = BarFlip.repositionTravel(0, recorded, { x: 712, y: 0 },
                                               false, BarFlip.MIN_TRAVEL);
        const second = BarFlip.repositionTravel(first.travel, { x: 712, y: 0 },
                                                { x: 820, y: 0 }, false, BarFlip.MIN_TRAVEL);
        compare(second.travel, -20);
        compare(second.travel, recorded.x - 820);
    }

    function test_a_vertical_bar_plays_the_same_reposition_down_its_strip() {
        const step = BarFlip.repositionTravel(0, { x: 4, y: 300 }, { x: 4, y: 220 },
                                              true, BarFlip.MIN_TRAVEL);
        verify(step.play);
        compare(step.travel, 80);
    }
}
