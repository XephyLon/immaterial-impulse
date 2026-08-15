.pragma library

/**
 * Where the controls for a region recording go, and how the region is read
 * back from the string the recorder was started with.
 *
 * The one rule everything here follows: the toolbar must never overlap the
 * region. A region recording captures whatever the compositor shows inside
 * that rectangle, so a toolbar drawn over it is a toolbar recorded into the
 * video - and worse, it is in every frame of a clip the user cannot re-take.
 * Outside or not at all.
 */

// The geometry record.sh is handed: "X,Y WxH", as slurp writes it.
const REGION_RE = /^(-?\d+),(-?\d+)\s+(\d+)x(\d+)$/;

function parseRegion(text) {
    const raw = (text === null || text === undefined) ? "" : String(text).trim();
    const match = REGION_RE.exec(raw);
    if (!match) return null;
    const region = {
        x: parseInt(match[1], 10),
        y: parseInt(match[2], 10),
        width: parseInt(match[3], 10),
        height: parseInt(match[4], 10),
    };
    // A zero-sized region is not a region; it would put the toolbar at a point.
    if (region.width <= 0 || region.height <= 0) return null;
    return region;
}

/**
 * Places the toolbar against the region, in screen coordinates.
 *
 * Below the region first, because that is where a caption belongs and where
 * the eye already is after dragging a selection downward. Above when there is
 * no room below. When neither side fits - a region tall enough to leave no gap,
 * which in practice means a full-height or full-screen capture - the answer is
 * `null`: no toolbar rather than one inside the frame. The bar's own recording
 * indicator still offers stop in that case, so nothing is lost but the
 * shortcut.
 *
 * Horizontally the toolbar is centred on the region and then clamped into the
 * screen, so a region hard against an edge keeps all of its controls reachable.
 */
function placeToolbar(region, screen, toolbar, gap) {
    if (!region || !screen || !toolbar) return null;
    const spacing = (gap === undefined || gap === null) ? 8 : gap;

    const below = region.y + region.height + spacing;
    const above = region.y - spacing - toolbar.height;

    let y;
    let side;
    if (below + toolbar.height <= screen.y + screen.height) {
        y = below;
        side = "below";
    } else if (above >= screen.y) {
        y = above;
        side = "above";
    } else {
        return null;
    }

    const centred = region.x + (region.width - toolbar.width) / 2;
    const leftLimit = screen.x + spacing;
    const rightLimit = screen.x + screen.width - toolbar.width - spacing;
    // Math.min first, then max: on a screen narrower than the toolbar the left
    // edge wins, which keeps the first controls on screen rather than the last.
    const x = Math.max(leftLimit, Math.min(centred, rightLimit));

    return { x: Math.round(x), y: Math.round(y), side: side };
}
