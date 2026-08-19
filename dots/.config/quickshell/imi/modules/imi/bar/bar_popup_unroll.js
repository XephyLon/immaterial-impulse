.pragma library

// The bar popup card's height, as arithmetic.
//
// Nothing about that card is reachable from a test: it lives on a
// wlr-layer-shell surface, which qmltestrunner cannot build and headless weston
// does not implement, so the decisions have to be somewhere a test can call
// them - the same reason ParallaxMath.sampleOrigin and clockDepth.js are pure.
//
// The card runs on ONE scalar, `openProgress`, 0 while idle and 1 while open.
// The fade rides it and so does the height, which is why the height is a plain
// binding rather than a second animation: a Behavior whose target moves every
// frame restarts every frame and never ticks
// (b710ef731 ("fix(plugins): stop the position Behavior swallowing the parallax
// cancellation")), and two animations of one quantity are two timings that have
// to agree.

// The card opens at the height of the content's FIRST drawn section and unfurls
// from there, instead of appearing at full height or growing out of nothing:
// the top edge never moves and the primary content is legible on frame one.
//
// A section is measured at its DRAWN height. A Layout child states its size
// through `Layout.preferredHeight` and carries no implicit height of its own,
// so reading `implicitHeight` here answers 0 for exactly the popups whose first
// section is a card - which is every popup the unroll exists for. Zero-height
// and undrawn children are skipped rather than accepted, for the same reason a
// stagger ranks by visible position: a spacer that spends a slot would make the
// hero the height of nothing.
function heroSectionHeight(sections, padding) {
    if (!sections)
        return 0;
    for (let index = 0; index < sections.length; index++) {
        const section = sections[index];
        if (!section || section.visible !== true)
            continue;
        const height = section.height;
        if (!(height > 0))
            continue;
        return height + padding * 2;
    }
    return 0;
}

// Where the card sits at progress 0, and therefore what it unrolls FROM.
//
// Opening with a hero that is the whole content (a one-section popup) leaves
// rest === open, so such a popup simply has no unroll rather than a special
// case. Leaving, or opening with no measurable first section, the rest is the
// small square parked on the widget the card belongs to - the card grows out of
// and collapses back into the bar, which is what it did before the unroll and
// is still the honest answer when there is no section to open at.
function restHeight(openHeight, heroHeight, parkedSize, exiting) {
    if (!(openHeight > 0))
        return 0;
    const rest = (exiting || !(heroHeight > 0)) ? parkedSize : heroHeight;
    return Math.max(0, Math.min(rest, openHeight));
}

// An idle card must be exactly 0 tall, because an `opacity: 0` card still
// publishes a full-size input region and a permanently-reachable one on a
// screen-sized Overlay surface eats every click in its rectangle. The height is
// derived, so emptying the region means emptying what it is derived FROM: a
// zero open height is 0 at every progress, including a progress the exit's
// curve has undershot below zero.
//
// The top end is deliberately NOT clamped: the spatial tier overshoots past 1,
// and a card that overshoots its content and settles back is the tier's own
// expressiveness - the same overshoot the height Behavior this replaced already
// produced.
function cardHeight(openHeight, heroHeight, parkedSize, exiting, progress) {
    if (!(openHeight > 0))
        return 0;
    const rest = restHeight(openHeight, heroHeight, parkedSize, exiting);
    const travelled = progress > 0 ? progress : 0;
    return rest + (openHeight - rest) * travelled;
}
