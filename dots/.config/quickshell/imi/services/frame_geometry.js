.pragma library

// Frame mode's arithmetic (docs/proposals/frame-mode.md, "a single geometry
// authority"): which edge is how thick, where each band starts and stops,
// and where the four inner fillets sit. Pure, so tests/tst_frame_geometry.qml
// can pin it; FrameGeometry.qml binds it to the config and the tokens.
//
// The frame has ONE occupant, the bar: its plate covers its strip edge to
// edge, so on the bar's edge the frame is the bar's zone plus the band under
// its plate. Every other edge is the band alone - the dock included. The
// dock is a pill in the middle of its strip, not a plate: modelling it as an
// occupant put a band above its zone (a line across the wallpaper with the
// dock floating under it), and then made the band its whole strip (a border
// as tall as the dock, mostly empty on both sides of the pill). Now the band
// stays thin and the dock meets it on the dock's own terms (dock_geometry.js
// `outwardMargin`): sitting on the band as a tab, or floating a gap above it.

// The band's thickness: the configured pixels, or the compositor's outer
// gap when 0 - the band then fills exactly the space windows already leave.
function bandThickness(configured, gapsOut) {
    var c = Number(configured) || 0;
    if (c > 0) return c;
    var g = Number(gapsOut) || 0;
    return g > 0 ? g : 0;
}

// How far the frame reaches in on each screen edge, i.e. where its inner
// corner is: the compositor reserves the bar's zone and THEN applies its
// outer gap, so the bar's edge is zone plus band (measured: modelling it as
// the painted height left a gap-wide wallpaper stripe under the bar); every
// other edge is the band. Not the dock's zone: the frame's inner corner on
// the dock's edge is where the band meets the inside, whatever hangs off
// the band there (a fillet placed at the dock's inset arced into wallpaper).
function edgeInsets(barEdge, barThickness, band) {
    var insets = { top: band, left: band, right: band, bottom: band };
    if (barEdge in insets) insets[barEdge] += Number(barThickness) || 0;
    return insets;
}

// The inner fillet's radius: the compositor's window rounding, full stop.
// The fillet's box already sits at the inset, so its arc is concentric
// with the window's corner only when the radii are equal; adding the band
// here (an earlier version did) drove the arc into the window.
function innerRadius(windowRounding) {
    return Math.max(0, (Number(windowRounding) || 0));
}

// Where a band starts on its OWN edge: under the bar's plate on the bar's
// edge, at the screen edge everywhere else.
function bandStart(edge, barEdge, barThickness) {
    return edge === barEdge ? (Number(barThickness) || 0) : 0;
}

// A band's four margins. The two horizontal bands span the screen's width;
// the two side bands run between them, from the top band's inner edge to
// the bottom band's - so no two bands overlap. Bands anchored the full
// screen length crossed at the corners, and the frame's colour is
// translucent: each crossing was a band-square painted twice, darker than
// the rest of the frame.
function bandMargins(edge, barEdge, barThickness, band) {
    var m = { top: 0, bottom: 0, left: 0, right: 0 };
    var b = Number(band) || 0;
    if (edge === "left" || edge === "right") {
        m.top = bandStart("top", barEdge, barThickness) + b;
        m.bottom = bandStart("bottom", barEdge, barThickness) + b;
    } else {
        m[edge] = bandStart(edge, barEdge, barThickness);
    }
    return m;
}

// A fillet's offset from its screen corner: it sits at the frame's inner
// corner, where the two edges' insets meet.
function cornerMargins(corner, insets) {
    switch (corner) {
    case "topLeft": return { left: insets.left, top: insets.top, right: 0, bottom: 0 };
    case "topRight": return { left: 0, top: insets.top, right: insets.right, bottom: 0 };
    case "bottomLeft": return { left: insets.left, top: 0, right: 0, bottom: insets.bottom };
    case "bottomRight": return { left: 0, top: 0, right: insets.right, bottom: insets.bottom };
    default: return { left: 0, top: 0, right: 0, bottom: 0 };
    }
}
