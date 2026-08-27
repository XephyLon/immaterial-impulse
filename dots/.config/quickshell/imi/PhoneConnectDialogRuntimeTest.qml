import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.imi.sidebarRight.phoneConnect

/**
 * Builds the REAL phone dialog over the REAL services/PhoneConnect.qml,
 * fed by a fake `busctl` on PATH, and reads the surface back: which device
 * the chip names, what the pills say, how many action buttons there are and
 * whether they answer, which child of the column owns the leftover height,
 * and what the pairing card does when its two buttons are clicked.
 *
 * Driven by tests/test_phone_connect_dialog_runtime.py, which reads the
 * fake's recorded invocations afterwards: the two pairing clicks are scored
 * there, as `acceptPairing`/`cancelPairing` argv aimed at the device that
 * asked and never at the paired phone.
 *
 * The fake daemon exposes two devices - a paired, reachable phone with a
 * battery, an address and an LTE report, and an unpaired laptop whose
 * pairState says the peer asked (2) and which has no battery or report leaf
 * at all - so every branch of the surface is on screen at once.
 *
 *   PATH=<dir with fake busctl>:$PATH qs -p PhoneConnectDialogRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int checksRun: 0
    property int elapsed: 0

    readonly property string phoneId: Quickshell.env("PHONE_ID") ?? ""
    readonly property string laptopId: Quickshell.env("LAPTOP_ID") ?? ""
    readonly property string expectAddress: Quickshell.env("PHONE_EXPECT_ADDRESS") ?? ""
    readonly property string expectLaptopAddress: Quickshell.env("LAPTOP_EXPECT_ADDRESS") ?? ""

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[PhoneConnectDialog] ${label}: ${ok ? "ok" : "FAIL"}`);
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

    function all(type) {
        return harness.findAll(loader.item, type, []);
    }

    function first(type) {
        return harness.all(type)[0] ?? null;
    }

    function badge(label) {
        return harness.all("Badge").find(b => b.label === label) ?? null;
    }

    function dialogButton(label) {
        return harness.all("DialogButton").find(b => b.buttonText === label) ?? null;
    }

    function click(item) {
        const centre = item.mapToItem(loader.item, item.width / 2, item.height / 2);
        driver.mouseClick(loader.item, centre.x, centre.y, Qt.LeftButton);
    }

    // The dialog's content column: the one ColumnLayout whose children
    // include the notification area.
    function contentColumn() {
        const area = harness.first("PhoneConnectNotificationArea");
        return area ? area.parent : null;
    }

    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 500
        implicitHeight: 800
        color: "black"

        TestCase {
            id: driver
            when: false
            name: "PhoneConnectDialogDriver"
        }

        Loader {
            id: loader
            anchors.fill: parent
            active: false
            sourceComponent: PhoneConnectDialog {}
        }
    }

    Component.onCompleted: {
        // A singleton is constructed on first use; this read starts the
        // presence probe and the first sweep.
        console.log(`[PhoneConnectDialog] service constructed, installed=${PhoneConnect.installed}`);
    }

    Timer {
        id: waitForReady
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            harness.elapsed += waitForReady.interval;
            if (!Config.ready || !PhoneConnect.installed || PhoneConnect.devices.length !== 2) {
                if (harness.elapsed >= 30000) {
                    harness.check(`Config ready, busctl found and both devices swept (got ${PhoneConnect.devices.length})`, false);
                    harness.finish();
                }
                return;
            }
            waitForReady.running = false;
            steps.running = true;
        }
    }

    function finish() {
        console.log(`[PhoneConnectDialog] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }

    property var stepList: [
        () => {
            loader.active = true;
            loader.item.show = true;
        },

        // ---- the chip and its pills read the active phone ---------------
        () => {
            const chip = harness.first("PhoneConnectDeviceChip");
            harness.check(`the chip names the paired phone, got ${chip?.device?.name}`,
                          chip !== null && chip.device?.id === harness.phoneId);
            const address = harness.badge(harness.expectAddress);
            harness.check(`the connection pill carries the phone's address ${harness.expectAddress}`,
                          address !== null && address.visible);
            const battery = harness.badge("85%");
            harness.check("the battery pill carries the phone's charge",
                          battery !== null && battery.visible);
            const cellular = harness.badge("LTE");
            harness.check("the cellular pill carries the report's network type",
                          cellular !== null && cellular.visible);
        },

        // ---- one row of the three model actions, live for a paired phone --
        () => {
            const buttons = harness.all("PhoneConnectActionButton");
            harness.check(`one action row of three buttons, got ${buttons.length}`, buttons.length === 3);
            harness.check("every action answers for a paired, reachable phone",
                          buttons.length === 3 && buttons.every(b => b.enabled && b.visible));
            const rows = new Set(buttons.map(b => b.parent));
            harness.check("the three sit in one row", rows.size === 1);
        },

        // ---- the notification area owns the leftover height --------------
        () => {
            const area = harness.first("PhoneConnectNotificationArea");
            const chip = harness.first("PhoneConnectDeviceChip");
            const action = harness.first("PhoneConnectActionButton");
            console.log(`[PhoneConnectDialog] area=${area?.height} chip=${chip?.height} action=${action?.height}`);
            harness.check("the notification area stands taller than the fixed rows around it",
                          area !== null && area.height > chip.height && area.height > action.height);
            const empty = harness.findAll(area, "StyledText", []).filter(t => t.visible);
            harness.check("and it draws a real empty state rather than nothing",
                          empty.length >= 1 && harness.findAll(area, "MaterialSymbol", []).some(s => s.visible));
        },

        // ---- the pairing card, for the device that asked ------------------
        () => {
            const cards = harness.all("PhoneConnectPairingCard");
            harness.check(`one pairing card, for the laptop, got ${cards.length}`,
                          cards.length === 1 && cards[0].device?.id === harness.laptopId);
            const accept = harness.dialogButton("Accept");
            const decline = harness.dialogButton("Decline");
            harness.check("Accept is the filled action and Decline the outlined one",
                          accept !== null && decline !== null
                          && accept.dialogActionFilled && !accept.outlined
                          && decline.outlined && !decline.dialogActionFilled);
        },
        () => harness.click(harness.dialogButton("Accept")),
        () => harness.click(harness.dialogButton("Decline")),

        // ---- the roster, behind the chip's arrow --------------------------
        () => {
            harness.check("the roster is folded until the chip is opened",
                          harness.all("PhoneConnectDeviceItem").filter(i => i.visible).length === 0);
            harness.click(harness.first("PhoneConnectDeviceChip"));
        },
        () => {
            const rows = harness.all("PhoneConnectDeviceItem").filter(i => i.visible);
            harness.check(`opening the chip lists both devices, got ${rows.length}`, rows.length === 2);
            const laptop = rows.find(r => r.device?.id === harness.laptopId) ?? null;
            if (laptop) harness.click(laptop);
        },
        () => {
            const chip = harness.first("PhoneConnectDeviceChip");
            harness.check(`picking a row shows that device on the chip, got ${chip?.device?.name}`,
                          chip?.device?.id === harness.laptopId);
            const buttons = harness.all("PhoneConnectActionButton");
            harness.check("the actions stand down for a device that is not paired",
                          buttons.length === 3 && buttons.every(b => !b.enabled));
            harness.check("the connection pill follows the shown device",
                          harness.badge(harness.expectLaptopAddress) !== null
                          && harness.badge(harness.expectAddress) === null);
            harness.check("a device without a battery has no battery pill",
                          harness.badge("85%") === null);
        },

        // ---- what the area owns is what is LEFT: take a card away and it
        // grows by exactly that card. Driven through the model, since the
        // fake daemon is stateless; the poll is seeded far out so a sweep
        // cannot put the card back between the two reads. -----------------
        () => {
            const area = harness.first("PhoneConnectNotificationArea");
            const card = harness.first("PhoneConnectPairingCard");
            harness.areaWithCard = area.height;
            harness.cardHeight = card.height;
            harness.columnSpacing = harness.contentColumn().spacing;
            PhoneConnect.applyDevices(PhoneConnect.devices.map(d => Object.assign({}, d, { hasPairingRequest: false })));
        },
        () => {
            const area = harness.first("PhoneConnectNotificationArea");
            const cards = harness.all("PhoneConnectPairingCard");
            const grewBy = area.height - harness.areaWithCard;
            console.log(`[PhoneConnectDialog] cards=${cards.length} area ${harness.areaWithCard} -> ${area.height}`
                        + ` (+${grewBy}; card was ${harness.cardHeight}, spacing ${harness.columnSpacing})`);
            harness.check("answering the request takes its card off the stack", cards.length === 0);
            harness.check("and the notification area grows by exactly the card it no longer shares the column with",
                          grewBy === harness.cardHeight + harness.columnSpacing);
        },

        () => harness.finish()
    ]

    property real areaWithCard: 0
    property real cardHeight: 0
    property real columnSpacing: 0

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
