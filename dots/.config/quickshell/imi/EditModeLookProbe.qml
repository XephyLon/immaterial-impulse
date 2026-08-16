import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets.widgetCanvas
import qs.modules.imi.background
import "modules/common/functions/edit_mode.js" as EditMode

/*
 * What Edit Mode's desktop looks like, in pixels.
 *
 * The mode is a transform on three siblings of a wlr-layer-shell PanelWindow,
 * and weston implements no layer shell - so the four-sibling arrangement is
 * re-declared here the way ClockDepthProbe re-declares the depth layer's, with
 * the real `EditModeCard`, the real `WidgetCanvas` and the real `edit_mode.js`
 * doing the work. What is re-declared is the arrangement; nothing about the
 * chrome or the lattice is copied, because a copy is a second thing to be wrong
 * and the point here is to score what ships.
 *
 * This half asserts the geometry and saves three frames. The pixels are scored
 * by tests/test_edit_mode_chrome.py: `ItemGrabResult.image` is a QImage and a
 * QImage is not scriptable from QML, so analysis belongs outside - the same
 * split test_card_shadow.py already runs on.
 *
 * The three frames answer the three questions no source check can:
 *
 * - the chrome stands down COMPLETELY on exit. `rest` and `after` must be the
 *   same picture, which is the only check that catches a radius, a shadow or a
 *   matrix left applied to the live desktop. A property assertion cannot: an
 *   inactive Loader and a zeroed radius are what a still-transformed viewport
 *   reports too.
 * - the desktop's corner is CUT. There is no rounded clip in QML, so the corner
 *   is made by covering it with the backdrop, and "did the cover land on the
 *   corner" is a question about one pixel. `cornerMarker` is pinned to the
 *   canvas's own top-left corner so the answer does not depend on the picture.
 * - the lattice is a SUBSTRATE. The desktop widgets arrive as external children
 *   of the canvas, so nothing in WidgetCanvas.qml decides whether they are drawn
 *   over the grid; an opaque widget must hide the lines under it completely.
 *
 * The wallpaper is whatever EDIT_MODE_WALLPAPER names, so the same probe serves
 * the synthetic fixture the suite runs and a real photograph a human looks at.
 * No check reads the wallpaper's own pixels.
 *
 *   EDIT_MODE_WALLPAPER=... EDIT_MODE_SHOT_DIR=... ./tests/run_edit_mode_look_probe.sh
 */
ShellRoot {
    id: harness

    property int checksRun: 0
    property int failures: 0
    function check(label, ok, detail) {
        harness.checksRun++;
        console.log(`[EditModeLook] ${label}: ${ok ? "ok" : "FAIL"}${detail ? " " + detail : ""}`);
        if (!ok) harness.failures++;
    }

    readonly property string wallpaperFile: Quickshell.env("EDIT_MODE_WALLPAPER") || ""
    readonly property string shotDir: Quickshell.env("EDIT_MODE_SHOT_DIR") || ""
    readonly property int screenWidth: parseInt(Quickshell.env("EDIT_MODE_WIDTH") || "1600")
    readonly property int screenHeight: parseInt(Quickshell.env("EDIT_MODE_HEIGHT") || "900")

    readonly property real drawerWidth: Appearance.sizes.editModeDrawerWidth
    readonly property real margin: Appearance.sizes.editModeMargin

    // The one thing that moves. Driven directly rather than through a Behavior:
    // every frame here is a settled one, and a curve sampled mid-flight is a
    // working animation reading as a wrong geometry.
    property real editProgress: 0

    readonly property var viewport: EditMode.viewportGeometry({
        screenWidth: harness.screenWidth,
        screenHeight: harness.screenHeight,
        drawerWidth: harness.drawerWidth,
        margin: harness.margin
    })
    readonly property var applied: EditMode.atProgress(harness.viewport, harness.editProgress)
    readonly property rect card: EditMode.cardRect(harness.viewport, harness.editProgress,
        harness.screenWidth, harness.screenHeight)
    readonly property real cardRadius: Appearance.rounding.verylarge * harness.editProgress

    // Opaque and unmistakable: the two pixel questions are "is this the marker"
    // rather than "is this a colour the wallpaper might also be".
    readonly property color cornerMarkerColor: "#ff00ff"
    readonly property color opaquePanelColor: "#00ff88"

    FloatingWindow {
        id: window
        implicitWidth: harness.screenWidth
        implicitHeight: harness.screenHeight
        color: "black"

        Item {
            id: field
            anchors.fill: parent
            // The grab takes THIS item, so it carries its own ground: grabbing
            // over the window's colour yields a transparent PNG whose "white"
            // reads as black to any analyser.
            Rectangle { anchors.fill: parent; color: "black"; z: -3 }

            Item {
                id: parallaxViewport
                anchors.fill: parent
                transform: Matrix4x4 { matrix: harness.matrix }

                Image {
                    id: wallpaper
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    cache: true
                    smooth: true
                    asynchronous: false
                    source: harness.wallpaperFile === "" ? "" : `file://${harness.wallpaperFile}`
                }
            }

            WidgetCanvas {
                id: widgetCanvas
                anchors.fill: parent
                z: 2
                editMode: harness.editProgress > 0.99
                selectionEnabled: true
                transform: Matrix4x4 { matrix: harness.matrix }

                // Pinned to the canvas's own top-left corner, which is the
                // card's top-left corner at every scale. Without a cut it
                // reaches the card's corner pixel; with one, the backdrop does.
                Rectangle {
                    id: cornerMarker
                    x: 0
                    y: 0
                    width: 220
                    height: 220
                    color: harness.cornerMarkerColor
                }

                // Opaque on purpose: a translucent panel cannot say whether the
                // lattice is under it or over it, because either way the line
                // shows through.
                Rectangle {
                    id: opaquePanel
                    x: 520
                    y: 300
                    width: 260
                    height: 180
                    radius: Appearance.rounding.normal
                    color: harness.opaquePanelColor
                }

                // What a desktop widget actually looks like: a translucent card
                // on the wallpaper. Here to be looked at, not to be measured.
                Repeater {
                    model: [
                        { wx: 130, wy: 420, ww: 300, wh: 200 },
                        { wx: 860, wy: 140, ww: 340, wh: 240 },
                        { wx: 900, wy: 520, ww: 240, wh: 150 }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        x: modelData.wx
                        y: modelData.wy
                        width: modelData.ww
                        height: modelData.wh
                        radius: Appearance.rounding.normal
                        color: Qt.alpha(Appearance.colors.colLayer1, 0.35)
                        border.width: Appearance.borderWidth.standard
                        border.color: Appearance.colors.colLayer0Border
                    }
                }
            }

            Loader {
                id: editChrome
                active: harness.editProgress > 0
                anchors.fill: parent
                z: 4
                enabled: false
                opacity: harness.editProgress
                sourceComponent: EditModeCard {
                    wallpaperLayer: wallpaper
                    blurRadius: Config.options.lock.blur.radius
                    blurSamples: Config.options.lock.blur.size
                    card: harness.card
                    cardRadius: harness.cardRadius
                }
            }
        }
    }

    readonly property matrix4x4 matrix: Qt.matrix4x4(
        harness.applied.scale, 0, 0, harness.applied.x,
        0, harness.applied.scale, 0, harness.applied.y,
        0, 0, 1, 0,
        0, 0, 0, 1)

    // Everything the pixel half needs to know where to look, so it holds no
    // copy of the geometry it is scoring.
    function reportGeometry(tag): void {
        console.log(`[EditModeLook] ${tag}: screen=${harness.screenWidth},${harness.screenHeight}`
            + ` card=${harness.card.x},${harness.card.y},${harness.card.width},${harness.card.height}`
            + ` radius=${harness.cardRadius} scale=${harness.applied.scale}`
            + ` marker=${cornerMarker.x},${cornerMarker.y},${cornerMarker.width},${cornerMarker.height}`
            + ` panel=${opaquePanel.x},${opaquePanel.y},${opaquePanel.width},${opaquePanel.height}`
            + ` markerColor=${harness.cornerMarkerColor} panelColor=${harness.opaquePanelColor}`);
    }

    function shoot(name, next) {
        field.grabToImage(result => {
            result.saveToFile(`${harness.shotDir}/${name}.png`);
            next();
        });
    }

    Timer {
        id: settle
        interval: 500
        property var next: null
        onTriggered: if (settle.next) settle.next()
    }
    function after(step) {
        settle.next = step;
        settle.restart();
    }

    Timer {
        running: true
        interval: 1200
        onTriggered: {
            harness.check("the fixture is on disk, decoded, and there is somewhere to shoot",
                harness.wallpaperFile !== "" && harness.shotDir !== ""
                    && wallpaper.status === Image.Ready,
                `status=${wallpaper.status}`);
            harness.check("at rest the card is the whole screen, square",
                harness.card.x === 0 && harness.card.y === 0
                    && harness.card.width === harness.screenWidth
                    && harness.card.height === harness.screenHeight
                    && harness.cardRadius === 0);
            harness.check("at rest there is no chrome to stand down",
                !editChrome.active);
            harness.shoot("rest", () => {
                harness.editProgress = 1;
                harness.after(harness.editing);
            });
        }
    }

    function editing(): void {
        harness.check("the mode shrinks the desktop enough to read as an object",
            harness.applied.scale <= EditMode.MAX_SCALE + 1e-9
                && harness.applied.scale > EditMode.MIN_SCALE,
            `scale=${harness.applied.scale.toFixed(3)}`);
        // Dead centre, with room on each side for the drawer to translate the
        // desktop into later. A shrink that opened one edge is a crop, and one
        // that opened three is the desktop being shoved aside.
        const freeX = harness.screenWidth - (harness.card.x + harness.card.width);
        const freeY = harness.screenHeight - (harness.card.y + harness.card.height);
        harness.check("...about dead centre, with room for the drawer on each side",
            Math.abs(harness.card.x - freeX) < 0.5
                && Math.abs(harness.card.y - freeY) < 0.5
                && harness.card.x >= harness.drawerWidth / 2 + harness.margin - 0.5
                && harness.card.y >= harness.margin - 0.5,
            `card=${harness.card.x.toFixed(1)},${harness.card.y.toFixed(1)}`
                + ` ${harness.card.width.toFixed(1)}x${harness.card.height.toFixed(1)}`);
        harness.reportGeometry("geometry");
        harness.shoot("editing", () => {
            harness.editProgress = 0.5;
            harness.after(harness.midway);
        });
    }

    function midway(): void {
        // The correction the centring is for is about the ENTRY, not about
        // where the desktop ends up: a geometry that reserved the drawer's
        // width on one side was symmetric nowhere, and the frames nobody looks
        // at are the ones in between. Held at half progress and photographed,
        // so the pixel half can measure where the desktop is actually drawn
        // rather than read the number back out of the same function.
        const freeX = harness.screenWidth - (harness.card.x + harness.card.width);
        const freeY = harness.screenHeight - (harness.card.y + harness.card.height);
        harness.check("half way in, the desktop is still dead centre",
            Math.abs(harness.card.x - freeX) < 0.5 && Math.abs(harness.card.y - freeY) < 0.5
                && harness.applied.scale > harness.viewport.scale
                && harness.applied.scale < 1,
            `card=${harness.card.x.toFixed(1)},${harness.card.y.toFixed(1)}`
                + ` scale=${harness.applied.scale.toFixed(3)}`);
        harness.reportGeometry("midGeometry");
        harness.shoot("midway", () => {
            harness.editProgress = 0;
            harness.after(harness.left);
        });
    }

    function left(): void {
        harness.check("leaving puts the card back to the whole screen, square, unchromed",
            harness.card.x === 0 && harness.card.y === 0
                && harness.card.width === harness.screenWidth
                && harness.cardRadius === 0
                && !editChrome.active);
        harness.shoot("after", () => harness.finish());
    }

    function finish(): void {
        console.log(`[EditModeLook] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }
}
