import QtQuick
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

    function beginTransition() {
        const pair = harness.transitions[harness.transitionIndex];
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
            console.log(`[MediaTreeMotion] failures: ${harness.failures}`);
            Qt.quit();
        }
    } }
    Timer { id: nextTimer; interval: 250; onTriggered: harness.beginTransition() }

    Timer { id: t0; interval: 1200; running: true; onTriggered: {
        PluginState.setPosition("nandoroid_media", harness.testScreen, { x: 40, y: 40, placementStrategy: "free" });
        settle0.start();
    } }
    Timer { id: settle0; interval: 800; onTriggered: harness.beginTransition() }
}
