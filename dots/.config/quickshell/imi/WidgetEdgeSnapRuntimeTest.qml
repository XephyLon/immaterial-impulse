import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.plugins
import qs.modules.common.widgets.widgetCanvas

/**
 * Drives the widget-to-widget edge snap (spec §6) with real mouse events, in
 * the live drag path - the half `tst_edge_snap.qml` cannot reach. The module's
 * arithmetic is proven there; what only real events can prove is the WIRING:
 * that the hold actually overrides the lattice in the drag Binding, that the
 * hysteresis is fed the shadow position rather than the rendered one, that
 * the canvas draws the guide where the hold says, that the perpendicular
 * filter refuses a distant neighbour on a real drag, and that a group drag's
 * leader snapping an edge moves the cluster whole.
 *
 * The anchor's x (305) is deliberately OFF the 12px lattice: every landing
 * this file asserts on a neighbour's edge is a position the lattice snap
 * cannot produce, so a broken wiring cannot pass by coincidence.
 *
 * Run it against a throwaway config:
 *   XDG_CONFIG_HOME=$(mktemp -d) XDG_STATE_HOME=$(mktemp -d) qs -p WidgetEdgeSnapRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int checksRun: 0
    readonly property string testScreen: "EDGE-SNAP-TEST"

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[WidgetEdgeSnap] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function finish() {
        console.log(`[WidgetEdgeSnap] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }

    function manifestFor(id) {
        return {
            id: id,
            name: id,
            defaultWidth: 160,
            defaultHeight: 100,
            desktopWidget: { type: "Item" }
        };
    }

    readonly property var crosserManifest: harness.manifestFor("runtime_edge_crosser")
    readonly property var moverManifest: harness.manifestFor("runtime_edge_mover")
    readonly property var anchorManifest: harness.manifestFor("runtime_edge_anchor")
    readonly property var buddyManifest: harness.manifestFor("runtime_edge_buddy")
    readonly property var distantManifest: harness.manifestFor("runtime_edge_distant")

    function at(widget, x, y) {
        return Math.round(widget.x) === x && Math.round(widget.y) === y;
    }

    // A held press whose pointer is steered by SHADOW position: the drag's
    // proxy is dragStart + pointer delta, so aiming the shadow is one
    // subtraction. Each drag opens with a move past the 10px threshold.
    property real pressX: 0
    property real pressY: 0
    property real startX: 0
    property real startY: 0

    function beginDrag(widget) {
        harness.startX = widget.x;
        harness.startY = widget.y;
        harness.pressX = widget.x + widget.width / 2;
        harness.pressY = widget.y + widget.height / 2;
        driver.mousePress(canvas, harness.pressX, harness.pressY, Qt.LeftButton);
        driver.mouseMove(canvas, harness.pressX + 12, harness.pressY, 20, Qt.LeftButton);
    }

    function moveShadowTo(sx, sy) {
        driver.mouseMove(canvas,
            harness.pressX + (sx - harness.startX),
            harness.pressY + (sy - harness.startY), 20, Qt.LeftButton);
    }

    function releaseAtShadow(sx, sy) {
        driver.mouseRelease(canvas,
            harness.pressX + (sx - harness.startX),
            harness.pressY + (sy - harness.startY), Qt.LeftButton);
    }

    FloatingWindow {
        visible: true
        implicitWidth: 1160
        implicitHeight: 700
        color: "black"

        TestCase {
            id: driver
            when: false
            name: "WidgetEdgeSnapDriver"
        }

        WidgetCanvas {
            id: canvas
            anchors.fill: parent
            selectionEnabled: true

            PluginWidget {
                id: crosserWidget
                manifest: harness.crosserManifest
                screenName: harness.testScreen
                screenWidth: 1160
                screenHeight: 700
                scaledScreenWidth: 1160
                scaledScreenHeight: 700
                wallpaperScale: 1
            }

            PluginWidget {
                id: moverWidget
                manifest: harness.moverManifest
                screenName: harness.testScreen
                screenWidth: 1160
                screenHeight: 700
                scaledScreenWidth: 1160
                scaledScreenHeight: 700
                wallpaperScale: 1
            }

            PluginWidget {
                id: anchorWidget
                manifest: harness.anchorManifest
                screenName: harness.testScreen
                screenWidth: 1160
                screenHeight: 700
                scaledScreenWidth: 1160
                scaledScreenHeight: 700
                wallpaperScale: 1
            }

            PluginWidget {
                id: buddyWidget
                manifest: harness.buddyManifest
                screenName: harness.testScreen
                screenWidth: 1160
                screenHeight: 700
                scaledScreenWidth: 1160
                scaledScreenHeight: 700
                wallpaperScale: 1
            }

            PluginWidget {
                id: distantWidget
                manifest: harness.distantManifest
                screenName: harness.testScreen
                screenWidth: 1160
                screenHeight: 700
                scaledScreenWidth: 1160
                scaledScreenHeight: 700
                wallpaperScale: 1
            }
        }
    }

    // crosser and mover are the dragged widgets; anchor (off-lattice at 305)
    // is the edge they align to; buddy is the group drag's follower; distant
    // sits 622px across the axis from crosser's column, past the 600px
    // relevance limit, with its top edge placed so a vertical drag releases
    // within its acquire band - the refusal is only provable where the snap
    // would otherwise have fired.
    function placeWidgets() {
        PluginState.setPosition("runtime_edge_crosser", harness.testScreen,
                                { x: 48, y: 48, placementStrategy: "free" });
        PluginState.setPosition("runtime_edge_mover", harness.testScreen,
                                { x: 500, y: 48, placementStrategy: "free" });
        PluginState.setPosition("runtime_edge_anchor", harness.testScreen,
                                { x: 305, y: 48, placementStrategy: "free" });
        PluginState.setPosition("runtime_edge_buddy", harness.testScreen,
                                { x: 700, y: 600, placementStrategy: "free" });
        PluginState.setPosition("runtime_edge_distant", harness.testScreen,
                                { x: 830, y: 380, placementStrategy: "free" });
    }

    // Same settle loop as the sibling harnesses: PluginState's FileView load
    // lands asynchronously and replays the file over anything written early.
    Timer {
        id: setup
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            if (!PluginState.ready || !Config.ready)
                return;
            Config.options.background.widgetsLocked = false;
            Config.options.background.showSnapLines = true;
            if (harness.at(crosserWidget, 48, 48)
                    && harness.at(moverWidget, 500, 48)
                    && harness.at(anchorWidget, 305, 48)
                    && harness.at(buddyWidget, 700, 600)
                    && harness.at(distantWidget, 830, 380)) {
                setup.running = false;
                stepPerp.running = true;
                return;
            }
            harness.placeWidgets();
        }
    }

    // ---- the perpendicular relevance filter, on a real drag ---------------
    // crosser's column (x 48..208) is 622px short of distant (x 830..990), so
    // distant's far-to-near target at 280 (its top edge 380 minus crosser's
    // height) must NOT fire even though the drag releases 5px from it. The
    // lattice takes the release instead: 285 rounds to 288, and 280 is what a
    // missing filter would have produced.
    Timer {
        id: stepPerp
        interval: 400
        onTriggered: {
            harness.check("the helpers ride showSnapLines and it is on",
                          Config.options.background.showSnapLines === true);
            harness.beginDrag(crosserWidget);
            harness.moveShadowTo(48, 285);
            harness.releaseAtShadow(48, 285);
            stepPerpVerify.running = true;
        }
    }

    Timer {
        id: stepPerpVerify
        interval: 400
        onTriggered: {
            harness.check("a neighbour across the axis offers no edge",
                          harness.at(crosserWidget, 48, 288));
            harness.check("no guide survives the refused drag",
                          canvas.edgeGuideXActive === false
                              && canvas.edgeGuideYActive === false);
            stepAcquire.running = true;
        }
    }

    // ---- acquire, the detent, and the release, mid-drag -------------------
    // mover walks left toward anchor's right edge (465). The shadow stops
    // 10px short: inside the acquire band, and on a target the lattice cannot
    // produce (465 is not a multiple of 12).
    Timer {
        id: stepAcquire
        interval: 400
        onTriggered: {
            harness.beginDrag(moverWidget);
            harness.moveShadowTo(475, 48);
            stepAcquireVerify.running = true;
        }
    }

    Timer {
        id: stepAcquireVerify
        interval: 300
        onTriggered: {
            harness.check("inside the acquire band the widget sits on the neighbour's edge, off the lattice",
                          Math.round(moverWidget.x) === 465);
            harness.check("and the vertical guide is up at that edge",
                          canvas.edgeGuideXActive === true
                              && Math.round(canvas.edgeGuideXPos) === 465);
            // 24px past the target: between the two thresholds. A single
            // threshold - or a resolver fed the rendered position - has
            // already let go here.
            harness.moveShadowTo(441, 48);
            stepDetentVerify.running = true;
        }
    }

    Timer {
        id: stepDetentVerify
        interval: 300
        onTriggered: {
            harness.check("between the thresholds the hold survives - the detent",
                          Math.round(moverWidget.x) === 465);
            harness.check("and the guide stays up with it",
                          canvas.edgeGuideXActive === true);
            // 40px past: released, and the lattice takes back over (425
            // rounds to 420).
            harness.moveShadowTo(425, 48);
            stepReleaseVerify.running = true;
        }
    }

    Timer {
        id: stepReleaseVerify
        interval: 300
        onTriggered: {
            harness.check("past the release threshold the lattice takes back over",
                          Math.round(moverWidget.x) === 420);
            harness.check("and the guide goes down",
                          canvas.edgeGuideXActive === false);
            harness.releaseAtShadow(425, 48);
            stepCommitVerify.running = true;
        }
    }

    Timer {
        id: stepCommitVerify
        interval: 400
        onTriggered: {
            harness.check("the release commits the lattice landing",
                          harness.at(moverWidget, 420, 48));
            // A second drag released INSIDE the hold: the commit is the
            // neighbour's edge, off the lattice, and it sticks.
            harness.beginDrag(moverWidget);
            harness.moveShadowTo(470, 48);
            harness.releaseAtShadow(470, 48);
            stepHeldCommitVerify.running = true;
        }
    }

    Timer {
        id: stepHeldCommitVerify
        interval: 400
        onTriggered: {
            harness.check("a release inside the hold commits the neighbour's edge, off the lattice",
                          harness.at(moverWidget, 465, 48));
            harness.check("the guides do not outlive the gesture",
                          canvas.edgeGuideXActive === false
                              && canvas.edgeGuideYActive === false);
            // Marquee crosser and buddy for the group half - a band that
            // covers both and neither of the top-row widgets.
            driver.mousePress(canvas, 20, 270, Qt.LeftButton);
            driver.mouseMove(canvas, 400, 500, 20, Qt.LeftButton);
            driver.mouseMove(canvas, 780, 700, 20, Qt.LeftButton);
            driver.mouseRelease(canvas, 780, 700, Qt.LeftButton);
            stepGroup.running = true;
        }
    }

    // ---- the group drag's leader snaps, the followers keep their offsets --
    Timer {
        id: stepGroup
        interval: 400
        onTriggered: {
            harness.check("the marquee selected the pair",
                          canvas.selectedWidgets.length === 2);
            harness.beginDrag(crosserWidget);
            // Toward anchor's left edge at 305, released still pressed: the
            // leader must hold it while both followers' offsets stand.
            harness.moveShadowTo(297, 288);
            stepGroupVerify.running = true;
        }
    }

    Timer {
        id: stepGroupVerify
        interval: 300
        onTriggered: {
            harness.check("the group's leader holds the neighbour's edge mid-drag",
                          Math.round(crosserWidget.x) === 305);
            harness.check("the follower keeps its x offset through the snap",
                          Math.round(buddyWidget.x - crosserWidget.x) === 652);
            harness.check("the follower keeps its y offset through the snap",
                          Math.round(buddyWidget.y - crosserWidget.y) === 312);
            harness.releaseAtShadow(297, 288);
            stepGroupCommitVerify.running = true;
        }
    }

    Timer {
        id: stepGroupCommitVerify
        interval: 400
        onTriggered: {
            harness.check("the release leaves the cluster where the snap put it",
                          Math.round(crosserWidget.x) === 305
                              && Math.round(buddyWidget.x - crosserWidget.x) === 652
                              && Math.round(buddyWidget.y - crosserWidget.y) === 312);
            harness.finish();
        }
    }
}
