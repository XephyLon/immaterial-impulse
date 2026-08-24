import QtTest
import "../modules/common/motion_policy.js" as Motion

// The motion policy: how the speed multiplier scales a catalogued duration,
// where the reduce-motion floor is and who can reach it, and how a group of
// things arrives in sequence.
//
// A multiplier is trivially testable and trivially fakeable - "the scalar
// exists" is worth nothing. What is pinned here is the behaviour that would be
// wrong if someone re-implemented this from the surveyed fork: that the floor
// is not somewhere a slider can land, that a long cascade terminates, and that
// a hidden member does not spend a slot.
TestCase {
    name: "MotionPolicyTest"

    function test_the_multiplier_scales_a_duration_in_both_directions() {
        compare(Motion.scaleDuration(200, 1.0, false), 200);
        compare(Motion.scaleDuration(200, 2.0, false), 400);
        compare(Motion.scaleDuration(500, 0.5, false), 250);
        compare(Motion.scaleDuration(150, 1.5, false), 225);
    }

    // The whole point of the clamp. `animationMultiplier <= 0.25` is how the
    // surveyed fork spells "the user turned motion off", re-derived by hand at
    // seven call sites - so there, dragging the slider one notch too far IS
    // the accessibility state, and dragging it back is losing it.
    function test_no_multiplier_can_reach_the_reduce_motion_floor() {
        const extremes = [0, -1, 0.01, 0.25, Motion.MULTIPLIER_MIN, NaN,
                          undefined, null, "0", -Infinity];
        for (let i = 0; i < extremes.length; i++) {
            const scaled = Motion.scaleDuration(200, extremes[i], false);
            verify(scaled > Motion.REDUCE_MOTION_DURATION,
                   "multiplier " + extremes[i] + " produced the floor: " + scaled);
            verify(scaled >= 200 * Motion.MULTIPLIER_MIN,
                   "multiplier " + extremes[i] + " scaled below the sanctioned range");
        }
    }

    function test_the_floor_is_reached_only_by_the_named_state() {
        compare(Motion.scaleDuration(500, 2.5, true), Motion.REDUCE_MOTION_DURATION,
                "reduce motion wins over any multiplier");
        compare(Motion.scaleDuration(500, 1.0, true), Motion.REDUCE_MOTION_DURATION);
        verify(Motion.MULTIPLIER_MIN > 0,
               "a multiplier range whose bottom is zero IS the floor");
    }

    function test_the_clamp_holds_for_a_hand_edited_config() {
        compare(Motion.clampMultiplier(9), Motion.MULTIPLIER_MAX);
        compare(Motion.clampMultiplier(-3), Motion.MULTIPLIER_MIN);
        compare(Motion.clampMultiplier("nonsense"), Motion.MULTIPLIER_DEFAULT);
        compare(Motion.clampMultiplier(undefined), Motion.MULTIPLIER_DEFAULT);
    }

    // A velocity is the reciprocal axis, so it must move the other way. A
    // multiplier applied to it as if it were a duration would make "slower"
    // mean "faster" for every SmoothedAnimation in the shell.
    function test_a_velocity_scales_the_other_way() {
        compare(Motion.scaleVelocity(650, 1.0, false), 650);
        verify(Motion.scaleVelocity(650, 2.0, false) < 650, "slower shell, slower travel");
        verify(Motion.scaleVelocity(650, 0.5, false) > 650, "faster shell, faster travel");
        verify(Motion.scaleVelocity(650, 1.0, true) >= Motion.REDUCE_MOTION_VELOCITY,
               "the floor makes velocity-driven motion effectively instant");
        verify(isFinite(Motion.scaleVelocity(650, 1.0, true)),
               "and finite, so QQuickSmoothedAnimation is never handed Infinity");
    }

    // `index * step` is unbounded, and the failure is silent: nothing errors,
    // the wave simply keeps admitting members long after the container that
    // opened for them has settled.
    function test_a_long_cascade_terminates() {
        const step = 40;
        const capped = Motion.staggerDelay(200, step, 0);
        compare(capped, Motion.STAGGER_MAX_RANK * step);
        compare(Motion.staggerDelay(Motion.STAGGER_MAX_RANK, step, 0), capped,
                "the clamp bites exactly at the ladder's last rung");
        verify(Motion.staggerDelay(4, step, 0) < capped,
               "and not before it");
    }

    function test_the_lead_in_is_added_once_and_survives_the_clamp() {
        compare(Motion.staggerDelay(0, 40, 120), 120);
        compare(Motion.staggerDelay(2, 40, 120), 200);
        compare(Motion.staggerDelay(99, 40, 120), 120 + Motion.STAGGER_MAX_RANK * 40);
        compare(Motion.staggerDelay(-1, 40, 120), 120,
                "an excluded member still starts with everything else");
    }

    // A hidden member that spends a slot leaves a hole one step wide in the
    // middle of the wave, and nothing downstream compensates because every
    // later member is still counted from its own index.
    function test_a_hidden_member_does_not_spend_a_slot() {
        const ranks = Motion.staggerRanks([true, false, true, true]);
        compare(ranks.length, 4, "the result stays index-aligned with the input");
        compare(ranks[0], 0);
        compare(ranks[1], -1, "excluded members are marked, not dropped");
        compare(ranks[2], 1, "the member after a hidden one takes the free slot");
        compare(ranks[3], 2);
    }

    function test_ranking_an_all_hidden_group_produces_no_wave() {
        const ranks = Motion.staggerRanks([false, false]);
        compare(ranks[0], -1);
        compare(ranks[1], -1);
        compare(Motion.staggerRanks([]).length, 0);
    }

    // The gate is what makes a staggered group read as composed rather than
    // loose: the contents wait for their container instead of racing the reveal
    // they are meant to land in.
    function test_contents_wait_for_the_container_on_the_way_in() {
        verify(!Motion.contentsArrived(0, true), "nothing arrives before the container does");
        verify(!Motion.contentsArrived(Motion.CONTAINER_CONTENT_GATE - 0.01, true));
        verify(Motion.contentsArrived(Motion.CONTAINER_CONTENT_GATE, true),
               "the gate is inclusive - a container exactly at it has arrived");
        verify(Motion.contentsArrived(1, true));
        // A spatial tier that overshoots hands this numbers above 1, and a
        // container past its destination is emphatically open.
        verify(Motion.contentsArrived(1.0139, true));
    }

    // ...and the asymmetry IS the rule: on the way out the contents do not
    // leave, they ride the container off as one rigid transform. So the closing
    // branch holds until the container has nothing left, which is where the
    // reset belongs - off screen, where nobody sees a member snap back.
    function test_contents_ride_the_container_out() {
        verify(Motion.contentsArrived(1, false));
        verify(Motion.contentsArrived(0.2, false),
               "a container still on screen still has its contents in it");
        verify(Motion.contentsArrived(0.001, false));
        verify(!Motion.contentsArrived(0, false), "gone is gone");
        // The same overshooting curve run backwards undershoots below zero, and
        // a container past its exit is not an arrival.
        verify(!Motion.contentsArrived(-0.0139, false));
    }

    // No guard is needed for these and none is written: every comparison
    // against NaN is false, so an absent or unparseable progress answers "not
    // arrived" on both branches by itself. Pinned because the tempting repair
    // is an isFinite() that no test can redden.
    function test_a_gate_asked_about_nothing_answers_no() {
        verify(!Motion.contentsArrived(undefined, true));
        verify(!Motion.contentsArrived(undefined, false));
        verify(!Motion.contentsArrived(NaN, false));
        verify(!Motion.contentsArrived("nonsense", true));
        // ...and null converts to 0, which is honestly "not open yet" rather
        // than a value that has to be rejected.
        verify(!Motion.contentsArrived(null, false));
    }

    // Expressed as a fraction of a catalogued duration rather than as a
    // literal, so it moves with any retiming of the tiers - and unscaled, so
    // whatever consumes it applies the multiplier exactly once.
    function test_the_step_is_a_fraction_of_a_catalogued_duration() {
        compare(Motion.staggerStep(200), 40);
        compare(Motion.staggerStep(500), 100);
        verify(Motion.staggerStep(200) < 200, "a step is a slice of a tier, not a tier");
    }

    // The consumer scales the step; scaling it here as well would apply the
    // multiplier twice and a wave would run at the square of the setting.
    function test_a_scaled_step_collapses_at_the_floor() {
        const step = Motion.scaleDuration(Motion.staggerStep(200), 1.0, true);
        compare(step, 0);
        compare(Motion.staggerDelay(3, step, 0), 0,
                "reduce motion needs no second gate on the stagger");
    }

    // A wave member's entrance scale is DERIVED from the rise and the width it
    // plays on, not picked: the survey measured 0.85 on a popup's compact
    // cards, and on a full-width row the same factor is a horizontal swing
    // wider than the rise it accompanies - a zoom, not a settle. Matching the
    // scale's excursion to the rise keeps the two terms one motion at any
    // width, with the measured 0.85 as the floor so a narrow member cannot
    // invert the proportion.
    function test_the_entrance_scale_matches_its_excursion_to_the_rise() {
        // The drawer's own numbers: a 20px rise on a 380px panel. This exact
        // value is what the drawer rendered before the derivation moved here,
        // so a change to it is a visible change to a shipped surface.
        fuzzyCompare(Motion.entranceScaleFrom(20, 380), 1 - 20 / 380, 1e-9);
        // Wide member, nearer 1 - the scale excursion stays the rise's size.
        fuzzyCompare(Motion.entranceScaleFrom(20, 4000), 0.995, 1e-9);
    }

    function test_the_entrance_scale_floors_at_the_measured_constant() {
        compare(Motion.ENTRANCE_SCALE_FLOOR, 0.85,
                "the floor is the survey's measured popup scale");
        compare(Motion.entranceScaleFrom(20, 100), Motion.ENTRANCE_SCALE_FLOOR,
                "a narrow member takes the floor, not a deeper zoom");
        compare(Motion.entranceScaleFrom(20, 0), Motion.ENTRANCE_SCALE_FLOOR,
                "an unmeasured width answers the floor, not 1 - rise/0");
    }

    // The absent-input rule this module already lives by: `Number(null)` is 0
    // and NaN compares false, so a guard has to be a comparison rather than a
    // Math.max, which returns the NaN it was supposed to remove.
    function test_a_nonsense_entrance_input_cannot_reach_the_render() {
        compare(Motion.entranceScaleFrom(NaN, 380), Motion.ENTRANCE_SCALE_FLOOR);
        compare(Motion.entranceScaleFrom(undefined, 380), Motion.ENTRANCE_SCALE_FLOOR);
        compare(Motion.entranceScaleFrom(20, NaN), Motion.ENTRANCE_SCALE_FLOOR);
        // A rise of zero (or a nonsense negative one) is no scale excursion at
        // all - never a member that arrives LARGER than it rests.
        compare(Motion.entranceScaleFrom(0, 380), 1);
        compare(Motion.entranceScaleFrom(-5, 380), 1);
    }

    function test_convergence_comes_from_the_members_own_side() {
        // The thirds rule: leftmost members from further left, rightmost from
        // further right, the middle third straight - and rows alternate.
        compare(Motion.convergeFrom(-0.8, 0).dx, -1);
        compare(Motion.convergeFrom(0.8, 0).dx, 1);
        compare(Motion.convergeFrom(0, 0).dx, 0);
        // Full-width sections sit dead centre, so a section column
        // degenerates to pure vertical alternation.
        compare(Motion.convergeFrom(0, 0).dy, -1);
        compare(Motion.convergeFrom(0, 1).dy, 1);
        compare(Motion.convergeFrom(0, 2).dy, -1);
        // The boundary itself is the middle third, so a member exactly on it
        // cannot flip direction on a one-pixel reflow.
        compare(Motion.convergeFrom(-1 / 3, 0).dx, 0);
        compare(Motion.convergeFrom(1 / 3, 0).dx, 0);
    }

    function test_the_settle_overshoots_and_lands() {
        // Endpoints are exact, so a settled member sits precisely in place
        // and a parked one precisely at its reach.
        compare(Motion.convergeSettle(0), 0);
        compare(Motion.convergeSettle(1), 1);
        // Late in the arrival the shape crosses 1 - the overshoot that makes
        // an arrival a landing - and returns.
        verify(Motion.convergeSettle(0.9) > 1);
        verify(Motion.convergeSettle(0.25) < 1);
        // Nonsense stays parked rather than becoming NaN geometry.
        compare(Motion.convergeSettle(NaN), 0);
        compare(Motion.convergeSettle(undefined), 0);
    }
}
