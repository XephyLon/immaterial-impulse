.pragma library

// Clock depth mode: when the wallpaper's subject may be drawn back over the
// desktop widgets, and where its mask has to land to line up with the picture.
//
// Both answers are here rather than in Background.qml for the same reason the
// parallax maths is: nothing about the rendered layer is reachable from a test -
// qmltestrunner cannot construct Quickshell types and the software scene graph
// draws no layer effect - so the decisions have to live somewhere a test can
// call them, and the file that draws them makes none of its own.

// Should the depth layer be showing?
//
// Expressed as a predicate over inherently-observable state rather than as a
// chain of guards in a binding, because the refusals are the interesting half:
// each of them is a wallpaper the shell does not own the pixels of, does not
// have a file for, or is in the middle of replacing.
//
// The caller turns a false into an OPACITY, not into a `visible`. A wallpaper
// switch is a refusal that lasts 1.2s and has to fade rather than blink, and a
// predicate that has to know the difference is a predicate with a rendering
// opinion.
function eligible(state) {
    const s = state || {};
    // The global switch. A feature that puts pixels over the clock ships off.
    if (!s.enable) return false;
    // The per-wallpaper opt-out. Checked before the mask, so a declined mask
    // left on disk beside its marker cannot come back.
    if (s.optedOut) return false;
    // The desktop selector is drawing the CANDIDATE at full size over these
    // same widgets. The accepted mask underneath it would be a second
    // silhouette arguing with the one being judged, and where the two disagree
    // the difference reads as the candidate having claimed something it did
    // not - which is a verdict given against the wrong picture.
    if (s.selecting) return false;
    // Edit Mode, for that same reason and one more. This layer paints the
    // wallpaper's subject back OVER the desktop widgets, which is the effect at
    // rest and is a partly hidden widget in the mode that exists to let the user
    // place it. The one more: the layer reconstructs the parallax viewport,
    // which is deliberately larger than the screen (workspaceZoom), and only the
    // layer surface's own edge keeps that overscan off screen. The mode's
    // transform pulls the desktop's edge away from the surface's and puts the
    // blurred backdrop in between, so at 1.07 zoom on a 5120px screen a subject
    // reaching the picture's edge would paint up to 154px past the card, on the
    // one part of the screen that is supposed to be what is OUTSIDE the desktop.
    if (s.editing) return false;
    if (!s.maskPath) return false;
    // A live Wallpaper Engine project is a moving surface with no file to
    // segment, and a mask of the frozen greeter still would be a stale
    // silhouette over animated content.
    if (s.weActive) return false;
    // mpvpaper is a separate Wayland client on its own layer surface. The shell
    // does not own those pixels and parallaxViewport does not move them, so a
    // cutout built from the ffmpeg first frame would be a still ghost of frame 1
    // hovering over a playing video.
    if (s.wallpaperIsVideo) return false;
    // Centred mode draws the wallpaper into a shape at its own size, which is a
    // completely different geometry from the viewport this layer is bound to.
    if (s.centeredWallpaper) return false;
    // The lock screen is its own image with its own peel machine and its own
    // clock placement - a second feature, not a special case of this one. Until
    // it exists, the desktop's subject must not appear over the lock wallpaper.
    if (s.screenLocked) return false;
    // For the length of a switch the viewport shows a shader blend of two
    // images, and a hard cutout of an image that is 30% faded in reads as a
    // sticker. The clock is briefly flat, during 1.2s in which the whole
    // wallpaper is visibly changing anyway.
    if (s.transitionInFlight) return false;
    return true;
}

// Where the mask has to be drawn so it lines up with the wallpaper under it.
//
// The mask is the model's own output: the whole picture squashed to a square,
// which is what the feasibility work rendered and judged by eye, so it is what
// the user accepts. That means it is NOT the wallpaper's aspect, and a mask
// simply filled into the same box as the wallpaper would be stretched
// differently from the image it masks - by 3.5x on this monitor.
//
// The wallpaper is drawn PreserveAspectCrop: scaled by whichever axis needs the
// most, centred, and clipped by the box. So the mask, stretched, has to cover
// exactly the rectangle the whole wallpaper would occupy if nothing clipped it.
// Undoing the squash and re-applying the crop is the same operation.
//
// Returns a rect in the box's own coordinates; x and y are usually negative,
// because most of the point is that the picture is bigger than the box.
function coverRect(sourceWidth, sourceHeight, boxWidth, boxHeight) {
    const sw = positive(sourceWidth);
    const sh = positive(sourceHeight);
    const bw = positive(boxWidth);
    const bh = positive(boxHeight);
    // Nothing here may return NaN or a zero size: the result goes straight onto
    // an item's x/y/width/height, where a NaN does not misplace the mask, it
    // stops the item rendering - which is indistinguishable from a wallpaper
    // that has no mask.
    if (sw === 0 || sh === 0 || bw === 0 || bh === 0)
        return { x: 0, y: 0, width: bw, height: bh };
    const scale = Math.max(bw / sw, bh / sh);
    const width = sw * scale;
    const height = sh * scale;
    return { x: (bw - width) / 2, y: (bh - height) / 2, width: width, height: height };
}

// A click on a preview, as a point in the picture's own frame.
//
// The inverse of what `coverRect` returns, and it takes that rectangle rather
// than recomputing one: the mask surface is where the whole wallpaper sits
// inside the preview box, so a click's fraction ALONG that rectangle is the same
// fraction of the picture whatever the preview's size or the monitor's aspect.
// Anything that worked the crop out again here would be a second registration,
// which is what ClockDepthCutout exists to prevent.
//
// Kept here rather than inline in the handler because it is the one part of the
// gesture a test can reach - nothing about a rendered preview is reachable from
// qmltestrunner - and because a click sent to the wrong part of the picture
// produces a perfectly good mask of the wrong thing, with nothing to show that
// anything went wrong.
//
// Clamped, not rejected: the producer refuses a point outside the picture, and a
// rounding error at the very edge of a frame would come back to the user as an
// error about a click that looked entirely ordinary. Returns null only for a
// rect with no area, where there is no picture to have clicked on.
function normalisedPoint(rect, x, y) {
    const r = rect || {};
    const width = positive(r.width);
    const height = positive(r.height);
    if (width === 0 || height === 0)
        return null;
    const originX = (typeof r.x === "number" && isFinite(r.x)) ? r.x : 0;
    const originY = (typeof r.y === "number" && isFinite(r.y)) ? r.y : 0;
    if (!isFinite(x) || !isFinite(y))
        return null;
    return {
        x: clamp01((x - originX) / width),
        y: clamp01((y - originY) / height)
    };
}

// A click on the DESKTOP, as a point in the picture's own frame.
//
// The selection surface is a separate, screen-sized layer surface sitting over
// the wallpaper, so a click arrives in screen coordinates while the
// registration - `normalisedPoint` and the rectangle it consumes - is expressed
// inside the box the cutout is drawn in. That box is the wallpaper viewport,
// which is oversized and negatively offset whenever parallax is on.
//
// Composed here rather than at the call site for the same reason
// `normalisedPoint` exists at all: the offset is the part that is silently
// zero for whoever writes it. A viewport at rest with parallax switched off
// sits at exactly (0, 0), so a translation that has been left out entirely is
// correct on the first screen anyone tries it on and wrong by up to the whole
// zoom overflow on every workspace but the middle one - and the wrong answer
// is still a perfectly good mask, of the wrong thing.
function promptFromScreen(box, pictureRect, screenX, screenY) {
    const b = box || {};
    if (!isFinite(screenX) || !isFinite(screenY))
        return null;
    return normalisedPoint(pictureRect, screenX - origin(b.x), screenY - origin(b.y));
}

// May a subject be picked on the desktop right now?
//
// A narrower question than `eligible`, and deliberately not a subset of it:
// two of that predicate's refusals - no mask, and the per-wallpaper opt-out -
// are exactly the states selecting exists to change, so gating the gesture on
// them would make the feature unreachable from the half of the library it was
// built for. What both refuse is the same underlying thing: a desktop whose
// pixels are not the still image the producer is being asked about.
function selectable(state) {
    const s = state || {};
    if (!s.wallpaperPath) return false;
    // The wallpaper selector reverts a preview the moment it closes, and the
    // gesture is entered by closing it - so the picture under the click would
    // not be the picture the clicks get stored against.
    if (s.previewing) return false;
    // A live Wallpaper Engine project owns the screen; the still this service
    // names is not what is being drawn, so a cutout of it is a sticker.
    if (s.weActive) return false;
    // Centred mode draws the wallpaper at its own size in its own shape, which
    // is not the geometry the cutout is registered against.
    if (s.centeredWallpaper) return false;
    if (s.screenLocked) return false;
    return true;
}

function clamp01(value) {
    return value < 0 ? 0 : (value > 1 ? 1 : value);
}

function origin(value) {
    return (typeof value === "number" && isFinite(value)) ? value : 0;
}

function positive(value) {
    return (typeof value === "number" && isFinite(value) && value > 0) ? value : 0;
}
