.pragma library

// How much of a screen the cheatsheet's window may take, and how far a page
// that is too big for that has to shrink.
//
// The window is a fixed-size toplevel (equal minimum and maximum hints are what
// make Hyprland float and centre it, see Cheatsheet.qml), so it never resizes
// itself: it is exactly as tall as its tallest page. Its pages therefore have
// to fit the screen on their own, and "the screen" is the part of it the
// compositor leaves - `hyprctl monitors` reports the reserved area the bar and
// the dock hold as [left, top, right, bottom], and a floating window is centred
// in what is left. The Elements page was a fixed 9 rows of 70px tiles, which is
// ~800px with its chrome; on a 1080p laptop at 1.25x scale the logical screen
// is 864 tall with 754 usable, so the window sat 17px under the bar and 17px
// under the dock, and at 1.5x (720 logical) it ran off both screen edges.
//
// Pure, so tst_cheatsheet_fit.qml can drive the three measured screens.

function reservedAlong(reserved, startIndex, endIndex) {
    if (!reserved || typeof reserved.length !== "number")
        return 0;
    const start = Number(reserved[startIndex]);
    const end = Number(reserved[endIndex]);
    return (isFinite(start) ? start : 0) + (isFinite(end) ? end : 0);
}

// The height a floating window may take on a screen: minus what the compositor
// has reserved at the top and bottom, minus one gap on each side so it does not
// touch either.
function usableHeight(screenHeight, reserved, gap) {
    return Math.max(0, screenHeight - reservedAlong(reserved, 1, 3) - 2 * gap);
}

function usableWidth(screenWidth, reserved, gap) {
    return Math.max(0, screenWidth - reservedAlong(reserved, 0, 2) - 2 * gap);
}

// What is left for a page once the window's own chrome (padding, the tab bar,
// the gaps between them) has taken its share.
function pageBudget(usable, chrome) {
    return Math.max(0, usable - chrome);
}

// The uniform scale that fits a page's natural size inside its budget: 1 while
// it already fits, never larger. A budget of 0 or less means "unbounded" on
// that axis - the window has not been told about its screen yet - and a page
// with no natural size yet is left alone rather than scaled by a NaN.
function fitScale(naturalWidth, naturalHeight, budgetWidth, budgetHeight) {
    let scale = 1;
    if (budgetWidth > 0 && naturalWidth > 0)
        scale = Math.min(scale, budgetWidth / naturalWidth);
    if (budgetHeight > 0 && naturalHeight > 0)
        scale = Math.min(scale, budgetHeight / naturalHeight);
    return scale;
}
