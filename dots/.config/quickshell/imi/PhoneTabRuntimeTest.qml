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
 * The driver also puts a fake `adb`, `scrcpy`, `droidcam-cli`, `pactl`,
 * `v4l2-ctl`, `lsmod`, `modinfo` and `mpv` on PATH, so PhoneDeps answers the
 * same way on every machine and the three feature cards are in a state other
 * than `unavailable`. The fake `adb` lists NO device, which is the machine
 * this branch was written against: KDE Connect reaches the phone over LAN and
 * adb has never seen it. What is read back here is the click PATH and the
 * card GEOMETRY, neither of which is reachable from qmltestrunner - the
 * decisions themselves live in phone_cards.js and are driven by
 * tests/tst_phone_cards.qml.
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

    // Items are found by TYPE everywhere above; the toast is a bare
    // Rectangle, so it is found by the two properties only it declares.
    function withProperties(item, names, out) {
        for (const child of item.children) {
            if (names.every(name => child[name] !== undefined))
                out.push(child);
            harness.withProperties(child, names, out);
        }
        return out;
    }

    function toastCard() {
        return harness.withProperties(loader.item, ["message", "ok"], [])[0] ?? null;
    }

    // A glyph a Control positions itself: its centre must land on the
    // button's, which an anchor cannot do and both alignments can.
    function glyphOffCentre(button) {
        const glyph = harness.findAll(button, "MaterialSymbol", [])[0] ?? null;
        if (!glyph) return Number.NaN;
        const centre = glyph.mapToItem(button, glyph.width / 2, glyph.height / 2);
        return Math.abs(centre.x - button.width / 2);
    }

    function cardTitled(fragment) {
        return harness.all("PhoneFeatureCard").find(c => `${c.title}`.indexOf(fragment) >= 0) ?? null;
    }

    // The footer's row, read structurally rather than by type: its three
    // children ARE the two actions and the pill between them, in that order,
    // and which of them is which is the whole thing being measured.
    function footerRow() {
        const footer = harness.first("PhoneFooterBar");
        return footer ? (footer.children[0] ?? null) : null;
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

        // ---- the footer toolbar: the pill's word, and the two actions ----
        () => {
            // The roster step above left the unpaired laptop showing, which is
            // the pill's other branch: a count of zero must not stand in for
            // "the phone is not here".
            const label = harness.findAll(harness.first("PhoneFooterBar"), "StyledText", [])[0] ?? null;
            harness.check(`an offline device says so instead of counting, got "${label?.text}"`,
                          label !== null && label.text === "Device offline");
            loader.item.pickedDeviceId = harness.phoneId;
        },
        () => {
            const row = harness.footerRow();
            const slots = row ? row.children : [];
            harness.footerButtons = slots.length === 3 ? [slots[0], slots[2]] : [];
            harness.footerPill = slots.length === 3 ? slots[1] : null;
            harness.footerLabel = harness.footerPill
                ? (harness.findAll(harness.footerPill, "StyledText", [])[0] ?? null) : null;
            const buttons = harness.footerButtons;
            const pill = harness.footerLabel;
            console.log(`[PhoneTab] footer w=${row?.width}`
                + ` buttons=${buttons.map(b => `${b.width}x${b.height}@${b.x}`)}`
                + ` label="${pill?.text}" w=${pill?.width} in pill ${harness.footerPill?.width}`);

            harness.check(`the footer draws two actions around one pill, got ${slots.length} slots`,
                          buttons.length === 2 && pill !== null);
            // The abbreviation is what the maintainer asked to be spelled out.
            harness.check(`the count pill spells the word out, got "${pill?.text}"`,
                          pill !== null && pill.text.indexOf("notification") >= 0
                          && pill.text.indexOf("notif.") < 0);
            harness.check("...and it is the plural, since the fake daemon mirrors none",
                          pill !== null && pill.text === "0 notifications");
        },
        () => {
            const buttons = harness.footerButtons;
            const wider = buttons.every(b => b.width > b.height);
            harness.check(`each action is wider than it is tall, got ${buttons.map(b => `${b.width}x${b.height}`)}`,
                          buttons.length === 2 && wider);
            harness.check("both actions take the same stated width",
                          buttons.length === 2 && buttons[0].width === buttons[1].width
                          && buttons[0].width === Appearance.sizes.phoneFooterButtonWidth
                          && buttons[0].height === Appearance.sizes.phoneFooterButtonHeight);
            const offsets = buttons.map(b => harness.glyphOffCentre(b));
            console.log(`[PhoneTab] glyph off centre by ${offsets}`);
            // A RippleButtonWithIcon's glyph was drawn 1.5px left of centre
            // here, because the empty label's Layout.fillWidth slot took the
            // rest of the row's width from inside the button.
            harness.check(`each glyph is centred in its action, off by ${offsets}`,
                          offsets.every(offset => offset < 1));
        },
        () => {
            // The pill is the row's only fillWidth item, so the label must
            // elide inside it rather than paint over the two actions.
            const label = harness.footerLabel;
            const pill = harness.footerPill;
            const buttons = harness.footerButtons;
            const left = label.mapToItem(pill.parent, 0, 0).x;
            const right = left + label.width;
            harness.check("the label elides rather than overflowing its pill",
                          label.elide === Text.ElideRight
                          && label.width <= pill.width);
            harness.check(`the label stays clear of both actions (${left}..${right})`,
                          left >= buttons[0].x + buttons[0].width
                          && right <= buttons[1].x);
            harness.check("neither action was squeezed to make room for it",
                          buttons.every(b => b.width === Appearance.sizes.phoneFooterButtonWidth));
        },

        // ---- the feature cards: what a click reaches ---------------------
        () => {
            const cards = harness.all("PhoneFeatureCard");
            console.log(`[PhoneTab] cards=${cards.map(c => `"${c.title}" ${c.cardState} @${c.y} ${c.width}x${c.height}`)}`);
            harness.check(`the three feature cards are drawn, got ${cards.length}`, cards.length === 3);
            harness.check("PhoneDeps answered every probe before the cards were read",
                          PhoneDeps.ready);
            harness.check(`the fake adb lists no device, got adbDevice=${PhoneDeps.adbDevice}`,
                          PhoneDeps.adb && !PhoneDeps.adbDevice);
        },
        () => {
            // The state a card can know BEFORE the click: the phone is
            // reachable over KDE Connect and adb cannot see it, so scrcpy has
            // nothing to attach to and the card says which link is missing.
            const mirror = harness.cardTitled("scrcpy Mirror");
            const mic = harness.cardTitled("Microphone");
            console.log(`[PhoneTab] mirror=${mirror?.cardState} "${mirror?.subtitle}"`
                + ` mic=${mic?.cardState} "${mic?.subtitle}"`);
            harness.check("a mirror with no ADB device is offline before it is clicked",
                          mirror !== null && mirror.cardState === "offline"
                          && mirror.subtitle.indexOf("No device over ADB") === 0);
            // The microphone's preferred backend is scrcpy, which drives the
            // phone over ADB; the webcam's droidcam-cli does not, so it is
            // deliberately still ready.
            harness.check("so is a microphone whose backend drives the phone over ADB",
                          mic !== null && mic.cardState === "offline"
                          && mic.subtitle.indexOf("No device over ADB") === 0);
            const webcam = harness.cardTitled("Webcam");
            harness.check("the webcam, which reaches the phone over Wi-Fi, is not refused",
                          webcam !== null && webcam.cardState === "ready");
        },
        () => {
            // Does the primary click fire at all, or is it swallowed by the
            // settings chip or by the status mark beside it? Clicked at the
            // card's own centre, and scored on the service.
            const mirror = harness.cardTitled("scrcpy Mirror");
            harness.check("the mirror is not already launching", !PhoneScrcpy.mirrorLaunching);
            harness.click(mirror);
        },
        () => {
            harness.check("a click on the card's body reaches launchMirror()",
                          PhoneScrcpy.mirrorLaunching || PhoneScrcpy.mirrorRunning
                          || PhoneScrcpy.lastError.length > 0);
            // Disarmed through the model rather than by stopping the mirror:
            // this harness has no phone and the supervisor's own exit is not
            // what is being scored here.
            PhoneScrcpy.mirrorLaunching = false;
        },
        () => {
            // The settings chip is a SECOND affordance on the same card, and
            // it must not be what the card's own click reaches.
            const webcam = harness.cardTitled("Webcam");
            const chip = harness.findAll(webcam, "RippleButton", [])[0] ?? null;
            harness.check("the webcam card carries its settings chip", chip !== null);
            harness.check("the sub-page is closed before the chip is clicked",
                          loader.item.subPage === "");
            if (chip) harness.click(chip);
        },
        () => {
            harness.check(`the chip opens the webcam page, got "${loader.item.subPage}"`,
                          loader.item.subPage === "webcam");
            loader.item.popSubPage();
        },

        // ---- a launch that fails says so, on the card and in the toast ----
        () => {
            // PhoneCamera leaves lastError set and goes back to `ready`, and
            // the card draws lastError only while it is ACTIVE - so this is
            // the path on which a failed webcam looked exactly like a card
            // that had ignored the click.
            PhoneCamera.lastError = "DroidCam did not start - is the app open on the phone?";
            PhoneCamera.errorOccurred(PhoneCamera.lastError);
        },
        () => {
            const webcam = harness.cardTitled("Webcam");
            console.log(`[PhoneTab] webcam=${webcam?.cardState} "${webcam?.subtitle}"`);
            harness.check(`a failed launch reaches the card's subtitle, got "${webcam?.subtitle}"`,
                          webcam !== null
                          && webcam.subtitle === "DroidCam did not start - is the app open on the phone?");
            const toast = harness.toastCard();
            harness.check(`the tab hears the service's own error signal, got "${toast?.message}"`,
                          toast !== null && toast.message === PhoneCamera.lastError && !toast.ok);
            PhoneCamera.lastError = "";
        },
        () => {
            const webcam = harness.cardTitled("Webcam");
            harness.check("clearing the error puts the card back on its ready line",
                          webcam.cardState === "ready"
                          && webcam.subtitle.indexOf("Tap to start") === 0);
            // The mirror's own feedback signal had no listener either.
            PhoneScrcpy.feedback("scrcpy: no device found", false);
        },
        () => {
            const toast = harness.toastCard();
            harness.check(`the tab hears PhoneScrcpy.feedback, got "${toast?.message}"`,
                          toast !== null && toast.message === "scrcpy: no device found" && !toast.ok);
        },

        () => harness.finish()
    ]

    property var footerButtons: []
    property var footerPill: null
    property var footerLabel: null

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
