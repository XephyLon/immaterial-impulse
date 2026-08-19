import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.imi.bar
import qs.services
import "modules/imi/bar/bar_popup_unroll.js" as BarPopupUnroll
import "modules/common/functions/weatherForecast.js" as WeatherForecast

/**
 * The weather popup with an hourly row in it, measured where the card can see
 * it.
 *
 * Two separate things are checked, and neither is reachable from a unit test.
 *
 * The first is the HERO. `BarPopupOverlay` opens the card at the height of the
 * content's first DRAWN section and unfurls from there, so adding a section to
 * a popup changes what that measurement returns unless the section lands after
 * the hero - and `heroSectionHeight` skips undrawn and zero-height children, so
 * "after the hero" is a fact about the built tree rather than about the source.
 * A row that became the hero would open the card as a 60px strip with the
 * temperature and the city below the fold.
 *
 * The second is the GROWTH. The bars grow from the axis on `charted`, which is
 * the popup's own visibility, so the motion plays on a refresh as well as on an
 * open - the tree this was taken from writes the heights from a NumberAnimation
 * that destroys the binding, so its chart animates on open and never on data
 * (docs/p3drovfx-animation-research-2026-08-16.md §3.3). A settled height is
 * the same number whether it animated or teleported, so every growth check
 * samples the bars in flight.
 *
 * Driven by tests/test_weather_popup_hero_runtime.py under headless weston and
 * its own bus. Nothing here needs a layer surface: the content is parented into
 * an ordinary window, which is what the overlay does to it anyway.
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int checksRun: 0
    property int step: 0

    // Sampled in flight and compared later, because a settled bar is the same
    // height whether it grew or snapped there.
    property real growthSample: -1
    property real settledFirstSeries: -1
    property real refreshSample: -1

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[WeatherHero] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function finish() {
        console.log(`[WeatherHero] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }

    // Slots the row will actually show: the module keeps only what is still
    // ahead of now, so a fixture with fixed timestamps would be empty by
    // definition.
    function seed(temps) {
        const base = new Date();
        return temps.map(function (temp, index) {
            const when = new Date(base.getTime() + (index + 1) * 3600 * 1000);
            return {
                ms: when.getTime(),
                date: WeatherForecast.localIsoDate(when),
                hour: when.getHours(),
                temp: temp,
                wCode: 800
            };
        });
    }

    function named(name) {
        const children = popup.contentItem?.children ?? [];
        for (let index = 0; index < children.length; index++) {
            if (children[index].objectName === name)
                return children[index];
        }
        return null;
    }

    function chartItem() {
        const children = popup.contentItem?.children ?? [];
        for (let index = 0; index < children.length; index++) {
            if (children[index].objectName === "hourlyChart")
                return children[index];
        }
        return null;
    }

    function chartIndex() {
        const children = popup.contentItem?.children ?? [];
        for (let index = 0; index < children.length; index++) {
            if (children[index].objectName === "hourlyChart")
                return index;
        }
        return -1;
    }

    // Every bar in the row, found by name rather than by walking a fixed path
    // through the layout - a delegate gains a label and the path moves.
    function bars(node, found) {
        const sink = found ?? [];
        if (!node)
            return sink;
        if (node.objectName === "hourlyBar")
            sink.push(node);
        const children = node.children ?? [];
        for (let index = 0; index < children.length; index++)
            harness.bars(children[index], sink);
        return sink;
    }

    function tallestBar() {
        let tallest = 0;
        harness.bars(harness.chartItem()).forEach(function (bar) {
            tallest = Math.max(tallest, bar.height);
        });
        return tallest;
    }

    function schedule(ms) {
        stepTimer.interval = ms;
        stepTimer.restart();
    }

    FloatingWindow {
        id: window
        implicitWidth: 420
        implicitHeight: 640
        color: "black"

        WeatherPopup {
            id: popup
        }

        Component.onCompleted: {
            // What the overlay does with a popup's content when it takes the
            // card: an unparented tree never polishes, so nothing about it can
            // be measured until it is in a window.
            popup.contentItem.parent = window.contentItem;
            Weather.hourly = harness.seed([9, 12, 17, 21, 14]);
            harness.schedule(1500);
        }
    }

    Timer {
        id: stepTimer
        repeat: false
        onTriggered: {
            harness.step++;
            switch (harness.step) {
            case 1: {
                const content = popup.contentItem;
                const chart = harness.chartItem();
                const padding = popup.contentPadding;
                const hero = BarPopupUnroll.heroSectionHeight(content.children, padding);
                const openHeight = content.implicitHeight + padding * 2;

                // Printed rather than only asserted: the numbers are what a
                // reviewer needs when a later section moves the hero.
                console.log(`[WeatherHero] geometry: hero=${hero} open=${openHeight} row=${chart ? chart.height : -1}`);

                harness.check("the hourly row is drawn",
                              !!chart && chart.visible && chart.height > 0);
                harness.check("the row is not the popup's first section",
                              harness.chartIndex() > 0);
                // Against the hero card BY NAME, never against `children[0]`:
                // a row that became the first child would satisfy that
                // comparison by being what it measured.
                harness.check("the card still unrolls from the hero card",
                              hero === harness.named("weatherHero").height + padding * 2);
                harness.check("the hero is a fraction of the open height, so there is still an unroll",
                              hero > 0 && hero < openHeight);
                // The feature's name, measured: every bar's bottom edge is the
                // same line, so what moves is the top.
                const feet = harness.bars(chart).map(function (bar) {
                    return bar.mapToItem(chart, 0, bar.height).y;
                });
                harness.check("the bars stand on one axis, whatever their height",
                              feet.length > 1
                              && feet.every(function (foot) { return Math.abs(foot - feet[0]) < 0.5; }));
                harness.check("the bars are flat while the popup is not showing",
                              harness.tallestBar() === 0);

                popup.pinnedOpen = true;
                harness.schedule(80);
                break;
            }
            case 2:
                harness.growthSample = harness.tallestBar();
                harness.schedule(1200);
                break;
            case 3:
                harness.settledFirstSeries = harness.tallestBar();
                harness.check("the bars settle at a height",
                              harness.settledFirstSeries > 0);
                harness.check("the bars grew from the axis rather than appearing at full height",
                              harness.growthSample > 0
                              && harness.growthSample < harness.settledFirstSeries - 1);

                // The refresh case: a series whose coldest hour becomes the
                // warmest, under a popup that is already open.
                Weather.hourly = harness.seed([21, 17, 12, 9, 14]);
                harness.schedule(80);
                break;
            case 4:
                harness.refreshSample = harness.tallestBar();
                harness.schedule(1200);
                break;
            case 5: {
                const settled = harness.tallestBar();
                harness.check("a refresh under an open popup animates rather than popping",
                              harness.refreshSample > 0
                              && Math.abs(harness.refreshSample - settled) > 0.5);

                Weather.hourly = [];
                harness.schedule(400);
                break;
            }
            case 6: {
                const content = popup.contentItem;
                const padding = popup.contentPadding;
                const chart = harness.chartItem();
                harness.check("a provider with no hourly data leaves no empty row",
                              !!chart && !chart.visible);
                harness.check("and the card still opens at the hero card",
                              BarPopupUnroll.heroSectionHeight(content.children, padding)
                              === harness.named("weatherHero").height + padding * 2);
                harness.finish();
                break;
            }
            }
        }
    }
}
