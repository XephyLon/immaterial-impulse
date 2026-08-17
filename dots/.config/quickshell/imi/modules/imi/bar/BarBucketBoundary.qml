import QtQuick
import qs
import qs.modules.common

/**
 * One bucket's visible boundary while Edit Mode is on - the one thing the
 * settings chip editor genuinely did better than the bar itself, because in
 * the real bar an empty middleLayout is indistinguishable from an invisible
 * one (spec §4.2).
 *
 * It is also the bucket's drop ANCHOR: `BarEditController.dropBuckets` hands
 * this item's centre to `layout_ops.dropTarget` when the bucket has nothing
 * visible in it, which is what makes an empty bucket a valid drop target. The
 * minimum run below is why an empty bucket has a centre at all - the bucket
 * containers size themselves from their rows, so an empty one is a zero-size
 * point.
 *
 * A plain Rectangle, deliberately: it takes no input (the widgets and their
 * edit overlays keep every click), and it fades on the mode's own scalar
 * rather than a Behavior of its own - one scalar for the whole mode is the
 * contract's one-scalar rule.
 */
Rectangle {
    id: root

    property bool vertical: false
    // At least a slot's worth along the bar, so an empty bucket is visible
    // and droppable.
    readonly property real minRun: 48

    color: "transparent"
    border.width: Appearance.borderWidth.standard
    border.color: Appearance.colors.colOutlineVariant
    radius: Appearance.rounding.small
    opacity: 0.6 * GlobalStates.editProgress
    visible: GlobalStates.editProgress > 0
}
