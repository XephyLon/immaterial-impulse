.pragma library

.import "./shapes/material-shapes.js" as MaterialShapes
.import "./shapes/rounded-polygon.js" as RoundedPolygon
.import "./shapes/corner-rounding.js" as CornerRounding
.import "./shapes/morph.js" as MorphLib

// The currency container's two shapes in one centred height-1 space: the Bun
// badge at 1x1 and the full-height right panel at 2x1 - the weather glyph's
// pattern (weather_shapes.js), third adopter of "one component whose shape is
// a parameter". The panel is built AT its aspect so the corners stay
// circular. (Two hand-rolled copies of this pattern now exist; extraction is
// step 10's call, made with both in hand.)

var PANEL_ASPECT = 140 / 108;
var PANEL_ROUNDING = 30 / 108;

var _shapes = {};
function shapeOf(name) {
    if (_shapes[name] !== undefined) return _shapes[name];
    var polygon;
    if (name === "bun") {
        polygon = MaterialShapes.getBun()
            .transformed(function (x, y) { return { x: x - 0.5, y: y - 0.5 }; });
    } else {
        polygon = RoundedPolygon.RoundedPolygon.rectangle(
            PANEL_ASPECT, 1, new CornerRounding.CornerRounding(PANEL_ROUNDING));
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
