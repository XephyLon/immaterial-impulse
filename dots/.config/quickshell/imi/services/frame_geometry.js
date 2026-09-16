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
// windows start: the compositor reserves each occupant's zone and THEN
// applies its outer gap, so an occupied edge is its zone(s) plus the band
// (measured: modelling the bar's edge as the painted height left a
// gap-wide wallpaper stripe under the bar); a free edge is the band alone.
// Occupants: the bar (barThickness on barEdge) and a pinned dock
// (dockThickness on dockEdge); both on one edge add up.
function edgeInsets(barEdge, barThickness, band, dockEdge, dockThickness) {
    var insets = { top: band, left: band, right: band, bottom: band };
    if (barEdge in insets) insets[barEdge] += barThickness;
    if (dockEdge && dockEdge in insets) insets[dockEdge] += Number(dockThickness) || 0;
    return insets;
}

// The inner fillet's radius: the compositor's window rounding, full stop.
// The fillet's box already sits at the inset, so its arc is concentric
// with the window's corner only when the radii are equal; adding the band
// here (an earlier version did) drove the arc into the window.
function innerRadius(windowRounding) {
    return Math.max(0, (Number(windowRounding) || 0));
}

// Where the band drawn on an edge starts: under the occupant(s) of that
// edge, i.e. after their zone(s).
function bandOffset(edge, barEdge, barThickness, dockEdge, dockThickness) {
    var offset = 0;
    if (edge === barEdge) offset += barThickness;
    if (dockEdge && edge === dockEdge) offset += Number(dockThickness) || 0;
    return offset;
}

// A band's four margins: on its own edge it starts under that edge's
// occupant(s); at its two ENDS it stops where the adjacent edges' bands
// start, so every band ends at the frame's corner instead of running the
// full screen length (measured: side bands anchored top+bottom dropped two
// band-wide tails through a pinned dock's strip to the screen edge).
// Where a band starts on its OWN edge: under the bar's plate, which covers
// its strip edge to edge - never above a pinned dock's zone. The dock is a
// pill in the middle of its strip, not a plate: a band placed above its zone
// read as a stray line across the wallpaper with the dock floating under it.
// On the dock's edge the band is the whole strip instead (bandExtent), and
// the dock is drawn over it, so the strip reads as frame like the bar's does.
function bandStart(edge, barEdge, barThickness) {
    return edge === barEdge ? barThickness : 0;
}

function bandExtent(edge, band, dockEdge, dockThickness) {
    return band + (dockEdge && edge === dockEdge ? (Number(dockThickness) || 0) : 0);
}

function bandMargins(edge, barEdge, barThickness, dockEdge, dockThickness) {
    var m = { top: 0, bottom: 0, left: 0, right: 0 };
    var ends = (edge === "left" || edge === "right") ? ["top", "bottom"] : ["left", "right"];
    m[edge] = bandStart(edge, barEdge, barThickness);
    for (var i = 0; i < ends.length; i++)
        m[ends[i]] = bandOffset(ends[i], barEdge, barThickness, dockEdge, dockThickness);
    return m;
}

// A fillet's offset from its screen corner: it sits at the inner corner,
// where the two occupied strips meet.
function cornerMargins(corner, insets) {
    switch (corner) {
    case "topLeft": return { left: insets.left, top: insets.top, right: 0, bottom: 0 };
    case "topRight": return { left: 0, top: insets.top, right: insets.right, bottom: 0 };
    case "bottomLeft": return { left: insets.left, top: 0, right: 0, bottom: insets.bottom };
    case "bottomRight": return { left: 0, top: 0, right: insets.right, bottom: insets.bottom };
    default: return { left: 0, top: 0, right: 0, bottom: 0 };
    }
}
