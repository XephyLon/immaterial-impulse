.pragma library

.import "./shapes/material-shapes.js" as MaterialShapes
.import "./shapes/rounded-polygon.js" as RoundedPolygon
.import "./shapes/corner-rounding.js" as CornerRounding
.import "./shapes/shape_morph.js" as ShapeMorph

// The weather glyph container's three shapes, in ONE centred height-1 space.
// The morphing mechanics - bounds, the Morph cache - are shape_morph.js now,
// shared with the media body and the currency badge; what stays here is the
// only thing that differs between them: which polygons this container has.
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

var _container = ShapeMorph.container(function (name) {
    if (name === "ghostish") {
        // normalized 0..1 -> centred -0.5..0.5
        return MaterialShapes.getGhostish()
            .transformed(function (x, y) { return { x: x - 0.5, y: y - 0.5 }; });
    }
    if (name === "panel") {
        return RoundedPolygon.RoundedPolygon.rectangle(
            PANEL_ASPECT, 1, new CornerRounding.CornerRounding(PANEL_ROUNDING));
    }
    return RoundedPolygon.RoundedPolygon.rectangle(
        1, 1, new CornerRounding.CornerRounding(LEAF_ROUNDING));
});

function shapeOf(name) { return _container.shapeOf(name); }
function containerAt(fromName, toName, t) { return _container.at(fromName, toName, t); }
