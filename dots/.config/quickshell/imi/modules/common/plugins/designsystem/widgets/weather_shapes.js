.pragma library

.import "./shapes/material-shapes.js" as MaterialShapes
.import "./shapes/rounded-polygon.js" as RoundedPolygon
.import "./shapes/corner-rounding.js" as CornerRounding
.import "./shapes/morph.js" as MorphLib

// The weather glyph container's three shapes, in ONE centred height-1 space,
// and the Morphs between them - the media body's pattern (media_shapes.js),
// applied to the element the morphing spec was written around (§3b: a
// Rectangle cannot morph into a MaterialShape; one component whose shape is a
// parameter can).
//
//  ghostish - the 3x1 floating shape, material-shapes' own, recentred.
//  panel    - the 2x1 right panel: aspect 76:108, r30, built AT aspect so the
//             corners stay circular (normalized-then-stretched corners are
//             the ellipse-pill lesson).
//  leaf     - the 1x1 slanted square, r16 at 50px. Rotation stays on the
//             item, not the polygon, so the icon can counter-rotate.

var PANEL_ASPECT = 76 / 108;
var PANEL_ROUNDING = 30 / 108;
var LEAF_ROUNDING = 16 / 50;

var _shapes = {};
function shapeOf(name) {
    if (_shapes[name] !== undefined) return _shapes[name];
    var polygon;
    if (name === "ghostish") {
        // normalized 0..1 -> centred -0.5..0.5
        polygon = MaterialShapes.getGhostish()
            .transformed(function (x, y) { return { x: x - 0.5, y: y - 0.5 }; });
    } else if (name === "panel") {
        polygon = RoundedPolygon.RoundedPolygon.rectangle(
            PANEL_ASPECT, 1, new CornerRounding.CornerRounding(PANEL_ROUNDING));
    } else {
        polygon = RoundedPolygon.RoundedPolygon.rectangle(
            1, 1, new CornerRounding.CornerRounding(LEAF_ROUNDING));
    }
    _shapes[name] = polygon;
    return polygon;
}

var _morphs = {};
function containerAt(fromName, toName, t) {
    var clamped = Math.max(0, Math.min(1, t));
    if (fromName === toName || clamped >= 0.999)
        return _bounded(shapeOf(toName).cubics);
    var key = fromName + ">" + toName;
    if (_morphs[key] === undefined)
        _morphs[key] = new MorphLib.Morph(shapeOf(fromName), shapeOf(toName));
    return _bounded(_morphs[key].asCubics(clamped));
}

function _bounded(cubics) {
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
