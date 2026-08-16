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

function positive(value) {
    return (typeof value === "number" && isFinite(value) && value > 0) ? value : 0;
}
