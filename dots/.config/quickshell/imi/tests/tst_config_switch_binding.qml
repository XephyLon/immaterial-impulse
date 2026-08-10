import QtQuick
import QtQuick.Controls
import QtTest

// A settings toggle has to survive being clicked: `checked` is bound to a
// config value, and a preset, a hand-edited config.json or a migration must
// still be able to move it afterwards. `ConfigSwitch` used to answer its own
// click with `checked = !checked`, which destroys that binding on the first
// click - the setting kept changing while the switch showed stale local state,
// and a click on a switch that looked on wrote `!off` = on (#158).
//
// The real widget cannot be instantiated here (it reaches StyledText, whose
// `font.variableAxes` needs a newer Qt than the suite runs against, and
// Appearance/Config are Quickshell singletons), so this rebuilds its exact
// three-part shape out of plain QtQuick.Controls: a row-sized AbstractButton
// standing in for the RippleButton root, an inner Switch standing in for
// StyledSwitch, and a `source` property standing in for the config leaf.
//
// The old idiom is modelled beside the new one on purpose. Proving it detaches
// is what makes a green result here mean something: without it, a harness that
// simply never breaks a binding would pass either way.
TestCase {
    id: testCase
    name: "ConfigSwitchBindingTest"
    when: windowShown
    visible: true
    width: 200
    height: 40

    // ConfigSwitch as it was: the click writes the property the call site bound.
    Component {
        id: detachingSwitch
        Item {
            id: host
            property bool source: false
            property alias control: row
            property alias handle: handle
            anchors.fill: parent

            AbstractButton {
                id: row
                anchors.fill: parent
                checked: host.source
                onClicked: checked = !checked
                onCheckedChanged: host.source = checked

                Switch {
                    id: handle
                    anchors.right: parent.right
                    width: 60
                    height: parent.height
                    checked: row.checked
                    onClicked: row.clicked()
                }
            }
        }
    }

    // ConfigSwitch as it is: the click is an intent the call site answers by
    // flipping the value at its source.
    Component {
        id: intentSwitch
        Item {
            id: host
            property bool source: false
            property alias control: row
            property alias handle: handle
            anchors.fill: parent

            AbstractButton {
                id: row
                signal toggleRequested
                anchors.fill: parent
                checked: host.source
                onClicked: row.toggleRequested()
                onToggleRequested: host.source = !host.source

                Switch {
                    id: handle
                    anchors.right: parent.right
                    width: 60
                    height: parent.height
                    checkable: false
                    checked: row.checked
                    onClicked: row.clicked()
                }
            }
        }
    }

    // A switch the call site refuses to move - "use the same wallpaper for
    // both" is on when two paths are empty and clearing them is all a click can
    // do, so a click while it is already on means nothing.
    Component {
        id: decliningSwitch
        Item {
            id: host
            property bool source: true
            property alias control: row
            property alias handle: handle
            anchors.fill: parent

            AbstractButton {
                id: row
                signal toggleRequested
                anchors.fill: parent
                checked: host.source
                onClicked: row.toggleRequested()
                onToggleRequested: {}

                Switch {
                    id: handle
                    anchors.right: parent.right
                    width: 60
                    height: parent.height
                    checkable: false
                    checked: row.checked
                    onClicked: row.clicked()
                }
            }
        }
    }

    // The bug, so the rest of this file cannot pass vacuously. One click and
    // the switch stops answering to the value it was bound to.
    function test_theOldIdiomDetachesOnTheFirstClick() {
        const host = createTemporaryObject(detachingSwitch, testCase);
        mouseClick(host.control, 10, 20);
        compare(host.source, true, "the click still writes the value");

        host.source = false;
        compare(host.control.checked, true,
                "assigning to `checked` from onClicked is supposed to destroy "
                + "the binding - if this now follows the source, the harness is "
                + "no longer able to detect the bug it is guarding");
    }

    function test_theBindingSurvivesAClickOnTheRow() {
        const host = createTemporaryObject(intentSwitch, testCase);
        mouseClick(host.control, 10, 20);
        compare(host.source, true, "the click flips the value at its source");
        compare(host.control.checked, true, "and the switch follows it");

        host.source = false;
        compare(host.control.checked, false,
                "an external write - a preset, a config edit - must still move "
                + "the switch after it has been clicked");
        host.source = true;
        compare(host.control.checked, true, "and back again");
    }

    function test_theBindingSurvivesAClickOnTheSwitchItself() {
        const host = createTemporaryObject(intentSwitch, testCase);
        mouseClick(host.handle, 30, 20);
        compare(host.source, true, "clicking the handle reaches the row");
        compare(host.handle.checked, true, "the handle draws the new state");

        host.source = false;
        compare(host.handle.checked, false,
                "the handle is a picture of the row's `checked`, so it has to "
                + "follow an external write too");
    }

    // The handle is where this goes wrong if it stays checkable: a QQC2 Switch
    // moves its own `checked` on click, so it would show a flip that never
    // happened and stay wrong until the config next changed.
    function test_aDeclinedIntentLeavesTheHandleWhereItWas() {
        const host = createTemporaryObject(decliningSwitch, testCase);
        mouseClick(host.handle, 30, 20);
        compare(host.control.checked, true, "nothing moved the value");
        compare(host.handle.checked, true,
                "so the handle must not have moved either");
    }

    function test_aDeclinedIntentOnTheRowLeavesNothingLookingFlipped() {
        const host = createTemporaryObject(decliningSwitch, testCase);
        mouseClick(host.control, 10, 20);
        compare(host.control.checked, true);
        compare(host.handle.checked, true);
    }
}
