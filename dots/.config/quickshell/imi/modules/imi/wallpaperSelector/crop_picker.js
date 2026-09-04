.pragma library

// The "fill" crop picker's geometry. A wallpaper whose content aspect differs
// from the screen's overflows on one axis under Fill (cover-crop): the picker
// draws the screen's viewport as a rectangle over the preview and a drag slides
// it along the overflowing axis, producing a focus fraction (0..1) the renderer
// applies live (WallpaperEngineSurface.focusX/focusY).
//
// contentAspect is the wallpaper's own w/h (approximated by the preview image
// here - the only image the shell has without running the scene); screenAspect
// is the output's. previewW/previewH are the preview's drawn box.

// The viewport rectangle over the preview, and which axis (if any) overflows.
// focusX (or focusY when vertical) is the crop position 0..1.
function viewport(contentAspect, screenAspect, previewW, previewH, focus) {
    var result = {
        x: 0, y: 0, width: previewW, height: previewH,
        overflowsX: false, overflowsY: false
    };
    if (!(contentAspect > 0) || !(screenAspect > 0) || previewW <= 0 || previewH <= 0)
        return result;
    if (contentAspect > screenAspect) {
        // Content wider than the screen: crop the sides. The viewport is full
        // height and a fraction of the width, sliding left-right.
        result.overflowsX = true;
        result.width = previewW * (screenAspect / contentAspect);
        result.height = previewH;
        result.x = (previewW - result.width) * clamp01(focus);
        result.y = 0;
    } else if (contentAspect < screenAspect) {
        // Content taller than the screen: crop top and bottom.
        result.overflowsY = true;
        result.width = previewW;
        result.height = previewH * (contentAspect / screenAspect);
        result.x = 0;
        result.y = (previewH - result.height) * clamp01(focus);
    }
    return result;
}

// The focus fraction a pointer at (px, py) on the preview produces: the
// viewport's CENTRE tracks the pointer, so the focus is the pointer's position
// within the slack (previewSize - viewportSize). The non-overflowing axis is
// pinned to centre.
function focusFromPointer(contentAspect, screenAspect, previewW, previewH, px, py) {
    var result = { x: 0.5, y: 0.5 };
    if (!(contentAspect > 0) || !(screenAspect > 0) || previewW <= 0 || previewH <= 0)
        return result;
    if (contentAspect > screenAspect) {
        var vw = previewW * (screenAspect / contentAspect);
        var slack = previewW - vw;
        result.x = slack > 0 ? clamp01((px - vw / 2) / slack) : 0.5;
    } else if (contentAspect < screenAspect) {
        var vh = previewH * (contentAspect / screenAspect);
        var slackY = previewH - vh;
        result.y = slackY > 0 ? clamp01((py - vh / 2) / slackY) : 0.5;
    }
    return result;
}

function clamp01(value) {
    if (typeof value !== "number" || isNaN(value)) return 0.5;
    return value < 0 ? 0 : (value > 1 ? 1 : value);
}
