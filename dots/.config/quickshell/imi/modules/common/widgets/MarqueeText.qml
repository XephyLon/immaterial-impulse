import qs.modules.common
import "../functions/marquee.js" as Marquee
import QtQuick

// A single-line label that scrolls only while it does not fit, for a string
// the user needs whole: a network's name, a paired device's name, the title
// that tells one of five identical windows from the others. Everywhere the
// truncation itself is the information - a status line, a label this repo
// wrote - `StyledText { elide: ... }` is still the right widget.
//
// Every decision it makes lives in marquee.js, because nothing about the
// rendered result is reachable from a test.
Item {
    id: root

    property alias text: label.text
    property alias color: label.color
    property alias font: label.font
    // Honoured only while the text fits. There is no such thing as centring
    // something wider than its box: a centred overflow hangs off BOTH ends, so
    // the marquee would start with the first character already off screen.
    property int horizontalAlignment: Text.AlignLeft

    readonly property bool overflows: Marquee.overflows(label.implicitWidth, root.width)
    readonly property real travelDistance: Marquee.travelDistance(label.implicitWidth, root.width)

    // The gate. An animation that loops forever must stop when what it
    // animates is off screen: a running animation writes a property every
    // frame, which dirties the scene, which commits a frame, which makes the
    // compositor repaint the whole output - measured at half a fullscreen
    // game's frame rate for one spinner nobody could see. `visible` is
    // EFFECTIVE visibility, false while any ancestor is hidden, so this does
    // not have to know why it is off screen.
    //
    // Note what it deliberately does NOT cover, and why this widget is adopted
    // only on surfaces that are unmapped when idle: a surface the compositor
    // COVERS is not a surface QML considers hidden (53d1ff893 ("fix(bar): drop
    // the cava claim while a fullscreen window covers the bar")).
    readonly property bool scrolling: root.overflows && root.visible

    // The label's natural width, so a layout still sizes this the way it sized
    // the StyledText it replaced. The label is sized FROM this item and never
    // the other way round - its implicit width is a function of the string and
    // the font alone, which is what keeps the pair off the Loader/implicit-size
    // binding loop.
    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight
    clip: true

    // Parked at the first character whenever it is not travelling - a stopped
    // marquee left mid-string is a label whose beginning is missing, which is
    // worse than the elision this replaces.
    onScrollingChanged: if (!root.scrolling) label.x = 0

    StyledText {
        id: label

        width: root.width
        height: root.height
        x: 0
        // The box clips; the label must not shorten itself, or there is
        // nothing left to scroll to.
        elide: Text.ElideNone
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: root.overflows ? Text.AlignLeft : root.horizontalAlignment
    }

    SequentialAnimation {
        running: root.scrolling
        loops: Animation.Infinite

        PauseAnimation { duration: Marquee.dwell(Appearance.animation.reduceMotion) }
        MarqueeTravel { to: -root.travelDistance }
        PauseAnimation { duration: Marquee.dwell(Appearance.animation.reduceMotion) }
        MarqueeTravel { to: 0 }
    }

    // Linear is the one curve this shell may take deliberately: an eased scroll
    // reads at a speed that changes under the eye, which is the whole thing a
    // constant ms-per-pixel exists to hold still. It is spelled out rather than
    // left to Qt's default, which is the same value arrived at by nobody
    // (docs/M3_GUIDELINES.md §2).
    //
    // The duration goes through the motion policy's own door, so the speed
    // slider retimes the scroll like everything else and reduce motion collapses
    // it to a snap between the two ends. That is the whole reason the dwell
    // above is NOT scaled: at the floor the dwell is the entire cycle, and the
    // accessibility state must not produce the fastest motion in the shell.
    component MarqueeTravel: NumberAnimation {
        target: label
        property: "x"
        duration: Appearance.animation.scale(
            Marquee.travelDuration(label.implicitWidth, root.width))
        easing.type: Easing.Linear
    }
}
