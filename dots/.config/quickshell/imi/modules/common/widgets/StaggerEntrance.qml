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
    readonly property real scaleFrom: Appearance.animation.entranceScaleFrom(
        root.reference > 0 ? root.reference : (root.target?.width ?? 0))

    property Component lift: Component {
        Translate {
            objectName: "staggerEntranceLift"
            property Item item
            y: (1 - (item?.appear ?? 1)) * root.rise
        }
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
            if (child.interactionMotion !== undefined)
                continue;
            if (root.dressed(child))
                continue;
            child.opacity = Qt.binding(() => child.appear);
            child.scale = Qt.binding(() =>
                root.scaleFrom + (1 - root.scaleFrom) * child.appear);
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
