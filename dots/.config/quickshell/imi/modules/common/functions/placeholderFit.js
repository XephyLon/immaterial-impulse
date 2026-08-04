.pragma library

// A PagePlaceholder centres its column in whatever space the page gives it,
// and a page shorter than that column does not clip it - the column simply
// draws outside the container it belongs to. The right sidebar's notification
// list is the case that forced this (#87): it shares the sidebar column with a
// fixed-height bottom widget group, so on a short screen it is squeezed until
// the placeholder's shape sits above the list's own top edge, outside the
// rounded rectangle that is supposed to hold it.
//
// The shape is both the tallest part of a placeholder and the part carrying
// the least information, so it is what gives way first - the text alone still
// says what the empty state is.

// Whether the shape still fits above the labels within `availableHeight`.
//
// `iconHeight` is the shape's own implicit height and `textHeights` are the
// visible labels' - never the column's own implicit height, which excludes an
// invisible child. Deciding from that would drop the shape, free its height,
// find there is room again, put it back, and oscillate forever.
//
// A page with no height yet has not been laid out; it is not "too short". A
// placeholder built before its first layout pass would otherwise start without
// its shape and pop it in, which reads as a glitch rather than as a fit.
function iconFits(availableHeight, iconHeight, textHeights, spacing) {
    if (!(availableHeight > 0))
        return true;
    const text = (textHeights || []).reduce(
        (total, height) => total + height + spacing, 0);
    return availableHeight >= iconHeight + text;
}
