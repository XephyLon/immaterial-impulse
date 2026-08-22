import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.imi.polkit

/**
 * Builds the REAL polkit prompt and reads its geometry, its hover feedback and
 * its masked glyphs back out of the objects on screen.
 *
 * Everything this file asks used to be a source sweep, and a source sweep
 * cannot see any of it: whether the action row lands in the dialog's content
 * box is a `Layout` decision three components down, whether a button answers
 * the pointer is a colour the shell computes at runtime, and whether the field
 * draws Material shapes instead of system bullets is a `Loader` gated on a
 * config key.
 *
 * The content tree is hosted in a plain window rather than on the polkit
 * surface, because the surface's own gate (`PolkitService.active`) is a
 * read-only alias onto the agent and a second agent cannot register for a
 * session that already has one - so the LAYER surface is out of reach here.
 * That is the same boundary `LockIslandReorderRuntimeTest` records for the
 * session lock, and it means this file says nothing about the compositor's
 * input region.
 *
 * The service is fed rather than driven for the same reason: nothing outside a
 * real authentication request can produce a flow.
 *
 * Run against a throwaway config:
 *   XDG_CONFIG_HOME=$(mktemp -d) XDG_STATE_HOME=$(mktemp -d) qs -p PolkitDialogRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int checksRun: 0

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[Polkit] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function typeName(obj) {
        return `${obj}`.split("(")[0].split("_QML")[0].trim();
    }

    function findAll(item, type, out) {
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

    function button(label) {
        return harness.findAll(loader.item, "DialogButton", []).find(b => b.buttonText === label) ?? null;
    }

    // The card is the one Rectangle at the caller's declared backgroundWidth.
    function card() {
        return harness.findAll(loader.item, "QQuickRectangle", []).find(r => r.width === 450) ?? null;
    }

    function box(item) {
        const point = item.mapToItem(loader.item, 0, 0);
        return { l: point.x, t: point.y, r: point.x + item.width, b: point.y + item.height };
    }

    // A colour stringified BEFORE it is stored. A QML value type read into JS
    // is a live reference to the property it came from, so a "before" kept as
    // an object reports the "after" and every delta below is 0.
    function frozen(colour) {
        return "" + colour;
    }

    function channelDelta(before, after) {
        const a = Qt.color(before);
        const b = Qt.color(after);
        return Math.round(255 * Math.max(Math.abs(a.r * a.a - b.r * b.a),
                                         Math.abs(a.g * a.a - b.g * b.a),
                                         Math.abs(a.b * a.a - b.b * b.a)));
    }

    function hover(item) {
        const centre = item.mapToItem(loader.item, item.width / 2, item.height / 2);
        driver.mouseMove(loader.item, centre.x, centre.y);
    }

    property var restFill: ({})

    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 900
        implicitHeight: 700
        color: "black"

        TestCase {
            id: driver
            when: false
            name: "PolkitDialogDriver"
        }

        Loader {
            id: loader
            anchors.fill: parent
            active: false
            sourceComponent: PolkitContent {}
        }
    }

    property var steps: [
        // ---- the prompt is built the way the agent builds it ---------------
        () => {
            PolkitService.interactionAvailable = true;
            PolkitService.cleanMessage = "Authentication is required to install or update software packages on this system, and to manage the repositories they are fetched from";
            PolkitService.cleanPrompt = "Password";
        },
        () => {
            loader.active = true;
        },

        // ---- the card's padding, and the row that used to leave it ---------
        () => {
            const cardBox = harness.box(harness.card());
            const column = harness.box(harness.first("QQuickColumnLayout"));
            const icon = harness.box(harness.first("MaterialSymbol"));
            const row = harness.box(harness.first("WindowDialogButtonRow"));
            const left = column.l - cardBox.l;
            const right = cardBox.r - column.r;
            const top = icon.t - cardBox.t;
            const bottom = cardBox.b - row.b;
            console.log(`[Polkit] paddings left=${left} right=${right} top=${top} bottom=${bottom}`);
            harness.check("the card's four paddings agree",
                          left === right && left === top && left === bottom);
        },
        () => {
            const field = harness.box(harness.first("PasswordField"));
            const row = harness.box(harness.first("WindowDialogButtonRow"));
            console.log(`[Polkit] field right=${field.r} row right=${row.r} row left=${row.l}`);
            harness.check("the actions line up with the field above them",
                          row.r === field.r && row.l === field.l);
        },
        () => {
            const cardBox = harness.box(harness.card());
            const row = harness.box(harness.first("WindowDialogButtonRow"));
            harness.check("the action row is drawn inside the card",
                          row.b <= cardBox.b && row.t >= cardBox.t);
        },

        // ---- the two buttons answer the pointer ----------------------------
        () => {
            for (const b of harness.findAll(loader.item, "DialogButton", []))
                harness.restFill[b.buttonText] = harness.frozen(b.buttonColor);
        },
        () => harness.hover(harness.button("Cancel")),
        () => {
            const cancel = harness.button("Cancel");
            const delta = harness.channelDelta(harness.restFill["Cancel"], harness.frozen(cancel.buttonColor));
            console.log(`[Polkit] Cancel rest=${harness.restFill["Cancel"]} hover=${harness.frozen(cancel.buttonColor)} delta=${delta}`);
            harness.check("the dismissing action lights under the pointer",
                          cancel.hovered && delta >= 20);
            harness.check("the confirming action stays dark while the pointer is on the other one",
                          !harness.button("OK").hovered);
        },
        () => harness.hover(harness.button("OK")),
        () => {
            const ok = harness.button("OK");
            const delta = harness.channelDelta(harness.restFill["OK"], harness.frozen(ok.buttonColor));
            console.log(`[Polkit] OK rest=${harness.restFill["OK"]} hover=${harness.frozen(ok.buttonColor)} delta=${delta}`);
            harness.check("the confirming action lights under the pointer",
                          ok.hovered && delta >= 10);
        },

        // ---- the field is the shell's masked one, glyphs and all -----------
        () => {
            const field = harness.first("PasswordField");
            harness.check("the prompt's field masks through the shared glyphs",
                          field !== null && field.materialShapeChars
                          && harness.findAll(field, "PasswordChars", []).length === 1
                          && field.color.a === 0);
        },
        () => {
            // A click, not a forceActiveFocus: the glyph overlay is a Flickable
            // drawn over the field, and an overlay that is not `enabled: false`
            // eats exactly this.
            const field = harness.first("PasswordField");
            const centre = field.mapToItem(loader.item, field.width / 2, field.height / 2);
            driver.mouseClick(loader.item, centre.x, centre.y, Qt.LeftButton);
        },
        () => {
            harness.check("clicking the field focuses it through the glyph overlay",
                          harness.first("PasswordField").activeFocus);
        },
        () => {
            driver.keyClick(Qt.Key_H);
            driver.keyClick(Qt.Key_U);
            driver.keyClick(Qt.Key_N);
            driver.keyClick(Qt.Key_T);
            driver.keyClick(Qt.Key_E);
        },
        () => {
            const field = harness.first("PasswordField");
            const glyphs = harness.findAll(field, "MaterialShape", []).length;
            console.log(`[Polkit] typed=${field.text.length} glyphs=${glyphs}`);
            harness.check("one animated glyph per typed character",
                          field.text.length === 5 && glyphs === 5);
        },

        () => {
            console.log(`[Polkit] checks: ${harness.checksRun} failures: ${harness.failures}`);
            Qt.exit(harness.failures === 0 ? 0 : 1);
        }
    ]

    property int stepIndex: 0
    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: {
            if (harness.stepIndex >= harness.steps.length)
                return;
            harness.steps[harness.stepIndex++]();
        }
    }
}
