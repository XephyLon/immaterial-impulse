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

// ...and a desktop scaled ABOVE this is not an object on the screen either: it
// is the screen with four thin strips of blur around it.
//
// The drawer-derived inset below is the right answer while the drawer is a
// meaningful fraction of the width, and it stops being one as the screen
// widens - 380px of drawer plus two 24px margins on a 5120px monitor leaves the
// desktop at 92%, which spends the whole mode signal on a border. The shrink IS
// the signal (spec §1.1: there is no scrim), so it has to be legible at every
// screen size and not only at the one where the arithmetic happens to bite.
//
// A ceiling rather than a second inset, because a ceiling cannot break the
// derivation stage 5 plugs into: the space reserved on the right of the desktop
// is `screenWidth - margin - width`, which the drawer term already holds at or
// above `drawerWidth + margin`, and lowering the scale further can only make it
// larger. So the drawer still opens into space that already exists, and on a
// screen where it is the tighter constraint it still decides.
var MAX_SCALE = 0.86;

// The SIZE is derived, not chosen: the desktop shrinks by at least what the
// drawer will need, so the drawer opens into space that already exists rather
// than covering the desktop or resizing it (spec §1.2, §1.3).
//
// The POSITION is dead centre, and the two are deliberately separate. Entering
// the mode is a concentric shrink - the desktop gets smaller where it is, and
// nothing slides - because reserving the drawer's width inside the resting
// geometry makes the entry asymmetric from its first frame: the desktop drifts
// toward one edge on the way in, which reads as being shoved aside rather than
// lifted off the wallpaper, and it does it whether or not a drawer exists yet.
// The drawer's width is still what decides how far the desktop moves when the
// drawer OPENS; that is a translation applied at that point, in stage 5, on top
// of the `x` this returns.
//
// The arithmetic that lets those two coexist: a centred desktop has
// `(screenWidth - width) / 2` free on each side, and the scale below holds
// `width <= screenWidth - drawerWidth - 2 * margin`, so each side has at least
// `drawerWidth / 2 + margin`. Opening a drawer of `drawerWidth + margin` on the
// right therefore needs the desktop to travel at most `drawerWidth / 2` left,
// which leaves exactly `margin` on its other side. The reservation is real; it
// is just spent when the drawer arrives instead of being held back from the
// start.
//
// `drawerWidth` is passed whether or not the drawer is open, and this function
// has no input for the open state on purpose. A desktop that was full width
// with the drawer closed would be RESIZED by opening it, and a viewport that
// changes size mid-edit rescales every widget under the cursor: a drag in
// flight finds its target a different size than when it was grabbed, and every
// Behavior carrying the box is handed a moving target, which per b710ef731
// ("fix(plugins): stop the position Behavior swallowing the parallax
// cancellation") means it restarts every frame and never ticks.
//
// `margin` is one token: the gap between the desktop and the screen's edge, and
// the gap between the desktop and the drawer's slot once there is a drawer.
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
        Math.min(MAX_SCALE, roomX / screenWidth, roomY / screenHeight));
    const width = screenWidth * scale;
    const height = screenHeight * scale;

    return {
        scale: scale,
        // Centred on both axes, which is what makes `atProgress` a concentric
        // shrink rather than a slide: the offset is linear in the scale, so
        // `x * t` is exactly the centring offset of the intermediate scale and
        // the four margins stay equal in pairs on every frame of the entry.
        x: (screenWidth - width) / 2,
        y: (screenHeight - height) / 2,
        width: width,
        height: height
    };
}

// The entry and exit animation, expressed as one scalar the shell can put a
// single `Behavior` on. Interpolating the geometry rather than animating three
// properties separately is what keeps the desktop's corner travelling in a
// straight line, and it means the transform's inputs move together or not at
// all - there is no frame in which the scale has arrived and the offset has
// not.
//
// The offset is scaled by the SAME t as the scale, and that is what makes the
// shrink concentric rather than merely centred at the end: a centred geometry's
// `x` is `screenWidth * (1 - scale) / 2`, which is linear in `(1 - scale)`, so
// `x * t` is the exact centring offset for the intermediate scale
// `1 + (scale - 1) * t`. The desktop's four margins are therefore equal in
// pairs at every point of the animation and not only at rest.
function atProgress(geometry, progress) {
    const t = Math.max(0, Math.min(1, progress || 0));
    return {
        scale: 1 + (geometry.scale - 1) * t,
        x: geometry.x * t,
        y: geometry.y * t
    };
}

// Where the desktop is ON SCREEN at a given progress - the rectangle the mode's
// chrome frames.
//
// It comes from the same `atProgress` the transform is built out of rather than
// from the transform's own terms, so the card's corner, its border and its
// shadow cannot end up a pixel off the desktop they belong to. That is the same
// rule ClockDepthCutout is one component for: two hand-written copies of a
// registration drift, and the drift is invisible because both look plausible.
//
// At progress 0 this is the whole screen at 0,0, which is what makes "the
// chrome stands down completely on exit" a property of the arithmetic rather
// than of a `visible` binding someone has to remember.
function cardRect(geometry, progress, screenWidth, screenHeight) {
    const applied = atProgress(geometry, progress);
    return {
        x: applied.x,
        y: applied.y,
        width: screenWidth * applied.scale,
        height: screenHeight * applied.scale
    };
}
