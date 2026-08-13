import QtQuick
import Quickshell

/*
 * The calendar widget's three modes on a light field, plus the tall mode a
 * second time with the host reporting a drag.
 *
 * The structural checks can only see that the widget names WidgetCard and
 * forwards `hostDragging`. What they cannot see is whether the card the
 * composition actually builds paints anything: the widget is content-sized,
 * so a card that failed to resolve leaves a zero-size widget, and a `dragging`
 * that never arrives leaves a shadow that simply does not lift - both silent.
 * This renders the real widget and test_calendar_card.py reads the pixels.
 *
 *   CALENDAR_CARD_SHOT=/tmp/cal.png ./tests/run_calendar_probe.sh
 */
ShellRoot {
    id: harness

    readonly property string widgetUrl: Quickshell.shellPath(
        "modules/common/plugins/bundled/calendar/Widget.qml")

    // Printed for the analyser, so it needs no duplicate copy of this layout.
    readonly property int fieldTop: 80
    readonly property int columnGap: 60
    readonly property int leftMargin: 60

    FloatingWindow {
        id: window
        implicitWidth: 1180
        implicitHeight: 420
        color: "white"

        Item {
            id: field
            anchors.fill: parent

            // The grab takes THIS item, not the window: grabbing over the
            // window's own colour produces a transparent PNG whose "white"
            // reads as black to any analyser (test_card_shadow.py's trap).
            Rectangle { anchors.fill: parent; color: "#e8e6ee" }

            Row {
                x: harness.leftMargin
                y: harness.fieldTop
                spacing: harness.columnGap

                Loader { id: oneByOne; source: harness.widgetUrl }
                Loader { id: twoByOne; source: harness.widgetUrl }
                Loader { id: twoByTwo; source: harness.widgetUrl }
                // The same card the host is dragging: its shadow lifts.
                Loader { id: dragged; source: harness.widgetUrl }
            }
        }
    }

    Timer {
        running: true
        interval: 900
        onTriggered: {
            // Assigning breaks the PluginState binding, which is exactly what
            // the widget's own handles do for live feedback.
            oneByOne.item.sizeMode = "1x1";
            twoByOne.item.sizeMode = "2x1";
            twoByTwo.item.sizeMode = "2x2";
            dragged.item.sizeMode = "2x2";
            dragged.item.hostDragging = true;
            shotTimer.start();
        }
    }

    Timer {
        id: shotTimer
        interval: 900
        onTriggered: {
            const shot = Quickshell.env("CALENDAR_CARD_SHOT") || "";
            if (shot === "") {
                console.log("[CalendarCard] FAIL: CALENDAR_CARD_SHOT unset");
                Qt.quit();
                return;
            }
            const boxes = [oneByOne, twoByOne, twoByTwo, dragged].map(
                loader => `${Math.round(loader.x + harness.leftMargin)},`
                    + `${harness.fieldTop},${Math.round(loader.width)},`
                    + `${Math.round(loader.height)}`);
            console.log(`[CalendarCard] layout ${boxes.join(" ")}`);
            // A strip of untouched field, well below the tallest card. The
            // field is not white after the grab - a shadow has to be measured
            // as darker than THIS, not as darker than zero, or an assertion
            // written against zero passes on a card with no shadow at all.
            console.log(`[CalendarCard] baseline ${harness.leftMargin},`
                + `${window.implicitHeight - 40},236,14`);
            field.grabToImage(result => {
                result.saveToFile(shot);
                console.log("[CalendarCard] saved");
                Qt.quit();
            });
        }
    }
}
