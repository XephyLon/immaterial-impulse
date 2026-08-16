import QtQuick
import Quickshell
import qs.modules.imi.background
import "modules/common/functions/clockDepth.js" as ClockDepthLogic

/*
 * The one invariant this feature cannot violate: with nothing underneath it,
 * turning depth ON must change nothing at all.
 *
 * The depth layer paints the wallpaper's own pixels back over the wallpaper.
 * Where no widget sits, that is drawing a picture over itself - so with the
 * widget canvas empty, depth on and depth off must be the same frame, whatever
 * the mask says. Any difference is the copy landing somewhere other than the
 * region it copies: a different crop, a different scale, a different offset.
 *
 * That oracle exists because the alternative is judging it by eye, and by eye a
 * near-miss double exposure does not read as a geometry bug. It reads as the
 * wallpaper's quality dropping - which is exactly how it was reported, and
 * exactly how a review then measured it wrong: two `grim` captures minutes
 * apart on a desktop somebody was using, with the wallpaper changed in between.
 * A single process, a pinned wallpaper and nothing but the depth flag moving
 * between the two frames is the control that was missing.
 *
 * The fixture deliberately CROPS. A wallpaper whose aspect matches its viewport
 * makes PreserveAspectCrop the identity and every crop bug invisible, which is
 * what the sibling compositing probe's 2:1-into-2:1 fixture does - so the
 * "the fixture crops" check below is load-bearing rather than decorative.
 *
 *   ./tests/run_clock_depth_noop_probe.sh
 */
ShellRoot {
    id: harness

    property int checksRun: 0
    property int failures: 0
    function check(label, ok, detail) {
        harness.checksRun++;
        console.log(`[ClockDepthNoOp] ${label}: ${ok ? "ok" : "FAIL"}${detail ? " " + detail : ""}`);
        if (!ok) harness.failures++;
    }

    readonly property string wallpaperFile: Quickshell.env("CLOCK_DEPTH_WALLPAPER") || ""
    readonly property string fullMaskFile: Quickshell.env("CLOCK_DEPTH_FULL_MASK") || ""
    readonly property string partMaskFile: Quickshell.env("CLOCK_DEPTH_PART_MASK") || ""
    readonly property string shotDir: Quickshell.env("CLOCK_DEPTH_SHOT_DIR") || ""

    // The only thing that moves between a pair of shots. Not the mask path:
    // swapping that would change two things at once and the diff could no
    // longer be attributed to the flag.
    property bool depthOn: false
    property string activeMask: harness.fullMaskFile

    FloatingWindow {
        id: window
        implicitWidth: 800
        implicitHeight: 225
        color: "black"

        Item {
            id: field
            anchors.fill: parent
            // The grab takes THIS item, so it carries its own ground: grabbing
            // over the window's colour yields a transparent PNG whose pixels
            // read as black to any analyser.
            Rectangle { anchors.fill: parent; color: "black" }

            // Oversized and offset, as the parallax viewport is at every
            // workspace but the middle one. At rest the layer and the viewport
            // are trivially level; the offset is where a copy that reconstructs
            // the position by hand can be wrong.
            Item {
                id: parallaxViewport
                width: 880
                height: 247
                x: -40
                y: -11

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

            // Deliberately empty. The widget canvas is what the depth layer
            // exists to draw over, and with anything on it the two frames
            // differ for the right reason and the invariant says nothing.
            Item {
                id: widgetCanvas
                anchors.fill: parent
                z: 2
            }

            Item {
                id: clockDepthLayer
                x: parallaxViewport.x
                y: parallaxViewport.y
                width: parallaxViewport.width
                height: parallaxViewport.height
                z: 3
                visible: clockDepthLayer.opacity > 0
                enabled: false
                opacity: ClockDepthLogic.eligible({
                    enable: harness.depthOn,
                    maskPath: harness.activeMask,
                    optedOut: false,
                    weActive: false,
                    wallpaperIsVideo: false,
                    centeredWallpaper: false,
                    screenLocked: false,
                    transitionInFlight: false
                }) ? 1 : 0

                ClockDepthCutout {
                    id: clockDepthCutout
                    anchors.fill: parent
                    wallpaperSource: wallpaper.source
                    maskPath: harness.activeMask
                }
            }
        }
    }

    function shoot(name, next) {
        field.grabToImage(result => {
            result.saveToFile(`${harness.shotDir}/${name}.png`);
            next();
        });
    }

    Timer {
        id: settle
        interval: 400
        property var next: null
        onTriggered: if (settle.next) settle.next()
    }
    function after(step) {
        settle.next = step;
        settle.restart();
    }

    Timer {
        running: true
        interval: 1000
        onTriggered: {
            harness.check("all three fixtures are on disk",
                harness.wallpaperFile !== "" && harness.fullMaskFile !== ""
                    && harness.partMaskFile !== "" && harness.shotDir !== "");
            harness.check("the wallpaper decoded",
                wallpaper.status === Image.Ready, `status=${wallpaper.status}`);
            harness.check("the mask decoded",
                clockDepthCutout.maskStatus === Image.Ready,
                `status=${clockDepthCutout.maskStatus}`);
            harness.check("the layer is exactly where the viewport is",
                clockDepthLayer.x === parallaxViewport.x
                    && clockDepthLayer.y === parallaxViewport.y
                    && clockDepthLayer.width === parallaxViewport.width
                    && clockDepthLayer.height === parallaxViewport.height);
            // Without this the whole probe can pass vacuously: at a matching
            // aspect PreserveAspectCrop crops nothing, so a layer that got the
            // scale wrong would still produce an identical frame.
            harness.check("the fixture actually crops",
                clockDepthCutout.maskRect.height > parallaxViewport.height + 1,
                `cover=${clockDepthCutout.maskRect.height.toFixed(1)} `
                    + `box=${parallaxViewport.height}`);
            harness.check("nothing is showing while depth is off",
                clockDepthLayer.opacity === 0 && !clockDepthLayer.visible,
                `opacity=${clockDepthLayer.opacity}`);
            harness.shoot("off_full", () => {
                harness.depthOn = true;
                harness.after(harness.fullOn);
            });
        }
    }

    function fullOn(): void {
        harness.check("the layer is fully opaque with an opaque mask and depth on",
            clockDepthLayer.opacity === 1 && clockDepthLayer.visible,
            `opacity=${clockDepthLayer.opacity}`);
        harness.shoot("on_full", () => {
            harness.depthOn = false;
            harness.activeMask = harness.partMaskFile;
            harness.after(harness.partOff);
        });
    }

    function partOff(): void {
        harness.check("the second mask decoded",
            clockDepthCutout.maskStatus === Image.Ready,
            `status=${clockDepthCutout.maskStatus}`);
        harness.shoot("off_part", () => {
            harness.depthOn = true;
            harness.after(harness.partOn);
        });
    }

    function partOn(): void {
        harness.shoot("on_part", () => harness.finish());
    }

    function finish(): void {
        console.log(`[ClockDepthNoOp] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.quit();
    }
}
