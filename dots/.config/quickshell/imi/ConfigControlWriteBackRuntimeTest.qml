import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.imi.settings.pages

/**
 * Opens a real settings page against a config its own controls cannot
 * represent, and checks that merely looking at it changes nothing.
 *
 * The bug this exists for: `SidebarsPanelsConfig.qml`'s OSD timeout spin box
 * declares `to: 3000`, while `Config.qml` declares a plain `int` and the shell
 * honours whatever is in it. A config holding `osd.timeout: 4321` was clamped
 * to 3000 and written straight back the moment the page was instantiated -
 * QQC2's SpinBox bounds `value` when the component completes and emits
 * `valueChanged`, and every settings page hung its write-back off exactly that
 * signal. No user, no interaction, no warning, and `Config` is a `JsonAdapter`
 * that rewrites the whole file.
 *
 * So the first half asserts the negative - the page is built, the control is
 * there, and `Config.options.osd.timeout` is still 4321. The second half
 * asserts the control is not merely inert: a real click on its decrement
 * button, delivered through QtTest, does write.
 *
 * Run against a throwaway XDG_CONFIG_HOME; it writes config.json:
 *   XDG_CONFIG_HOME=$(mktemp -d) XDG_STATE_HOME=$(mktemp -d) \
 *     qs -p ConfigControlWriteBackRuntimeTest.qml
 */
ShellRoot {
    id: harness

    // What the seeded config.json holds, and what the control's own range
    // would have clamped it to.
    readonly property int storedTimeout: 4321
    readonly property int controlMaximum: 3000
    readonly property int stepSize: 100

    property int failures: 0
    property int checksRun: 0
    property var timeoutSpinBox: null

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[ConfigControlWriteBack] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function finish() {
        console.log(`[ConfigControlWriteBack] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }

    function findByName(item, name) {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        for (let i = 0; i < item.children.length; i++) {
            const found = harness.findByName(item.children[i], name);
            if (found)
                return found;
        }
        return null;
    }

    TestCase {
        id: driver
        when: false
        name: "ConfigControlWriteBackDriver"
    }

    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 900
        implicitHeight: 700
        color: "black"

        // Built only once the config has actually loaded, which is what the
        // real Settings window does - it is opened from an already-running
        // shell. Instantiating the page at startup instead hides the bug: the
        // page is constructed against schema defaults and its binding is gone
        // by the time the file lands, so nothing ever clamps the real value.
        Loader {
            id: pageLoader
            anchors.fill: parent
            active: harness.configSettled
            sourceComponent: SidebarsPanelsConfig {}
        }
    }

    property bool configSettled: false
    readonly property var page: pageLoader.item

    Timer {
        id: settle
        interval: 400
        repeat: true
        running: true
        property int ticks: 0
        onTriggered: {
            settle.ticks++;
            if (!Config.ready) {
                if (settle.ticks > 25) {
                    harness.check("Config became ready", false);
                    harness.finish();
                }
                return;
            }
            harness.check("the config loaded with the out-of-range value intact",
                          Config.options.osd.timeout === harness.storedTimeout);
            settle.running = false;
            harness.configSettled = true;
            build.running = true;
        }
    }

    Timer {
        id: build
        // Long enough for the page to complete and for Config's debounced
        // write timer to have fired, had anything triggered it.
        interval: 1200
        onTriggered: {
            harness.timeoutSpinBox = harness.findByName(harness.page, "osdTimeoutSpinBox");
            inspect.running = true;
        }
    }

    Timer {
        id: inspect
        interval: 200
        onTriggered: {
            harness.check("the page built and the OSD timeout control exists",
                          harness.timeoutSpinBox !== null);
            if (!harness.timeoutSpinBox) {
                harness.finish();
                return;
            }

            // The whole bug, in one assertion.
            harness.check("opening the page leaves the stored value alone",
                          Config.options.osd.timeout === harness.storedTimeout);
            harness.check("and did not clamp it to the control's maximum",
                          Config.options.osd.timeout !== harness.controlMaximum);

            // A control silently reading 3000 for a config of 4321 is the same
            // lie told quietly, so the range has to widen to admit it.
            harness.check("the control shows what the config actually holds",
                          harness.timeoutSpinBox.value === harness.storedTimeout);

            // The OSD section is far down a long page, so the control is off
            // screen until the flickable is scrolled to it - a click at its
            // mapped coordinates would land outside the window and prove
            // nothing.
            harness.page.contentY = harness.timeoutSpinBox.mapToItem(harness.page.contentItem, 0, 0).y
                - window.height / 2;
            press.running = true;
        }
    }

    Timer {
        id: press
        interval: 400
        onTriggered: {
            // The spin box is the last child of the ConfigSpinBox row, and its
            // decrement button is the square at the left end.
            const spin = harness.timeoutSpinBox.children[harness.timeoutSpinBox.children.length - 1];
            const indicator = spin.down.indicator;
            const point = indicator.mapToItem(window.contentItem,
                                              indicator.width / 2, indicator.height / 2);
            harness.check("the control is on screen to be clicked",
                          point.x > 0 && point.y > 0
                          && point.x < window.width && point.y < window.height);
            driver.mouseClick(spin, indicator.x + indicator.width / 2,
                              indicator.y + indicator.height / 2, Qt.LeftButton);
            verify.running = true;
        }
    }

    Timer {
        id: verify
        interval: 400
        onTriggered: {
            harness.check("a real click on the decrement button does write",
                          Config.options.osd.timeout === harness.storedTimeout - harness.stepSize);
            harness.finish();
        }
    }
}
