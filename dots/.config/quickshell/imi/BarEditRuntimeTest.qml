import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.imi.bar

/**
 * Drives the bar's in-place edit gesture with real mouse events, in both
 * orientations, against the real Config-backed layouts.
 *
 * The named test is the along/across pair for the bar's buckets: a drag ALONG
 * the bar must reorder and a drag ACROSS it must not, with the horizontal
 * orientation run first as the control - three "nothing happened" results
 * prove nothing if the harness quietly stopped delivering events, and an
 * axis-inert comparison is exactly how the vertical dock's reorder shipped
 * broken (40c64996b's lesson, applied to the surface stage 8 adds).
 *
 * The slots are synthetic - real `BarGroup`s carrying a stand-in widget that
 * counts its clicks - because the real bar widget files reach Hyprland,
 * PipeWire and the tray, none of which a weston harness has. What IS real is
 * everything stage 8 added: BarGroup's edit loader, BarWidgetEditItem's eater
 * and badge, ReorderDragArea's gesture, BarEditController's mapping and
 * commits, and the stored `Config.options.bar.layouts.*` they write. One
 * stored entry ("ghostly") is deliberately hidden by the harness's visibility
 * predicate, so every commit exercises the visible-to-stored mapping - a
 * reorder that ate hidden entries would show up as ghostly disappearing from
 * the stored list.
 *
 * What this cannot see: the bar's layer surface (weston implements no
 * wlr-layer-shell), the mustShow suspension, and the real widget files. Those
 * are the contract test's and a live load's.
 *
 * Run it against a throwaway config:
 *   XDG_CONFIG_HOME=$(mktemp -d) XDG_STATE_HOME=$(mktemp -d) qs -p BarEditRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int checksRun: 0
    property int widgetClicks: 0
    property bool vertical: false

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[BarEdit] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    // The harness's own filter rule, standing in for the trees' (an empty
    // tray, a disabled plugin): "ghostly" is stored but never drawn.
    function widgetVisible(name) {
        return name !== "ghostly";
    }

    function effective(layout) {
        const drawn = [];
        const count = layout && typeof layout.length === "number" ? layout.length : 0;
        for (let i = 0; i < count; i++)
            if (harness.widgetVisible(layout[i]))
                drawn.push(layout[i]);
        return drawn;
    }

    function stored() {
        return [
            (Config.options.bar.layouts.leftLayout ?? []).join(","),
            (Config.options.bar.layouts.middleLayout ?? []).join(","),
            (Config.options.bar.layouts.rightLayout ?? []).join(",")
        ].join("|");
    }

    function resetLayouts() {
        Config.options.bar.layouts.leftLayout = ["a", "ghostly", "b"];
        Config.options.bar.layouts.middleLayout = [];
        Config.options.bar.layouts.rightLayout = ["c"];
    }

    // Slot i of a bucket sits i steps along the bar; the bucket boxes sit at
    // fixed offsets so the gesture arithmetic below cannot drift from the
    // layout it drives.
    readonly property var bucketStart: [0, 270, 440]
    readonly property int slotStep: 50
    readonly property int slotAlong: 46
    readonly property int slotCross: 40

    function slotCenter(bucket, index) {
        const along = harness.bucketStart[bucket] + index * harness.slotStep + harness.slotAlong / 2;
        const cross = 24;
        return harness.vertical ? Qt.point(cross, along) : Qt.point(along, cross);
    }

    function badgeCenter(bucket, index) {
        // The badge is 18x18 anchored to the slot's top-right corner.
        const alongStart = harness.bucketStart[bucket] + index * harness.slotStep;
        const crossStart = 4;
        if (harness.vertical)
            return Qt.point(crossStart + harness.slotCross - 9, alongStart + 9);
        return Qt.point(alongStart + harness.slotAlong - 9, crossStart + 9);
    }

    FloatingWindow {
        visible: true
        implicitWidth: 720
        implicitHeight: 720
        color: "black"

        TestCase {
            id: driver
            when: false
            name: "BarEditDriver"
        }

        Item {
            id: bar
            x: 20
            y: 20
            width: harness.vertical ? 48 : 640
            height: harness.vertical ? 640 : 48

            component BucketBox: Item {
                id: bucketBox
                property int bucket: 0
                property string bucketName: "left"
                x: harness.vertical ? 0 : harness.bucketStart[bucket]
                y: harness.vertical ? harness.bucketStart[bucket] : 0
                width: harness.vertical ? 48 : 200
                height: harness.vertical ? 200 : 48

                property alias repeater: slotRepeater

                BarBucketBoundary {
                    id: zone
                    anchors.centerIn: parent
                    width: harness.vertical ? parent.width - 4 : Math.max(minRun, 4)
                    height: harness.vertical ? Math.max(minRun, 4) : parent.height - 4
                }
                property alias zoneItem: zone

                Repeater {
                    id: slotRepeater
                    model: harness.effective(bucketBox.bucket === 0
                        ? Config.options.bar.layouts.leftLayout
                        : bucketBox.bucket === 1
                            ? Config.options.bar.layouts.middleLayout
                            : Config.options.bar.layouts.rightLayout)
                    delegate: BarGroup {
                        required property var modelData
                        required property int index
                        x: harness.vertical ? 4 : index * harness.slotStep
                        y: harness.vertical ? index * harness.slotStep : 4
                        width: harness.vertical ? harness.slotCross : harness.slotAlong
                        height: harness.vertical ? harness.slotAlong : harness.slotCross
                        currentIndex: index
                        editController: controller
                        editBucket: bucketBox.bucketName
                        editWidgetId: modelData

                        Rectangle {
                            implicitWidth: 30
                            implicitHeight: 20
                            color: "gray"
                            // The widget stand-in: a click that reaches this is
                            // a click the mode failed to eat.
                            MouseArea {
                                anchors.fill: parent
                                onClicked: harness.widgetClicks++
                            }
                        }
                    }
                }
            }

            BucketBox { id: leftBucket; bucket: 0; bucketName: "left" }
            BucketBox { id: middleBucket; bucket: 1; bucketName: "middle" }
            BucketBox { id: rightBucket; bucket: 2; bucketName: "right" }

            BarEditController {
                id: controller
                anchors.fill: parent
                z: 200
                vertical: harness.vertical
                widgetVisible: name => harness.widgetVisible(name)
                slotItemsFor: bucket => {
                    const box = bucket === "left" ? leftBucket
                        : bucket === "middle" ? middleBucket : rightBucket;
                    const items = [];
                    for (let i = 0; i < box.repeater.count; i++)
                        items.push(box.repeater.itemAt(i));
                    return items;
                }
                leftZone: leftBucket.zoneItem
                middleZone: middleBucket.zoneItem
                rightZone: rightBucket.zoneItem
            }
        }
    }

    // ---- gestures ---------------------------------------------------------

    function dragFromTo(from, to) {
        driver.mousePress(bar, from.x, from.y, Qt.LeftButton);
        driver.mouseMove(bar, from.x + (to.x - from.x) * 0.3,
                         from.y + (to.y - from.y) * 0.3, 20, Qt.LeftButton);
        driver.mouseMove(bar, from.x + (to.x - from.x) * 0.7,
                         from.y + (to.y - from.y) * 0.7, 20, Qt.LeftButton);
        driver.mouseMove(bar, to.x, to.y, 20, Qt.LeftButton);
        driver.mouseRelease(bar, to.x, to.y, Qt.LeftButton);
    }

    function alongPoint(point, delta) {
        return harness.vertical ? Qt.point(point.x, point.y + delta)
                                : Qt.point(point.x + delta, point.y);
    }

    function acrossPoint(point, delta) {
        return harness.vertical ? Qt.point(point.x + delta, point.y)
                                : Qt.point(point.x, point.y + delta);
    }

    readonly property var steps: [
        // ---- horizontal, the control -------------------------------------
        () => {
            const first = leftBucket.repeater.itemAt(0);
            const second = leftBucket.repeater.itemAt(1);
            harness.check("the slots exist and stack along the bar",
                          first && second && second.x > first.x && second.y === first.y);
        },
        () => {
            // Out of the mode the widget itself answers the click: the eater
            // must not exist here, or the mode never ends for the bar.
            const p = harness.slotCenter(0, 0);
            driver.mouseClick(bar, p.x, p.y, Qt.LeftButton);
            harness.check("out of the mode a click reaches the widget",
                          harness.widgetClicks === 1);
        },
        () => { GlobalStates.editMode = true; },
        () => {
            const p = harness.slotCenter(0, 0);
            driver.mouseClick(bar, p.x, p.y, Qt.LeftButton);
            harness.check("in the mode the same click is eaten",
                          harness.widgetClicks === 1);
        },
        // A drag along the bar reorders - and the stored list keeps its hidden
        // entry, which is the visible-to-stored mapping working.
        () => harness.dragFromTo(harness.slotCenter(0, 0),
                                 harness.alongPoint(harness.slotCenter(0, 1), 15)),
        () => harness.check("a drag along the bar reorders around the hidden entry, "
                            + `got ${harness.stored()}`,
                            harness.stored() === "ghostly,b,a||c"),
        () => { harness.resetLayouts(); },
        // ...and a drag across it does not: the pointer leaves the strip
        // without travelling along it, so the nearest gap is the one the drag
        // began in.
        () => harness.dragFromTo(harness.slotCenter(0, 0),
                                 harness.acrossPoint(harness.slotCenter(0, 0), 30)),
        () => harness.check("a drag across the bar does not reorder, "
                            + `got ${harness.stored()}`,
                            harness.stored() === "a,ghostly,b||c"),
        // The empty middle bucket is a valid drop target, through its
        // boundary's anchor.
        () => harness.dragFromTo(harness.slotCenter(0, 1),
                                 harness.slotCenter(1, 0)),
        () => harness.check("a drag into the empty middle bucket moves the widget, "
                            + `got ${harness.stored()}`,
                            harness.stored() === "a,ghostly|b|c"),
        // Past the last slot of a bucket is an append.
        () => harness.dragFromTo(harness.slotCenter(0, 0),
                                 harness.alongPoint(harness.slotCenter(2, 0), 40)),
        () => harness.check("a drag past a bucket's last slot appends, "
                            + `got ${harness.stored()}`,
                            harness.stored() === "ghostly|b|c,a"),
        () => { harness.resetLayouts(); },
        // The badge removes the entry it sits on - through the same mapping,
        // so the hidden entry survives.
        () => {
            const p = harness.badgeCenter(0, 1);
            driver.mouseClick(bar, p.x, p.y, Qt.LeftButton);
        },
        () => harness.check("the remove badge takes out the widget it rides, "
                            + `got ${harness.stored()}`,
                            harness.stored() === "a,ghostly||c"),
        () => { harness.resetLayouts(); },
        // ---- the two cancels ---------------------------------------------
        //
        // Leaving the mode mid-drag: the overlay dies with the grab, so the
        // release still coming can commit nothing.
        () => {
            const p = harness.slotCenter(0, 0);
            driver.mousePress(bar, p.x, p.y, Qt.LeftButton);
            const q = harness.alongPoint(p, 60);
            driver.mouseMove(bar, q.x, q.y, 20, Qt.LeftButton);
            harness.check("the bar drag is a gesture in flight",
                          GlobalStates.editBarDragActive);
            GlobalStates.editMode = false;
            driver.mouseRelease(bar, q.x, q.y, Qt.LeftButton);
        },
        () => {
            harness.check("leaving the mode mid-drag commits nothing, "
                          + `got ${harness.stored()}`,
                          harness.stored() === "a,ghostly,b||c");
            harness.check("...and the gesture flag is cleared",
                          !GlobalStates.editBarDragActive);
            // The overlay whose handlers would have ended the drag was torn
            // down WITH the mode, so this is the controller's own central
            // reset being scored: a stale ghost chip here would be drawn over
            // the live bar for the rest of the session.
            const ghost = driver.findChild(controller, "barEditGhost");
            const indicator = driver.findChild(controller, "barEditDropIndicator");
            harness.check("...and the ghost and the indicator stand down",
                          !ghost.visible && !indicator.visible
                          && !controller.dragActive);
            GlobalStates.editMode = true;
        },
        // The ladder's cancel: the canvas raises editReorderCancel, the slot
        // holding the grab abandons, and the release lands on nothing.
        () => {
            const p = harness.slotCenter(0, 0);
            driver.mousePress(bar, p.x, p.y, Qt.LeftButton);
            const q = harness.alongPoint(p, 60);
            driver.mouseMove(bar, q.x, q.y, 20, Qt.LeftButton);
            GlobalStates.editReorderCancel();
            harness.check("the ladder's cancel clears the gesture before the release",
                          !GlobalStates.editBarDragActive);
            driver.mouseRelease(bar, q.x, q.y, Qt.LeftButton);
        },
        () => {
            harness.check("...and the cancelled drag commits nothing, "
                          + `got ${harness.stored()}`,
                          harness.stored() === "a,ghostly,b||c");
        },
        // ---- vertical: the same pair, transposed --------------------------
        () => {
            GlobalStates.editMode = false;
            harness.vertical = true;
            harness.resetLayouts();
        },
        () => {
            const first = leftBucket.repeater.itemAt(0);
            const second = leftBucket.repeater.itemAt(1);
            harness.check("a vertical bar stacks its slots down the strip",
                          first && second && second.y > first.y && second.x === first.x);
            GlobalStates.editMode = true;
        },
        () => harness.dragFromTo(harness.slotCenter(0, 0),
                                 harness.alongPoint(harness.slotCenter(0, 1), 15)),
        () => harness.check("a drag along the column reorders, "
                            + `got ${harness.stored()}`,
                            harness.stored() === "ghostly,b,a||c"),
        () => { harness.resetLayouts(); },
        () => harness.dragFromTo(harness.slotCenter(0, 0),
                                 harness.acrossPoint(harness.slotCenter(0, 0), 30)),
        () => {
            harness.check("a drag across the column does not, "
                          + `got ${harness.stored()}`,
                          harness.stored() === "a,ghostly,b||c");
            GlobalStates.editMode = false;
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
            if (harness.stored() !== "a,ghostly,b||c") {
                harness.resetLayouts();
                return;
            }
            setup.running = false;
            runner.running = true;
        }
    }

    // One step per tick, outlasting the slots' own animations, so every check
    // reads a settled value.
    Timer {
        id: runner
        interval: 600
        repeat: true
        running: false
        onTriggered: {
            if (harness.stepIndex >= harness.steps.length) {
                runner.running = false;
                console.log(`[BarEdit] checks: ${harness.checksRun} failures: ${harness.failures}`);
                Qt.exit(harness.failures === 0 ? 0 : 1);
                return;
            }
            harness.steps[harness.stepIndex++]();
        }
    }
}
