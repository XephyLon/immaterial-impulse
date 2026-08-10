.pragma library

// Wallpaper parallax maths.
//
// The whole effect is one idea: draw the wallpaper larger than the screen, then
// choose which part of that overflow is visible. Everything here works in
// fractions of the overflow - 0 is the left/top edge of the picture, 1 the
// right/bottom edge, 0.5 dead centre - and only the last step turns them into
// pixels. Background.qml feeds live state in and applies the result; it makes
// no positioning decisions of its own, which is what lets this be tested
// without a compositor.
//
// Nothing here may return NaN. Background.qml binds these straight to x/y, and
// a NaN there does not misplace the wallpaper, it stops the item rendering
// entirely - so every input is defaulted rather than trusted.

const CENTRE = 0.5;

function clamp01(value) {
    if (!isFinite(value)) return CENTRE;
    return Math.max(0, Math.min(1, value));
}

function number(value, fallback) {
    return (typeof value === "number" && isFinite(value)) ? value : fallback;
}

// Where this workspace sits along the pan, 0..1.
//
// Divided by (total - 1) rather than by total: the pan runs between the first
// and last workspace, so the last one reaches the far edge of the picture
// instead of stopping one step short. One workspace has nowhere to pan and
// stays centred - which is also the divide-by-zero guard.
function workspaceFraction(workspaceIndex, totalWorkspaces) {
    const total = number(totalWorkspaces, 1);
    if (total <= 1) return CENTRE;
    return clamp01(number(workspaceIndex, 0) / (total - 1));
}

// Fractions for both axes, given the full parallax state.
//
// Sidebars always act on X even in vertical mode: they are horizontal surfaces
// sliding in from the left and right edges whichever way the workspaces pan, so
// moving the wallpaper vertically for them would not read as the same effect.
function fractions(state) {
    state = state || {};
    const vertical = !!state.vertical;
    const workspace = state.enableWorkspace === false
        ? CENTRE
        : workspaceFraction(state.workspaceIndex, state.totalWorkspaces);

    let x = vertical ? CENTRE : workspace;
    let y = vertical ? workspace : CENTRE;

    if (state.enableSidebar !== false) {
        const nudge = number(state.sidebarFraction, 0);
        if (state.sidebarRightOpen) x += nudge;
        if (state.sidebarLeftOpen) x -= nudge;
    }

    return { x: clamp01(x), y: clamp01(y) };
}

// Fractions turned into the pixel offsets the wallpaper container is placed at.
//
// Negative: the container is bigger than the screen and slides underneath it,
// so showing the right-hand end of the picture means moving the container left.
function offsets(state) {
    state = state || {};
    const f = fractions(state);
    const overflowX = Math.max(0, number(state.overflowX, 0));
    const overflowY = Math.max(0, number(state.overflowY, 0));
    return {
        x: -overflowX * f.x,
        y: -overflowY * f.y
    };
}

// How far the desktop widgets travel for a given wallpaper offset.
//
// A factor above 1 moves the widgets further than the wallpaper, which is what
// reads as depth; equal factors would glue them to the picture and the effect
// disappears. Kept as its own function because the widget layer is a sibling of
// the wallpaper container, not a child, so it cannot inherit the offset.
function widgetOffset(wallpaperOffset, factor) {
    return number(wallpaperOffset, 0) * number(factor, 0);
}

// The same travel, measured from the centre rather than from the edge.
//
// `offsets()` is written for the wallpaper container, which is genuinely larger
// than the screen: parking an axis at CENTRE shows the middle of the picture,
// which is what you want. The widget canvas is *screen-sized*, so the identical
// arithmetic means something else entirely - half the overflow of static shift,
// pushing the canvas off the screen and taking that strip of desktop with it.
//
// It is worst on the axis that does not travel at all. `vertical: false` sends
// workspace movement to x and parks y at CENTRE, so with the shipped 107% zoom
// and 1.2 factor a 1440-tall screen loses its bottom 60px permanently, to buy
// motion that never happens.
//
// Subtracting CENTRE makes the resting position 0 on both axes: the canvas
// covers the screen exactly when nothing is panned, and swings symmetrically
// either side of that when something is. A parked axis contributes nothing.
function widgetOffsets(state, factor) {
    state = state || {};
    const f = fractions(state);
    const scale = number(factor, 0);
    const overflowX = Math.max(0, number(state.overflowX, 0));
    const overflowY = Math.max(0, number(state.overflowY, 0));
    return {
        x: -overflowX * (f.x - CENTRE) * scale,
        y: -overflowY * (f.y - CENTRE) * scale
    };
}

// Where a desktop widget's frost has to sample the wallpaper.
//
// Three items, three positions. The wallpaper sits in a container larger than
// the screen, placed at `wallpaperOffset` (offsets()); the widget canvas is a
// screen-sized SIBLING of that container, placed at `canvasOffset`
// (widgetOffsets()); a widget's own x/y are measured inside the canvas. So a
// widget's screen position is canvasOffset + widgetPos, and the wallpaper pixel
// under it is that, measured from where the wallpaper container starts.
//
// Both terms are needed and neither cancels the other: the canvas travels at
// `widgetsFactor` and the wallpaper at 1 - that difference IS the parallax, so
// they are never the same number except at rest.
function sampleOrigin(canvasOffset, widgetPos, wallpaperOffset) {
    canvasOffset = canvasOffset || {};
    widgetPos = widgetPos || {};
    wallpaperOffset = wallpaperOffset || {};
    return {
        x: number(canvasOffset.x, 0) + number(widgetPos.x, 0) - number(wallpaperOffset.x, 0),
        y: number(canvasOffset.y, 0) + number(widgetPos.y, 0) - number(wallpaperOffset.y, 0)
    };
}

// What a single widget adds to its own placement to opt OUT of the pan.
//
// This is not the same kind of quantity as widgetOffset above, and the
// difference is the whole reason it needs a function: the widget canvas is one
// item whose x/y ARE the pan, so a widget cannot decline to travel by being
// given a smaller offset - it is already moving because its parent is. It has
// to cancel the canvas's offset instead, and the two summing to zero is what
// leaves it at the same place on screen while its neighbours slide.
//
// Following is the default, so anything other than an explicit `false` follows:
// a widget whose flag has not loaded yet must move with the rest rather than
// pinning itself against a canvas offset it has not seen.
function parallaxCancel(canvasOffset, follows) {
    if (follows === false) return -number(canvasOffset, 0);
    return 0;
}

// A desktop widget has two positions, and this is the only conversion between
// them. Both directions live here so they cannot drift apart.
//
// PluginState stores a widget's PLACEMENT: where it sits when the pan is at
// rest. That is one meaning for every widget, whatever its `followParallax`
// says - a following widget's canvas coordinate is already pan-invariant, and
// an opted-out widget's screen coordinate is the same number, because at rest
// the canvas covers the screen exactly (widgetOffsets subtracts CENTRE). So
// the clamp to [0, screenSize - widgetSize] is valid for both, and toggling
// the flag never has to rewrite a stored position.
//
// What the flag changes is where the widget is DRAWN on the canvas, which is
// the placement plus the cancellation. Anything that reads a widget's `x` is
// reading the drawn coordinate; anything that writes the store converts back.
function drawnFromPlacement(placement, cancel) {
    return number(placement, 0) + number(cancel, 0);
}

function placementFromDrawn(drawn, cancel) {
    return number(drawn, 0) - number(cancel, 0);
}
