import QtTest
import "../modules/common/plugins/designsystem/widgets/shapes/shape_morph.js" as ShapeMorph
import "../modules/common/plugins/designsystem/widgets/shapes/rounded-polygon.js" as RoundedPolygon
import "../modules/common/plugins/designsystem/widgets/shapes/corner-rounding.js" as CornerRounding

// The mechanics three morphing containers share, tested once instead of not
// at all: bounds, the endpoint short-circuit, and the Morph cache.
TestCase {
    name: "ShapeMorphTest"

    function make(name) {
        if (name === "wide")
            return RoundedPolygon.RoundedPolygon.rectangle(2, 1, new CornerRounding.CornerRounding(0.1));
        if (name === "tall")
            return RoundedPolygon.RoundedPolygon.rectangle(1, 2, new CornerRounding.CornerRounding(0.1));
        return RoundedPolygon.RoundedPolygon.rectangle(1, 1, new CornerRounding.CornerRounding(0.1));
    }

    function test_bounds_are_measured_from_the_cubics() {
        const container = ShapeMorph.container(make);
        const wide = container.at("wide", "wide", 1);
        const tall = container.at("tall", "tall", 1);
        verify(wide.maxX - wide.minX > wide.maxY - wide.minY, "wide is wider");
        verify(tall.maxY - tall.minY > tall.maxX - tall.minX, "tall is taller");
    }

    function test_a_morph_travels_between_its_endpoints() {
        const container = ShapeMorph.container(make);
        const mid = container.at("wide", "tall", 0.5);
        const wide = container.at("wide", "wide", 1);
        const tall = container.at("tall", "tall", 1);
        const w = s => s.maxX - s.minX;
        verify((w(mid) - w(wide)) * (w(mid) - w(tall)) < 0,
               "the mid-flight width lies between the two ends");
    }

    function test_t_is_clamped_and_the_endpoint_short_circuits() {
        const container = ShapeMorph.container(make);
        const past = container.at("wide", "tall", 4.0);
        const at1 = container.at("tall", "tall", 1);
        compare(past.cubics.length, at1.cubics.length);
        fuzzyCompare(past.maxX - past.minX, at1.maxX - at1.minX, 0.001);
        const before = container.at("wide", "tall", -3.0);
        const wide = container.at("wide", "wide", 1);
        fuzzyCompare(before.maxX - before.minX, wide.maxX - wide.minX, 0.05);
    }

    function test_each_container_keeps_its_own_caches() {
        // Two widgets can both call a shape "panel" and mean different
        // polygons; a shared cache keyed on the name would hand one widget
        // the other's shape.
        let firstCalls = 0, secondCalls = 0;
        const first = ShapeMorph.container(name => { firstCalls++; return make("wide"); });
        const second = ShapeMorph.container(name => { secondCalls++; return make("tall"); });
        first.at("panel", "panel", 1);
        second.at("panel", "panel", 1);
        const a = first.at("panel", "panel", 1);
        const b = second.at("panel", "panel", 1);
        compare(firstCalls, 1, "resolved once, then cached");
        compare(secondCalls, 1);
        verify(a.maxX - a.minX > b.maxX - b.minX, "and they are not the same shape");
    }

    function test_pinned_bounds_ignore_the_measured_wobble() {
        const container = ShapeMorph.container(make);
        const measured = container.at("wide", "wide", 1);
        const pinnedShape = ShapeMorph.pinned(measured.cubics);
        compare(pinnedShape.minX, -0.5);
        compare(pinnedShape.maxY, 0.5);
        compare(pinnedShape.cubics, measured.cubics);
    }
}
