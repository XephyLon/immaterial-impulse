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

// How far each screen edge's occupied strip reaches in: the bar's edge is
// the bar's thickness, the other three are the band.
function edgeInsets(barEdge, barThickness, band) {
    var insets = { top: band, left: band, right: band, bottom: band };
    if (barEdge in insets) insets[barEdge] = barThickness;
    return insets;
}

// A fillet window's margins: it sits at the inner corner, where the two
// occupied strips meet.
function cornerMargins(corner, insets) {
    switch (corner) {
    case "topLeft": return { left: insets.left, top: insets.top, right: 0, bottom: 0 };
    case "topRight": return { left: 0, top: insets.top, right: insets.right, bottom: 0 };
    case "bottomLeft": return { left: insets.left, top: 0, right: 0, bottom: insets.bottom };
    case "bottomRight": return { left: 0, top: 0, right: insets.right, bottom: insets.bottom };
    default: return { left: 0, top: 0, right: 0, bottom: 0 };
    }
}
