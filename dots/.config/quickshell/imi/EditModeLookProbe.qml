import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets.widgetCanvas
import qs.modules.imi.background
import qs.modules.imi.editMode
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
 * - the PICTURE's corner is CUT. There is no rounded clip in QML, so the corner
 *   is made by covering it with the backdrop, and "did the cover land on the
 *   corner" is a question about one pixel. `cornerMarker` is pinned to the
 *   wallpaper viewport's own top-left corner so the answer does not depend on
 *   the picture's content.
 * - ...and a WIDGET's corner is not. The cover sits below the widget canvas, so
 *   a widget the user parked against the desktop's corner overhangs the
 *   rounding instead of losing a bite to it. `cornerWidget` is that widget,
 *   pinned to the canvas's bottom-left corner because that is where this
 *   machine's own store keeps `visualizer` (0,1200 on a 1440-tall screen).
 * - the lattice arrives with the DRAG, not with the mode. Three frames say it:
 *   in the mode at rest there are no lines, mid-drag there are, and the frame
 *   after the drag ends is the same picture as the one before it started.
 * - the lattice is a SUBSTRATE. The desktop widgets arrive as external children
 *   of the canvas, so nothing in WidgetCanvas.qml decides whether they are drawn
 *   over the grid; an opaque widget must hide the lines under it completely.
 * - the chrome KEEPS OFF the bar and the dock. Two opaque bands stand in for
 *   them on the two edges the mode may not draw on, under the chrome rather
 *   than over it, so an overlap paints the toolbar's own colour inside a band
 *   instead of being hidden by it.
 * - the card's edge FALLS OFF its crest. The wallpaper here is flat, so every
 *   level in the band across that edge is the bevel and nothing else - which is
 *   the one place a profile through it can be read without the picture in the
 *   way.
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
    readonly property real edgeMargin: Appearance.sizes.editModeEdgeMargin
    readonly property real chromeThickness: Appearance.sizes.toolbarHeight

    // What the bar and the dock occupy. `EditModeInsets` answers this on the
    // real shell from the two panels' configuration; here they are literals,
    // and they are the numbers this machine's compositor actually reports
    // (`hyprctl layers`: quickshell:bar at y=5 h=63, quickshell:dock 75 tall).
    // Deliberately UNEQUAL, because a top and a bottom inset that match are
    // indistinguishable from a symmetric margin and every "which edge did you
    // subtract" bug passes on them.
    readonly property real insetTop: parseFloat(Quickshell.env("EDIT_MODE_INSET_TOP") || "68")
    readonly property real insetBottom: parseFloat(Quickshell.env("EDIT_MODE_INSET_BOTTOM") || "75")

    // The one thing that moves. Driven directly rather than through a Behavior:
    // every frame here is a settled one, and a curve sampled mid-flight is a
    // working animation reading as a wrong geometry.
    property real editProgress: 0

    readonly property var viewport: EditMode.viewportGeometry({
        screenWidth: harness.screenWidth,
        screenHeight: harness.screenHeight,
        drawerWidth: harness.drawerWidth,
        margin: harness.margin,
        edgeMargin: harness.edgeMargin,
        chromeThickness: harness.chromeThickness,
        insetTop: harness.insetTop,
        insetBottom: harness.insetBottom
    })
    readonly property var applied: EditMode.atProgress(harness.viewport, harness.editProgress)
    readonly property rect card: EditMode.cardRect(harness.viewport, harness.editProgress,
        harness.screenWidth, harness.screenHeight)
    readonly property rect area: EditMode.areaRect(harness.viewport, harness.editProgress,
        harness.screenWidth, harness.screenHeight)
    readonly property real cardRadius: Appearance.rounding.verylarge * harness.editProgress

    // Opaque and unmistakable: the two pixel questions are "is this the marker"
    // rather than "is this a colour the wallpaper might also be".
    readonly property color cornerMarkerColor: "#ff00ff"
    readonly property color opaquePanelColor: "#00ff88"
    readonly property color cornerWidgetColor: "#ffcc00"
    readonly property color reservedColor: "#ff4400"

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

                // Part of the PICTURE, pinned to the viewport's own top-left
                // corner, which is the card's top-left corner at every scale.
                // In the wallpaper layer rather than on the canvas because the
                // rounding is the picture's now: without a cut this reaches the
                // card's corner pixel, with one the backdrop does. It is not
                // what the backdrop samples (that is the Image alone), so the
                // pixel the cut reveals is blurred wallpaper rather than a
                // blurred marker.
                Rectangle {
                    id: cornerMarker
                    x: 0
                    y: 0
                    width: 220
                    height: 220
                    color: harness.cornerMarkerColor
                }
            }

            WidgetCanvas {
                id: widgetCanvas
                anchors.fill: parent
                z: 2
                editMode: harness.editProgress > 0.99
                selectionEnabled: true
                transform: Matrix4x4 { matrix: harness.matrix }

                // A widget the user parked in the desktop's bottom-left corner,
                // which is where this machine's own plugin-state.json keeps
                // `visualizer` - the case the mode was cutting. Opaque for the
                // same reason opaquePanel is: a translucent one cannot say
                // whether its corner survived or the backdrop is showing
                // through it.
                Rectangle {
                    id: cornerWidget
                    x: 0
                    y: widgetCanvas.height - height
                    width: 240
                    height: 200
                    color: harness.cornerWidgetColor
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

            // BELOW widgetCanvas (z 2), which is the arrangement Background.qml
            // has: the cover rounds the picture and the widgets draw over it
            // uncut. test_edit_mode_contract.py pins this z against
            // Background.qml's, because a probe re-declaring the arrangement can
            // score one the shell does not have - and it did, for exactly one
            // render of this fix.
            Loader {
                id: editChrome
                active: harness.editProgress > 0
                anchors.fill: parent
                z: 1
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

            // The mode's chrome. On the real shell this is a layer surface of
            // its own on Overlay, because the bar and the dock sit above the
            // background - none of which weston can show, so what is rebuilt
            // here is the arrangement (a full-screen item over the card, at the
            // card's own geometry) and the content is the shipped component.
            // Stand-ins for the bar and the dock: opaque bands on the two edges
            // the mode must not draw on. UNDER the chrome (z 3 against 5), so
            // an overlap paints the toolbar's own colour inside a band and the
            // pixel half can see it. Drawn at all, rather than left as two
            // numbers, because a saved frame with them in it is a frame a human
            // can judge the clearance in.
            Rectangle {
                z: 3
                x: 0; y: 0
                width: field.width
                height: harness.insetTop
                color: harness.reservedColor
            }
            Rectangle {
                z: 3
                x: 0
                y: field.height - harness.insetBottom
                width: field.width
                height: harness.insetBottom
                color: harness.reservedColor
            }

            Loader {
                id: chromeLoader
                active: harness.editProgress > 0
                anchors.fill: parent
                z: 5
                opacity: harness.editProgress
                sourceComponent: EditModeChromeContent {
                    card: harness.card
                    area: harness.area
                    bandFraction: EditMode.chromeBandFraction(harness.viewport)
                }
            }
        }
    }

    // The chrome's toolbar, when there is one. Reached through the loader
    // rather than held as an id, since it does not exist at rest.
    readonly property Item toolbar: chromeLoader.item?.toolbarItem ?? null

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
            + ` corner=${cornerWidget.x},${cornerWidget.y},${cornerWidget.width},${cornerWidget.height}`
            + ` markerColor=${harness.cornerMarkerColor} panelColor=${harness.opaquePanelColor}`
            + ` cornerColor=${harness.cornerWidgetColor}`
            + ` toolbar=${harness.toolbar?.x ?? -1},${harness.toolbar?.y ?? -1}`
            + `,${harness.toolbar?.width ?? 0},${harness.toolbar?.height ?? 0}`
            + ` area=${harness.area.x},${harness.area.y},${harness.area.width},${harness.area.height}`
            + ` reserved=${harness.insetTop},${harness.insetBottom}`
            + ` chromeColor=${Appearance.m3colors.m3surfaceContainer}`);
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
                !editChrome.active && !chromeLoader.active);
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
        // Dead centre OF THE USABLE AREA, with room on each side for the drawer
        // to translate the desktop into later. A shrink that opened one edge is
        // a crop, and one that opened three is the desktop being shoved aside.
        // Measured against the area rather than the screen because the two stop
        // being the same rectangle the moment the bar and the dock are
        // subtracted, and the whole point is that the desktop sits in what is
        // left rather than in the middle of a panel it overlaps.
        const freeX = harness.area.x + harness.area.width - (harness.card.x + harness.card.width);
        const freeY = harness.area.y + harness.area.height - (harness.card.y + harness.card.height);
        harness.check("...about dead centre of the usable area, with room for the drawer",
            Math.abs((harness.card.x - harness.area.x) - freeX) < 0.5
                && Math.abs((harness.card.y - harness.area.y) - freeY) < 0.5
                && harness.card.x - harness.area.x >= harness.drawerWidth / 2 + harness.margin - 0.5
                && harness.card.y - harness.area.y >= harness.margin - 0.5,
            `card=${harness.card.x.toFixed(1)},${harness.card.y.toFixed(1)}`
                + ` ${harness.card.width.toFixed(1)}x${harness.card.height.toFixed(1)}`
                + ` area=${harness.area.y.toFixed(1)}+${harness.area.height.toFixed(1)}`);
        // The chrome frames the desktop, so it has to be OUTSIDE it: a toolbar
        // overlapping the card covers the widgets it exists to help arrange,
        // and one that has left the screen is not there at all. Both bands are
        // opened by the shrink itself, which is why this is asserted against
        // the card rather than against a chosen inset.
        harness.check("the toolbar sits in the band the shrink opened above the desktop",
            harness.toolbar !== null
                && harness.toolbar.y >= 0
                && harness.toolbar.y + harness.toolbar.height <= harness.card.y + 0.5,
            `toolbar=${harness.toolbar?.y.toFixed(1)}+${harness.toolbar?.height.toFixed(1)}`
                + ` band=${harness.card.y.toFixed(1)}`);
        // ...and clear of the two edges the bar and the dock own, by the edge
        // margin at each end. This is the check stage 4 did not have: its bands
        // were whatever the ceiling left over, so the toolbar started 22px into
        // a screen whose bar occupies the first 68 and the tab bar landed on the
        // dock. Asserted against the reserved insets rather than against the
        // area, so it cannot be satisfied by an area that forgot to subtract
        // them.
        //
        // The gap is `edgeMargin`, not `margin`: the band is asymmetric, with
        // the tight gap on the outside against the panel and the generous one
        // on the inside against the desktop. Clearing the panel is what this
        // check is about, so it is the outer number that belongs here - and
        // the inner one is asserted by the band check above.
        harness.check("...clear of the bar's and the dock's own edges",
            harness.toolbar !== null && harness.tabBar !== null
                && harness.toolbar.y >= harness.insetTop + harness.edgeMargin - 0.5
                && harness.tabBar.y + harness.tabBar.height
                    <= harness.screenHeight - harness.insetBottom
                        - harness.edgeMargin + 0.5
                && harness.card.y >= harness.insetTop
                && harness.card.y + harness.card.height
                    <= harness.screenHeight - harness.insetBottom,
            `toolbar=${harness.toolbar?.y.toFixed(1)} reserved=${harness.insetTop},${harness.insetBottom}`);
        // ...and on the desktop's own axis rather than the screen's, which is
        // the same point today and stops being one when the drawer translates
        // the card. The two gaps are compared to each other because the card is
        // centred in the area: chrome that drifted toward one edge would still
        // be "inside the band".
        const gapAbove = harness.toolbar !== null ? harness.toolbar.y - harness.area.y : -1;
        const gapBelow = harness.tabBar !== null
            ? harness.area.y + harness.area.height - (harness.tabBar.y + harness.tabBar.height) : -2;
        harness.check("...centred on the desktop, in two bands of equal height",
            harness.toolbar !== null && harness.tabBar !== null
                && Math.abs((harness.toolbar.x + harness.toolbar.width / 2)
                    - (harness.card.x + harness.card.width / 2)) < 0.5
                && Math.abs((harness.tabBar.x + harness.tabBar.width / 2)
                    - (harness.card.x + harness.card.width / 2)) < 0.5
                && Math.abs(gapAbove - gapBelow) < 0.5
                // ...and both are the EDGE margin. Equal to each other alone
                // passes at any symmetric value, including the old one, so it
                // could not see the band's split arrive or leave.
                && Math.abs(gapAbove - harness.edgeMargin) < 0.5,
            `gaps=${gapAbove.toFixed(1)},${gapBelow.toFixed(1)}`
                + ` edgeMargin=${harness.edgeMargin.toFixed(1)}`);
        harness.check("in the mode at rest the lattice is down",
            !widgetCanvas.gridVisible && widgetCanvas.gridStrength === 0);
        harness.reportGeometry("geometry");
        harness.shoot("editing", () => {
            // Through the canvas's own drag reporter, which is what
            // AbstractWidget calls from onDraggingChanged - there is no QtTest
            // here to press a real button with, so the harness enters the state
            // by the same door the gesture does rather than by writing the flag
            // this check reads. The TRIGGER (press versus press-and-moved) is
            // scored with real mouse events in EditModeRuntimeTest.qml; what
            // only this probe can see is what the lattice looks like once it is
            // up, and that it leaves nothing behind when it goes.
            widgetCanvas.setDragging(true);
            harness.after(harness.dragging);
        });
    }

    function dragging(): void {
        harness.check("...and a drag brings it up",
            widgetCanvas.gridVisible && widgetCanvas.gridStrength === 1);
        harness.shoot("dragging", () => {
            widgetCanvas.setDragging(false);
            harness.after(harness.released);
        });
    }

    function released(): void {
        harness.check("...and letting go takes it away again",
            !widgetCanvas.gridVisible && widgetCanvas.gridStrength === 0);
        harness.shoot("released", () => {
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
        // Horizontally the destination is still the screen's centre, so the old
        // symmetry holds on that axis and is still asserted. Vertically it is
        // not - the card lands between a 68px band and a 75px one - so what is
        // checked there is the property that survives the re-centring and is
        // what the eye actually follows: every corner travels in a straight
        // line from the whole screen to the card, i.e. the drawn offset is the
        // settled offset times the same t the scale is at.
        const freeX = harness.screenWidth - (harness.card.x + harness.card.width);
        const t = (1 - harness.applied.scale) / (1 - harness.viewport.scale);
        harness.check("half way in, the desktop is on the straight line to its slot",
            Math.abs(harness.card.x - freeX) < 0.5
                && Math.abs(harness.card.y - harness.viewport.y * t) < 0.5
                && harness.applied.scale > harness.viewport.scale
                && harness.applied.scale < 1,
            `card=${harness.card.x.toFixed(1)},${harness.card.y.toFixed(1)}`
                + ` expectedY=${(harness.viewport.y * t).toFixed(1)}`
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
        // Its own check rather than a term in the one above: the chrome is a
        // whole surface on the real shell, and "the desktop came back" and "the
        // toolbar went away" are two different regressions.
        harness.check("...and takes the chrome with it", !chromeLoader.active
            && harness.toolbar === null && harness.tabBar === null);
        harness.shoot("after", () => harness.finish());
    }

    function finish(): void {
        console.log(`[EditModeLook] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }
}
