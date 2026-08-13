import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.plugins.designsystem.widgets as Expressive

/*
 * Does the card actually cast a shadow, does it lift when handled, and does
 * it stop casting one while it is moving?
 *
 * Structure tests can only see that the wiring is spelled correctly. This
 * renders real WidgetCards on a white field and measures the pixels just
 * below each one: a shadow darkens that strip, a bigger shadow darkens it
 * more, and a card in motion should not darken it at all.
 *
 *   ./tests/run_card_shadow_probe.sh
 */
ShellRoot {
    id: harness

    property int failures: 0
    function check(label, ok, detail) {
        console.log(`[CardShadow] ${label}: ${ok ? "ok" : "FAIL"}${detail ? " " + detail : ""}`);
        if (!ok) harness.failures++;
    }

    readonly property int cardW: 200
    readonly property int cardH: 120

    FloatingWindow {
        id: window
        implicitWidth: 900
        implicitHeight: 400
        color: "white"

        Item {
            id: field
            anchors.fill: parent

            // The grab takes THIS item, not the window, so the field carries
            // its own ground - grabbing over the window's colour produces a
            // transparent PNG whose "white" reads as black to any analyser.
            Rectangle { anchors.fill: parent; color: "white" }

            // Rest, handled, and mid-motion - same card, three states.
            Expressive.WidgetCard {
                id: restCard
                x: 60; y: 60
                width: harness.cardW; height: harness.cardH
                tint: "#2a2733"
            }
            Expressive.WidgetCard {
                id: draggedCard
                x: 340; y: 60
                width: harness.cardW; height: harness.cardH
                tint: "#2a2733"
                dragging: true
            }
            Expressive.WidgetCard {
                id: movingCard
                x: 620; y: 60
                width: harness.cardW; height: harness.cardH
                tint: "#2a2733"
                // A card mid-morph: the shadow is dropped for the duration.
                motionActive: true
            }
        }
    }

    // The measuring happens outside: ItemGrabResult.image is not scriptable
    // from QML, so the probe renders and saves, and test_card_shadow.py reads
    // the pixels. Card boxes are printed so the analyser needs no duplicate
    // copy of this layout.
    Timer {
        running: true
        interval: 1500
        onTriggered: {
            const shot = Quickshell.env("CARD_SHADOW_SHOT") || "";
            if (shot === "") {
                console.log("[CardShadow] FAIL: CARD_SHADOW_SHOT unset");
                Qt.quit();
                return;
            }
            console.log(`[CardShadow] layout cardW=${harness.cardW} cardH=${harness.cardH} `
                + `rest=60 dragged=340 moving=620 top=60`);
            field.grabToImage(result => {
                result.saveToFile(shot);
                console.log("[CardShadow] saved");
                Qt.quit();
            });
        }
    }
}
