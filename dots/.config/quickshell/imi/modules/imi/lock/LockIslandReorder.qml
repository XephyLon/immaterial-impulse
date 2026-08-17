import QtQuick
import qs
import qs.modules.common
import "../../common/functions/layout_ops.js" as LayoutOps
import "../../common/functions/lock_islands.js" as LockIslands

/**
 * One island's worth of Edit Mode's reorder: the coordinator each island
 * instantiates with its name, its Repeater and its toolbar - the same split
 * `BarEditController` established, one size down. It owns the drag's
 * bookkeeping, the drop indicator, and the COMMIT; the gesture itself is
 * `ReorderDragArea`, instantiated per slot by `LockIslandEditItem`, so this
 * file has no DragHandler of its own and `layout_ops` + `lock_islands` are
 * the only arithmetic anywhere in it.
 *
 * ---- one bucket, deliberately ----------------------------------------------
 *
 * `dropTarget` speaks buckets, and the three islands could have been three of
 * them - but a cross-island move would write an id into a list whose island
 * does not know it, and the resolver's unknown-id rule (correctly) skips what
 * it does not know: the item would vanish from both islands. Each island's
 * vocabulary is its own defaults, so each controller offers exactly one
 * bucket and an item reorders within its island.
 *
 * ---- rendered indices, not visible ones -------------------------------------
 *
 * The drag's indices are the RENDERED order's (the resolver's answer, which
 * the Repeater models), and an invisible slot - the username while media
 * shows, the battery pair on a desktop - is a HOLE in the centres, exactly
 * like the bar's filtered slots. That keeps the indexing aligned with the
 * model with no flags walk: the centres array is indexed by rendered index by
 * construction.
 *
 * The write-back is `LockIslands.storedOrder`: the moved rendered order plus
 * every unknown stored id appended, so a list written by a newer shell
 * version loses nothing when this one reorders it.
 *
 * Two smaller facts, stated so nobody "fixes" either toward the bar's shape:
 * a drop at an island's END lands before any hidden tail entry (the centres
 * cap the insertion at the last VISIBLE slot, where the bar's
 * insertionForVisible maps an append to the stored end) - visible items stay
 * contiguous ahead of hidden ones, which is the behaviour a pointer gesture
 * over visible slots can actually mean. And like the bar's flag, a drag
 * whose overlay is destroyed without its end handlers (an external rebuild
 * of the model mid-drag) leaves `editLockDragActive` up until the mode's
 * exit reset - the central endDrag below is the recovery both flags share.
 */
Item {
    id: root

    // "main" | "left" | "right", for the literal write below and for the
    // module's reorderable() rule at the call sites.
    property string island: ""
    // The island's rendered order (the resolver's answer), its Repeater, and
    // the toolbar the indicator is drawn against - handed in by LockSurface.
    property var orderedIds: []
    property Repeater repeater: null
    property Item islandItem: null

    property int dragIndex: -1
    readonly property bool dragActive: root.dragIndex >= 0

    // The three stored lists as literal paths - an allowlist reachable
    // through a computed key is not an allowlist (the scope lint's rule
    // about exactly these writes).
    function storedList() {
        if (root.island === "main") return Config.options.lock.islands.main;
        if (root.island === "left") return Config.options.lock.islands.left;
        return Config.options.lock.islands.right;
    }

    function defaults() {
        if (root.island === "main") return LockIslands.MAIN_DEFAULT;
        if (root.island === "left") return LockIslands.LEFT_DEFAULT;
        return LockIslands.RIGHT_DEFAULT;
    }

    function writeList(list) {
        if (root.island === "main") Config.options.lock.islands.main = list;
        else if (root.island === "left") Config.options.lock.islands.left = list;
        else Config.options.lock.islands.right = list;
    }

    // layout_ops.dropTarget's one bucket, in scene coordinates, built fresh
    // per pointer event: an invisible slot and the dragged one are holes, and
    // the toolbar's own centre is the anchor so an island whose every other
    // slot is hidden still takes the drop back.
    function dropBuckets() {
        const centres = [];
        const count = root.repeater ? root.repeater.count : 0;
        for (let index = 0; index < count; index++) {
            const item = root.repeater.itemAt(index);
            const hole = !item || !item.visible || index === root.dragIndex;
            centres.push(hole ? null : item.mapToItem(null, item.width / 2, item.height / 2));
        }
        return [{
            centres: centres,
            anchor: root.islandItem
                ? root.islandItem.mapToItem(null, root.islandItem.width / 2,
                    root.islandItem.height / 2)
                : null
        }];
    }

    function beginDrag(index) {
        root.dragIndex = index;
        // For the exit ladder: an island drag is a gesture in flight, and
        // Escape's first answer to one is cancel-not-exit.
        GlobalStates.editLockDragActive = true;
    }

    function endDrag() {
        root.dragIndex = -1;
        GlobalStates.editLockDragActive = false;
        dropIndicator.shown = false;
    }

    // The mode's exit destroys the overlays holding the gesture's end
    // handlers, so none is guaranteed to run - the same central reset the bar
    // controller carries, for the same reason.
    property Connections modeWatcher: Connections {
        target: GlobalStates
        function onEditModeChanged() {
            if (!GlobalStates.editMode) root.endDrag();
        }
    }

    // The indicator marks the GAP the insertion index names: before the slot
    // it points at, after the last visible one for an append. Positioned
    // imperatively per pointer event - mapToItem in a binding goes stale.
    function dragMoved(target) {
        if (!root.dragActive || !target) {
            dropIndicator.shown = false;
            return;
        }
        const count = root.repeater ? root.repeater.count : 0;
        let reference = null;
        let atEnd = true;
        for (let index = target.index; index < count; index++) {
            const item = root.repeater.itemAt(index);
            if (item && item.visible && index !== root.dragIndex) {
                reference = item;
                atEnd = false;
                break;
            }
        }
        if (reference === null) {
            for (let index = count - 1; index >= 0; index--) {
                const item = root.repeater.itemAt(index);
                if (item && item.visible && index !== root.dragIndex) {
                    reference = item;
                    break;
                }
            }
        }
        if (reference === null) {
            dropIndicator.shown = false;
            return;
        }
        const topLeft = reference.mapToItem(root, 0, 0);
        dropIndicator.width = 3;
        dropIndicator.height = reference.height;
        dropIndicator.x = (atEnd ? topLeft.x + reference.width : topLeft.x)
            - dropIndicator.width / 2;
        dropIndicator.y = topLeft.y;
        dropIndicator.shown = true;
    }

    // Guarded on the mode because a drag can outlive it - Done mid-gesture,
    // the exit ladder - and an end the user meant as "stop" must not store an
    // order they never chose.
    function commitReorder(from, target) {
        if (!GlobalStates.editMode || !target) return;
        const destination = LayoutOps.moveTargetForInsertion(from, target.index);
        if (destination === from) return;
        const moved = LayoutOps.move(root.orderedIds, from, destination);
        root.writeList(LockIslands.storedOrder(moved, root.storedList(), root.defaults()));
    }

    Rectangle {
        id: dropIndicator
        objectName: "lockIslandDropIndicator"
        property bool shown: false
        visible: root.dragActive && shown
        radius: Appearance.rounding.unsharpen
        color: Appearance.colors.colPrimary
    }
}
