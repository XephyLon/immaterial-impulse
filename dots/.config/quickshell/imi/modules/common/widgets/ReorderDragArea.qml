import QtQuick
import "../functions/layout_ops.js" as LayoutOps

/**
 * The reorder gesture as one component (spec §10.2): a DragHandler whose only
 * arithmetic is `layout_ops.dropTarget`, exposing where the drag would land.
 *
 * It deliberately owns NO commit. Each surface commits to its own store -
 * `Config.options` arrays, `plugin-state.json` and a local drag order are
 * three different commit paths, and only the arithmetic between them is
 * shared - so the component answers "where is the pointer, in bucket-and-
 * insertion terms" and raises `dropped` for the caller to act on.
 *
 * `bucketsProvider` is a function returning `layout_ops.dropTarget`'s buckets
 * (scene-space centres with holes, plus an anchor for an empty bucket),
 * called fresh per pointer event: positions are read off live items at the
 * moment they are compared, which is what LayoutSection already does and what
 * sidesteps the mapToItem-in-a-binding staleness trap.
 *
 * A cancel is a first-class end, not a missing commit: Edit Mode can end
 * mid-drag (Done, the exit ladder), and a gesture that commits on an end the
 * user meant as "stop" stores an order they never chose - the same
 * cancel-not-commit rule the desktop drag earned in 705e9006d's aftermath.
 * The pointer is still grabbed when `cancel()` runs, so the release that is
 * still coming must land on nothing; `abandoned` is what swallows it.
 */
Item {
    id: root

    // () => [{ centres: [point|null], anchor: point|null }], scene coordinates.
    property var bucketsProvider: null
    // The axis the buckets run along - the caller's knowledge, for the same
    // reason indexAt takes it: a column compared on x is an inert comparison.
    property string axis: "x"
    property bool interactive: true

    // Where the drag would land right now: { bucket, index } insertion, or
    // null outside a drag (and for the remainder of a cancelled one).
    property var target: null
    property bool abandoned: false
    readonly property bool dragging: dragHandler.active && !root.abandoned
    readonly property point scenePosition: dragHandler.centroid.scenePosition

    signal dragStarted()
    signal dropped(var target)
    signal dragEnded()

    function cancel() {
        if (!dragHandler.active) return;
        root.abandoned = true;
        root.target = null;
    }

    DragHandler {
        id: dragHandler
        target: null
        enabled: root.interactive
        // The press usually belongs to whatever sits under this item - an
        // input eater, a button - and the drag takes over past the threshold,
        // which is the DragApps/DockButton arrangement.
        grabPermissions: PointerHandler.CanTakeOverFromAnything

        onActiveChanged: {
            if (active) {
                root.abandoned = false;
                root.target = null;
                root.dragStarted();
                return;
            }
            const landed = root.abandoned ? null : root.target;
            root.target = null;
            if (landed)
                root.dropped(landed);
            root.dragEnded();
        }

        onCentroidChanged: {
            if (!active || root.abandoned || !root.bucketsProvider) return;
            root.target = LayoutOps.dropTarget(root.bucketsProvider(),
                dragHandler.centroid.scenePosition, root.axis);
        }
    }
}
