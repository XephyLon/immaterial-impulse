import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.common.plugins
import qs.modules.common.widgets.widgetCanvas

/**
 * Scores a span change as motion rather than as a result.
 *
 * `WidgetResizeGripRuntimeTest.qml` deliberately reads only settled sizes -
 * whether the corner resizes the widget or walks it is a question about where
 * things end up. This harness asks the opposite question, and it is the only
 * one that can tell a working animation from the snap it replaced: it samples
 * the widget's width *while* a span change is in flight and fails if the width
 * was already at its destination.
 *
 * That is precisely the failure a `Behavior` produces when it is handed a
 * target that moves every frame (AGENT.md: the parallax opt-out froze that
 * way). It never ticks, the property jumps to the final value, and every
 * settled-size check in the sibling harness stays green. So both gestures are
 * driven here: a Size row change, which is one discrete write, and a grip drag,
 * which re-previews on every mouse move and hands the host a fresh span object
 * each time.
 *
 * Three further things are scored because none of them are visible from a
 * settled size either:
 *   - the content's span name swaps at the *midpoint* of the move, not at
 *     either end - a widget with a layout per span (media loads a different
 *     file per span) would otherwise pop at the moment the motion exists to
 *     cover;
 *   - a widget grown at the right-hand screen edge ends up inside the screen,
 *     and its stored position agrees. The clamp runs when the span commits,
 *     when the widget is still the size it is leaving, so an animation that is
 *     measured wrong strands it outside with nothing left running to notice;
 *   - Escape returns the size on a move, not on a snap.
 *
 * Run it against a throwaway config:
 *   XDG_CONFIG_HOME=$(mktemp -d) XDG_STATE_HOME=$(mktemp -d) qs -p WidgetResizeMotionRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    readonly property string testScreen: "MOTION-TEST"
    readonly property int screenW: 1200
    readonly property int screenH: 700

    function check(label, ok) {
        console.log(`[WidgetResizeMotion] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function spanW(cols) { return Math.round(Appearance.sizes.widgetGridSpanX(cols)); }
    function spanH(rows) { return Math.round(Appearance.sizes.widgetGridSpanY(rows)); }

    function manifestFor(id) {
        return {
            id: id,
            name: id,
            grid: {
                cols: 3, rows: 2,
                sizes: [{ cols: 3, rows: 2 }, { cols: 2, rows: 2 }, { cols: 2, rows: 1 }]
            },
            desktopWidget: { type: "Item" }
        };
    }

    readonly property var motionManifest: harness.manifestFor("motion-probe")
    readonly property var edgeManifest: harness.manifestFor("edge-probe")

    FloatingWindow {
        visible: true
        implicitWidth: harness.screenW
        implicitHeight: harness.screenH
        color: "black"

        TestCase {
            id: driver
            when: false
            name: "WidgetResizeMotionDriver"
        }

        WidgetCanvas {
            id: canvas
            anchors.fill: parent

            PluginWidget {
                id: motionWidget
                manifest: harness.motionManifest
                screenName: harness.testScreen
                screenWidth: harness.screenW
                screenHeight: harness.screenH
                scaledScreenWidth: harness.screenW
                scaledScreenHeight: harness.screenH
                wallpaperScale: 1
            }

            // Placed so that its 2x2 self ends exactly at the right edge: one
            // step up to 3x2 is 144px it does not have.
            PluginWidget {
                id: edgeWidget
                manifest: harness.edgeManifest
                screenName: harness.testScreen
                screenWidth: harness.screenW
                screenHeight: harness.screenH
                scaledScreenWidth: harness.screenW
                scaledScreenHeight: harness.screenH
                wallpaperScale: 1
            }
        }
    }

    readonly property real edgeStartX: harness.screenW - harness.spanW(2)

    function placeWidgets() {
        PluginState.setPosition("motion-probe", harness.testScreen,
                                { x: 40, y: 40, placementStrategy: "free" });
        PluginState.setPosition("edge-probe", harness.testScreen,
                                { x: harness.edgeStartX, y: 400, placementStrategy: "free" });
    }

    // ---- sampling -------------------------------------------------------
    //
    // Three samples per gesture, taken against wall-clock offsets from the
    // moment the span changes. 80ms and 240ms are both well inside the 500ms
    // commit move (and the 350ms drag move), and 400ms is past the midpoint the
    // content swap lands on and still short of the end.

    property var samples: ({})

    function sampleOf(widget) {
        return {
            width: Math.round(widget.width),
            height: Math.round(widget.height),
            shown: widget.shownGridSpan,
            x: Math.round(widget.x)
        };
    }

    property Item sampledWidget: null

    function startSampling(widget) {
        harness.samples = ({});
        harness.sampledWidget = widget;
        earlySample.restart();
        midSample.restart();
        lateSample.restart();
    }

    Timer {
        id: earlySample
        interval: 80
        onTriggered: harness.samples.early = harness.sampleOf(harness.sampledWidget)
    }
    Timer {
        id: midSample
        interval: 240
        onTriggered: harness.samples.mid = harness.sampleOf(harness.sampledWidget)
    }
    Timer {
        id: lateSample
        interval: 400
        onTriggered: harness.samples.late = harness.sampleOf(harness.sampledWidget)
    }

    // The check that separates an animation from a snap. A size that is already
    // at the target 80ms in is exactly what a Behavior that never ticks
    // produces, and it is indistinguishable from the instant resize this
    // replaced.
    //
    // The axis is named by the caller rather than assumed: a 2x2 -> 2x1 drag
    // moves only the height, and scoring its width instead passes every check
    // here vacuously - the width is neither of the two *heights* it is being
    // compared against.
    function scoreInFlight(label, axis, fromSize, toSize) {
        const early = harness.samples.early;
        const mid = harness.samples.mid;
        harness.check(`${label}: sampled at all`, !!early && !!mid);
        if (!early || !mid) return;
        harness.check(`${label}: the axis under test actually moves`, fromSize !== toSize);
        harness.check(`${label}: was not already at the new span`,
                      early[axis] !== toSize);
        harness.check(`${label}: had left the old span`, early[axis] !== fromSize);
        harness.check(`${label}: was still travelling`, early[axis] !== mid[axis]);
    }

    function scoreSettled(label, widget, cols, rows) {
        harness.check(`${label}: settles on the span`,
                      Math.round(widget.width) === harness.spanW(cols)
                      && Math.round(widget.height) === harness.spanH(rows));
        harness.check(`${label}: the content is the span it settled on`,
                      widget.shownGridSpan === `${cols}x${rows}`);
    }

    // The content changes identity once, in the middle. Either end is a pop:
    // at the start the new layout is drawn into the old box for the whole
    // move, at the end the old one is.
    function scoreSwapsAtTheMidpoint(label, fromSpan, toSpan) {
        const early = harness.samples.early;
        const late = harness.samples.late;
        harness.check(`${label}: sampled at all`, !!early && !!late);
        if (!early || !late) return;
        harness.check(`${label}: the content is still the old span early on`,
                      early.shown === fromSpan);
        harness.check(`${label}: and the new one by the second half`,
                      late.shown === toSpan);
    }

    // ---- gestures -------------------------------------------------------

    function gripCenter(widget) {
        const inset = Appearance.spacing.space100 + 8;
        return { x: widget.x + widget.width - inset, y: widget.y + widget.height - inset };
    }

    property var pendingGrip: null

    function hoverGrip(widget) {
        harness.pendingGrip = harness.gripCenter(widget);
        driver.mouseMove(canvas, harness.pendingGrip.x, harness.pendingGrip.y);
    }

    // Press and drag, leaving the button down: the samples are taken while the
    // gesture is still live, which is the whole point of driving the grip as
    // well as the Size row.
    function pressAndDrag(dx, dy) {
        const point = harness.pendingGrip;
        driver.mousePress(canvas, point.x, point.y, Qt.LeftButton);
        driver.mouseMove(canvas, point.x + dx, point.y + dy, 20, Qt.LeftButton);
    }

    function releaseDrag(dx, dy) {
        const point = harness.pendingGrip;
        driver.mouseRelease(canvas, point.x + dx, point.y + dy, Qt.LeftButton);
    }

    function escapeDrag() { driver.keyClick(Qt.Key_Escape); }

    function setSpan(id, span) { PluginState.setOption(id, "__gridSize", span); }

    // ---- the steps ------------------------------------------------------

    readonly property var steps: [
        // The Size row's path: one discrete write, from the manifest default.
        () => {
            harness.setSpan("motion-probe", "2x2");
            harness.startSampling(motionWidget);
        },
        () => {
            harness.scoreInFlight("a Size row change", "width", harness.spanW(3), harness.spanW(2));
            harness.scoreSwapsAtTheMidpoint("a Size row change", "3x2", "2x2");
            harness.scoreSettled("a Size row change", motionWidget, 2, 2);
        },

        // The grip's path. Its target is re-written on every mouse move with a
        // fresh span object, which is the shape that froze the parallax
        // opt-out's position Behavior solid.
        () => harness.hoverGrip(motionWidget),
        () => {
            harness.pressAndDrag(0, -120);
            harness.startSampling(motionWidget);
        },
        () => {
            harness.scoreInFlight("a grip drag", "height", harness.spanH(2), harness.spanH(1));
            harness.releaseDrag(0, -120);
        },
        () => harness.scoreSettled("a grip drag", motionWidget, 2, 1),

        // Escape mid-drag returns the size, and that return is a move too.
        () => harness.hoverGrip(motionWidget),
        () => {
            harness.pressAndDrag(144, 0);
            harness.startSampling(motionWidget);
        },
        () => {
            harness.escapeDrag();
            harness.startSampling(motionWidget);
        },
        () => {
            harness.scoreInFlight("escape", "width", harness.spanW(3), harness.spanW(2));
            harness.releaseDrag(144, 0);
        },
        () => harness.scoreSettled("escape", motionWidget, 2, 1),

        // Growing at the screen edge. The clamp runs when the span commits,
        // while the widget is still the size it is leaving, so it has to
        // measure the widget by the span it is growing *into*.
        () => {
            harness.check("the edge widget starts flush with the right edge",
                          Math.round(edgeWidget.x) === Math.round(harness.edgeStartX));
            harness.setSpan("edge-probe", "3x2");
            harness.startSampling(edgeWidget);
        },
        () => {
            harness.scoreSettled("growing at the edge", edgeWidget, 3, 2);
            harness.check("growing at the edge: the widget stays on screen",
                          Math.round(edgeWidget.x + edgeWidget.width) <= harness.screenW);
            harness.check("growing at the edge: the store agrees with the screen",
                          Math.round(PluginState.position("edge-probe", harness.testScreen).x)
                              === harness.screenW - harness.spanW(3));
        }
    ]

    property int stepIndex: 0

    Timer {
        id: setup
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            if (!PluginState.ready || !Config.ready)
                return;
            Config.options.background.widgetsLocked = false;
            // Both manifests default to 3x2, which is 420 wide: the edge widget
            // cannot be placed flush with the right edge until it is the 2x2 it
            // is meant to grow *from*, because the host clamps it back in.
            if (PluginState.option("edge-probe", "__gridSize", "") !== "2x2") {
                PluginState.setOption("edge-probe", "__gridSize", "2x2");
                return;
            }
            if (Math.round(motionWidget.x) === 40
                    && Math.round(edgeWidget.x) === Math.round(harness.edgeStartX)) {
                setup.running = false;
                runner.running = true;
                return;
            }
            harness.placeWidgets();
        }
    }

    // A harness that never reaches its steps is a 180s timeout in the driver
    // and no output at all - qs buffers stdout into a pipe, so a killed run
    // says nothing about why.
    Timer {
        interval: 60000
        running: true
        onTriggered: {
            console.log(`[WidgetResizeMotion] FAIL: gave up at step ${harness.stepIndex}`
                        + ` of ${harness.steps.length}`);
            console.log(`[WidgetResizeMotion] failures: ${harness.failures + 1}`);
            Qt.exit(1);
        }
    }

    // Long enough for the whole move plus the position Behavior that follows a
    // clamp, so every step starts from a settled widget.
    Timer {
        id: runner
        interval: 900
        repeat: true
        running: false
        onTriggered: {
            if (harness.stepIndex >= harness.steps.length) {
                runner.running = false;
                console.log(`[WidgetResizeMotion] failures: ${harness.failures}`);
                Qt.exit(harness.failures === 0 ? 0 : 1);
                return;
            }
            harness.steps[harness.stepIndex++]();
        }
    }
}
