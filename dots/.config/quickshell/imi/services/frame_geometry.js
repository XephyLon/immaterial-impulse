.pragma library

// Frame mode's arithmetic (docs/proposals/frame-mode.md, "a single geometry
// authority"): which edge is how thick, and where the four inner fillets
// sit. Pure, so tests/tst_frame_geometry.qml can pin it; FrameGeometry.qml
// binds it to the config and the tokens.

// The band's thickness: the configured pixels, or the compositor's outer
// gap when 0 - the band then fills exactly the space windows already leave.
function bandThickness(configured, gapsOut) {
    var c = Number(configured) || 0;
    if (c > 0) return c;
    var g = Number(gapsOut) || 0;
    return g > 0 ? g : 0;
}

// How far each screen edge's occupied strip reaches in, i.e. where the
// windows start: the compositor reserves the bar's zone and THEN applies its
// outer gap, so the bar's edge is the zone plus the band (measured: modelling
// it as the bar's painted height left a gap-wide wallpaper stripe under the
// bar); the other three edges are the band alone. An edge the dock is
// pinned to reserves the dock's own zone, which this model does not know
// (the dock's pin is per-screen runtime state), so that edge is reported
// with a 0 inset: no band, no fillet - the dock stays its own island in
// stage 1 and the changelog says so.
function edgeInsets(barEdge, barThickness, band, dockEdge) {
    var insets = { top: band, left: band, right: band, bottom: band };
    if (barEdge in insets) insets[barEdge] = barThickness + band;
    if (dockEdge && dockEdge in insets && dockEdge !== barEdge) insets[dockEdge] = 0;
    return insets;
}

// The inner fillet's radius: concentric with the window corner it wraps,
// so the compositor's window rounding plus the band between them.
function innerRadius(windowRounding, band) {
    return Math.max(0, (Number(windowRounding) || 0)) + band;
}

// The band drawn on the bar's own edge sits under the bar plate: it starts
// where the bar's zone ends.
function bandOffset(edge, barEdge, barThickness) {
    return edge === barEdge ? barThickness : 0;
}

// A fillet's offset from its screen corner: it sits at the inner corner,
// where the two occupied strips meet. A corner touching an edge with a 0
// inset (a dock edge) has no frame to fillet and gets `draw: false`.
function cornerMargins(corner, insets) {
    var m;
    switch (corner) {
    case "topLeft": m = { left: insets.left, top: insets.top, right: 0, bottom: 0 }; break;
    case "topRight": m = { left: 0, top: insets.top, right: insets.right, bottom: 0 }; break;
    case "bottomLeft": m = { left: insets.left, top: 0, right: 0, bottom: insets.bottom }; break;
    case "bottomRight": m = { left: 0, top: 0, right: insets.right, bottom: insets.bottom }; break;
    default: return { left: 0, top: 0, right: 0, bottom: 0, draw: false };
    }
    m.draw = (m.left + m.right) > 0 && (m.top + m.bottom) > 0;
    return m;
}
