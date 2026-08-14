.pragma library

.import "../../designsystem/widgets/shapes/rounded-polygon.js" as RoundedPolygon
.import "../../designsystem/widgets/shapes/corner-rounding.js" as CornerRounding
.import "../../designsystem/widgets/shapes/morph.js" as MorphLib
.import "../../designsystem/widgets/shapes/shape_morph.js" as ShapeMorph

// The play button's two selves, in ONE coordinate space, and the Morph
// between them.
//
// MaterialShapes' library shapes are normalized to the unit square, which is
// right for square glyphs and wrong for the 3x2 pill: stretched to 192x66 a
// normalized "pill" polygon is an ellipse, and that ellipse shipped (the
// review screenshot). A true capsule has straight sides and semicircular
// caps, and it cannot be produced by non-uniformly scaling anything square.
//
// So both endpoints are built RAW, centred on the origin, height 1:
//  - the capsule: a rectangle of the pill's own aspect with full corner
//    rounding, so its caps are semicircles at any width;
//  - the cookie: the 12-lobed star at circumradius 0.5, the same recipe as
//    material-shapes' cookie12 before its normalization.
// One Morph between them, built once. The drawer scales by the box height
// and clamps to the mid-flight bounds so nothing clips.

var PILL_ASPECT = 192 / 66;

var _capsule = null;
function capsule() {
    if (_capsule === null)
        _capsule = RoundedPolygon.RoundedPolygon.rectangle(
            PILL_ASPECT, 1, new CornerRounding.CornerRounding(0.5));
    return _capsule;
}

// ONE recipe for the cookie at rest and the cookie breathing: cookieRaw IS
// liveCookieRaw at zero levels. star() and starPerLobe() build not-quite-
// identical vertex paths, and having the rest shape come from one and the
// breathing shape from the other flickered a frame at every switchover -
// first at the settle threshold, then (after gating on breath) at the first
// audible lobe. Same constructor, same shape, nothing to flicker between.
var _cookieRaw = null;
function cookieRaw() {
    if (_cookieRaw === null)
        _cookieRaw = liveCookieRaw([], 12);
    return _cookieRaw;
}

var _bodyMorph = null;
function bodyMorph() {
    if (_bodyMorph === null)
        _bodyMorph = new MorphLib.Morph(capsule(), cookieRaw());
    return _bodyMorph;
}

// The cubics at progress t, with the bounds they actually occupy - the
// caller scales so the mid-flight shape fits its box instead of clipping.
function bodyAt(t) {
    var clamped = Math.max(0, Math.min(1, t));
    // Endpoint bounds are PINNED: the interpolated cubics' measured bounds
    // wobble by a hair around the endpoints, and a hair of scale at the
    // settle threshold reads as a flicker. Mid-flight they are measured,
    // because the capsule really is wider than the box it is travelling to.
    if (clamped >= 0.999)
        return ShapeMorph.pinned(bodyMorph().asCubics(1));
    return ShapeMorph.bounded(bodyMorph().asCubics(clamped));
}

// The seeker's ring endpoints: a perfect circle (2x2, inside the button) and
// the same raw cookie the body settles into (2x1, the button's outline).
var _ringMorph = null;
function ringMorph() {
    if (_ringMorph === null)
        _ringMorph = new MorphLib.Morph(
            RoundedPolygon.RoundedPolygon.circle(12, 0.5), cookieRaw());
    return _ringMorph;
}

function ringAt(t) {
    return ringMorph().asCubics(Math.max(0, Math.min(1, t)));
}

// The ring's cubics AND their arc-length measure, cached against t.
//
// path-length.js states the contract this exists to keep: "The cost is per
// geometry change, not per frame: a static shape pays it once, which is what
// makes a progress ring stroked around a cookie's outline cost nothing to
// animate." Both callers were rebuilding the Morph and re-measuring 24 cubics
// on every paint of a 240Hz frame clock, and again on every mouse move through
// the seeker's hit test - while `ringT` holds one of two values except during
// a 300ms span change.
//
// Pure in t, so this trades no correctness property: same input, same cubics,
// same lengths. One slot is enough - t moves monotonically through a
// transition and rests at an endpoint.
var _ringMeasureT = null;
var _ringMeasured = null;
function ringMeasuredAt(t, measureCubics) {
    var clamped = Math.max(0, Math.min(1, t));
    if (_ringMeasureT === clamped && _ringMeasured !== null) return _ringMeasured;
    var cubics = ringAt(clamped);
    _ringMeasureT = clamped;
    _ringMeasured = { cubics: cubics, measure: measureCubics(cubics) };
    return _ringMeasured;
}

// The live cookie: cookieRaw's own recipe with per-lobe inner radii, so the
// breathing shape and the resting shape are one family in one space. Levels
// are 0..1 per lobe; base and reach are the breathing cookie's tuning,
// halved into the height-1 space like everything else here.
function liveCookieRaw(levels, lobes) {
    var count = lobes || 12;
    var radii = [];
    for (var i = 0; i < count; i++) {
        var level = i < levels.length ? Math.max(0, Math.min(1, levels[i])) : 0;
        radii.push((0.8 + level * 0.14) * 0.5);
    }
    var cos30 = Math.cos(Math.PI / 6), sin30 = Math.sin(Math.PI / 6);
    return RoundedPolygon.RoundedPolygon.starPerLobe(
        count, 0.5, radii, new CornerRounding.CornerRounding(0.25))
        .transformed(function (x, y) {
            return { x: x * cos30 - y * sin30, y: x * sin30 + y * cos30 };
        });
}
