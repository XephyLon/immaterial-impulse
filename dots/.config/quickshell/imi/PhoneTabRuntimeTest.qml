import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.imi.phone
import qs.modules.imi.sidebarLeft.phone

/**
 * Builds the REAL Phone tab over the REAL services/PhoneConnect.qml, fed
 * by a fake `busctl` on PATH, and reads the surface back: which device the
 * chip names, what the pills say, how many action buttons there are and
 * which of them answer, which child of the column owns the leftover
 * height, what the pairing card does when its two buttons are clicked, and
 * that the sub-page overlay degrades to nothing while the other
 * workstream's pages are absent.
 *
 * Driven by tests/test_phone_tab_runtime.py, which reads the fake's
 * recorded invocations afterwards: the two pairing clicks are scored
 * there, as `acceptPairing`/`cancelPairing` argv aimed at the device that
 * asked and never at the paired phone.
 *
 * The fake daemon exposes two devices - a paired, reachable phone with a
 * battery, an address and an LTE report, and an unpaired laptop whose
 * pairState says the peer asked (2) and which has no battery or report
 * leaf at all - so every branch of the surface is on screen at once.
 *
 *   PATH=<dir with fake busctl>:$PATH qs -p PhoneTabRuntimeTest.qml
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
        console.log(`[PhoneTab] ${label}: ${ok ? "ok" : "FAIL"}`);
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

    // The tab's content column: the one ColumnLayout whose children include
    // the notification list.
    function contentColumn() {
        const list = harness.first("PhoneNotificationList");
        return list ? list.parent : null;
    }

    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 460
        implicitHeight: 900
        color: "black"

        TestCase {
            id: driver
            when: false
            name: "PhoneTabDriver"
        }

        Loader {
            id: loader
            anchors.fill: parent
            active: false
            sourceComponent: Phone {}
        }
    }

    Component.onCompleted: {
        // A singleton is constructed on first use; this read starts the
        // presence probe and the first sweep.
        console.log(`[PhoneTab] service constructed, installed=${PhoneConnect.installed}`);
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
        console.log(`[PhoneTab] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }

    property var stepList: [
        () => {
            loader.active = true;
        },

        // ---- the chip and its pills read the active phone ---------------
        () => {
            const chip = harness.first("PhoneDeviceChip");
            harness.check(`the chip names the paired phone, got ${chip?.device?.name}`,
                          chip !== null && chip.device?.id === harness.phoneId);
            // The pill says the CELLULAR type where the daemon reported one,
            // and falls back to the address only where it did not - which is
            // the whole ordering the header exists to get right.
            const cellular = harness.badge("LTE");
            harness.check("the connection pill carries the report's network type",
                          cellular !== null && cellular.visible);
            harness.check("...and not the address it outranks",
                          harness.badge(harness.expectAddress) === null);
            const battery = harness.badge("85%");
            harness.check("the battery pill carries the phone's charge",
                          battery !== null && battery.visible);
        },

        // ---- one row of six actions, live for a paired phone -------------
        () => {
            const buttons = harness.all("PhoneActionButton");
            harness.check(`one action row of six buttons, got ${buttons.length}`, buttons.length === 6);
            harness.check("every action answers for a paired, reachable phone on kdeconnect",
                          buttons.length === 6 && buttons.every(b => b.enabled && b.visible));
            const rows = new Set(buttons.map(b => b.parent));
            harness.check("the six sit in one row", rows.size === 1);
        },

        // ---- the notification list owns the leftover height --------------
        () => {
            const list = harness.first("PhoneNotificationList");
            const chip = harness.first("PhoneDeviceChip");
            const action = harness.first("PhoneActionButton");
            console.log(`[PhoneTab] list=${list?.height} chip=${chip?.height} action=${action?.height}`);
            harness.check("the notification list stands taller than the fixed rows around it",
                          list !== null && list.height > chip.height && list.height > action.height);
            const empty = harness.findAll(list, "StyledText", []).filter(t => t.visible);
            harness.check("and it draws a real empty state rather than nothing",
                          empty.length >= 1);
        },

        // ---- the footer names the count ----------------------------------
        () => {
            const footer = harness.first("PhoneFooterBar");
            harness.check("the footer bar is drawn under the list",
                          footer !== null && footer.y > harness.first("PhoneNotificationList").y);
        },

        // ---- the nav cards, and the sub-page overlay that has no pages ----
        () => {
            // Read by their LABELS rather than by the inline component's
            // type name: an inline component's name is not what a
            // `${obj}` reports, and a type check that silently matches
            // nothing here would report two missing cards as a clean run.
            const cards = harness.first("PhoneNavCards");
            const labels = harness.findAll(cards, "StyledText", []).map(t => t.text);
            harness.check(`the two navigation cards are named, got ${labels}`,
                          cards !== null && labels.includes("Contacts") && labels.includes("Android Apps"));
            loader.item.openSubPage("contacts");
        },
        () => {
            // The other workstream's pages are not in the tree yet, so the
            // overlay must degrade to an empty Loader rather than take the
            // tab down. This is the check that has to keep passing once they
            // land, with `item` no longer null.
            harness.check("asking for a page that does not exist yet leaves the tab standing",
                          loader.item !== null && loader.item.shownSubPage === "contacts");
            harness.check("...and the column is still there behind it",
                          harness.first("PhoneNotificationList") !== null);
            loader.item.popSubPage();
        },
        () => {
            harness.check("popping the page clears the request", loader.item.subPage === "");
        },

        // ---- the pairing card, for the device that asked ------------------
        () => {
            const cards = harness.all("PhonePairingCard");
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
                          harness.all("PhoneDeviceItem").filter(i => i.visible).length === 0);
            harness.click(harness.first("PhoneDeviceChip"));
        },
        () => {
            const rows = harness.all("PhoneDeviceItem").filter(i => i.visible);
            harness.check(`opening the chip lists both devices, got ${rows.length}`, rows.length === 2);
            const laptop = rows.find(r => r.device?.id === harness.laptopId) ?? null;
            if (laptop) harness.click(laptop);
        },
        () => {
            const chip = harness.first("PhoneDeviceChip");
            harness.check(`picking a row shows that device on the chip, got ${chip?.device?.name}`,
                          chip?.device?.id === harness.laptopId);
            const buttons = harness.all("PhoneActionButton");
            harness.check("the actions stand down for a device that is not paired",
                          buttons.length === 6 && buttons.every(b => !b.enabled));
            harness.check("the connection pill follows the shown device",
                          harness.badge(harness.expectLaptopAddress) !== null
                          && harness.badge("LTE") === null);
            harness.check("a device without a battery has no battery pill",
                          harness.badge("85%") === null);
        },

        // ---- what the list owns is what is LEFT: take a card away and it
        // grows by exactly that card. Driven through the model, since the
        // fake daemon is stateless; the poll is seeded far out so a sweep
        // cannot put the card back between the two reads. -----------------
        () => {
            const list = harness.first("PhoneNotificationList");
            const card = harness.first("PhonePairingCard");
            harness.listWithCard = list.height;
            harness.cardHeight = card.height;
            harness.columnSpacing = harness.contentColumn().spacing;
            PhoneConnect.applyDevices(PhoneConnect.devices.map(d => Object.assign({}, d, { hasPairingRequest: false })));
        },
        () => {
            const list = harness.first("PhoneNotificationList");
            const cards = harness.all("PhonePairingCard");
            const grewBy = list.height - harness.listWithCard;
            console.log(`[PhoneTab] cards=${cards.length} list ${harness.listWithCard} -> ${list.height}`
                        + ` (+${grewBy}; card was ${harness.cardHeight}, spacing ${harness.columnSpacing})`);
            harness.check("answering the request takes its card off the stack", cards.length === 0);
            harness.check("and the notification list grows by exactly the card it no longer shares the column with",
                          grewBy === harness.cardHeight + harness.columnSpacing);
        },

        () => harness.finish()
    ]

    property real listWithCard: 0
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
