import QtQuick
import Quickshell
import qs.modules.common

/*
 * The five older bundled widgets, measured rather than spelled.
 *
 * `WidgetCardShadowProbe.qml` renders three WidgetCards; this renders the five
 * widgets that were never cards - the cookie clock, the pixel clock, the
 * shape-masked image, the user card and the world clock - each one three
 * times: at rest, handled, and with its elevation suppressed. The analyser
 * (tests/test_widget_elevation.py) reads the strip under each specimen, so
 * whatever a widget happens to paint there is present in all three columns and
 * only the shadow differs between them.
 *
 * The three columns are driven duck-typed - `hostDragging` for the drag, and
 * `motionActive` on anything exposing `shadowVisible` for the suppressed
 * column - so the probe needs no test-only property on any widget.
 *
 *   ./tests/run_widget_elevation_probe.sh
 */
ShellRoot {
    id: harness

    readonly property string bundled: Quickshell.shellPath("modules/common/plugins/bundled")

    // Sizes are each widget's own: the cookie is a 230px dial, the pixel clock
    // a 276x252 glyph grid, and the three grid widgets their manifest spans.
    readonly property var specimens: [
        { tag: "clock", source: harness.bundled + "/clock/CookieClock.qml", w: 230, h: 230 },
        { tag: "pixel-clock", source: harness.bundled + "/clock/PixelClock.qml", w: 276, h: 252 },
        { tag: "custom-image", source: harness.bundled + "/custom-image/Widget.qml", w: 200, h: 200 },
        { tag: "user-card", source: harness.bundled + "/user-card/Widget.qml", w: 276, h: 228 },
        { tag: "world-clock", source: harness.bundled + "/world-clock/Widget.qml", w: 276, h: 228 }
    ]
    readonly property var columns: ["rest", "handled", "still"]

    readonly property int originX: 40
    readonly property int originY: 40
    readonly property int pitchX: 320
    readonly property int pitchY: 300

    function suppress(item) {
        if (!item)
            return;
        if (item.shadowVisible !== undefined && item.motionActive !== undefined)
            item.motionActive = true;
        for (const child of item.children)
            harness.suppress(child);
    }

    FloatingWindow {
        id: window
        implicitWidth: harness.originX * 2 + harness.pitchX * harness.columns.length
        implicitHeight: harness.originY * 2 + harness.pitchY * harness.specimens.length
        color: "white"

        Item {
            id: field
            anchors.fill: parent

            // The grab takes THIS item, not the window, so the field carries
            // its own ground - grabbing over the window's colour produces a
            // transparent PNG whose "white" reads as black to any analyser.
            Rectangle {
                anchors.fill: parent
                color: "white"
            }

            Repeater {
                model: harness.specimens.length * harness.columns.length

                Item {
                    id: cell
                    required property int index
                    readonly property int row: Math.floor(cell.index / harness.columns.length)
                    readonly property int column: cell.index % harness.columns.length
                    readonly property var specimen: harness.specimens[cell.row]

                    x: harness.originX + cell.column * harness.pitchX
                    y: harness.originY + cell.row * harness.pitchY
                    width: cell.specimen.w
                    height: cell.specimen.h

                    Loader {
                        anchors.fill: parent
                        source: cell.specimen.source
                        onLoaded: {
                            if (cell.column === 1 && item.hostDragging !== undefined)
                                item.hostDragging = true;
                            if (cell.column === 1 && item.dragging !== undefined)
                                item.dragging = true;
                            if (cell.column === 2)
                                harness.suppress(item);
                        }
                    }
                }
            }
        }
    }

    // The measuring happens outside: ItemGrabResult.image is not scriptable
    // from QML, so the probe renders and saves, and test_widget_elevation.py
    // reads the pixels. The layout is printed so the analyser needs no
    // duplicate copy of it.
    Timer {
        running: true
        interval: 2500
        onTriggered: {
            const shot = Quickshell.env("WIDGET_ELEVATION_SHOT") || "";
            if (shot === "") {
                console.log("[WidgetElevation] FAIL: WIDGET_ELEVATION_SHOT unset");
                Qt.quit();
                return;
            }
            for (let row = 0; row < harness.specimens.length; row++) {
                const specimen = harness.specimens[row];
                console.log(`[WidgetElevation] specimen ${specimen.tag} `
                    + `y=${harness.originY + row * harness.pitchY} `
                    + `w=${specimen.w} h=${specimen.h}`);
            }
            for (let column = 0; column < harness.columns.length; column++)
                console.log(`[WidgetElevation] column ${harness.columns[column]} `
                    + `x=${harness.originX + column * harness.pitchX}`);
            field.grabToImage(result => {
                result.saveToFile(shot);
                console.log("[WidgetElevation] saved");
                Qt.quit();
            });
        }
    }
}
