import QtQuick
import QtQuick.Layouts
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.imi.bar

/**
 * Scores a bar reflow as motion rather than as a result.
 *
 * A settled check cannot tell the reposition from the teleport it replaces:
 * both end with every slot in the right place, and the difference exists only
 * in the frames in between. So this harness samples where each slot is DRAWN
 * 40ms and 240ms into a reflow and fails if it was already at its destination
 * - the same question `WidgetResizeMotionRuntimeTest.qml` asks of a span
 * change, for the same reason.
 *
 * Three strips are built because a bar's buckets are anchored three ways and
 * the interesting slot is a different one in each:
 *
 *   - a LEFT-anchored bucket is the plain case: take a widget out and the ones
 *     after it move, in their row's coordinates and on screen alike;
 *   - a RIGHT-anchored bucket is the case the idiom this was taken from cannot
 *     see. Its section is sized by its row, so removing a widget moves the
 *     SECTION and leaves the first slot at row-local zero: that slot travels
 *     the whole width of what left while its own `x` never changes, and a
 *     reposition watching only `onXChanged` animates every slot but that one.
 *     The harness asserts the slot's own coordinate really did not move, or
 *     the check above passes vacuously - and asserts the mirror image on the
 *     last slot, whose own coordinate changes and which does not travel at all;
 *   - the vertical bar's far-edge bucket is the same turn, down the strip.
 *
 * Three more things are scored, none of them visible from a settled position:
 *
 *   - a widget with no record snaps. That is the first layout of every shell
 *     start - nothing has been drawn yet, so there is nothing to invert from,
 *     and a reposition there would slide the whole bar in from the frame's
 *     origin - and it is equally a widget switched back on minutes later,
 *     whose record expired with the reflow that removed it. The second is what
 *     is driven here, because it runs the same recall on a strip already on
 *     screen;
 *   - a reorder drag in flight suppresses the reposition, because the gesture
 *     reads slot centres through a `mapToItem` that composes the transform
 *     this animates;
 *   - and the motion is along the bar only, at both orientations, which is the
 *     axis-inert comparison the vertical dock's reorder shipped without.
 *
 * The slots are synthetic - real `BarGroup`s carrying a coloured rectangle -
 * because the real bar widget files reach Hyprland, PipeWire and the tray,
 * none of which a weston harness has. What IS real is everything the feature
 * added: BarGroup's translate, its ancestor walk, BarFlipRegistry's deposit,
 * recall and expiry, and bar_flip.js's arithmetic under all of it.
 *
 * Run it against a throwaway config:
 *   XDG_CONFIG_HOME=$(mktemp -d) XDG_STATE_HOME=$(mktemp -d) qs -p BarFlipRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int checksRun: 0

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[BarFlip] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    // Sizes that differ per widget, so a reflow moves every survivor by a
    // different amount and no check can pass on a coincidence.
    function sizeOf(id) {
        return ({ alpha: 40, beta: 70, gamma: 100 })[id] ?? 40;
    }

    property var nearModel: ["alpha", "beta", "gamma"]
    property var farModel: ["alpha", "beta", "gamma"]
    property var colModel: ["alpha", "beta", "gamma"]

    FloatingWindow {
        visible: true
        implicitWidth: 900
        implicitHeight: 500
        color: "black"

        TestCase {
            id: driver
            when: false
            name: "BarFlipDriver"
        }

        // The near-edge bucket: anchored where the row starts.
        Item {
            id: nearFrame
            x: 0
            y: 0
            width: parent.width
            height: 60

            BarFlipRegistry { id: nearRegistry }

            Item {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: nearRow.implicitWidth

                RowLayout {
                    id: nearRow
                    anchors.fill: parent
                    spacing: 4

                    Repeater {
                        id: nearRepeater
                        model: harness.nearModel
                        delegate: BarGroup {
                            required property var modelData
                            required property int index
                            // As the content trees declare them: a horizontal
                            // slot fills the bar's height and a vertical one
                            // its width, so the CROSS coordinate is zero and
                            // stays there. Without that the harness rescues an
                            // implementation watching only the slot's own
                            // coordinate - the cross-axis centring writes it
                            // once at creation and that write alone triggers a
                            // measurement the real bar never gets.
                            Layout.fillHeight: true
                            currentIndex: index
                            totalCount: harness.nearModel.length
                            widgetId: modelData
                            flipRegistry: nearRegistry
                            Rectangle {
                                implicitWidth: harness.sizeOf(modelData)
                                implicitHeight: 24
                                color: "gray"
                            }
                        }
                    }
                }
            }
        }

        // The far-edge bucket: anchored to the other end of the bar, sized by
        // its row, which is what makes the section itself move.
        Item {
            id: farFrame
            x: 0
            y: 70
            width: parent.width
            height: 60

            BarFlipRegistry { id: farRegistry }

            Item {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: farRow.implicitWidth

                RowLayout {
                    id: farRow
                    anchors.fill: parent
                    spacing: 4

                    Repeater {
                        id: farRepeater
                        model: harness.farModel
                        delegate: BarGroup {
                            required property var modelData
                            required property int index
                            // As the content trees declare them: a horizontal
                            // slot fills the bar's height and a vertical one
                            // its width, so the CROSS coordinate is zero and
                            // stays there. Without that the harness rescues an
                            // implementation watching only the slot's own
                            // coordinate - the cross-axis centring writes it
                            // once at creation and that write alone triggers a
                            // measurement the real bar never gets.
                            Layout.fillHeight: true
                            currentIndex: index
                            totalCount: harness.farModel.length
                            widgetId: modelData
                            flipRegistry: farRegistry
                            Rectangle {
                                implicitWidth: harness.sizeOf(modelData)
                                implicitHeight: 24
                                color: "gray"
                            }
                        }
                    }
                }
            }
        }

        // The vertical bar's far-edge bucket, the same arrangement turned.
        // Three frames rather than one that re-anchors: an item holding two
        // orientations' anchors at once is the silent full-fill defect
        // AGENT.md records for the dock's turn, and this harness has no reason
        // to reproduce it.
        Item {
            id: colFrame
            x: 0
            y: 150
            width: 60
            height: parent.height - 150

            BarFlipRegistry { id: colRegistry }

            Item {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: col.implicitHeight

                ColumnLayout {
                    id: col
                    anchors.fill: parent
                    spacing: 4

                    Repeater {
                        id: colRepeater
                        model: harness.colModel
                        delegate: BarGroup {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            vertical: true
                            currentIndex: index
                            totalCount: harness.colModel.length
                            widgetId: modelData
                            flipRegistry: colRegistry
                            Rectangle {
                                implicitWidth: 24
                                implicitHeight: harness.sizeOf(modelData)
                                color: "gray"
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- reading a strip ---------------------------------------------------
    //
    // A reflow destroys every delegate and builds the replacements, so a slot
    // is looked up by widget id at the moment it is read, never held.

    function slotOf(repeater, id) {
        for (let i = 0; i < repeater.count; i++) {
            const item = repeater.itemAt(i);
            if (item && item.widgetId === id) return item;
        }
        return null;
    }

    // Where the slot is DRAWN, read through Qt's own transform chain rather
    // than through the reposition's arithmetic. `mapToItem` composes the
    // Translate - which is exactly why BarGroup may not measure with it, and
    // exactly why this may: a harness that read the implementation's own
    // accounting back would agree with it by construction, including about an
    // axis it had stopped applying.
    function scenePoint(repeater, id) {
        const slot = harness.slotOf(repeater, id);
        return slot ? slot.mapToItem(null, 0, 0) : null;
    }

    function drawnAlong(repeater, id, vertical) {
        const point = harness.scenePoint(repeater, id);
        if (!point) return NaN;
        return Math.round(vertical ? point.y : point.x);
    }

    function drawnAcross(repeater, id, vertical) {
        const point = harness.scenePoint(repeater, id);
        if (!point) return NaN;
        return Math.round(vertical ? point.x : point.y);
    }

    // The slot's own coordinate, which is what the layout writes and what the
    // idiom this replaces would have watched.
    function ownAlong(repeater, id, vertical) {
        const slot = harness.slotOf(repeater, id);
        if (!slot) return NaN;
        return Math.round(vertical ? slot.y : slot.x);
    }

    // ---- sampling ----------------------------------------------------------
    //
    // 40ms and 240ms are both well inside the 350ms tier the reposition takes,
    // and the runner's own tick is past its end, so a settled read is settled.
    //
    // The early one is deliberately EARLY rather than merely in flight. The
    // spatial tier is front-loaded, so by 80ms a reposition is already ~90%
    // of the way there - and so is one that started on the mirror side of its
    // destination, which is what an inverse applied with the wrong sign
    // produces. Measured: 0.55 of the travel at 40ms against 0.90 at 80ms, so
    // only the earlier sample leaves the two apart.

    property var samples: ({})
    property var sampled: []
    property var sampleRepeater: null
    property bool sampleVertical: false

    function sampleNow() {
        const shot = ({});
        for (const id of harness.sampled) {
            shot[id] = {
                along: harness.drawnAlong(harness.sampleRepeater, id, harness.sampleVertical),
                across: harness.drawnAcross(harness.sampleRepeater, id, harness.sampleVertical)
            };
        }
        return shot;
    }

    function startSampling(repeater, vertical, ids) {
        harness.samples = ({});
        harness.sampleRepeater = repeater;
        harness.sampleVertical = vertical;
        harness.sampled = ids;
        earlySample.restart();
        midSample.restart();
    }

    Timer {
        id: earlySample
        interval: 40
        onTriggered: harness.samples.early = harness.sampleNow()
    }
    Timer {
        id: midSample
        interval: 240
        onTriggered: harness.samples.mid = harness.sampleNow()
    }

    // The check that separates a reposition from a teleport. A slot already at
    // its destination 80ms in is exactly what the Repeater does on its own.
    function scoreInFlight(label, id, from, to) {
        const early = harness.samples.early;
        const mid = harness.samples.mid;
        harness.check(`${label}: sampled at all`,
                      !!early && !!mid && !!early[id] && !!mid[id]);
        if (!early || !mid || !early[id] || !mid[id]) return;
        harness.check(`${label}: the slot under test actually moves, `
                      + `${from} to ${to}`, from !== to);
        harness.check(`${label}: was not already at its new place, `
                      + `got ${early[id].along} against ${to}`,
                      early[id].along !== to);
        harness.check(`${label}: had left its old one, `
                      + `got ${early[id].along} against ${from}`,
                      early[id].along !== from);
        harness.check(`${label}: was still travelling, `
                      + `got ${early[id].along} then ${mid[id].along}`,
                      early[id].along !== mid[id].along);
        // ...and travelling the right WAY, which every check above is
        // satisfied by: an inverse applied with the wrong sign puts the slot
        // on the mirror side of its destination and eases it back across, so
        // it is never at either endpoint and never stops moving. Scored as
        // progress from the old place to the new, with a quarter of the travel
        // of headroom past the end because the spatial tier's control points
        // leave the unit box and a sample is allowed to overshoot. A mirrored
        // start reads as 2.
        const progress = (early[id].along - from) / (to - from);
        harness.check(`${label}: was on its way there, `
                      + `got ${early[id].along} at progress ${progress.toFixed(2)}`,
                      progress >= 0 && progress <= 1.25);
    }

    function scoreSnapped(label, id, to) {
        const early = harness.samples.early;
        harness.check(`${label}: sampled at all`, !!early && !!early[id]);
        if (!early || !early[id]) return;
        harness.check(`${label}: was already where it belongs, `
                      + `got ${early[id].along} against ${to}`,
                      early[id].along === to);
    }

    // ---- the run -----------------------------------------------------------

    property var before: ({})

    readonly property var steps: [
        // The strips built at all, and built along their own axes. Every
        // "nothing moved" result below proves nothing if the harness never
        // drew anything.
        () => {
            harness.check("a near-edge bucket stacks along the bar",
                          harness.drawnAlong(nearRepeater, "alpha", false)
                          < harness.drawnAlong(nearRepeater, "gamma", false));
            harness.check("a far-edge bucket does too",
                          harness.drawnAlong(farRepeater, "alpha", false)
                          < harness.drawnAlong(farRepeater, "gamma", false));
            harness.check("and a vertical bucket stacks down its strip",
                          harness.drawnAlong(colRepeater, "alpha", true)
                          < harness.drawnAlong(colRepeater, "gamma", true));
        },
        // The plain case: a widget disappears from a near-edge bucket - the
        // tray emptying, a plugin switched off - and everything after it moves.
        () => {
            harness.before = ({
                alpha: harness.drawnAlong(nearRepeater, "alpha", false),
                gamma: harness.drawnAlong(nearRepeater, "gamma", false),
                gammaOwn: harness.ownAlong(nearRepeater, "gamma", false)
            });
            harness.startSampling(nearRepeater, false, ["alpha", "gamma"]);
            harness.nearModel = ["alpha", "gamma"];
        },
        () => {
            scoreInFlight("a widget leaving a near-edge bucket", "gamma",
                          harness.before.gamma,
                          harness.drawnAlong(nearRepeater, "gamma", false));
            harness.check("...its own coordinate moved too, "
                          + `got ${harness.ownAlong(nearRepeater, "gamma", false)} `
                          + `against ${harness.before.gammaOwn}`,
                          harness.ownAlong(nearRepeater, "gamma", false)
                          !== harness.before.gammaOwn);
            harness.check("...and the slot before it stayed where it was",
                          harness.drawnAlong(nearRepeater, "alpha", false)
                          === harness.before.alpha);
            harness.check("...with the reposition settled on the layout's own place",
                          harness.slotOf(nearRepeater, "gamma").flipTravel === 0);
        },
        // The case a reposition watching the slot's own x cannot see: in a
        // far-edge bucket the SECTION moves and the first slot does not.
        () => {
            harness.before = ({
                alpha: harness.drawnAlong(farRepeater, "alpha", false),
                alphaOwn: harness.ownAlong(farRepeater, "alpha", false),
                alphaAcross: harness.drawnAcross(farRepeater, "alpha", false),
                gamma: harness.drawnAlong(farRepeater, "gamma", false),
                gammaOwn: harness.ownAlong(farRepeater, "gamma", false)
            });
            harness.startSampling(farRepeater, false, ["alpha", "gamma"]);
            harness.farModel = ["alpha", "gamma"];
        },
        () => {
            scoreInFlight("a widget leaving a far-edge bucket", "alpha",
                          harness.before.alpha,
                          harness.drawnAlong(farRepeater, "alpha", false));
            // Without this the check above is satisfied by any implementation:
            // it is only interesting because the slot's own coordinate is the
            // one it always had and only its section moved under it.
            harness.check("...while its own coordinate never changed, "
                          + `got ${harness.ownAlong(farRepeater, "alpha", false)} `
                          + `against ${harness.before.alphaOwn}`,
                          harness.ownAlong(farRepeater, "alpha", false)
                          === harness.before.alphaOwn);
            // And the mirror image, so the pair cannot both be read off one
            // property: the last slot's own coordinate moves and the slot does
            // not travel, because the far edge is where it already was.
            harness.check("...and the last slot's own coordinate moved without it travelling",
                          harness.ownAlong(farRepeater, "gamma", false)
                          !== harness.before.gammaOwn
                          && harness.drawnAlong(farRepeater, "gamma", false)
                          === harness.before.gamma);
            const early = harness.samples.early;
            harness.check("a horizontal bar's slots do not travel across it, "
                          + `got ${early.alpha.across} against ${harness.before.alphaAcross}`,
                          early.alpha.across === harness.before.alphaAcross);
        },
        // A record is worth one reflow. Switching the widget back on a second
        // later finds nothing to invert from - and it comes back at the END
        // of the bucket, somewhere it has never been drawn, because a widget
        // returning to the slot it left would snap whether or not its record
        // had expired.
        () => {
            harness.before = ({
                alpha: harness.drawnAlong(farRepeater, "alpha", false)
            });
            harness.startSampling(farRepeater, false, ["alpha", "beta"]);
            harness.farModel = ["alpha", "gamma", "beta"];
        },
        () => {
            scoreSnapped("a widget switched back on later", "beta",
                         harness.drawnAlong(farRepeater, "beta", false));
            scoreInFlight("...while its neighbour still makes room", "alpha",
                          harness.before.alpha,
                          harness.drawnAlong(farRepeater, "alpha", false));
        },
        // A reorder drag reads slot centres through mapToItem, which composes
        // the transform, so the gesture and the reposition may not overlap.
        () => {
            GlobalStates.editBarDragActive = true;
            harness.startSampling(farRepeater, false, ["alpha"]);
            harness.farModel = ["alpha", "gamma"];
        },
        () => {
            scoreSnapped("a reflow while a reorder drag is in flight", "alpha",
                         harness.drawnAlong(farRepeater, "alpha", false));
            GlobalStates.editBarDragActive = false;
        },
        // ---- the same reflow, down a vertical bar -------------------------
        () => {
            harness.before = ({
                alpha: harness.drawnAlong(colRepeater, "alpha", true),
                alphaOwn: harness.ownAlong(colRepeater, "alpha", true),
                alphaAcross: harness.drawnAcross(colRepeater, "alpha", true)
            });
            harness.startSampling(colRepeater, true, ["alpha"]);
            harness.colModel = ["alpha", "gamma"];
        },
        () => {
            scoreInFlight("a widget leaving a vertical bar", "alpha",
                          harness.before.alpha,
                          harness.drawnAlong(colRepeater, "alpha", true));
            harness.check("...while its own coordinate never changed, "
                          + `got ${harness.ownAlong(colRepeater, "alpha", true)} `
                          + `against ${harness.before.alphaOwn}`,
                          harness.ownAlong(colRepeater, "alpha", true)
                          === harness.before.alphaOwn);
            const early = harness.samples.early;
            harness.check("a vertical bar's slots do not travel across it, "
                          + `got ${early.alpha.across} against ${harness.before.alphaAcross}`,
                          early.alpha.across === harness.before.alphaAcross);
        }
    ]

    property int stepIndex: 0

    Timer {
        id: setup
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            if (!Config.ready)
                return;
            setup.running = false;
            runner.running = true;
        }
    }

    // One step per tick, and the tick outlasts the reposition, so every
    // settled read below is a settled read.
    Timer {
        id: runner
        interval: 900
        repeat: true
        running: false
        onTriggered: {
            if (harness.stepIndex >= harness.steps.length) {
                runner.running = false;
                console.log(`[BarFlip] checks: ${harness.checksRun} failures: ${harness.failures}`);
                Qt.exit(harness.failures === 0 ? 0 : 1);
                return;
            }
            harness.steps[harness.stepIndex++]();
        }
    }
}
