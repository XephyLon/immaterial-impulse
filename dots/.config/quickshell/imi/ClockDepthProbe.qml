import QtQuick
import Quickshell
import Qt5Compat.GraphicalEffects
import "modules/common/functions/clockDepth.js" as ClockDepthLogic

/*
 * Does the depth layer actually put the wallpaper's subject over the clock, and
 * does it follow the pan rather than the pan's destination?
 *
 * Both are invisible from the source and unreachable from qmltestrunner - the
 * software scene graph draws no layer effect, and Quickshell's own types cannot
 * be constructed there at all. So this renders the four-sibling stack with a
 * SYNTHETIC mask: a known rectangle over a flat field, with a bar standing in
 * for the clock underneath it. No model is ever run; what is being scored is the
 * compositing contract, not any mask's quality.
 *
 * The layer is re-declared here rather than reached into, because
 * Background.qml's is inside a wlr-layer-shell PanelWindow and weston implements
 * no layer shell. tests/lint_clock_depth_geometry.py is the other half of that
 * split: it pins the real layer's geometry, gates and image request to the shape
 * this probe scores.
 *
 *   ./tests/run_clock_depth_probe.sh
 */
ShellRoot {
    id: harness

    property int checksRun: 0
    property int failures: 0
    function check(label, ok, detail) {
        harness.checksRun++;
        console.log(`[ClockDepth] ${label}: ${ok ? "ok" : "FAIL"}${detail ? " " + detail : ""}`);
        if (!ok) harness.failures++;
    }

    readonly property string wallpaperFile: Quickshell.env("CLOCK_DEPTH_WALLPAPER") || ""
    readonly property string maskFile: Quickshell.env("CLOCK_DEPTH_MASK") || ""
    readonly property string restShot: Quickshell.env("CLOCK_DEPTH_REST_SHOT") || ""
    readonly property string panShot: Quickshell.env("CLOCK_DEPTH_PAN_SHOT") || ""
    readonly property string flatShot: Quickshell.env("CLOCK_DEPTH_FLAT_SHOT") || ""

    // Driven by the probe, and the only thing that moves.
    property real panTarget: 0
    readonly property real panDistance: -200
    // Cleared for the last shot, to score the degradation: a wallpaper with no
    // mask must render exactly as it does today.
    property string activeMask: harness.maskFile

    FloatingWindow {
        id: window
        implicitWidth: 800
        implicitHeight: 400
        color: "black"

        Item {
            id: field
            anchors.fill: parent
            // The grab takes THIS item, so it carries its own ground: grabbing
            // over the window's colour yields a transparent PNG whose pixels
            // read as black to any analyser.
            Rectangle { anchors.fill: parent; color: "black" }

            // The wallpaper's viewport. Oversized and positioned by its x, with
            // the same 600ms Behavior Background.qml gives the pan.
            Item {
                id: parallaxViewport
                width: 1000
                height: 500
                x: harness.panTarget
                y: 0
                Behavior on x {
                    NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
                }

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

            // The desktop widgets: a screen-sized sibling that does not pan, so
            // the bar stays put while the wallpaper travels under it.
            Item {
                id: widgetCanvas
                anchors.fill: parent
                z: 2
                Rectangle {
                    id: clockBar
                    y: 160
                    width: parent.width
                    height: 80
                    color: "#ff2020"
                }
            }

            // The depth layer. Every binding here is the one the lint pins in
            // Background.qml.
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
                    enable: true,
                    maskPath: harness.activeMask,
                    optedOut: false,
                    weActive: false,
                    wallpaperIsVideo: false,
                    centeredWallpaper: false,
                    screenLocked: false,
                    transitionInFlight: false
                }) ? 1 : 0

                Image {
                    id: clockDepthWallpaper
                    anchors.fill: parent
                    source: wallpaper.source
                    fillMode: Image.PreserveAspectCrop
                    cache: true
                    smooth: true
                    asynchronous: false
                    visible: false
                }

                Item {
                    id: clockDepthMaskSurface
                    anchors.fill: parent
                    visible: false
                    clip: true

                    Image {
                        id: clockDepthMask
                        readonly property var coverRect: ClockDepthLogic.coverRect(
                            clockDepthWallpaper.implicitWidth, clockDepthWallpaper.implicitHeight,
                            clockDepthMaskSurface.width, clockDepthMaskSurface.height)
                        x: clockDepthMask.coverRect.x
                        y: clockDepthMask.coverRect.y
                        width: clockDepthMask.coverRect.width
                        height: clockDepthMask.coverRect.height
                        source: harness.activeMask === "" ? "" : `file://${harness.activeMask}`
                        fillMode: Image.Stretch
                        smooth: true
                        asynchronous: false
                    }
                }

                OpacityMask {
                    anchors.fill: parent
                    source: clockDepthWallpaper
                    maskSource: clockDepthMaskSurface
                }
            }
        }
    }

    // Sampled 120ms into the pan. A settled sample passes identically on a layer
    // bound to the pan's DESTINATION and on one bound to the viewport, which is
    // the whole bug this probe exists for.
    Timer {
        id: midPanSample
        interval: 120
        onTriggered: {
            const travelled = parallaxViewport.x;
            harness.check("the pan is in flight when it is sampled",
                travelled < -1 && travelled > harness.panDistance + 1,
                `viewport.x=${travelled.toFixed(1)} target=${harness.panDistance}`);
            harness.check("the layer is exactly where the viewport is, mid-pan",
                Math.abs(clockDepthLayer.x - parallaxViewport.x) < 0.001,
                `layer.x=${clockDepthLayer.x.toFixed(1)} viewport.x=${travelled.toFixed(1)}`);
            harness.check("the layer has NOT jumped to the pan's destination",
                Math.abs(clockDepthLayer.x - harness.panDistance) > 1,
                `layer.x=${clockDepthLayer.x.toFixed(1)} destination=${harness.panDistance}`);
            if (harness.panShot !== "")
                field.grabToImage(result => {
                    result.saveToFile(harness.panShot);
                    flatStep.start();
                });
            else
                flatStep.start();
        }
    }

    Timer {
        id: flatStep
        interval: 900
        onTriggered: {
            harness.activeMask = "";
            harness.check("a wallpaper with no mask hides the layer entirely",
                clockDepthLayer.opacity === 0 && !clockDepthLayer.visible,
                `opacity=${clockDepthLayer.opacity} visible=${clockDepthLayer.visible}`);
            settleFlat.start();
        }
    }

    Timer {
        id: settleFlat
        interval: 200
        onTriggered: {
            if (harness.flatShot !== "")
                field.grabToImage(result => {
                    result.saveToFile(harness.flatShot);
                    harness.finish();
                });
            else
                harness.finish();
        }
    }

    function finish(): void {
        console.log(`[ClockDepth] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.quit();
    }

    Timer {
        running: true
        interval: 900
        onTriggered: {
            harness.check("both fixtures are on disk",
                harness.wallpaperFile !== "" && harness.maskFile !== "");
            harness.check("the wallpaper decoded",
                wallpaper.status === Image.Ready, `status=${wallpaper.status}`);
            harness.check("the mask decoded",
                clockDepthMask.status === Image.Ready, `status=${clockDepthMask.status}`);
            harness.check("the layer sits above the widget canvas",
                clockDepthLayer.z > widgetCanvas.z,
                `layer.z=${clockDepthLayer.z} canvas.z=${widgetCanvas.z}`);
            harness.check("the layer takes no input",
                clockDepthLayer.enabled === false);
            harness.check("a mask is present, so the layer is showing",
                clockDepthLayer.opacity === 1 && clockDepthLayer.visible);
            // Stated as the invariant rather than as this fixture's numbers, so
            // the probe answers the same question when it is hand-fed a real
            // wallpaper: the mask covers the box on both axes (or a band of
            // wallpaper would be drawn unmasked over the widgets) and carries
            // the wallpaper's aspect rather than the box's, which is the whole
            // of the un-squash.
            const wallpaperAspect = clockDepthWallpaper.implicitWidth / clockDepthWallpaper.implicitHeight;
            harness.check("the mask covers the box on both axes",
                clockDepthMask.width >= parallaxViewport.width - 0.001
                    && clockDepthMask.height >= parallaxViewport.height - 0.001,
                `mask=${clockDepthMask.width.toFixed(1)}x${clockDepthMask.height.toFixed(1)} `
                    + `box=${parallaxViewport.width}x${parallaxViewport.height}`);
            harness.check("the mask is un-squashed to the wallpaper's aspect",
                Math.abs(clockDepthMask.width / clockDepthMask.height - wallpaperAspect) < 0.001,
                `mask=${(clockDepthMask.width / clockDepthMask.height).toFixed(3)} `
                    + `wallpaper=${wallpaperAspect.toFixed(3)}`);
            harness.check("the layer starts level with the viewport",
                clockDepthLayer.x === parallaxViewport.x && clockDepthLayer.y === parallaxViewport.y);

            if (harness.restShot === "") {
                harness.check("CLOCK_DEPTH_REST_SHOT is set", false);
                harness.finish();
                return;
            }
            field.grabToImage(result => {
                result.saveToFile(harness.restShot);
                harness.panTarget = harness.panDistance;
                midPanSample.start();
            });
        }
    }
}
