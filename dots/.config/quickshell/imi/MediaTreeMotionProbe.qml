import QtQuick
import QtTest
import qs.services
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.plugins
import qs.modules.common.widgets.widgetCanvas
import "modules/common/plugins" as Plugins

/*
 * Does the media tree's play button MOVE during a span change, or snap?
 *
 * Loads the real nandoroid-media package in a real PluginWidget, commits a
 * span change, and samples the play button's scene rect while the change is
 * in flight. Prints [MediaTreeMotion] lines; the driver scores them.
 */
ShellRoot {
    id: harness

    readonly property int screenW: 1200
    readonly property int screenH: 700
    readonly property string testScreen: "probe-screen"

    property int failures: 0
    property int checksRun: 0
    function check(label, ok) {
        harness.checksRun++;
        console.log(`[MediaTreeMotion] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok) harness.failures++;
    }

    readonly property var mediaManifest: {
        const base = Quickshell.shellPath("modules/common/plugins/bundled/nandoroid-media");
        return {
            id: "nandoroid_media",
            name: "media probe",
            _basePath: base,
            grid: { cols: 3, rows: 2,
                sizes: [{ cols: 3, rows: 2 }, { cols: 2, rows: 2 }, { cols: 2, rows: 1 }] },
            desktopWidget: { component: "Widget.qml" }
        };
    }

    function findByName(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        for (const child of item.children) {
            const hit = findByName(child, name);
            if (hit) return hit;
        }
        return null;
    }

    FloatingWindow {
        visible: true
        implicitWidth: harness.screenW
        implicitHeight: harness.screenH
        color: "black"

        TestCase { id: driver; when: false; name: "MediaTreePointerDriver" }

        WidgetCanvas {
            id: canvas
            anchors.fill: parent

            PluginWidget {
                id: widget
                manifest: harness.mediaManifest
                screenName: harness.testScreen
                screenWidth: harness.screenW
                screenHeight: harness.screenH
                scaledScreenWidth: harness.screenW
                scaledScreenHeight: harness.screenH
                wallpaperScale: 1
            }
        }
    }

    // ---- the sweep: every span pair, both directions ---------------------
    //
    // For each transition, signal connections record every value the moving
    // parts take - immune to event-loop stalls, which ate the first version
    // of these checks. A part with fewer than 3 recorded intermediate values
    // snapped, and the sweep says which part on which transition.
    readonly property var transitions: [
        ["3x2", "2x2"], ["2x2", "2x1"], ["2x1", "1x1"], ["1x1", "3x2"],
        ["3x2", "2x1"], ["2x1", "2x2"], ["2x2", "3x2"], ["1x1", "2x1"]
    ]
    property int transitionIndex: 0
    property var trails: ({})
    property var connections: []

    function spanOf(name) {
        return { cols: parseInt(name[0]), rows: parseInt(name[2]) };
    }

    function watch(label, object, signalName, getter) {
        if (!object) { console.log(`[MediaTreeMotion] missing: ${label}`); return; }
        harness.trails[label] = [getter()];
        const handler = () => harness.trails[label].push(getter());
        object[signalName].connect(handler);
        harness.connections.push({ object: object, signalName: signalName, handler: handler });
    }

    function unwatchAll() {
        for (const c of harness.connections)
            c.object[c.signalName].disconnect(c.handler);
        harness.connections = [];
    }

    // Visual capture: a PNG at each settle and one mid-flight, so the sweep
    // can be JUDGED as pixels, not only scored as numbers.
    property string shotDir: Quickshell.env("MEDIA_PROBE_SHOTS") || ""
    function shoot(tag) {
        if (harness.shotDir === "") return;
        widget.grabToImage(result => {
            result.saveToFile(`${harness.shotDir}/${tag}.png`);
        });
    }
    Timer { id: midShot; interval: 160; onTriggered: harness.shoot(`${harness.transitions[harness.transitionIndex][0]}-to-${harness.transitions[harness.transitionIndex][1]}_mid`) }

    function beginTransition() {
        const pair = harness.transitions[harness.transitionIndex];
        harness.shoot(`${pair[0]}_settled`);
        midShot.start();
        harness.trails = ({});
        const play = harness.findByName(widget, "playButton");
        const prev = harness.findByName(widget, "prevButton");
        const slider = harness.findByName(widget, "progressSlider");
        const art = harness.findByName(widget, "playArtwork");
        const ringItem = harness.findByName(widget, "playRing");
        harness.watch("play.w", play, "widthChanged", () => play.width);
        harness.watch("play.x", play, "xChanged", () => play.x);
        harness.watch("prev.x", prev, "xChanged", () => prev.x);
        harness.watch("slider.o", slider, "opacityChanged", () => slider.opacity);
        if (art) harness.watch("art.w", art, "widthChanged", () => art.width);
        if (ringItem) harness.watch("ring.t", ringItem, "morphTChanged", () => ringItem.morphT);
        widget.commitGridSize(harness.spanOf(pair[1]));
        settleTimer.start();
    }

    Timer { id: settleTimer; interval: 1100; onTriggered: {
        const pair = harness.transitions[harness.transitionIndex];
        const tag = `${pair[0]}->${pair[1]}`;
        harness.unwatchAll();
        for (const label in harness.trails) {
            const trail = harness.trails[label];
            const first = trail[0], last = trail[trail.length - 1];
            const moved = Math.abs(last - first) > 0.5 || (label === "slider.o" && Math.abs(last - first) > 0.01)
                || (label === "ring.t" && Math.abs(last - first) > 0.01);
            if (!moved) { console.log(`[MediaTreeMotion] ${tag} ${label}: static (${first.toFixed ? first.toFixed(1) : first})`); continue; }
            harness.check(`${tag} ${label} animates (${trail.length} steps)`, trail.length >= 4);
        }
        harness.transitionIndex++;
        if (harness.transitionIndex < harness.transitions.length) {
            nextTimer.start();
        } else {
            pointerSweep.start();
        }
    } }

    // ---- the pointer sweep: every control, every span, real clicks -------
    //
    // Scores signals, not playback: `activated` on each button and `sought`
    // on the seeker, because the sandbox must never toggle whatever the
    // session is really playing. The seeker check is the routing one that
    // shipped broken: a click on the play button's FACE must reach the
    // button (the ring passes it through), and a click ON the ring's stroke
    // must seek and not activate.
    property var pointerSpans: ["3x2", "2x2", "2x1", "1x1"]
    property int pointerIndex: 0
    property int activatedCount: 0
    property int soughtCount: 0

    Timer { id: pointerSweep; interval: 300; onTriggered: {
        widget.commitGridSize(harness.spanOf(harness.pointerSpans[harness.pointerIndex]));
        pointerSettle.start();
    } }
    Timer { id: pointerSettle; interval: 900; onTriggered: {
        const span = harness.pointerSpans[harness.pointerIndex];
        const play = harness.findByName(widget, "playButton");
        const prev = harness.findByName(widget, "prevButton");
        const next = harness.findByName(widget, "nextButton");
        const seeker = harness.findByName(widget, "progressSlider");
        for (const pair of [["play", play], ["prev", prev], ["next", next]]) {
            const item = pair[1];
            let hits = 0;
            const bump = () => hits++;
            item.activated.connect(bump);
            const scene = item.mapToItem(null, item.width / 2, item.height / 2);
            driver.mouseMove(canvas, scene.x, scene.y);
            harness.check(`${span} ${pair[0]} hovers under the pointer`, item.hoveredNow === true);
            // The shared interaction model resolves the state immediately;
            // only the progress toward it is animated.
            harness.check(`${span} ${pair[0]} reads as hovered to the model`,
                item.motion.interactionState === "hovered");
            driver.mousePress(canvas, scene.x, scene.y, Qt.LeftButton);
            harness.check(`${span} ${pair[0]} acknowledges the press`,
                item.motion.interactionState === "pressed");
            driver.mouseRelease(canvas, scene.x, scene.y, Qt.LeftButton);
            item.activated.disconnect(bump);
            harness.check(`${span} ${pair[0]} click reaches the button`, hits === 1);
            harness.check(`${span} ${pair[0]} returns to hovered after release`,
                item.motion.interactionState === "hovered");
        }
        // The wash the body paints is driven by hoverProgress, and a state
        // flag that flips while the progress stays at 0 would paint nothing.
        // Canvas pixels are not readable from QML, so the value the painter
        // consumes is what gets checked.
        {
            const scene = play.mapToItem(null, play.width / 2, play.height / 2);
            driver.mouseMove(canvas, scene.x, scene.y);
            driver.wait(320);
            harness.check(`${span} play's wash progress rises on hover`,
                play.motion.hoverProgress > 0.5, `(${play.motion.hoverProgress.toFixed(2)})`);

            // The badge lifts instead - the play button deliberately does not
            // scale, or it would pull away from the ring drawn around it.
            const prevScene = prev.mapToItem(null, prev.width / 2, prev.height / 2);
            driver.mouseMove(canvas, prevScene.x, prevScene.y);
            driver.wait(320);
            harness.check(`${span} prev's badge lifts on hover`,
                prev.motion.scale > 1.005, `(scale ${prev.motion.scale.toFixed(3)})`);
            // ...and the lift reaches the item that is drawn, not just the
            // model: a transform that silently does nothing passes the check
            // above and moves no pixel.
            harness.check(`${span} the lift reaches the drawn badge`,
                prev.appliedBadgeScale > 1.005,
                `(applied ${prev.appliedBadgeScale.toFixed(3)})`);
            harness.check(`${span} the play button does not scale`,
                Math.abs(play.motion.scale - 1) < 0.001
                || play.motion.interactionState === "rest",
                `(scale ${play.motion.scale.toFixed(3)})`);
        }

        driver.mouseMove(canvas, 5, 5);
        // Pointer gone: a release that happened off the control still has to
        // leave it resting, never stuck at its pressed size.
        for (const pair of [["play", play], ["prev", prev], ["next", next]]) {
            if (pair[1].motion.interactionState !== "rest")
                console.log(`[MediaTreeMotion] DIAG ${span} ${pair[0]} state=${pair[1].motion.interactionState}`
                    + ` hoveredNow=${pair[1].hoveredNow} covered=${pair[1].coveredHover}`
                    + ` seekerHoverPlay=${seeker ? seeker.hoveringPlay : "n/a"}`
                    + ` seekerContains=${seeker ? seeker.seekAreaContainsMouse : "n/a"}`);
            harness.check(`${span} ${pair[0]} rests once the pointer leaves`,
                pair[1].motion.interactionState === "rest");
        }
        // a click on the seeker's own stroke seeks and does not activate play
        if (seeker && seeker.visible) {
            let sought = 0, played = 0;
            const onSeek = () => sought++;
            const onPlay = () => played++;
            seeker.sought.connect(onSeek);
            play.activated.connect(onPlay);
            const pts = seeker.baselinePoints(96);
            const at = pts[Math.round(pts.length * 0.25)];
            const scene = seeker.mapToItem(null, at.x, at.y);
            driver.mouseClick(canvas, scene.x, scene.y, Qt.LeftButton);
            seeker.sought.disconnect(onSeek);
            play.activated.disconnect(onPlay);
            harness.check(`${span} stroke click seeks`, sought >= 1);
            harness.check(`${span} stroke click does not activate play`, played === 0);
        }
        harness.pointerIndex++;
        if (harness.pointerIndex < harness.pointerSpans.length) {
            pointerSweep.start();
        } else {
            console.log(`[MediaTreeMotion] checks: ${harness.checksRun} failures: ${harness.failures}`);
            Qt.quit();
        }
    } }
    Timer { id: nextTimer; interval: 250; onTriggered: harness.beginTransition() }

    Timer { id: t0; interval: 1200; running: true; onTriggered: {
        PluginState.setPosition("nandoroid_media", harness.testScreen, { x: 40, y: 40, placementStrategy: "free" });
        settle0.start();
    } }
    Timer { id: settle0; interval: 800; onTriggered: {
        // One forced-wave portrait before the sweep: the wave exists only
        // while playing, and the sandbox player may be paused, so the check
        // that the sine is a sine would otherwise be vacuously flat.
        const seeker = harness.findByName(widget, "progressSlider");
        if (seeker) { seeker.playing = true; seeker.progress = 0.6; }
        waveShot.start();
    } }
    Timer { id: waveShot; interval: 400; onTriggered: {
        harness.shoot("wave_forced");
        wave2x1.start();
    } }
    Timer { id: wave2x1; interval: 200; onTriggered: {
        widget.commitGridSize({ cols: 2, rows: 1 });
        wave2x1Shot.start();
    } }
    Timer { id: wave2x1Shot; interval: 900; onTriggered: {
        const seeker = harness.findByName(widget, "progressSlider");
        if (seeker) { seeker.playing = true; seeker.progress = 0.6; }
        wave2x1Final.start();
    } }
    Timer { id: wave2x1Final; interval: 400; onTriggered: {
        harness.shoot("wave2x1_forced");
        widget.commitGridSize({ cols: 3, rows: 2 });
        restore3x2.start();
    } }
    Timer { id: restore3x2; interval: 900; onTriggered: {
        const seeker = harness.findByName(widget, "progressSlider");
        if (seeker) {
            seeker.playing = Qt.binding(() => MprisController.isPlaying);
            seeker.progress = Qt.binding(() => harness.findByName(widget, "playButton") ? widgetProgress() : 0);
            // restore the real binding through the tree's own property
            seeker.progress = Qt.binding(() => widget ? widgetTreeProgress() : 0);
        }
        harness.beginTransition();
    } }
    function widgetProgress() { return 0; }
    function widgetTreeProgress() {
        const item = harness.findByName(widget, "playButton");
        return item ? item.progress ?? 0 : 0;
    }
}
