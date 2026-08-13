.pragma library

.import "./morph.js" as MorphLib

// The mechanics every morphing container shares: measured bounds, and a cache
// of the Morph objects between named shapes.
//
// Three copies of this existed by the time the third widget adopted the
// pattern (media's body, weather's glyph, currency's badge), and the two
// later ones were byte-identical apart from their shape tables - which is the
// evidence the spec asked for before extracting anything (§8: derive the
// framework from a working case, not from a guess).
//
// What stays with each widget is the only thing that actually differs: which
// polygons it has, and what it calls them. A widget passes a resolver -
// `name -> RoundedPolygon` - and gets back a container that morphs between
// them.

// The measured extent of a set of cubics. A morphing shape is drawn scaled to
// fit its box, so the caller needs the bounds the interpolation actually
// produced, not the ones its endpoints have.
function bounded(cubics) {
    var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (var i = 0; i < cubics.length; i++) {
        var c = cubics[i];
        var xs = [c.anchor0X, c.control0X, c.control1X, c.anchor1X];
        var ys = [c.anchor0Y, c.control0Y, c.control1Y, c.anchor1Y];
        for (var j = 0; j < 4; j++) {
            if (xs[j] < minX) minX = xs[j];
            if (xs[j] > maxX) maxX = xs[j];
            if (ys[j] < minY) minY = ys[j];
            if (ys[j] > maxY) maxY = ys[j];
        }
    }
    return { cubics: cubics, minX: minX, minY: minY, maxX: maxX, maxY: maxY };
}

// The same, with the extent PINNED rather than measured. The interpolated
// cubics' measured bounds wobble by a hair around the endpoints, and a hair of
// scale at a settle threshold reads as a flicker - the media body shipped that
// flicker and this is what fixed it.
function pinned(cubics, halfWidth, halfHeight) {
    var x = halfWidth === undefined ? 0.5 : halfWidth;
    var y = halfHeight === undefined ? 0.5 : halfHeight;
    return { cubics: cubics, minX: -x, minY: -y, maxX: x, maxY: y };
}

// A container over a widget's own shape table.
//
//   var container = ShapeMorph.container(function (name) { ... });
//   container.at("bun", "panel", t);
//
// Both caches live in the returned object, so two widgets never share a
// Morph keyed by names that mean different things in each.
function container(resolve) {
    var shapes = {};
    var morphs = {};

    function shapeOf(name) {
        if (shapes[name] === undefined) shapes[name] = resolve(name);
        return shapes[name];
    }

    // A Morph is rebuilt only when a PAIR is seen for the first time: building
    // one per frame is the shape of a stall, not of a morph.
    function at(fromName, toName, t) {
        var clamped = Math.max(0, Math.min(1, t));
        if (fromName === toName || clamped >= 0.999)
            return bounded(shapeOf(toName).cubics);
        var key = fromName + ">" + toName;
        if (morphs[key] === undefined)
            morphs[key] = new MorphLib.Morph(shapeOf(fromName), shapeOf(toName));
        return bounded(morphs[key].asCubics(clamped));
    }

    return { shapeOf: shapeOf, at: at };
}
