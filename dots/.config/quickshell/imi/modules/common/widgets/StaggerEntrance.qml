import QtQuick
import qs.modules.common

/**
 * The one spelling of how a wave member ARRIVES: opacity, a scale from a
 * derived near-1 start, and a small rise, all riding the same `appear` scalar
 * a `StaggerWave` animates. The wave decides WHEN a member moves; this decides
 * what moving looks like - three channels on one scalar, so they cannot land
 * on different schedules (docs/M3_GUIDELINES.md §2, "Component Entrance and
 * Exit"; measured off the sibling fork in
 * docs/p3drovfx-motion-measured-2026-08-22.md §3).
 *
 * Declared beside the wave, aimed at the same container, and it dresses every
 * child that declares `appear` - which is what keeps the tenth row added next
 * year from being the fourth hand-copied dressing that drifts by a channel,
 * the way Edit Mode's drawer spelled these three bindings out nine times
 * before this existed.
 *
 * Two refusals are as load-bearing as the dressing:
 *
 *  - A child without `appear` is not a wave member and is left alone.
 *  - A child that owns an `interactionMotion` (RippleButton and its kin)
 *    already folds `appear` into the opacity binding that carries its
 *    disabled dim, and owns `scale` through the model - so it rides the wave
 *    through the property the runner writes, and a second writer of either
 *    channel here would REPLACE the control's binding rather than compose
 *    with it: a press that stops squishing, and a disabled row drawn as
 *    enabled. `lint_interaction_motion_double.py` and
 *    `lint_disabled_opacity.py` fail the suite on a StaggerEntrance declared
 *    inside such a control for the same reason.
 *
 * The scale START is `Appearance.animation.entranceScaleFrom(reference)` -
 * derived from the rise and the width the member plays on, floored at the
 * survey's measured 0.85, so the scale's excursion stays the rise's size at
 * any width (see motion_policy.js for the derivation's reasoning).
 *
 * The channels are installed as bindings once per member rather than asked
 * for per call site, because "from one place" is the entire point: the member
 * declares `property real appear: 1` and nothing else. A QtObject rather than
 * an Item for the StaggerWave reason - a dresser declared inside the
 * container it dresses must not become a member of it.
 */
QtObject {
    id: root

    // The container whose `appear`-declaring children are dressed.
    property Item target: null

    // The width the scale's excursion is matched to. Defaults to the
    // container's own; a caller whose panel is wider than the dressed column
    // (the drawer's margins) passes the panel's width instead.
    property real reference: 0

    readonly property real rise: Appearance.animation.entranceRise
    readonly property real scaleFrom: root.convergent
        ? Appearance.animation.convergeScaleFrom
        : Appearance.animation.entranceScaleFrom(
              root.reference > 0 ? root.reference : (root.target?.width ?? 0))

    // Convergent mode: instead of one uniform rise, each member starts a
    // short reach away from its place ON ITS OWN SIDE - leftmost members from
    // further left, rightmost from further right, alternating members from
    // above and below - and the spatial channels settle through an OutBack
    // shape while opacity tracks `appear` directly, so an arrival lands with
    // a hair of overshoot instead of fading into position. Measured off the
    // sibling fork's sidebars; arithmetic and provenance in motion_policy.js.
    // The direction reads the member's LIVE position (a binding on child.x),
    // so a reflow re-aims it and nothing is captured stale.
    property bool convergent: false

    property Component lift: Component {
        Translate {
            objectName: "staggerEntranceLift"
            property Item item
            readonly property real settle: root.convergent
                ? Appearance.animation.convergeSettle(item?.appear ?? 1)
                : (item?.appear ?? 1)
            readonly property var direction: {
                if (!root.convergent || !item || !root.target || root.target.width <= 0)
                    return { dx: 0, dy: -1 };
                const centre = (item.x + item.width / 2) / root.target.width * 2 - 1;
                return Appearance.animation.convergeFrom(centre, root.memberParity(item));
            }
            x: root.convergent
                ? (1 - settle) * direction.dx * Appearance.animation.convergeReachX
                : 0
            y: root.convergent
                ? (1 - settle) * direction.dy * Appearance.animation.convergeReachY
                : (1 - settle) * root.rise
        }
    }

    // A member's vertical alternation is its position among the members that
    // are actually drawn - the wave's own visible-rank rule, reused so a
    // hidden member does not flip every later member's direction.
    function memberParity(child: Item): int {
        const kids = members();
        let rank = 0;
        for (let i = 0; i < kids.length; i++) {
            if (kids[i] === child)
                return rank;
            if (kids[i]?.appear !== undefined && kids[i].visible)
                rank++;
        }
        return rank;
    }

    function members(): var {
        return root.target ? root.target.children : [];
    }

    // Whether a member already carries this dressing, read off the member
    // itself rather than off a list of references: a Repeater destroys and
    // rebuilds delegates, and a bookkeeping list would hold the dead.
    function dressed(child: Item): bool {
        for (let i = 0; i < child.transform.length; i++)
            if (child.transform[i]?.objectName === "staggerEntranceLift")
                return true;
        return false;
    }

    function dress() {
        const kids = root.target ? root.target.children : [];
        for (let i = 0; i < kids.length; i++) {
            const child = kids[i];
            if (child.appear === undefined)
                continue;
            if (root.dressed(child))
                continue;
            if (child.interactionMotion !== undefined) {
                // A control that applies the interaction model owns its scale
                // (the model's) and folds `appear` into its own opacity (the
                // binding that carries the disabled dim) - writing either here
                // REPLACES those bindings, the doubling the composition lints
                // exist to fail. Its POSITION belongs to nobody, so in
                // convergent mode a control still travels into place; in
                // uniform mode it keeps its own 6px fold untouched.
                if (root.convergent)
                    child.transform.push(root.lift.createObject(child, { item: child }));
                continue;
            }
            child.opacity = Qt.binding(() => child.appear);
            child.scale = Qt.binding(() =>
                root.scaleFrom + (1 - root.scaleFrom) *
                (root.convergent ? Appearance.animation.convergeSettle(child.appear) : child.appear));
            child.transform.push(root.lift.createObject(child, { item: child }));
        }
    }

    // Members that arrive after completion - a Repeater filling the container
    // - are dressed on arrival; `dressed()` keeps the residents from being
    // dressed twice.
    property Connections arrivals: Connections {
        target: root.target
        function onChildrenChanged() {
            root.dress();
        }
    }

    Component.onCompleted: root.dress()
}
