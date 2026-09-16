import qs.modules.common
import QtQuick

/**
 * A standalone pill in the bar - the submap indicator, the timer, the
 * active mode: a pill on the group pill's centre line that fades and
 * scales with `shown` and dims while hovered, sized to the content
 * declared inside it (a RowLayout across, a ColumnLayout when the bar is
 * vertical). Three widgets carried this block verbatim, comments included.
 */
Rectangle {
    id: pill

    property bool vertical: false
    property bool shown: true
    // Dims to say "this is pressable" while the widget's pointer area is over it.
    property bool dimmed: false
    // Air beside the content across the bar (the privacy pill is tighter).
    property real horizontalPadding: Appearance.spacing.space150
    default property alias content: slot.data

    anchors.centerIn: parent
    // The pill belongs to the group pill's footprint, not the bar's - shift
    // onto the group pill's centre along the bar's thickness.
    anchors.verticalCenterOffset: pill.vertical ? 0 : Appearance.sizes.barStandalonePillOffset
    anchors.horizontalCenterOffset: pill.vertical ? Appearance.sizes.barStandalonePillOffset : 0
    radius: Appearance.rounding.full
    // Fade + scale with the show/hide so it eases in and out.
    opacity: pill.shown ? (pill.dimmed ? 0.88 : 1) : 0
    scale: pill.shown ? 1 : 0.7
    transformOrigin: Item.Center
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    Behavior on scale {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    implicitWidth: slot.implicitWidth + (pill.vertical ? Appearance.spacing.space50 : pill.horizontalPadding) * 2
    // A badge inside the group pill, not a group pill of its own.
    implicitHeight: pill.vertical
        ? slot.implicitHeight + Appearance.spacing.space50 * 2
        : Appearance.sizes.barStandalonePillHeight

    // Sized from the VISIBLE content: a widget declares a row for the
    // horizontal bar and a column for the vertical one and hides the other,
    // and childrenRect counts a hidden child (measured: a 120px hidden row
    // widened a 30px vertical pill to 142).
    Item {
        id: slot
        anchors.centerIn: parent
        implicitWidth: {
            let w = 0;
            for (let i = 0; i < slot.children.length; i++) {
                const c = slot.children[i];
                if (c.visible) w = Math.max(w, c.implicitWidth);
            }
            return w;
        }
        implicitHeight: {
            let h = 0;
            for (let i = 0; i < slot.children.length; i++) {
                const c = slot.children[i];
                if (c.visible) h = Math.max(h, c.implicitHeight);
            }
            return h;
        }
    }
}
