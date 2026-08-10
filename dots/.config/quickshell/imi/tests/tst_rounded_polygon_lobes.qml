import QtQuick
import QtTest
import "../modules/common/plugins/designsystem/widgets/shapes/rounded-polygon.js" as RoundedPolygon
import "../modules/common/plugins/designsystem/widgets/shapes/corner-rounding.js" as CornerRounding

// star() takes one scalar inner radius, so every lobe of a cookie is the same
// and animating it only makes the whole shape breathe. starPerLobe() takes one
// radius per lobe, which is what a per-band visualizer needs.
TestCase {
    id: root
    name: "RoundedPolygonLobesTest"

    // A QML list<real> is a sequence object, not a JS array - the shape of
    // input the visualizer actually hands the maths.
    property list<real> sequenceRadii: [0.80, 0.85, 0.90, 0.95]

    readonly property var cookieRounding: new CornerRounding.CornerRounding(0.5)

    function radiusOf(vertices, index) {
        const x = vertices[index * 2];
        const y = vertices[index * 2 + 1];
        return Math.sqrt(x * x + y * y);
    }

    // --- scalar behaviour is unchanged -------------------------------------

    function test_a_scalar_inner_radius_is_exactly_the_old_star() {
        const perLobe = RoundedPolygon.RoundedPolygon.starVerticesPerLobe(12, 1, 0.8, 0, 0);
        const original = RoundedPolygon.RoundedPolygon.starVerticesFromNumVerts(12, 1, 0.8, 0, 0);
        compare(perLobe.length, original.length);
        for (let i = 0; i < original.length; i++)
            fuzzyCompare(perLobe[i], original[i], 1e-12);
    }

    function test_a_scalar_polygon_matches_star() {
        const perLobe = RoundedPolygon.RoundedPolygon.starPerLobe(12, 1, 0.8, root.cookieRounding);
        const original = RoundedPolygon.RoundedPolygon.star(12, 1, 0.8, root.cookieRounding);
        compare(perLobe.cubics.length, original.cubics.length);
        for (let i = 0; i < original.cubics.length; i++) {
            fuzzyCompare(perLobe.cubics[i].anchor0X, original.cubics[i].anchor0X, 1e-12);
            fuzzyCompare(perLobe.cubics[i].anchor0Y, original.cubics[i].anchor0Y, 1e-12);
        }
    }

    // --- one radius per lobe -----------------------------------------------

    function test_each_lobe_takes_its_own_radius() {
        const radii = [];
        for (let i = 0; i < 12; i++)
            radii.push(0.70 + i * 0.02);
        const vertices = RoundedPolygon.RoundedPolygon.starVerticesPerLobe(12, 1, radii, 0, 0);

        compare(vertices.length, 12 * 4);
        for (let lobe = 0; lobe < 12; lobe++) {
            // Vertices alternate outer, inner, outer, inner...
            fuzzyCompare(radiusOf(vertices, lobe * 2), 1, 1e-9);
            fuzzyCompare(radiusOf(vertices, lobe * 2 + 1), radii[lobe], 1e-9);
        }
    }

    function test_twelve_distinct_radii_give_twelve_distinct_lobes() {
        const radii = [];
        for (let i = 0; i < 12; i++)
            radii.push(0.70 + i * 0.02);
        const vertices = RoundedPolygon.RoundedPolygon.starVerticesPerLobe(12, 1, radii, 0, 0);

        const seen = {};
        for (let lobe = 0; lobe < 12; lobe++)
            seen[radiusOf(vertices, lobe * 2 + 1).toFixed(6)] = true;
        compare(Object.keys(seen).length, 12);
    }

    function test_a_moved_lobe_reaches_the_built_geometry() {
        // The vertex helper being right is not enough: the radii have to
        // survive the rounding/cubic build, which is what actually gets drawn.
        const flat = [];
        const bumped = [];
        for (let i = 0; i < 12; i++) {
            flat.push(0.8);
            bumped.push(i === 3 ? 0.99 : 0.8);
        }
        const flatBounds = RoundedPolygon.RoundedPolygon.starPerLobe(12, 1, flat, root.cookieRounding).calculateMaxBounds();
        const bumpedBounds = RoundedPolygon.RoundedPolygon.starPerLobe(12, 1, bumped, root.cookieRounding).calculateMaxBounds();

        verify(bumpedBounds[2] > flatBounds[2]);
    }

    function test_which_lobe_moved_changes_the_outline() {
        // Magnitude alone would pass even if every lobe read radii[0]; the two
        // shapes must differ from each other, not just from the resting one.
        function bumpedAt(lobe) {
            const radii = [];
            for (let i = 0; i < 12; i++)
                radii.push(i === lobe ? 0.99 : 0.8);
            return RoundedPolygon.RoundedPolygon.starPerLobe(12, 1, radii, root.cookieRounding).cubics;
        }
        const first = bumpedAt(0);
        const other = bumpedAt(6);
        compare(first.length, other.length);

        let differences = 0;
        for (let i = 0; i < first.length; i++) {
            if (Math.abs(first[i].anchor0X - other[i].anchor0X) > 1e-6
                || Math.abs(first[i].anchor0Y - other[i].anchor0Y) > 1e-6)
                differences++;
        }
        verify(differences > 0);
    }

    function test_a_sequence_of_radii_is_not_mistaken_for_a_scalar() {
        const vertices = RoundedPolygon.RoundedPolygon.starVerticesPerLobe(4, 1, root.sequenceRadii, 0, 0);
        for (let lobe = 0; lobe < 4; lobe++)
            fuzzyCompare(radiusOf(vertices, lobe * 2 + 1), root.sequenceRadii[lobe], 1e-9);
    }

    // --- degenerate input --------------------------------------------------

    function test_fewer_radii_than_lobes_hold_the_last_one() {
        // Never undefined: a NaN vertex propagates into geometry QtQuick
        // relayout never converges on.
        const vertices = RoundedPolygon.RoundedPolygon.starVerticesPerLobe(6, 1, [0.5, 0.6], 0, 0);
        fuzzyCompare(radiusOf(vertices, 1), 0.5, 1e-9);
        fuzzyCompare(radiusOf(vertices, 3), 0.6, 1e-9);
        for (let lobe = 2; lobe < 6; lobe++)
            fuzzyCompare(radiusOf(vertices, lobe * 2 + 1), 0.6, 1e-9);
    }

    function test_no_radii_at_all_still_yields_finite_vertices() {
        const vertices = RoundedPolygon.RoundedPolygon.starVerticesPerLobe(6, 1, [], 0, 0);
        compare(vertices.length, 24);
        for (let i = 0; i < vertices.length; i++)
            verify(isFinite(vertices[i]));
    }
}
