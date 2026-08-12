.pragma library

// How a normalised rounded polygon is placed inside the item that draws it.
//
// This lived inline in `ShapeCanvas.onPaint`, which made it unreachable: a
// `Canvas` draws nothing under the software scene graph the tests run on, so
// the only part anyone could check was that the file parsed. It is arithmetic,
// so it belongs where arithmetic can be scored.
//
// Two placements:
//
// - **square** (the default, and what every existing caller wants): scale by
//   `min(width, height)` and centre. Right for a glyph, a button, a clock face
//   - anything as tall as it is wide.
// - **stretch**: fill the item. A card is 320x112, and under the square rule it
//   would draw a 112x112 shape floating in the middle of it, so a shape can
//   only be a card's outline if it may take the box it is given.
//
// `normalized` false means the polygon already carries pixel coordinates, so it
// is placed but never scaled - the centring still applies, which is what the
// original did and what its callers expect.
function fit(width, height, normalized, stretch) {
    const w = Number.isFinite(width) && width > 0 ? width : 0;
    const h = Number.isFinite(height) && height > 0 ? height : 0;
    const size = Math.min(w, h);

    if (!normalized)
        return { scaleX: 1, scaleY: 1, offsetX: w / 2 - size / 2, offsetY: h / 2 - size / 2 };
    if (stretch)
        return { scaleX: w, scaleY: h, offsetX: 0, offsetY: 0 };
    return { scaleX: size, scaleY: size, offsetX: w / 2 - size / 2, offsetY: h / 2 - size / 2 };
}

// Map a polygon point into pixels.
//
// The path is built in pixel space rather than drawn through `ctx.scale()`,
// because scaling the context scales the pen with it. The square case hid that:
// one `lineWidth / size` divide cancelled a uniform scale exactly. Stretching
// scales x and y differently and no single divide cancels that - a stroke would
// come out thicker on the short axis by the aspect ratio. Mapping the points
// leaves the pen in pixel space, so a border width means pixels at any aspect.
function mapX(value, placement) {
    return placement.offsetX + value * placement.scaleX;
}

function mapY(value, placement) {
    return placement.offsetY + value * placement.scaleY;
}
