import QtQuick
// For the attached Layout the rows are read back through - an attached type
// is only resolvable where its module is imported, and without this every
// key's `Layout` reads undefined.
import QtQuick.Layouts
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
            // A row is no longer an item - the keyboard is one grid, so a row
            // is whatever covers it, tall keys from the row above included.
            const grid = keyboard.children[0];
            const rows = [];
            const tall = [];
            for (let i = 0; i < grid.children.length; i++) {
                const key = grid.children[i];
                if (key.keyData === undefined)
                    continue;
                const span = key.Layout.rowSpan;
                for (let r = key.Layout.row; r < key.Layout.row + span; r++) {
                    if (rows[r] === undefined)
                        rows[r] = { left: key.x, right: key.x + key.width };
                    rows[r].left = Math.min(rows[r].left, key.x);
                    rows[r].right = Math.max(rows[r].right, key.x + key.width);
                }
                if (span > 1)
                    tall.push(`${key.keyData.label}@${Math.round(key.x)},${Math.round(key.y)}`
                        + ` ${Math.round(key.width)}x${Math.round(key.height)}`);
            }
            const widths = rows.map(row => Math.round((row.right - row.left) * 100) / 100);
            console.log(`[OskLayout] rowWidths ${widths.join(" ")}`);
            // A double-height key is ONE key of two rows. Printed because two
            // keys stacked and one key spanning look identical in a total.
            console.log(`[OskLayout] tallKeys ${tall.length} ${tall.join(" ")}`);
            field.grabToImage(result => {
                result.saveToFile(shot);
                console.log("[OskLayout] saved");
                Qt.quit();
            });
        }
    }
}
