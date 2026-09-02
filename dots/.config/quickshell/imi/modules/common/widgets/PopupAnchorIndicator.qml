import QtQuick
import qs.modules.common

/**
 * The one open state a bar widget has while a click holds its popup open.
 *
 * Material's active indicator: a primary bar, `borderWidth.emphasis` thick,
 * as long as the widget's visual, lying on the bar surface's popup-facing
 * edge under that visual. It lives at the edge, outside any group pill, so
 * it collides with nothing under any bar style or group style - a ring or a
 * container around the visual needs air the group pills and the flat bar do
 * not give (a filled pill behind a bare gauge, a dashed ring a pixel from
 * the pill's edge). And it points at the popup: the state is "this opens
 * from here", not "selected".
 *
 * Never snapped: one presence scalar fades it on the effects tier, and on a
 * spatial tier it grows from its centre to the visual's length on the way in
 * and shrinks back on the way out, one tier for both directions because the
 * state is reversible.
 *
 * Mounting: `wraps` is the visual (its length and centre), `edgeItem` the
 * widget's root - the indicator parents itself to it. The edge it lies on
 * is the SURFACE's: the nearest ancestor of the root that exposes a
 * `popupAnchorSurface` - the widget's own group pill when it is painted,
 * else the section's plate (the material pill, the island, the centre
 * pill) or the bar background, whichever the style in force paints. Not
 * the root's edge (a vertical bar's widgets are narrower than the bar) and
 * not the window's (taller than the plate by shadows and gaps, and not
 * evenly). `edge` is the edge the popup opens from, `BarEdges.popupEdge(...)`.
 */
Item {
    id: root

    property bool shown: false
    property Item wraps: null
    property Item edgeItem: null
    // "bottom" | "top" | "left" | "right"
    property string edge: "bottom"

    readonly property real thickness: Appearance.borderWidth.emphasis
    readonly property bool horizontalEdge: root.edge === "bottom" || root.edge === "top"
    // The plate this lies on: the nearest ancestor exposing a painted
    // popupAnchorSurface. The root's parents are read so a re-parenting
    // (a style change rebuilds the bar) finds the new plate.
    readonly property Item surface: {
        let node = root.edgeItem;
        for (let depth = 0; node && depth < 16; depth++) {
            void node.x;
            if (node.popupAnchorSurface !== undefined && node.popupAnchorSurface)
                return node.popupAnchorSurface;
            node = node.parent;
        }
        return null;
    }

    property real presence: root.shown ? 1 : 0
    Behavior on presence {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    property real grow: root.shown ? 1 : 0
    Behavior on grow {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    opacity: root.presence
    visible: root.presence > 0
    z: 1

    onEdgeItemChanged: if (root.edgeItem) root.parent = root.edgeItem
    Component.onCompleted: if (root.edgeItem) root.parent = root.edgeItem

    // The visual's centre in the root's coordinates. mapToItem is not a
    // binding on its own, so the positions and sizes it depends on are read
    // here: the visual's, its parents' up the short chain a bar widget has,
    // and the root's.
    readonly property point centre: {
        if (!root.wraps || !root.edgeItem)
            return Qt.point(0, 0);
        const w = root.wraps;
        void [w.x, w.y, w.width, w.height, root.edgeItem.width, root.edgeItem.height,
              w.parent?.x, w.parent?.y, w.parent?.width, w.parent?.height,
              w.parent?.parent?.x, w.parent?.parent?.y, w.parent?.parent?.width,
              w.parent?.parent?.parent?.x, w.parent?.parent?.parent?.width];
        return w.mapToItem(root.edgeItem, w.width / 2, w.height / 2);
    }
    readonly property real length: (root.horizontalEdge ? (root.wraps?.width ?? 0) : (root.wraps?.height ?? 0)) * root.grow
    // Where the surface's popup-facing edge is, in the root's coordinates,
    // the indicator's thickness inside it. mapToItem is not a binding on its
    // own, so the geometry it depends on is read: the surface's, the root's
    // and the root's parents' up the short chain a bar widget has. With no
    // surface (a harness, a preview) the root's own edge stands in.
    readonly property real edgeInRoot: {
        const e = root.edgeItem;
        if (!e)
            return 0;
        const far = root.edge === "bottom" || root.edge === "right";
        const s = root.surface;
        if (!s)
            return far ? (root.horizontalEdge ? e.height : e.width) - root.thickness : 0;
        void [s.x, s.y, s.width, s.height, e.x, e.y, e.width, e.height,
              e.parent?.x, e.parent?.y, e.parent?.parent?.x, e.parent?.parent?.y,
              e.parent?.parent?.parent?.x, e.parent?.parent?.parent?.y,
              e.parent?.parent?.parent?.parent?.x, e.parent?.parent?.parent?.parent?.y];
        const p = s.mapToItem(e, far ? s.width : 0, far ? s.height : 0);
        const at = root.horizontalEdge ? p.y : p.x;
        return far ? at - root.thickness : at;
    }

    width: root.horizontalEdge ? root.length : root.thickness
    height: root.horizontalEdge ? root.thickness : root.length
    x: root.horizontalEdge ? root.centre.x - root.width / 2 : root.edgeInRoot
    y: root.horizontalEdge ? root.edgeInRoot : root.centre.y - root.height / 2

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.full
        color: Appearance.colors.colPrimary
    }
}
