import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.plugins
import qs.modules.common.widgets.widgetCanvas
import "modules/common/plugins/designsystem/services" as ExpressiveServices

/*
 * The movement block's registration against the value it describes, measured
 * on the rendered tree rather than screenshotted off a desktop a window may
 * be covering. Service values are seeded (two daily closes per quote), the
 * widget is driven to its detailed spans, and each visible movement column
 * must share its value's bottom line. CURRENCY_ALIGN_SHOTS takes PNGs of
 * both spans for the visual half.
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
        console.log(`[CurrencyAlign] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok) harness.failures++;
    }

    readonly property var manifest: {
        const base = Quickshell.shellPath("modules/common/plugins/bundled/nandoroid-currency");
        return {
            id: "nandoroid_currency",
            name: "currency align probe",
            _basePath: base,
            grid: { cols: 2, rows: 1,
                sizes: [{ cols: 2, rows: 1 }, { cols: 3, rows: 1 }, { cols: 3, rows: 2 }] },
            desktopWidget: { component: "Widget.qml" }
        };
    }

    function dateKey(t) {
        const d = new Date(t);
        const month = String(d.getUTCMonth() + 1).padStart(2, "0");
        const day = String(d.getUTCDate()).padStart(2, "0");
        return `${d.getUTCFullYear()}-${month}-${day}`;
    }

    function seedService() {
        const service = ExpressiveServices.CurrencyService;
        const now = Date.now();
        const day = 86400000;
        const quotes = { EUR: 58.81, GBP: 50.74, JPY: 0.3176, CAD: 36.53 };
        const yesterday = {}, before = {};
        for (const code in quotes) {
            yesterday[code] = quotes[code] * 0.999;
            before[code] = quotes[code] * 1.002;
        }
        const days = {};
        days[harness.dateKey(now - day)] = yesterday;
        days[harness.dateKey(now - 2 * day)] = before;
        service.rates = quotes;
        service.daily = { base: "USD", days: days };
        service.loading = false;
        service.errorMessage = "";
    }

    function findAll(item, name, hits) {
        if (!item) return hits;
        if (item.objectName === name) hits.push(item);
        for (const child of item.children)
            harness.findAll(child, name, hits);
        return hits;
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

    property string shotDir: Quickshell.env("CURRENCY_ALIGN_SHOTS") || ""
    function shoot(tag, andThen) {
        if (harness.shotDir === "") { if (andThen) andThen(); return; }
        widget.grabToImage(result => {
            result.saveToFile(`${harness.shotDir}/${tag}.png`);
            if (andThen) andThen();
        });
    }

    function measureSpan(tag) {
        const values = harness.findAll(widget, "currencyQuoteValue", []);
        const columns = harness.findAll(widget, "currencyMovementColumn", []);
        console.log(`[CurrencyAlign] ${tag} diag: values=${values.length} columns=${columns.length}`
            + ` seededRates=${JSON.stringify(ExpressiveServices.CurrencyService.rates)}`
            + ` firstValueText=${values.length > 0 ? values[0].text : "n/a"}`
            + ` firstColVisible=${columns.length > 0 ? columns[0].visible + "/" + columns[0].opacity : "n/a"}`);
        let visibleColumns = 0;
        for (const column of columns) {
            if (!column.visible || column.opacity === 0) continue;
            visibleColumns++;
            // The value in the same cell: the column's parent holds both.
            const cell = column.parent;
            const cellValues = harness.findAll(cell, "currencyQuoteValue", []);
            if (cellValues.length !== 1) {
                harness.check(`${tag}: a movement column can name its value`, false);
                continue;
            }
            const value = cellValues[0];
            const valueBottom = value.mapToItem(widget, 0, value.height).y;
            const columnBottom = column.mapToItem(widget, 0, column.height).y;
            harness.check(
                `${tag}: movement bottom sits on the value's line (|${valueBottom.toFixed(1)} - ${columnBottom.toFixed(1)}|)`,
                Math.abs(valueBottom - columnBottom) <= 1.5);
        }
        harness.check(`${tag}: detailed cells actually showed movement (${visibleColumns})`,
            visibleColumns >= 4);
    }

    Timer { id: t0; interval: 1500; running: true; onTriggered: {
        harness.seedService();
        PluginState.setPosition("nandoroid_currency", harness.testScreen,
            { x: 40, y: 40, placementStrategy: "free" });
        toSpan1.start();
    } }
    Timer { id: toSpan1; interval: 800; onTriggered: {
        widget.commitGridSize({ cols: 3, rows: 2 });
        settle1.start();
    } }
    // Re-seeded right before each measurement: the service's own startup
    // fetch lands after the first seed and clobbers it (no network in the
    // harness, so its error path empties the tables).
    Timer { id: settle1; interval: 1400; onTriggered: {
        harness.seedService();
        postSeed1.start();
    } }
    // Retried: the service's own fetch cadence races the seed, and a late
    // clobber can catch one measurement window with every column mid-fade.
    property int seedTries: 0
    function columnsReady() {
        const columns = harness.findAll(widget, "currencyMovementColumn", []);
        return columns.filter(c => c.visible && c.opacity === 1).length >= 4;
    }
    Timer { id: postSeed1; interval: 300; onTriggered: {
        if (!harness.columnsReady() && harness.seedTries++ < 12) {
            harness.seedService();
            postSeed1.start();
            return;
        }
        harness.seedTries = 0;
        harness.measureSpan("3x2");
        harness.shoot("align_3x2", () => toSpan2.start());
    } }
    Timer { id: toSpan2; interval: 250; onTriggered: {
        widget.commitGridSize({ cols: 3, rows: 1 });
        settle2.start();
    } }
    Timer { id: settle2; interval: 1400; onTriggered: {
        harness.seedService();
        postSeed2.start();
    } }
    Timer { id: postSeed2; interval: 300; onTriggered: {
        if (!harness.columnsReady() && harness.seedTries++ < 12) {
            harness.seedService();
            postSeed2.start();
            return;
        }
        harness.measureSpan("3x1");
        harness.shoot("align_3x1", () => {
            console.log(`[CurrencyAlign] checks: ${harness.checksRun} failures: ${harness.failures}`);
            Qt.quit();
        });
    } }
}
