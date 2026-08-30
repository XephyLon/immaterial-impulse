import qs.modules.common
import QtQuick
import QtQuick.Layouts

/**
 * A list of rows drawn as one grouped surface: each row gets its own tinted
 * plate, the outer corners are rounded and the inner ones are not.
 *
 * ---- a row that comes and goes declares `rowVisible`, never `visible` -------
 *
 * The plates are built by a `Repeater` over the declared items and each one
 * sizes itself from its item's `implicitHeight`. That arithmetic never asked
 * whether the item was drawn, so a row hidden with `visible: false` kept its
 * plate: a row-height band of `bgcolor` with nothing in it. Two call sites had
 * it - the desktop menu's Edit layout row, which disappears while Edit Mode is
 * on, and Settings > Services > Weather's API-key field, which is OWM-only.
 *
 * The fix cannot be for the plate to mirror its item's `visible`, and that is
 * worth stating because it is the obvious shape. `Item.visible` reads back
 * EFFECTIVE visibility - the item's own flag AND its parents' - and the item is
 * a descendant of the plate, so a plate that hid itself from it would hide the
 * item too, and the item would then report false for ever. Probed with `qml6`
 * against a control row: the item toggled true/false/true while the mirrored
 * one read `false` on every one of the four samples after the first hide.
 *
 * So the declaration is a property of its own. A row that never disappears
 * declares nothing and reads `undefined`, which takes the `?? true` and costs
 * one property lookup.
 */
Item {
    id: root
    default property list<Item> items
    // ---- a group whose rows are not known when the file is written --------
    //
    // The declared spelling above cannot say "one row per device the daemon
    // knows". A call site that needed that used to wrap a list view in a
    // rectangle of its own, which is the presentation M3_GUIDELINES.md names
    // this component for - and it came out square, because `clip` on a
    // Rectangle clips to the box and not to the radius, so opaque rows paint
    // straight over the rounded corners.
    //
    // A row built from a model gets its data and its plate's corners handed to
    // it BY NAME after it loads: a Component declared at the call site resolves
    // its names in the call site's scope, not in the Loader's, so a plate that
    // merely exposed `modelData` would hand it nothing.
    property var model: null
    property Component rowDelegate: null
    readonly property bool modelDriven: root.rowDelegate !== null
    property real bigRadius: Appearance.rounding.normal
    property real smallRadius: Appearance.rounding.unsharpenmore
    property bool cohesive: false
    property color bgcolor: Appearance.colors.colLayer1
    property real itemVerticalPadding: Appearance.spacing.space300
    // The inset a row that paints itself keeps: not the plate's 8px plus
    // 24px of padding, which put 40px between the phone roster's devices,
    // and not nothing, which let the hover lift bleed past the plate's edge
    // (the runtime harness pins it inside). 6px holds the 4.4px lift.
    readonly property real selfSurfacedInset: Appearance.spacing.space75
    Layout.fillWidth: true
    implicitHeight: col.implicitHeight

    // Which rows are drawn, in declaration order. A binding rather than a
    // function so that a row flipping its own `rowVisible` re-rounds the group:
    // the outer corners belong to the first and last row ON SCREEN, and reading
    // `isFirst` off the declared index leaves a hidden row holding the group's
    // rounding while the row above it is drawn square.
    readonly property var drawnIndices: {
        const drawn = [];
        // A model's rows are all drawn: `rowVisible` is a declared row's way of
        // leaving the group, and a model leaves by not carrying the entry.
        if (root.modelDriven) {
            const count = root.model?.length ?? 0;
            for (let i = 0; i < count; i++)
                drawn.push(i);
            return drawn;
        }
        for (let i = 0; i < root.items.length; i++) {
            const item = root.items[i];
            if (item && (item.rowVisible ?? true))
                drawn.push(i);
        }
        return drawn;
    }

    ColumnLayout {
        id: col
        anchors.fill: parent
        spacing: root.cohesive ? 0 : Appearance.spacing.space25

        Repeater {
            model: root.modelDriven ? root.model : root.items.length
            delegate: Rectangle {
                id: plate
                required property int index
                required property var modelData
                readonly property bool isFirst: index === root.drawnIndices[0]
                readonly property bool isLast: index === root.drawnIndices[root.drawnIndices.length - 1]
                // A `ColumnLayout` leaves an invisible child out of the layout
                // entirely, so this is what takes the plate's height AND the
                // spacing beside it out of the group rather than collapsing one
                // and leaving the other.
                visible: root.drawnIndices.indexOf(index) !== -1
                Layout.fillWidth: true
                // The plate's vertical padding is the room a plain row's text
                // gets on the plate. A row that paints its OWN surface has
                // its own padding already, and the plate behind it is
                // transparent - so the padding showed as 24px of nothing
                // between the device rows of the phone roster.
                implicitHeight: (root.modelDriven
                    ? (rowLoader.item?.implicitHeight ?? 0)
                    : (root.items[index]?.implicitHeight ?? 0))
                    + (ownsItsSurface ? root.selfSurfacedInset * 2 : root.itemVerticalPadding)
                // A row that takes the plate's corners is a row that paints its
                // own background - that is what the corner protocol below is
                // FOR, since a plate cannot show through an opaque row. Such a
                // row IS the plate: painting a second surface behind it leaves
                // only the inset showing, as a ring of `bgcolor` around every
                // row. With several rows that ring passes for the group's seam
                // material; with one row the ring is the entire group, and the
                // device roster shipped looking like a frame drawn around a
                // single item for no reason.
                readonly property bool ownsItsSurface: rowLoader.item?.cornerTopLeft !== undefined
                color: ownsItsSurface ? "transparent" : root.bgcolor
                topLeftRadius:     isFirst ? root.bigRadius : (root.cohesive ? 0 : root.smallRadius)
                topRightRadius:    isFirst ? root.bigRadius : (root.cohesive ? 0 : root.smallRadius)
                bottomLeftRadius:  isLast  ? root.bigRadius : (root.cohesive ? 0 : root.smallRadius)
                bottomRightRadius: isLast  ? root.bigRadius : (root.cohesive ? 0 : root.smallRadius)

                Component.onCompleted: {
                    if (root.modelDriven)
                        return;
                    const child = root.items[index]
                    if (child) {
                        child.parent = contentArea
                        child.Layout.fillWidth = true
                    }
                }

                ColumnLayout {
                    id: contentArea
                    // The inset stays whatever the group's rows have always
                    // had, INCLUDING for a row that paints itself. What made
                    // the roster look framed was the plate's colour showing
                    // through it, not the inset - and the inset is also the
                    // only room a row has to grow into when the interaction
                    // model lifts it by `hoverScale` on hover. Take it away and
                    // a hovered row grows straight past the group's edge.
                    // No inset for a row that paints itself: with the plate
                    // transparent the inset was pure gap, and stacked with
                    // the plate padding it put 24px of nothing between the
                    // phone roster's rows. The rows sit `spacing` apart - the
                    // related-but-distinct gap the group already draws - and
                    // the hover lift may overflow its plate the way every
                    // other button's does.
                    anchors { fill: parent; margins: ownsItsSurface ? root.selfSurfacedInset : Appearance.spacing.space100 }
                    spacing: 0

                    Loader {
                        id: rowLoader
                        active: root.modelDriven
                        Layout.fillWidth: true
                        sourceComponent: root.rowDelegate
                    }
                }

                // The row's data, and - for a row that paints its own
                // background, which a plate cannot show through - the plate's
                // own corners. Bindings rather than an `onLoaded` assignment so
                // that a row keeps following its entry when the model is
                // re-filtered under it instead of holding the first one it saw.
                Binding {
                    target: rowLoader.item
                    property: "modelData"
                    value: plate.modelData
                    when: rowLoader.item !== null
                }
                Binding {
                    target: rowLoader.item
                    property: "cornerTopLeft"
                    value: plate.topLeftRadius
                    when: rowLoader.item?.cornerTopLeft !== undefined
                }
                Binding {
                    target: rowLoader.item
                    property: "cornerTopRight"
                    value: plate.topRightRadius
                    when: rowLoader.item?.cornerTopRight !== undefined
                }
                Binding {
                    target: rowLoader.item
                    property: "cornerBottomLeft"
                    value: plate.bottomLeftRadius
                    when: rowLoader.item?.cornerBottomLeft !== undefined
                }
                Binding {
                    target: rowLoader.item
                    property: "cornerBottomRight"
                    value: plate.bottomRightRadius
                    when: rowLoader.item?.cornerBottomRight !== undefined
                }
            }
        }
    }
}
