import QtTest
import "../modules/common/functions/edge_snap.js" as EdgeSnap

// Widget-to-widget edge alignment (spec §6). Three decisions live in the
// module and nothing else does: which alignments a neighbour offers (four
// relations per axis, each carrying the position the widget travels to AND the
// edge the guide is drawn at, because the line belongs to the OTHER widget),
// which neighbours are close enough across the axis to matter at all, and the
// two-threshold hold - acquire near, release far, both measured against the
// UNSNAPPED shadow position. Everything about the rendered guide needs a real
// canvas `qmltestrunner` cannot construct, so the arithmetic is the part a
// test can reach.
TestCase {
    name: "EdgeSnapTest"

    // One neighbour, seen from the x axis. The dragged widget is 60 wide and
    // overlaps the neighbour vertically, so every relation is offered.
    readonly property var xNeighbour: ({ x: 300, y: 100, width: 120, height: 80 })

    function hasCandidate(candidates, target, guide) {
        for (let i = 0; i < candidates.length; i++) {
            if (candidates[i].target === target && candidates[i].guide === guide)
                return true;
        }
        return false;
    }

    function test_four_relations_per_neighbour_on_x() {
        const candidates = EdgeSnap.candidatesForAxis([xNeighbour], "x", 60, 120, 40);
        compare(candidates.length, 4);
        // near-to-near: our left on their left, line at their left.
        verify(hasCandidate(candidates, 300, 300));
        // far-to-far: our right on their right - the widget travels to
        // 420 - 60, but the line is drawn at THEIR edge, not where we land.
        verify(hasCandidate(candidates, 360, 420));
        // near-to-far: our left against their right (sitting beside them).
        verify(hasCandidate(candidates, 420, 420));
        // far-to-near: our right against their left.
        verify(hasCandidate(candidates, 240, 300));
    }

    function test_four_relations_per_neighbour_on_y() {
        const neighbour = { x: 40, y: 500, width: 90, height: 200 };
        const candidates = EdgeSnap.candidatesForAxis([neighbour], "y", 80, 60, 50);
        compare(candidates.length, 4);
        verify(hasCandidate(candidates, 500, 500));      // top-to-top
        verify(hasCandidate(candidates, 620, 700));      // bottom-to-bottom
        verify(hasCandidate(candidates, 700, 700));      // top under their bottom
        verify(hasCandidate(candidates, 420, 500));      // bottom on their top
    }

    function test_a_neighbour_across_the_axis_contributes_nothing() {
        // The neighbour spans y 100..180. A widget whose own vertical extent
        // sits a gap short of the limit still aligns to it...
        const nearlyFar = EdgeSnap.candidatesForAxis([xNeighbour], "x", 60,
            180 + EdgeSnap.PERPENDICULAR_LIMIT_PX - 1, 40);
        compare(nearlyFar.length, 4);
        // ...and at exactly the limit it does not: the boundary value is
        // excluded, so the limit is the first distance that contributes
        // nothing rather than the last one that does.
        const atTheLimit = EdgeSnap.candidatesForAxis([xNeighbour], "x", 60,
            180 + EdgeSnap.PERPENDICULAR_LIMIT_PX, 40);
        compare(atTheLimit.length, 0);
        const past = EdgeSnap.candidatesForAxis([xNeighbour], "x", 60,
            180 + EdgeSnap.PERPENDICULAR_LIMIT_PX + 50, 40);
        compare(past.length, 0);
    }

    function test_overlapping_extents_are_distance_zero() {
        // Perpendicular distance is the GAP between extents, not a
        // centre-to-centre measure: any overlap is distance zero, so a tall
        // neighbour cannot be pushed out of relevance by its own height.
        const tall = { x: 300, y: 0, width: 120, height: 2000 };
        const candidates = EdgeSnap.candidatesForAxis([tall], "x", 60, 900, 40);
        compare(candidates.length, 4);
    }

    function test_acquire_happens_only_inside_the_near_threshold() {
        const candidates = EdgeSnap.candidatesForAxis([xNeighbour], "x", 60, 120, 40);
        // 283 is 17 short of the near-to-near target at 300: inside.
        const held = EdgeSnap.resolveSnap(283, candidates, null);
        verify(held !== null);
        compare(held.target, 300);
        compare(held.guide, 300);
        // 282 is exactly the acquire threshold away: outside. A boundary that
        // acquires is a boundary the release test can sit on.
        compare(EdgeSnap.resolveSnap(300 - EdgeSnap.ACQUIRE_PX, candidates, null), null);
    }

    function test_the_nearest_candidate_wins() {
        // Two neighbours whose left edges are 10px apart; a shadow between
        // them acquires whichever is closer, not whichever came first.
        const pair = [
            { x: 300, y: 100, width: 120, height: 80 },
            { x: 310, y: 100, width: 120, height: 80 }
        ];
        const candidates = EdgeSnap.candidatesForAxis(pair, "x", 60, 120, 40);
        const held = EdgeSnap.resolveSnap(306, candidates, null);
        verify(held !== null);
        compare(held.target, 310);
    }

    function test_a_walk_past_the_guide_acquires_near_and_releases_only_far() {
        // The assertion the whole section exists for, driven as a sequence of
        // raw shadow positions the way a drag delivers them. A single-threshold
        // implementation fails it by flip-flopping: its decision boundary and
        // the resulting position are the same number, so it releases the
        // moment the pointer clears the near threshold. An implementation that
        // compares the RENDERED position instead of the shadow fails the other
        // way - the rendered position sits on the target, so it never
        // releases at all.
        const candidates = EdgeSnap.candidatesForAxis([xNeighbour], "x", 60, 120, 40);
        let held = null;
        // The walk stops at 340: past that the shadow starts closing on the
        // far-to-far target at 360, which is a different acquisition, not this
        // test's release.
        for (let pos = 270; pos <= 340; pos++) {
            held = EdgeSnap.resolveSnap(pos, candidates, held);
            const distance = Math.abs(pos - 300);
            if (distance >= EdgeSnap.RELEASE_PX) {
                verify(held === null,
                    `still held ${distance}px past the guide, at ${pos}`);
            } else if (pos > 300) {
                // Between the two thresholds, approached from inside: the
                // detent. This is the band a single-threshold implementation
                // has already let go of.
                verify(held !== null && held.target === 300,
                    `released early at ${pos}, ${distance}px from the guide`);
            } else if (distance < EdgeSnap.ACQUIRE_PX) {
                verify(held !== null && held.target === 300,
                    `not acquired at ${pos}, ${distance}px from the guide`);
            } else {
                // Approaching from outside, past neither threshold yet.
                verify(held === null,
                    `acquired at ${pos}, ${distance}px out - before the near threshold`);
            }
        }
    }

    function test_a_held_candidate_survives_regenerated_lists() {
        // Candidates are rebuilt on every drag event, so the hold has to be
        // identity by VALUE - a held object compared by reference against a
        // fresh list would release on every event.
        const first = EdgeSnap.candidatesForAxis([xNeighbour], "x", 60, 120, 40);
        const held = EdgeSnap.resolveSnap(295, first, null);
        verify(held !== null);
        const second = EdgeSnap.candidatesForAxis([xNeighbour], "x", 60, 125, 40);
        const stillHeld = EdgeSnap.resolveSnap(320, second, held);
        verify(stillHeld !== null);
        compare(stillHeld.target, 300);
    }

    function test_a_held_candidate_that_leaves_the_set_releases() {
        // The neighbour moved out of perpendicular relevance mid-drag (the
        // dragged widget travelled across the axis), so its candidates are
        // gone from the regenerated list. The hold releases even though the
        // shadow is still within the release threshold of the old target -
        // a guide for a neighbour that no longer qualifies is a line about
        // nothing.
        const before = EdgeSnap.candidatesForAxis([xNeighbour], "x", 60, 120, 40);
        const held = EdgeSnap.resolveSnap(295, before, null);
        verify(held !== null);
        const after = EdgeSnap.candidatesForAxis([xNeighbour], "x", 60,
            180 + EdgeSnap.PERPENDICULAR_LIMIT_PX, 40);
        compare(EdgeSnap.resolveSnap(295, after, held), null);
    }

    function test_the_two_thresholds_are_a_detent_not_a_line() {
        // The mechanism is not the two numbers, it is that they differ: the
        // gap between them is what makes the hold feel like a detent. Equal
        // thresholds are the flip-flop the walk above catches behaviourally;
        // this pins the shape so a "simplification" to one constant reddens
        // by name.
        verify(EdgeSnap.ACQUIRE_PX < EdgeSnap.RELEASE_PX);
        verify(EdgeSnap.ACQUIRE_PX > 0);
        verify(EdgeSnap.PERPENDICULAR_LIMIT_PX > 0);
    }

    function test_no_neighbours_means_no_candidates_and_no_hold() {
        compare(EdgeSnap.candidatesForAxis([], "x", 60, 120, 40).length, 0);
        compare(EdgeSnap.resolveSnap(300, [], null), null);
    }
}
