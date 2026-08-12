.pragma library

.import "../../designsystem/widgets/shapes/rounded-polygon.js" as RoundedPolygon
.import "../../designsystem/widgets/shapes/corner-rounding.js" as CornerRounding
.import "../../designsystem/widgets/shapes/morph.js" as MorphLib

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

var _cookieRaw = null;
function cookieRaw() {
    if (_cookieRaw === null) {
        // material-shapes' cookie12 exactly, in the height-1 space: star(12,
        // r, 0.8r, rounding) rotated 30 degrees. CornerRounding is an
        // ABSOLUTE distance, so at half the radius the rounding halves too -
        // the first version kept 0.4 at radius 0.5, effectively double the
        // real cookie's rounding, and the lobes came out as shallow scallops
        // that matched nothing else on the widget (the review screenshot).
        var cos30 = Math.cos(Math.PI / 6), sin30 = Math.sin(Math.PI / 6);
        _cookieRaw = RoundedPolygon.RoundedPolygon.star(
            12, 0.5, 0.5 * 0.8, new CornerRounding.CornerRounding(0.25))
            .transformed(function (x, y) {
                return { x: x * cos30 - y * sin30, y: x * sin30 + y * cos30 };
            });
    }
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
    var cubics = bodyMorph().asCubics(Math.max(0, Math.min(1, t)));
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
