import QtQuick
import QtQuick.Layouts
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.imi.phone
import qs.modules.imi.sidebarLeft.phone

/**
 * How wide the Phone tab's Webcam and Microphone sub-pages ASK to be, and
 * where their rows are actually drawn, measured in a real window.
 *
 * The defect this exists for is invisible to every static check and to
 * `qmltestrunner`: both pages are a `ContentPage`, whose content column is
 * `Math.max(baseWidth, implicitWidth)` wide and centred in the flickable.
 * `baseWidth` defaults to 600 - a settings-window number - so inside a 460px
 * sidebar the column hung ~80px off each side and every row was clipped at
 * the panel's left edge while the page rendered perfectly and logged nothing.
 * The second half is the same failure from the other end: a `NoticeBox`
 * reports its string's UNWRAPPED width as its implicit width, so one long
 * service error (`PhoneCamera.lastError`) widened the whole page past even
 * that 600.
 *
 * So every check here is one of two numbers read off an item that is on
 * screen: where a row is drawn against the page's own box, and what a row
 * ASKS for - its implicit width, clamped by whatever `Layout.maximumWidth`
 * it declares, because that pair is exactly what a QQuickLayout resolves a
 * child's preferred width to.
 *
 * The pages are built inside the REAL tab, by the real `subPageLoader`, so
 * the width being measured is the width the panel really hands them.
 *
 * Two properties keep this harness off the maintainer's machine. Every tool
 * `PhoneDeps` probes is a stub first on PATH, so `PhoneMic` - which runs
 * `pactl get-default-sink` from its own `Component.onCompleted` and can go
 * on to `set-default-sink` - never reaches the session's audio. And the
 * daemon is a fake `busctl`, under a bus of the driver's own.
 *
 * Driven by tests/test_phone_subpage_width_runtime.py, which brings the
 * weston, the session bus and those stubs.
 *
 *   PATH=<dir with the stubs>:$PATH qs -p PhoneSubPageWidthRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int checksRun: 0
    property int elapsed: 0

    // The maintainer's own screenshot: this is the string that was drawn as
    // "m did not start - is the DroidCam app open on the phone?", its start
    // hanging off the left edge of the panel.
    readonly property string longError: "DroidCam did not start - is the DroidCam app open on the phone?"

    // The panel's real width (Appearance.sizes.sidebarWidth), and the width
    // it takes when the sidebar is extended. The second one is not decoration:
    // a page pinned to a literal 440 passes every check at the first width.
    property real viewportWidth: 460
    property real narrowWidth: 0

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[PhoneSubPageWidth] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function typeName(obj) {
        return `${obj}`.split("(")[0].split("_QML")[0].trim();
    }

    function findAll(item, type, out) {
        if (!item)
            return out;
        for (const child of item.children) {
            if (harness.typeName(child) === type)
                out.push(child);
            harness.findAll(child, type, out);
        }
        return out;
    }

    function first(type) {
        return harness.findAll(loader.item, type, [])[0] ?? null;
    }

    function boxIn(item, reference) {
        const origin = item.mapToItem(reference, 0, 0);
        return { left: origin.x, right: origin.x + item.width };
    }

    // What a row asks its column for. `Layout.maximumWidth` defaults to
    // infinity, so this is the implicit width for a row that declares none -
    // and the clamped value for one that does, which is what the engine
    // resolves the preferred width to.
    function askedWidth(row) {
        const cap = row.Layout.maximumWidth;
        return (cap !== undefined && cap > 0) ? Math.min(row.implicitWidth, cap) : row.implicitWidth;
    }

    // The rows a page draws: the direct children of the ContentPage's own
    // content column, which is where every NoticeBox and ContentSection of
    // these two pages lands.
    function pageRows(page) {
        const flickable = harness.findAll(page, "ContentPage", [])[0] ?? null;
        if (flickable === null)
            return null;
        const column = flickable.contentItem.children
            .find(child => harness.typeName(child) === "QQuickColumnLayout") ?? null;
        if (column === null)
            return null;
        return {
            flickable: flickable,
            column: column,
            rows: [...column.children].filter(child => child.visible)
        };
    }

    function measure(type, label) {
        const page = harness.first(type);
        const found = page === null ? null : harness.pageRows(page);
        if (found === null) {
            harness.check(`${label}: the page and its content column are on screen`, false);
            return null;
        }

        const widest = found.rows
            .map(row => ({ name: harness.typeName(row), asked: harness.askedWidth(row),
                           implicit: row.implicitWidth, drawn: harness.boxIn(row, page) }))
            .sort((a, b) => b.asked - a.asked);
        console.log(`[PhoneSubPageWidth] ${label}: page ${page.width} flickable ${found.flickable.width}`
                    + ` column ${found.column.width} (implicit ${found.column.implicitWidth})`);
        for (const row of widest)
            console.log(`[PhoneSubPageWidth]   ${row.name} asked ${row.asked}`
                        + ` implicit ${row.implicit} drawn ${row.drawn.left}-${row.drawn.right}`);

        // The column is what centres, so it is where the overflow starts.
        harness.check(`${label}: the content column fits the page, got ${found.column.width}`
                      + ` in ${found.flickable.width}`,
                      found.column.width <= found.flickable.width + 1);

        const outside = widest.filter(row => row.drawn.left < -1 || row.drawn.right > page.width + 1);
        harness.check(`${label}: every row is drawn inside the page, ${outside.length} are not`
                      + `${outside.length > 0 ? ` (${outside[0].name} at ${outside[0].drawn.left}`
                        + `-${outside[0].drawn.right} of ${page.width})` : ""}`,
                      outside.length === 0 && widest.length > 0);

        const overWide = widest.filter(row => row.asked > page.width + 1);
        harness.check(`${label}: no row asks for more width than the page has,`
                      + ` widest is ${widest[0]?.name} at ${widest[0]?.asked} of ${page.width}`,
                      overWide.length === 0);
        return found;
    }

    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 760
        implicitHeight: 900
        color: "black"

        TestCase {
            id: driver
            when: false
            name: "PhoneSubPageWidthDriver"
        }

        // The host is sized by the harness rather than by the window, because
        // a FloatingWindow cannot be resized under headless weston - the same
        // constraint PhoneTabLayoutRuntimeTest.qml records for its height.
        Loader {
            id: loader
            width: harness.viewportWidth
            height: parent.height
            active: false
            sourceComponent: Phone {}
        }
    }

    Component.onCompleted: {
        // A singleton is constructed on first use; this read starts the
        // presence probes and the daemon sweep.
        console.log(`[PhoneSubPageWidth] services constructed, installed=${PhoneConnect.installed}`);
    }

    Timer {
        id: waitForReady
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            harness.elapsed += waitForReady.interval;
            const ready = Config.ready && PhoneConnect.installed
                && PhoneConnect.devices.length === 1 && PhoneDeps.ready;
            if (!ready) {
                if (harness.elapsed >= 40000) {
                    harness.check(`the fake daemon answered and the probes settled`
                                  + ` (devices ${PhoneConnect.devices.length},`
                                  + ` deps ready ${PhoneDeps.ready})`, false);
                    harness.finish();
                }
                return;
            }
            waitForReady.running = false;
            steps.running = true;
        }
    }

    function finish() {
        console.log(`[PhoneSubPageWidth] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }

    property var stepList: [
        () => {
            loader.active = true;
        },
        () => {},

        // ---- the webcam page, as it opens ---------------------------------
        () => loader.item.openSubPage("webcam"),
        () => {},
        () => {
            harness.narrowWidth = harness.measure("PhoneWebcamPage", "webcam")?.flickable.width ?? 0;
        },

        // ---- ...and with the service reporting a failure -------------------
        () => {
            PhoneCamera.lastError = harness.longError;
        },
        () => {},
        () => {
            const page = harness.first("PhoneWebcamPage");
            const banner = harness.findAll(page, "NoticeBox", []).find(box => box.visible
                && String(box.text).indexOf("DroidCam did not start") >= 0) ?? null;
            // The control: a pass measured with the banner absent measures the
            // page without the row it exists to measure, and says nothing.
            harness.check("the error banner is on screen to be measured", banner !== null);
            harness.measure("PhoneWebcamPage", "webcam with a long service error");
        },

        // ---- ...at the width an extended sidebar gives it ------------------
        () => {
            harness.viewportWidth = 740;
        },
        () => {},
        () => {
            const found = harness.measure("PhoneWebcamPage", "webcam in a wider panel");
            harness.check(`the page really did get wider, got ${found?.flickable.width}`
                          + ` against ${harness.narrowWidth}`,
                          found !== null && found.flickable.width > harness.narrowWidth + 100);
            // A column that follows the panel, rather than one that happens to
            // fit at both widths because it is a constant under both.
            harness.check(`...and the column followed it, got ${found?.column.width}`,
                          found !== null && found.column.width > harness.narrowWidth);
        },
        () => {
            harness.viewportWidth = 460;
            loader.item.popSubPage();
        },
        () => {},

        // ---- the microphone page, at rest and reporting a failure ---------
        () => loader.item.openSubPage("mic"),
        () => {},
        () => harness.measure("PhoneMicPage", "microphone"),
        () => {
            PhoneMic.lastError = harness.longError;
        },
        () => {},
        () => {
            const page = harness.first("PhoneMicPage");
            const banner = harness.findAll(page, "NoticeBox", []).find(box => box.visible
                && String(box.text).indexOf("DroidCam did not start") >= 0) ?? null;
            harness.check("the microphone's error banner is on screen to be measured",
                          banner !== null);
            harness.measure("PhoneMicPage", "microphone with a long service error");
        },

        () => harness.finish()
    ]

    property int stepIndex: 0
    Timer {
        id: steps
        interval: 500
        repeat: true
        onTriggered: {
            if (harness.stepIndex >= harness.stepList.length)
                return;
            harness.stepList[harness.stepIndex++]();
        }
    }
}
