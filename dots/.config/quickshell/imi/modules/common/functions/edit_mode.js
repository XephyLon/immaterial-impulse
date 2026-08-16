.pragma library

// Edit Mode's two pieces of arithmetic, kept here because they are the only
// parts of the mode a test can reach: everything else about it is a layer
// surface, a transform and a pointer, and `qmltestrunner` can construct none of
// those.
//
// See docs/superpowers/specs/2026-08-16-edit-mode-design.md §8.2 (the ladder)
// and §1.2 (the inset).

// The tab the mode opens on. A string rather than a boolean because the
// Lockscreen tab joins it later (spec §1.4) and the ladder already has to say
// which tab it returns to.
var DESKTOP_TAB = "desktop";

// Escape is overloaded on the desktop before Edit Mode exists: WidgetCanvas
// clears a marquee selection with it and PluginWidget cancels a grip resize
// with it. So the mode may not simply take the key - it resolves in order and
// the first match wins, which is what keeps both of those working while the
// mode is on.
//
// A pure function of three inputs, so the precedence is checkable without a
// canvas, a widget or a compositor. The caller does the work each answer names.
function resolveEscape(state) {
    const s = state || {};
    if (s.gestureInFlight)
        return "cancelGesture";
    if ((s.selectionCount || 0) > 0)
        return "clearSelection";
    if ((s.tab || DESKTOP_TAB) !== DESKTOP_TAB)
        return "desktopTab";
    return "exit";
}

// A desktop scaled below this is not an editor any more, it is a thumbnail.
// Only reachable on a screen too narrow to host the drawer at all, where the
// alternative answers are a zero or a negative scale.
var MIN_SCALE = 0.2;

// The viewport's inset is DERIVED, not chosen: the desktop shrinks by exactly
// what the drawer will need, so the drawer opens into space that already
// exists rather than covering the desktop or resizing it (spec §1.2, §1.3).
//
// `drawerWidth` is passed whether or not the drawer is open, and this function
// has no input for the open state on purpose. A desktop that was full width
// with the drawer closed would be RESIZED by opening it, and a viewport that
// changes size mid-edit rescales every widget under the cursor: a drag in
// flight finds its target a different size than when it was grabbed, and every
// Behavior carrying the box is handed a moving target, which per b710ef731
// ("fix(plugins): stop the position Behavior swallowing the parallax
// cancellation") means it restarts every frame and never ticks. Opening the
// drawer translates the desktop instead, which is stage 5's `x` offset on top
// of the `x` this returns.
//
// `margin` is one token: the desktop is inset by it on the left, on the top and
// on the bottom, and the space reserved on the right is the drawer's own width
// plus one more of it - the gap between the desktop and the drawer. What the
// drawer does inside that slot is stage 5's business; the desktop's geometry
// does not depend on it.
function viewportGeometry(input) {
    const screenWidth = (input && input.screenWidth) || 0;
    const screenHeight = (input && input.screenHeight) || 0;
    const drawerWidth = (input && input.drawerWidth) || 0;
    const margin = (input && input.margin) || 0;
    if (screenWidth <= 0 || screenHeight <= 0)
        return { scale: 1, x: 0, y: 0, width: screenWidth, height: screenHeight };

    // Two margins horizontally (outside the desktop, and between the desktop
    // and the drawer) and two vertically, so the desktop is inset by the same
    // amount on every side it does not share with the drawer.
    const roomX = screenWidth - drawerWidth - margin * 2;
    const roomY = screenHeight - margin * 2;
    const scale = Math.max(MIN_SCALE,
        Math.min(1, roomX / screenWidth, roomY / screenHeight));

    return {
        scale: scale,
        // The left margin is fixed; whatever slack the other axis leaves
        // accumulates on the right, which is the side the drawer is on.
        x: margin,
        y: (screenHeight - screenHeight * scale) / 2,
        width: screenWidth * scale,
        height: screenHeight * scale
    };
}

// The entry and exit animation, expressed as one scalar the shell can put a
// single `Behavior` on. Interpolating the geometry rather than animating three
// properties separately is what keeps the desktop's corner travelling in a
// straight line, and it means the transform's inputs move together or not at
// all - there is no frame in which the scale has arrived and the offset has
// not.
function atProgress(geometry, progress) {
    const t = Math.max(0, Math.min(1, progress || 0));
    return {
        scale: 1 + (geometry.scale - 1) * t,
        x: geometry.x * t,
        y: geometry.y * t
    };
}
