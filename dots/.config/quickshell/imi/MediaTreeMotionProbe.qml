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

    property var samples: []
    function sampleNow(tag) {
        const play = harness.findByName(widget, "playButton");
        if (!play) { console.log("[MediaTreeMotion] no play button found"); return; }
        const scene = play.mapToItem(null, 0, 0);
        harness.samples.push({ tag: tag, x: Math.round(scene.x), y: Math.round(scene.y),
                               w: Math.round(play.width), h: Math.round(play.height),
                               boxW: Math.round(widget.width) });
        console.log(`[MediaTreeMotion] sample ${tag}: play=${Math.round(scene.x)},${Math.round(scene.y)} ` +
                    `${Math.round(play.width)}x${Math.round(play.height)} box=${Math.round(widget.width)}`);
    }

    Timer { id: t0; interval: 1200; running: true; onTriggered: {
        PluginState.setPosition("nandoroid_media", harness.testScreen, { x: 40, y: 40, placementStrategy: "free" });
        settle.start();
    } }
    Timer { id: settle; interval: 800; onTriggered: {
        harness.sampleNow("before");
        widget.commitGridSize({ cols: 2, rows: 2 });
        s1.start(); s2.start(); s3.start(); s4.start();
    } }
    Timer { id: s1; interval: 40;  onTriggered: harness.sampleNow("t40") }
    Timer { id: s2; interval: 120; onTriggered: harness.sampleNow("t120") }
    Timer { id: s3; interval: 240; onTriggered: harness.sampleNow("t240") }
    Timer { id: s4; interval: 900; onTriggered: {
        harness.sampleNow("settled");
        const first = harness.samples[0], last = harness.samples[harness.samples.length - 1];
        const mids = harness.samples.slice(1, -1);
        harness.check("the play button ends somewhere new",
            first.x !== last.x || first.w !== last.w);
        harness.check("the box is in flight at t40/t120 (Behavior alive)",
            mids.some(s => s.boxW !== first.boxW && s.boxW !== last.boxW));
        harness.check("the play button is in flight mid-change, not snapped",
            mids.some(s => (s.x !== first.x && s.x !== last.x)
                        || (s.w !== first.w && s.w !== last.w)));
        // The check the teleport passed and travel requires: the SIZE is
        // strictly between its endpoints somewhere mid-change. A snap is at
        // one end or the other in every sample.
        harness.check("the play button's size travels, not teleports",
            mids.some(s => (s.w - first.w) * (s.w - last.w) < 0));
        harness.check("the play button's y travels, not teleports",
            mids.some(s => (s.y - first.y) * (s.y - last.y) < 0));
        console.log(`[MediaTreeMotion] failures: ${harness.failures}`);
        Qt.quit();
    } }
}
