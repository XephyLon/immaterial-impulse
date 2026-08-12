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
    function check(label, ok) {
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
        ["3x2", "2x2"], ["2x2", "2x1"], ["2x1", "3x2"],
        ["3x2", "2x1"], ["2x1", "2x2"], ["2x2", "3x2"]
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

    function census(item, depth) {
        if (!item || depth > 6) return;
        for (const child of item.children) {
            if (child.visible && child.x < 6 && child.y < 6 && (child.text !== undefined && child.text !== ""))
                console.log(`[MediaTreeMotion] census: text item at 0,0: "${String(child.text).slice(0, 18)}" ` +
                            `visible=${child.visible} w=${Math.round(child.width)} opacity=${child.opacity.toFixed(2)} name=${child.objectName}`);
            harness.census(child, depth + 1);
        }
    }

    function playFace(item, depth, indent) {
        if (!item || depth > 5) return;
        for (const child of item.children) {
            console.log(`[MediaTreeMotion] face${indent} ${child.toString().split("(")[0]} ` +
                `vis=${child.visible} o=${child.opacity.toFixed(2)} ${Math.round(child.width)}x${Math.round(child.height)}` +
                (child.status !== undefined ? ` status=${child.status}` : "") +
                (child.polygon !== undefined ? ` polygonCubics=${child.polygon ? child.polygon.cubics.length : "null"} lobes=${child.lobes}` : "") +
                (child.available !== undefined ? ` canvasAvailable=${child.available}` : ""));
            harness.playFace(child, depth + 1, indent + "-");
        }
    }

    function beginTransition() {
        const pair = harness.transitions[harness.transitionIndex];
        if (pair[0] === "2x2") {
            harness.playFace(harness.findByName(widget, "playButton"), 0, "");
            // Force-paint experiment: count painted() from the visualizer's
            // canvas and repaint it by hand. Painted-but-blank means the
            // pixels are lost after painting; no painted() means the paint
            // never runs at all.
            const play = harness.findByName(widget, "playButton");
            const walk = (item, depth) => {
                if (!item || depth > 6) return null;
                for (const child of item.children) {
                    if (child.polygon !== undefined && child.lobes !== undefined) return child;
                    const hit = walk(child, depth + 1);
                    if (hit) return hit;
                }
                return null;
            };
            const cookie = walk(play, 0);
            if (cookie) {
                const cookieCanvas = cookie.children[0];
                let paints = 0;
                cookieCanvas.painted.connect(() => paints++);
                cookieCanvas.requestPaint();
                Qt.callLater(() => console.log(`[MediaTreeMotion] cookie canvas painted ${paints} times after forced request, available=${cookieCanvas.available}, size=${cookieCanvas.width}x${cookieCanvas.height}, parentOpacity=${cookie.opacity}`));
            } else console.log("[MediaTreeMotion] no cookie found in play button");
        }
        harness.census(widget, 0);
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
    property var pointerSpans: ["3x2", "2x2", "2x1"]
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
            driver.mouseClick(canvas, scene.x, scene.y, Qt.LeftButton);
            item.activated.disconnect(bump);
            harness.check(`${span} ${pair[0]} click reaches the button`, hits === 1);
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
            console.log(`[MediaTreeMotion] failures: ${harness.failures}`);
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
