import QtQuick
import qs
import qs.modules.common
import qs.modules.common.plugins
import qs.modules.common.widgets
import "../../common/functions/layout_ops.js" as LayoutOps

/**
 * One bar's worth of Edit Mode's reorder: the coordinator both content trees
 * instantiate, so the horizontal and the vertical bar run the SAME edit logic
 * rather than two copies that can drift (the a47462fcc lesson - a capability
 * added to one bar and not the other is invisible on a default screen).
 *
 * ---- what it owns, and what it does not -------------------------------------
 *
 * It owns the drag's bookkeeping (which slot is being carried, where it would
 * land), the drop indicator and the ghost chip, and the COMMITS - each surface
 * commits to its own store, and the bar's store is the three
 * `Config.options.bar.layouts.*Layout` arrays. Every list operation goes
 * through `layout_ops.js`; this file has no DragHandler of its own (the
 * gesture is `ReorderDragArea`, instantiated per slot by `BarWidgetEditItem`),
 * so `lint_reorder_arithmetic.py` cannot sweep it and
 * `test_bar_dock_edit_contract.py` pins the no-local-arithmetic half instead.
 *
 * ---- the visible-to-stored mapping ------------------------------------------
 *
 * The drawn slots are the FILTERED layouts (an empty tray drops sysTray, a
 * disabled plugin drops its widget), so every index the gesture reads counts
 * visible slots while the store holds the whole list. The mapping walks a
 * flags array built from the same predicate the content tree filters with -
 * handed in as `widgetVisible`, so the two cannot disagree - and shifts hidden
 * entries along with their visible neighbours instead of eating them.
 *
 * ---- why the indicator and the ghost are positioned imperatively ------------
 *
 * They follow the pointer and the target, both of which change per pointer
 * event, and their positions are maps of OTHER items' geometry. `mapToItem`
 * in a binding re-evaluates only when the binding's own dependencies change,
 * not when an ancestor moves, so a declarative spelling is the staleness trap;
 * a per-event imperative update reads everything at the moment it is true.
 */
Item {
    id: root

    property bool vertical: false
    readonly property string axis: root.vertical ? "y" : "x"
    readonly property var bucketNames: ["left", "middle", "right"]

    // Handed in by the content tree: the drawn slot items per bucket (the
    // visible style's Repeater items, layout order), the filter predicate the
    // tree draws with, and the three bucket-boundary zones - the stand-in drop
    // anchors for a bucket with nothing visible in it.
    property var slotItemsFor: null
    property var widgetVisible: null
    property Item leftZone: null
    property Item middleZone: null
    property Item rightZone: null

    // The drag in flight, or -1/"" outside one.
    property int dragBucket: -1
    property int dragVisibleIndex: -1
    property string dragWidgetId: ""
    readonly property bool dragActive: root.dragVisibleIndex >= 0

    function zoneFor(bucket) {
        return [root.leftZone, root.middleZone, root.rightZone][bucket] ?? null;
    }

    // The three stored lists, spelled as literal paths rather than a computed
    // key: an allowlist reachable through a variable is not an allowlist, and
    // the same reasoning keeps a reviewer able to grep every write.
    function storedLayout(bucket) {
        if (bucket === 0) return Config.options.bar.layouts.leftLayout;
        if (bucket === 1) return Config.options.bar.layouts.middleLayout;
        return Config.options.bar.layouts.rightLayout;
    }

    function writeLayout(bucket, list) {
        if (bucket === 0) Config.options.bar.layouts.leftLayout = list;
        else if (bucket === 1) Config.options.bar.layouts.middleLayout = list;
        else Config.options.bar.layouts.rightLayout = list;
    }

    // flags[i]: is stored entry i drawn - the same predicate the tree filters
    // with, walked index-by-index because the list crosses the QML boundary
    // without its Array brand.
    function flagsFor(bucket) {
        const stored = root.storedLayout(bucket);
        const count = stored && typeof stored.length === "number" ? stored.length : 0;
        const flags = [];
        for (let i = 0; i < count; i++)
            flags.push(root.widgetVisible(stored[i]) === true);
        return flags;
    }

    // layout_ops.dropTarget's buckets, in scene coordinates, built fresh per
    // pointer event. The dragged slot is a hole - it is still laid out where
    // the drag began and would be its own nearest neighbour - and a bucket's
    // boundary zone is its anchor, which is what makes an empty bucket a
    // valid drop target.
    function dropBuckets() {
        const buckets = [];
        for (let b = 0; b < 3; b++) {
            const items = root.slotItemsFor ? (root.slotItemsFor(root.bucketNames[b]) || []) : [];
            const centres = [];
            for (let i = 0; i < items.length; i++) {
                const item = items[i];
                const hole = !item || (b === root.dragBucket && i === root.dragVisibleIndex);
                centres.push(hole ? null : item.mapToItem(null, item.width / 2, item.height / 2));
            }
            const zone = root.zoneFor(b);
            buckets.push({
                centres: centres,
                anchor: zone ? zone.mapToItem(null, zone.width / 2, zone.height / 2) : null
            });
        }
        return buckets;
    }

    function beginDrag(bucket, visibleIndex, widgetId) {
        root.dragBucket = bucket;
        root.dragVisibleIndex = visibleIndex;
        root.dragWidgetId = widgetId;
        // For the exit ladder: a bar drag is a gesture in flight, and Escape's
        // first answer to one is cancel-not-exit.
        GlobalStates.editBarDragActive = true;
    }

    function endDrag() {
        root.dragBucket = -1;
        root.dragVisibleIndex = -1;
        root.dragWidgetId = "";
        GlobalStates.editBarDragActive = false;
        dropIndicator.shown = false;
        ghost.shown = false;
    }

    // The overlay's end-of-drag handlers live on the BarWidgetEditItem the
    // mode's exit destroys, so - exactly like GlobalStates' own central
    // editBarDragActive reset, and for the reason its comment gives - none of
    // them is guaranteed to run for an exit mid-drag. Without this, the drag
    // bookkeeping and a stale ghost chip would survive onto the LIVE bar:
    // this controller is instantiated unconditionally in both content trees.
    // The rectangles' `visible` is additionally bound through `dragActive`,
    // so even a reset path nobody predicted cannot strand a drawn chip.
    property Connections modeWatcher: Connections {
        target: GlobalStates
        function onEditModeChanged() {
            if (!GlobalStates.editMode) root.endDrag();
        }
    }

    function dragMoved(target, scenePoint) {
        if (!root.dragActive) return;
        const local = root.mapFromItem(null, scenePoint.x, scenePoint.y);
        ghost.x = local.x - ghost.width / 2;
        ghost.y = local.y - ghost.height - Appearance.spacing.space100;
        ghost.shown = true;
        root.placeIndicator(target);
    }

    // The indicator marks the GAP the insertion index names: before the slot
    // at the index, after the last one for an append, and the zone's centre
    // for an empty bucket.
    function placeIndicator(target) {
        if (!target) {
            dropIndicator.shown = false;
            return;
        }
        const items = root.slotItemsFor(root.bucketNames[target.bucket]) || [];
        let along;
        let crossCentre;
        let crossSize;
        const atEnd = target.index >= items.length;
        const reference = items.length === 0 ? null
            : items[atEnd ? items.length - 1 : target.index];
        if (!reference) {
            const zone = root.zoneFor(target.bucket);
            if (!zone) {
                dropIndicator.shown = false;
                return;
            }
            const centre = zone.mapToItem(root, zone.width / 2, zone.height / 2);
            along = root.vertical ? centre.y : centre.x;
            crossCentre = root.vertical ? centre.x : centre.y;
            crossSize = root.vertical ? zone.width : zone.height;
        } else {
            const topLeft = reference.mapToItem(root, 0, 0);
            const size = root.vertical ? reference.height : reference.width;
            const start = root.vertical ? topLeft.y : topLeft.x;
            along = atEnd ? start + size : start;
            crossCentre = root.vertical
                ? topLeft.x + reference.width / 2
                : topLeft.y + reference.height / 2;
            crossSize = root.vertical ? reference.width : reference.height;
        }
        if (root.vertical) {
            dropIndicator.width = crossSize;
            dropIndicator.height = 3;
            dropIndicator.x = crossCentre - crossSize / 2;
            dropIndicator.y = along - dropIndicator.height / 2;
        } else {
            dropIndicator.width = 3;
            dropIndicator.height = crossSize;
            dropIndicator.x = along - dropIndicator.width / 2;
            dropIndicator.y = crossCentre - crossSize / 2;
        }
        dropIndicator.shown = true;
    }

    // The commits. Guarded on the mode because a drag can outlive it - Done
    // mid-gesture, the exit ladder - and an end the user meant as "stop" must
    // not store an order they never chose.
    function commitReorder(fromBucket, fromVisible, target) {
        if (!GlobalStates.editMode || !target) return;
        if (target.bucket === fromBucket) {
            const flags = root.flagsFor(fromBucket);
            const visibleDest = LayoutOps.moveTargetForInsertion(fromVisible, target.index);
            if (visibleDest === fromVisible) return;
            root.writeLayout(fromBucket, LayoutOps.move(root.storedLayout(fromBucket),
                LayoutOps.nthVisible(flags, fromVisible),
                LayoutOps.nthVisible(flags, visibleDest)));
            return;
        }
        const fromFlags = root.flagsFor(fromBucket);
        const toFlags = root.flagsFor(target.bucket);
        const storedFrom = LayoutOps.nthVisible(fromFlags, fromVisible);
        if (storedFrom === -1) return;
        const source = root.storedLayout(fromBucket);
        const id = source[storedFrom];
        root.writeLayout(fromBucket, LayoutOps.remove(source, storedFrom));
        root.writeLayout(target.bucket, LayoutOps.insert(root.storedLayout(target.bucket),
            id, LayoutOps.insertionForVisible(toFlags, target.index)));
    }

    function removeAt(bucket, visibleIndex) {
        if (!GlobalStates.editMode) return;
        const flags = root.flagsFor(bucket);
        const stored = LayoutOps.nthVisible(flags, visibleIndex);
        if (stored === -1) return;
        root.writeLayout(bucket, LayoutOps.remove(root.storedLayout(bucket), stored));
    }

    Rectangle {
        id: dropIndicator
        objectName: "barEditDropIndicator"
        property bool shown: false
        visible: root.dragActive && shown
        radius: Appearance.rounding.unsharpen
        color: Appearance.colors.colPrimary
    }

    // The chip riding the pointer, so a drag between distant buckets carries
    // its name with it - the drawer's ghost, at the bar's scale.
    Rectangle {
        id: ghost
        objectName: "barEditGhost"
        property bool shown: false
        visible: root.dragActive && shown
        width: ghostLabel.implicitWidth + Appearance.spacing.space200
        height: 28
        radius: height / 2
        color: Appearance.colors.colSecondaryContainer

        StyledText {
            id: ghostLabel
            anchors.centerIn: parent
            text: BarWidgets.nameFor(root.dragWidgetId)
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnSecondaryContainer
        }
    }
}
