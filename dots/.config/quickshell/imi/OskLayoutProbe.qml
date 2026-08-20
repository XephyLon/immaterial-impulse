import QtQuick
import Quickshell
import "modules/imi/onScreenKeyboard" as Osk
import "modules/imi/onScreenKeyboard/layouts.js" as Layouts

/*
 * Every on-screen keyboard layout, drawn.
 *
 * The contract test can prove that a row spans the units it claims to. It
 * cannot see whether the thing those units add up to looks like a keyboard:
 * whether the numpad's columns sit under each other, whether the arrow cluster
 * is an inverted T rather than four keys in a line, whether a label overflows
 * its cap. That is a picture, so this takes one.
 *
 *   OSK_LAYOUT_SHOT=/tmp/osk.png ./tests/run_osk_layout_probe.sh
 *   OSK_LAYOUT_SHOT=/tmp/osk-de.png OSK_LAYOUT=German ./tests/run_osk_layout_probe.sh
 */
ShellRoot {
    id: harness

    readonly property string layoutName: Quickshell.env("OSK_LAYOUT") || Layouts.defaultLayout
    readonly property int margin: 24

    FloatingWindow {
        id: window
        implicitWidth: keyboard.implicitWidth + harness.margin * 2
        implicitHeight: keyboard.implicitHeight + harness.margin * 2

        Item {
            id: field
            anchors.fill: parent

            // Grabbing the window itself yields a transparent PNG whose white
            // reads as black to any analyser (test_card_shadow.py's trap), so
            // the ground the keyboard is photographed against is drawn here.
            // Deliberately not a shell colour: colLayer1 is what a keycap is
            // painted in, and a ground taken from the same palette leaves the
            // caps three levels off the field they are supposed to be read
            // against.
            Rectangle {
                anchors.fill: parent
                color: "#3f3f46"
            }

            Osk.OskContent {
                id: keyboard
                x: harness.margin
                y: harness.margin
                width: implicitWidth
                height: implicitHeight
                activeLayoutName: harness.layoutName
            }
        }
    }

    Timer {
        running: true
        interval: 1200
        onTriggered: {
            const shot = Quickshell.env("OSK_LAYOUT_SHOT") || "";
            if (shot === "") {
                console.log("[OskLayout] FAIL: OSK_LAYOUT_SHOT unset");
                Qt.quit();
                return;
            }
            console.log(`[OskLayout] layout ${harness.layoutName} size `
                + `${Math.round(keyboard.implicitWidth)}x${Math.round(keyboard.implicitHeight)}`);
            // Every row is drawn to the same width or the clusters on the
            // right drift; measured off the built tree rather than asserted
            // from the units, which is the half the contract test cannot see.
            const column = keyboard.children[0];
            const widths = [];
            for (let i = 0; i < column.children.length; i++) {
                const row = column.children[i];
                if (row.children.length > 0)
                    widths.push(Math.round(row.width * 100) / 100);
            }
            console.log(`[OskLayout] rowWidths ${widths.join(" ")}`);
            field.grabToImage(result => {
                result.saveToFile(shot);
                console.log("[OskLayout] saved");
                Qt.quit();
            });
        }
    }
}
