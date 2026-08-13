.pragma library

.import "./shapes/material-shapes.js" as MaterialShapes
.import "./shapes/rounded-polygon.js" as RoundedPolygon
.import "./shapes/corner-rounding.js" as CornerRounding
.import "./shapes/shape_morph.js" as ShapeMorph

// The currency container's two shapes in one centred height-1 space: the Bun
// badge at 1x1 and the full-height right panel at 2x1. The panel is built AT
// its aspect so the corners stay circular. The morph mechanics are shared
// (shape_morph.js) - this file is the shape table and nothing else.

var PANEL_ASPECT = 140 / 108;
var PANEL_ROUNDING = 30 / 108;

var _container = ShapeMorph.container(function (name) {
    if (name === "bun") {
        return MaterialShapes.getBun()
            .transformed(function (x, y) { return { x: x - 0.5, y: y - 0.5 }; });
    }
    return RoundedPolygon.RoundedPolygon.rectangle(
        PANEL_ASPECT, 1, new CornerRounding.CornerRounding(PANEL_ROUNDING));
});

function shapeOf(name) { return _container.shapeOf(name); }
function containerAt(fromName, toName, t) { return _container.at(fromName, toName, t); }
