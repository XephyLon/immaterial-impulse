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
 * mid-flight (MEDIA_PROBE_SHOTS-style, WEATHER_PROBE_SHOTS here).
 */
ShellRoot {
    id: harness

    readonly property int screenW: 1200
    readonly property int screenH: 700
    readonly property string testScreen: "probe-screen"

    property int failures: 0
    function check(label, ok) {
        console.log(`[WeatherTreeMotion] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok) harness.failures++;
    }

    readonly property var manifest: {
        const base = Quickshell.shellPath("modules/common/plugins/bundled/nandoroid-weather");
        return {
            id: "nandoroid_weather",
            name: "weather probe",
            _basePath: base,
            grid: { cols: 3, rows: 1,
                sizes: [{ cols: 3, rows: 1 }, { cols: 2, rows: 1 }, { cols: 1, rows: 1 },
                        { cols: 3, rows: 2 }] },
            desktopWidget: { component: "Widget.qml" }
        };
    }

    // There is no network here and no API key, so the service publishes
    // nothing and the card would sweep every span showing "--" over an empty
    // forecast band - which is a real state, but not the one the second row
    // exists for. `Weather.data` and `Weather.forecast` are plain writable
    // properties with no binding on them, so seeding them is injection rather
    // than a mock, and the widget is the real widget reading the real service.
    function isoIn(days) {
        const at = new Date(new Date().getTime() + days * 24 * 60 * 60 * 1000);
        const pad = n => (n < 10 ? "0" + n : "" + n);
        return at.getFullYear() + "-" + pad(at.getMonth() + 1) + "-" + pad(at.getDate());
    }
    // Four days is OpenWeatherMap's cap; `seedForecast(3)` is wttr.in's count
    // and the sweep runs both, because the row divides the strip by the count
    // it is handed and a layout that only ever saw one of them proves nothing.
    function seedForecast(count) {
        // OpenWeatherMap condition ids, because that is the provider a config
        // with nothing set resolves to and the card reads `wCode` against
        // whichever one reported it. Seeded with wttr's WWO codes instead, the
        // shots render four storms and a cloud - correct behaviour for codes
        // the provider did not send, and a misleading picture of the widget.
        // The mapping itself is unit-tested on both providers.
        const codes = [800, 500, 202, 601];
        const days = [];
        for (let i = 0; i < count; i++)
            days.push({ date: harness.isoIn(i), wCode: codes[i % codes.length],
                        high: 24 - i, low: 12 - i });
        Weather.forecast = days;
    }
    function seedWeather() {
        // Sunrise and sunset in the shape OpenWeatherMap's parser publishes
        // them (en-US, with seconds). Without them the sun marker is correctly
        // hidden - "0" is an unknown day, not midnight - and the shots would
        // show a curve with nothing on it while looking perfectly fine.
        Weather.data = {
            temp: "21°C", tempFeelsLike: "19°C", tempHigh: "24°C", tempLow: "12°C",
            description: "Light rain", humidity: "72%", wind: "12 km/h", wCode: 296,
            sunrise: "6:12:00 AM", sunset: "7:48:00 PM"
        };
        harness.seedForecast(4);
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

    property string shotDir: Quickshell.env("WEATHER_PROBE_SHOTS") || ""
    function shoot(tag) {
        if (harness.shotDir === "") return;
        widget.grabToImage(result => result.saveToFile(`${harness.shotDir}/${tag}.png`));
    }

    // Every ordered pair of spans, so each one is entered and left. 3x2 is in
    // both directions against all three of the one-row spans: it is the only
    // span whose transitions change the card's HEIGHT, and the elements that
    // travel into it travel on the axis the other five pairs never exercise.
    readonly property var transitions: [
        ["3x1", "2x1"], ["2x1", "1x1"], ["1x1", "3x1"],
        ["3x1", "1x1"], ["1x1", "2x1"], ["2x1", "3x1"],
        ["3x1", "3x2"], ["3x2", "3x1"],
        ["3x2", "2x1"], ["2x1", "3x2"],
        ["3x2", "1x1"], ["1x1", "3x2"]
    ]
    property int transitionIndex: 0
    property var trails: ({})
    property var connections: []
    // Which span the card is actually at. The list above is a list of ORDERED
    // PAIRS, not a walk: `3x2 -> 2x1` follows `3x2 -> 3x1`, so the card is at
    // 3x1 when that pair starts. Nothing put it back, so the sweep ran
    // 3x1 -> 2x1 under the label `3x2->2x1`, filed its settled shot as
    // `3x2_settled.png`, and the real 3x2 -> 2x1 was never run at all - the one
    // pair whose card SHRINKS in both axes. A pair the sweep names has to be a
    // pair the sweep runs.
    property string currentSpan: "3x1"

    function spanOf(name) {
        const parts = name.split("x");
        return { cols: parseInt(parts[0]), rows: parseInt(parts[1]) };
    }

    function watch(label, object, signalName, getter) {
        if (!object) { console.log(`[WeatherTreeMotion] missing: ${label}`); return; }
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

    // Put the card at the pair's starting span before running the pair. The
    // reposition is a span change like any other, so it gets its own settle
    // rather than being folded into the transition being measured.
    function beginTransition() {
        const pair = harness.transitions[harness.transitionIndex];
        if (harness.currentSpan !== pair[0]) {
            widget.commitGridSize(harness.spanOf(pair[0]));
            harness.currentSpan = pair[0];
            repositionSettle.start();
            return;
        }
        harness.runTransition();
    }

    Timer { id: repositionSettle; interval: 1100; onTriggered: harness.runTransition() }

    function runTransition() {
        const pair = harness.transitions[harness.transitionIndex];
        harness.shoot(`${pair[0]}_settled`);
        midShot.start();
        harness.trails = ({});
        const temp = harness.findByName(widget, "weatherTemp");
        const glyph = harness.findByName(widget, "weatherGlyph");
        const condition = harness.findByName(widget, "weatherCondition");
        harness.watch("temp.x", temp, "xChanged", () => temp.x);
        // x alone is not enough now that a span change can be vertical. The
        // temperature and the condition both hold their x between 3x1 and 3x2
        // and travel on y and in font size, so an x-only sweep reported them
        // "static" through the one pair that moves them - it would have passed
        // just as green on a snap.
        harness.watch("temp.y", temp, "yChanged", () => temp.y);
        harness.watch("temp.size", temp, "fontChanged", () => temp.font.pixelSize);
        harness.watch("cond.y", condition, "yChanged", () => condition.y);
        harness.watch("glyph.x", glyph, "xChanged", () => glyph.x);
        harness.watch("glyph.w", glyph, "widthChanged", () => glyph.width);
        harness.watch("glyph.rot", glyph, "rotationChanged", () => glyph.rotation);
        harness.watch("cond.x", condition, "xChanged", () => condition.x);
        // The elements the second row added. The pills and the column rule
        // travel between the two wide spans on the y axis alone, so watching
        // x - which is what every other trail here watches - would report them
        // static through the one transition that moves them.
        const pills = harness.findByName(widget, "weatherPills");
        const rule = harness.findByName(widget, "weatherColumnRule");
        const strip = harness.findByName(widget, "weatherForecast");
        harness.watch("pills.y", pills, "yChanged", () => pills.y);
        harness.watch("rule.h", rule, "heightChanged", () => rule.height);
        harness.watch("strip.op", strip, "opacityChanged", () => strip.opacity);
        // The shape morph itself: morphT must sweep 0 -> 1 on a shape change,
        // not flip at the top - the retarget-through-a-live-Behavior bug made
        // exactly that snap while every position trail stayed green.
        if (glyph && glyph.children.length > 0 && glyph.children[0].morphT !== undefined) {
            const canvas = glyph.children[0];
            harness.watch("glyph.morphT", canvas, "morphTChanged", () => canvas.morphT);
        }
        widget.commitGridSize(harness.spanOf(pair[1]));
        harness.currentSpan = pair[1];
        settleTimer.start();
    }

    Timer { id: settleTimer; interval: 1100; onTriggered: {
        const pair = harness.transitions[harness.transitionIndex];
        const tag = `${pair[0]}->${pair[1]}`;
        harness.unwatchAll();
        for (const label in harness.trails) {
            const trail = harness.trails[label];
            const first = trail[0], last = trail[trail.length - 1];
            const moved = label === "glyph.morphT"
                ? trail.some(v => v > 0.05 && v < 0.95)
                : Math.abs(last - first) > 0.5;
            if (label === "glyph.morphT" && trail.length > 1 && !moved) {
                harness.check(`${tag} glyph.morphT sweeps instead of flipping`, false);
                continue;
            }
            if (!moved) { console.log(`[WeatherTreeMotion] ${tag} ${label}: static`); continue; }
            harness.check(`${tag} ${label} animates (${trail.length} steps)`, trail.length >= 4);
        }
        harness.transitionIndex++;
        if (harness.transitionIndex < harness.transitions.length) {
            nextTimer.start();
        } else {
            countPhase.start();
        }
    } }
    Timer { id: nextTimer; interval: 250; onTriggered: harness.beginTransition() }

    // ---- the second row's day count -------------------------------------
    //
    // The providers disagree - wttr.in answers with three days and
    // OpenWeatherMap with four - and a failed forecast request answers with
    // none, on a provider whose current conditions arrived fine. The row
    // divides the strip by the count it is handed, so all three are laid out
    // here rather than reasoned about: a layout that only ever saw four would
    // leave a hole on the default provider's alternative and nothing would
    // report it.
    readonly property var countCases: [4, 3, 1, 0]
    property int countIndex: 0

    Timer { id: countPhase; interval: 250; onTriggered: {
        widget.commitGridSize(harness.spanOf("3x2"));
        harness.currentSpan = "3x2";
        countSettle.start();
    } }
    Timer { id: countSettle; interval: 900; onTriggered: harness.runCountCase() }

    function runCountCase() {
        harness.seedForecast(harness.countCases[harness.countIndex]);
        countCheck.start();
    }

    Timer { id: countCheck; interval: 700; onTriggered: {
        const count = harness.countCases[harness.countIndex];
        const strip = harness.findByName(widget, "weatherForecast");
        const cards = [];
        for (const child of strip.children)
            if (child.width > 0) cards.push(child);
        cards.sort((a, b) => a.x - b.x);
        harness.check(`${count} days -> ${cards.length} cards`, cards.length === count);
        if (count > 0) {
            const last = cards[cards.length - 1];
            harness.check(`${count} days fill the strip`,
                Math.abs(cards[0].x) < 0.5
                && Math.abs(last.x + last.width - strip.width) < 0.5);
            harness.check(`${count} days: the strip is shown`, strip.opacity > 0.9);
        } else {
            // Not merely hidden: the delegates are gone, so no CustomIcon is
            // held warm for a band that is not drawn.
            harness.check("no forecast: the strip is gone", strip.opacity < 0.01);
            const highLow = harness.findByName(widget, "weatherHighLow");
            harness.check("no forecast: the high/low line comes back at 3x2",
                highLow.opacity > 0.5);
        }
        harness.shoot(`3x2_${count}days`);
        // The shot lands on a LATER frame than the call, so seeding the next
        // count in this handler files each case's PNG under the previous
        // case's name - which is the same trap that once filed a transition's
        // first frame as "settled", one screenshot removed. Let the grab
        // happen before moving on.
        countAdvance.start();
    } }

    Timer { id: countAdvance; interval: 200; onTriggered: {
        harness.countIndex++;
        if (harness.countIndex < harness.countCases.length) {
            harness.runCountCase();
        } else {
            console.log(`[WeatherTreeMotion] failures: ${harness.failures}`);
            Qt.quit();
        }
    } }

    Timer { id: t0; interval: 1200; running: true; onTriggered: {
        harness.seedWeather();
        PluginState.setPosition("nandoroid_weather", harness.testScreen, { x: 40, y: 40, placementStrategy: "free" });
        settle0.start();
    } }
    Timer { id: settle0; interval: 800; onTriggered: harness.beginTransition() }
}
