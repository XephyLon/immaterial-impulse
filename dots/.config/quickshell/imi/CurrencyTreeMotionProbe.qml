import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.plugins
import qs.modules.common.widgets.widgetCanvas

/*
 * The weather tree's motion sweep: every span pair, both directions, with
 * signal trails on the shared three - and a PNG at each settle and
 * mid-flight (MEDIA_PROBE_SHOTS-style, CURRENCY_PROBE_SHOTS here).
 */
ShellRoot {
    id: harness

    readonly property int screenW: 1200
    readonly property int screenH: 700
    readonly property string testScreen: "probe-screen"

    property int failures: 0
    function check(label, ok) {
        console.log(`[CurrencyTreeMotion] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok) harness.failures++;
    }

    readonly property var manifest: {
        const base = Quickshell.shellPath("modules/common/plugins/bundled/nandoroid-currency");
        return {
            id: "nandoroid_currency",
            name: "weather probe",
            _basePath: base,
            grid: { cols: 2, rows: 1,
                sizes: [{ cols: 1, rows: 1 }, { cols: 2, rows: 1 }] },
            desktopWidget: { component: "Widget.qml" }
        };
    }

    function findByName(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        for (const child of item.children) {
            const hit = harness.findByName(child, name);
            if (hit) return hit;
        }
        return null;
    }

    FloatingWindow {
        visible: true
        implicitWidth: harness.screenW
        implicitHeight: harness.screenH
        color: "black"

        TestCase { id: driver; when: false; name: "WeatherTreePointerDriver" }

        WidgetCanvas {
            id: canvas
            anchors.fill: parent

            PluginWidget {
                id: widget
                manifest: harness.manifest
                screenName: harness.testScreen
                screenWidth: harness.screenW
                screenHeight: harness.screenH
                scaledScreenWidth: harness.screenW
                scaledScreenHeight: harness.screenH
                wallpaperScale: 1
            }
        }
    }

    property string shotDir: Quickshell.env("CURRENCY_PROBE_SHOTS") || ""
    function shoot(tag) {
        if (harness.shotDir === "") return;
        widget.grabToImage(result => result.saveToFile(`${harness.shotDir}/${tag}.png`));
    }

    readonly property var transitions: [
        ["2x1", "1x1"], ["1x1", "2x1"]
    ]
    property int transitionIndex: 0
    property var trails: ({})
    property var connections: []

    function spanOf(name) { return { cols: parseInt(name[0]), rows: 1 }; }

    function watch(label, object, signalName, getter) {
        if (!object) { console.log(`[CurrencyTreeMotion] missing: ${label}`); return; }
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

    Timer { id: midShot; interval: 160; onTriggered: harness.shoot(`${harness.transitions[harness.transitionIndex][0]}-to-${harness.transitions[harness.transitionIndex][1]}_mid`) }

    function beginTransition() {
        const pair = harness.transitions[harness.transitionIndex];
        harness.shoot(`${pair[0]}_settled`);
        midShot.start();
        harness.trails = ({});
        const container = harness.findByName(widget, "currencyContainer");
        const base = harness.findByName(widget, "currencyBase");
        const label = harness.findByName(widget, "currencyRatesLabel");
        harness.watch("container.x", container, "xChanged", () => container.x);
        harness.watch("container.w", container, "widthChanged", () => container.width);
        harness.watch("base.y", base, "yChanged", () => base.y);
        harness.watch("base.size", base, "fontChanged", () => base.font.pixelSize);
        harness.watch("label.x", label, "xChanged", () => label.x);
        if (container && container.children.length > 0 && container.children[0].morphT !== undefined) {
            const canvas = container.children[0];
            harness.watch("container.morphT", canvas, "morphTChanged", () => canvas.morphT);
        }
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
            const moved = label === "container.morphT"
                ? trail.some(v => v > 0.05 && v < 0.95)
                : Math.abs(last - first) > 0.5;
            if (label === "container.morphT" && trail.length > 1 && !moved) {
                harness.check(`${tag} container.morphT sweeps instead of flipping`, false);
                continue;
            }
            if (!moved) { console.log(`[CurrencyTreeMotion] ${tag} ${label}: static`); continue; }
            harness.check(`${tag} ${label} animates (${trail.length} steps)`, trail.length >= 4);
        }
        harness.transitionIndex++;
        if (harness.transitionIndex < harness.transitions.length) {
            nextTimer.start();
        } else {
            console.log(`[CurrencyTreeMotion] failures: ${harness.failures}`);
            Qt.quit();
        }
    } }
    Timer { id: nextTimer; interval: 250; onTriggered: harness.beginTransition() }

    Timer { id: t0; interval: 1200; running: true; onTriggered: {
        PluginState.setPosition("nandoroid_currency", harness.testScreen, { x: 40, y: 40, placementStrategy: "free" });
        settle0.start();
    } }
    Timer { id: settle0; interval: 800; onTriggered: harness.beginTransition() }
}
