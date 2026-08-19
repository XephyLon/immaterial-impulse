import QtQuick

/**
 * Where each of one bar's widgets was drawn, for exactly as long as a reflow
 * takes.
 *
 * FLIP needs a "First" - where the thing being repositioned was before the
 * layout changed - and a bar slot cannot keep it itself. Measured with a
 * `qml6` probe: a `Repeater` whose model is a JS array answers a reassignment
 * by destroying EVERY delegate and building the replacements, so the widget
 * that is about to slide is not the object that was standing there. The
 * outgoing slot deposits where it was drawn, the incoming one recalls it, and
 * the identity that survives in between is the widget id.
 *
 * ---- why one of these per content tree, and not a singleton ---------------
 *
 * The ids are the same on every screen and the positions are not: a bar's
 * right-hand bucket sits at the screen's width. A singleton would have each
 * screen's bar overwriting the others' records during the one config change
 * that reflows all of them at once, and every bar but the last would invert
 * from a position on somebody else's monitor.
 *
 * ---- why the records expire ------------------------------------------------
 *
 * A record is worth exactly one reflow. The destroy-and-rebuild burst happens
 * inside a single turn of the event loop, so a recall always beats the timer -
 * while a widget the user switches back on from Settings ten minutes later
 * finds nothing, and simply appears where it belongs instead of flying in from
 * wherever it last sat. Keeping the record would be indistinguishable from a
 * bug the moment the bar's layout had changed in between.
 */
Item {
    id: root

    // The frame every position is measured in: this item's own parent, which
    // is the content tree's root. Deliberately NOT the window - the bar's body
    // slides on its margins for auto-hide, and a frame that travelled with the
    // screen would read the slide as every slot repositioning at once.
    readonly property Item frame: root.parent

    visible: false
    width: 0
    height: 0

    // widgetId -> { x, y }, in `frame` coordinates.
    property var positions: ({})

    function deposit(widgetId, point) {
        if (!widgetId || !point) return;
        root.positions[widgetId] = point;
        expiry.restart();
    }

    function recall(widgetId) {
        if (!widgetId) return null;
        const point = root.positions[widgetId];
        return point === undefined ? null : point;
    }

    Timer {
        id: expiry
        // Zero, not a duration: "the rest of this turn of the event loop" is
        // the whole life of a record, and a real interval would be a guess at
        // how long a rebuild takes.
        interval: 0
        onTriggered: root.positions = ({})
    }
}
