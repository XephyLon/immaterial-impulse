import QtTest
import "../modules/common/interaction_motion.js" as Motion

// The interaction motion model: which state the flags resolve to, what that
// state targets, and which transition carries the element there.
TestCase {
    name: "InteractionMotionTest"

    readonly property var tokens: ({
        hoverScale: 1.02, pressScale: 0.97,
        pressRadiusScale: 0.85, disabledOpacity: 0.4
    })
    readonly property var tiers: ({
        hoverIn: { duration: 200, curve: [0, 0, 1, 1] },
        hoverOut: { duration: 250, curve: [0, 0, 1, 1] },
        press: { duration: 150, curve: [0, 0, 1, 1] },
        release: { duration: 350, curve: [0.42, 1.67, 0.21, 0.9, 1, 1] },
        instant: { duration: 0, curve: [0, 0, 1, 1] },
        hold: { duration: 0, curve: [0, 0, 1, 1] }
    })

    function test_disabled_outranks_every_other_flag() {
        compare(Motion.stateOf({ enabled: false, hovered: true, down: true }), "disabled");
        compare(Motion.stateOf({ enabled: true, hovered: true, down: true }), "pressed");
        compare(Motion.stateOf({ enabled: true, hovered: true }), "hovered");
        compare(Motion.stateOf({ enabled: true }), "rest");
        compare(Motion.stateOf({}), "rest", "absent flags are a resting control");
    }

    function test_hover_lifts_and_press_settles() {
        const hover = Motion.targetsFor("hovered", tokens);
        const press = Motion.targetsFor("pressed", tokens);
        const rest = Motion.targetsFor("rest", tokens);
        verify(hover.scale > rest.scale, "hover lifts");
        verify(press.scale < rest.scale, "press settles into the surface");
        verify(press.radiusScale < 1, "and its corners tighten");
        compare(hover.radiusScale, 1, "hover does not reshape");
    }

    function test_a_pressed_control_is_still_hovered_by_the_model() {
        // A wash driven by `hover` must not fade out the instant the press
        // lands - that reads as the control letting go under the finger.
        compare(Motion.targetsFor("pressed", tokens).hover, 1);
        compare(Motion.targetsFor("hovered", tokens).hover, 1);
        compare(Motion.targetsFor("rest", tokens).hover, 0);
        compare(Motion.targetsFor("disabled", tokens).hover, 0);
    }

    function test_disabled_is_opacity_only() {
        const disabled = Motion.targetsFor("disabled", tokens);
        compare(disabled.scale, 1);
        compare(disabled.radiusScale, 1);
        verify(disabled.opacity < 1);
        verify(Motion.isMotionless(Motion.transitionFor("rest", "disabled", tiers)));
        verify(Motion.isMotionless(Motion.transitionFor("disabled", "hovered", tiers)));
    }

    function test_a_press_is_acknowledged_faster_than_it_is_released() {
        const press = Motion.transitionFor("hovered", "pressed", tiers);
        const release = Motion.transitionFor("pressed", "hovered", tiers);
        verify(press.duration < release.duration);
        compare(press, tiers.press);
    }

    function test_a_release_animates_even_when_the_pointer_has_left() {
        // Press, drag off the control, let go: the state goes pressed -> rest
        // with no hover in between. Treating that as a hover-out is how a
        // control ends up visibly stuck at its pressed size.
        compare(Motion.transitionFor("pressed", "rest", tiers), tiers.release);
        compare(Motion.transitionFor("hovered", "rest", tiers), tiers.hoverOut);
    }

    function test_the_return_is_slower_than_the_arrival() {
        verify(Motion.transitionFor("rest", "hovered", tiers).duration
             < Motion.transitionFor("hovered", "rest", tiers).duration);
    }

    function test_the_release_curve_overshoots() {
        // The spring is the point: a release that eases flat reads as the
        // control deflating rather than springing back.
        const release = Motion.transitionFor("pressed", "rest", tiers);
        verify(release.curve.some(v => v > 1.0), "some control point leaves the unit box");
    }

    function test_a_state_that_did_not_change_does_not_animate() {
        verify(Motion.isMotionless(Motion.transitionFor("hovered", "hovered", tiers)));
    }
}
