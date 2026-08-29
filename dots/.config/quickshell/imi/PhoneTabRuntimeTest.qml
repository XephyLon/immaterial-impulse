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
 * Five things here are WATCHED rather than read once, because each of them
 * is a defect that only exists between two settled states:
 *
 *  - the mirror launch. `Directories.scriptPath` resolves to this checkout,
 *    so the click really starts scripts/phone/scrcpy_session_manager.py,
 *    which really spawns the fake scrcpy, which exits 1 the way the real one
 *    does with no phone on adb. `launchWatch` samples every 25ms and the step
 *    after it asserts that the card was NEVER read as running or active -
 *    the supervisor's `started` means "spawned" - that the badge's glyph
 *    never blanked, and that what the card settles on is the error rather
 *    than the line it was already showing before the click;
 *  - the sub-page cross-fade. `fadeWatch` samples the outgoing column's
 *    opacity and scale, and the check that matters is that a MID-flight
 *    reading exists: every "was it ever out of range" assertion passes
 *    identically on a transition that never ran;
 *  - the roster's reveal, in both directions. `rosterWatch` samples the box
 *    that uncovers the device list, and what is asserted is that a MID-flight
 *    height exists: a reveal that never ran and one that completed in a frame
 *    settle on the same number;
 *  - the footer's clear action, across the one glyph swap this bar has. A
 *    deferred text swap on a Control's content item lands the glyph on the
 *    padded rect's corner rather than on its centre and leaves it there, so
 *    the reading taken before the count first moves is identical whether or
 *    not the rest of the session is drawn off centre. `swapWatch` samples
 *    both axes and the glyph's opacity across it;
 *  - the toast's width, against a control. A short message must produce a
 *    toast narrower than the cap before a long one is allowed to prove the
 *    cap holds.
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

    // The plate a group drew for this row, or null. Walked rather than counted:
    // a row sits under a Loader under the plate's content column, and reading
    // `parent.parent` off that structure was one level short - which threw on
    // an Item with no `color` and took the REST of the step with it, including
    // the click that followed. A lookup in a harness fails by returning null.
    function plateOf(row) {
        let item = row?.parent ?? null;
        while (item) {
            if (item.color !== undefined && item.topLeftRadius !== undefined)
                return item;
            item = item.parent;
        }
        return null;
    }

    // Hover, for the states a click cannot leave an element in.
    function hover(item) {
        const centre = item.mapToItem(loader.item, item.width / 2, item.height / 2);
        driver.mouseMove(loader.item, centre.x, centre.y);
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
    //
    // BOTH axes, signed. The first version returned |dx| alone and could not
    // have seen the defect it was written for: a `Behavior on text` animates
    // the Text's OWN x and y, so a one-axis reading reports half of what is
    // on screen and an absolute one cannot say which way it went.
    function glyphOffset(button) {
        const glyph = harness.footerGlyph(button);
        if (!glyph) return { dx: Number.NaN, dy: Number.NaN };
        const centre = glyph.mapToItem(button, glyph.width / 2, glyph.height / 2);
        return { dx: centre.x - button.width / 2, dy: centre.y - button.height / 2 };
    }

    function glyphOffCentre(button) {
        const off = harness.glyphOffset(button);
        return Math.max(Math.abs(off.dx), Math.abs(off.dy));
    }

    function glyphOffsetText(button) {
        const off = harness.glyphOffset(button);
        return `(${off.dx.toFixed(2)},${off.dy.toFixed(2)})`;
    }

    function footerGlyph(button) {
        return harness.findAll(button, "MaterialSymbol", [])[0] ?? null;
    }

    function cardTitled(fragment) {
        return harness.all("PhoneFeatureCard").find(c => `${c.title}`.indexOf(fragment) >= 0) ?? null;
    }

    // The footer's three slots. Read by TYPE now, not by walking children: the
    // bar is a ButtonGroup, whose `default property alias data` reparents what
    // it is given into an inner RowLayout, so the bar's own first child is that
    // layout rather than the first button. Which slot is which is still the
    // thing being measured - the two actions are the ends, the count is the
    // middle - so the order matters and the count does.
    function footerSlots() {
        const footer = harness.first("PhoneFooterBar");
        return footer ? harness.findAll(footer, "NotificationStatusButton", []) : [];
    }

    function footerRow() {
        const slots = harness.footerSlots();
        return slots.length > 0 ? slots[0].parent : null;
    }

    // The badge a feature card leads with: the MaterialShape and the
    // MaterialSymbol inside it are two objects with two `text` values (the
    // shape aliases the symbol's), and the defect this reads for is the
    // symbol drawn at zero opacity inside a shape that is not.
    function cardBadge(card) {
        return harness.findAll(card, "MaterialShapeWrappedMaterialSymbol", [])[0] ?? null;
    }

    function cardGlyph(card) {
        const badge = harness.cardBadge(card);
        return badge ? (harness.findAll(badge, "MaterialSymbol", [])[0] ?? null) : null;
    }

    // The roster's list, and the box that reveals it. Reached through a row
    // rather than by type: a ListView parents its delegates into its own
    // content item, and the tab draws a second StyledListView - the
    // notification list - that a search by type would reach first.
    function rosterList() {
        return harness.first("GroupedList");
    }

    // The roster's rows in the order they are drawn, which is the order their
    // plates are in - the corners belong to the first and the last of them.
    function rosterRows() {
        return harness.all("PhoneDeviceItem").filter(r => r.visible);
    }

    // The box that folds, found by walking OUT of the list until the item
    // that owns the reveal turns up. The list's parent is the menu's surface
    // now, and a locator spelled as "the list's parent" silently measured
    // that surface instead the day the surface appeared.
    function rosterBox() {
        let item = harness.rosterList();
        while (item) {
            if (item.objectName === "rosterReveal")
                return item;
            item = item.parent;
        }
        return null;
    }

    // The Stop button of a card that is on its `active` rung, found by what it
    // draws rather than by position: a card carries a settings chip and its
    // inline actions in the same tree, and which RippleButton comes first is a
    // property of the file's declaration order.
    function stopButton(card) {
        return harness.findAll(card, "RippleButton", [])
            .find(b => harness.findAll(b, "MaterialSymbol", [])
                              .some(g => `${g.text}` === "stop_circle")) ?? null;
    }

    // A glyph-plus-label pair's DRAWN extent inside its button, and where the
    // middle of it lands against the button's own middle.
    //
    // The drawn extent, never the boxes: a Text a layout has stretched still
    // PAINTS at its content width from its left edge, so a label slot reaching
    // the right border reports a box that looks centred and a picture that is
    // not. That difference is the whole question this measures.
    function labelledPair(button) {
        if (!button) return null;
        const glyph = harness.findAll(button, "MaterialSymbol", [])[0] ?? null;
        const label = harness.findAll(button, "StyledText", [])[0] ?? null;
        if (!glyph || !label) return null;
        const g = glyph.mapToItem(button, 0, 0);
        const l = label.mapToItem(button, 0, 0);
        const left = Math.min(g.x, l.x);
        const right = Math.max(g.x + Math.min(glyph.width, glyph.contentWidth),
                               l.x + Math.min(label.width, label.contentWidth));
        return { left: left, right: right, width: right - left,
                 offset: (left + right) / 2 - button.width / 2 };
    }

    function pairText(pair) {
        return pair ? `${pair.width.toFixed(2)}w@${pair.offset.toFixed(2)}` : "none";
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

    // ---- the Stop button, at two widths, and the component it declined ----
    //
    // A Stop button exists only on a card's `active` rung, and nothing this
    // harness can drive puts a card there: the fake `adb` lists no device, so
    // every launch fails before it starts. The cards are built directly
    // instead - in a window of their own, so a fixture can never take a click
    // aimed at the tab - and at TWO widths, because a pair that is centred at
    // one width is also exactly what a pair filling its button looks like.
    //
    // The third fixture is the control for the component decision.
    // `RippleButtonWithIcon` is the shell's glyph-plus-label button and is the
    // obvious thing to reach for here; what it does on a button wider than its
    // content is the measured reason the card does not.
    FloatingWindow {
        id: stopWindow
        visible: true
        implicitWidth: 520
        implicitHeight: 360
        color: "black"

        Column {
            anchors.fill: parent
            anchors.margins: Appearance.spacing.space100
            spacing: Appearance.spacing.space100

            PhoneFeatureCard {
                id: narrowStopCard
                width: 200
                cardState: "active"
                title: "Narrow"
                subtitle: "stop fixture"
            }
            PhoneFeatureCard {
                id: wideStopCard
                width: 460
                cardState: "active"
                title: "Wide"
                subtitle: "stop fixture"
            }
            RippleButtonWithIcon {
                id: labelledControl
                width: 460
                materialIcon: "stop_circle"
                mainText: "Stop"
            }
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
            const list = harness.rosterList();
            harness.check("the roster is folded until the chip is opened",
                          harness.all("PhoneDeviceItem").filter(i => i.visible).length === 0);
            // The component the guidelines name for rows that are related but
            // stay visually distinct, over the daemon's devices. Not a shape of
            // its own: a rectangle wrapped around a list view was exactly the
            // hand-rolled surface that rule exists to prevent.
            harness.check(`the roster is the shell's grouped list over the daemon's devices,`
                          + ` got ${harness.typeName(list)} of ${list?.model?.length}`,
                          list !== null && harness.typeName(list) === "GroupedList"
                          && (list.model?.length ?? -1) === PhoneConnect.devices.length);
            harness.rosterSaw = { samples: 0, mid: 0, maxHeight: 0 };
            harness.click(harness.first("PhoneDeviceChip"));
            rosterWatch.running = true;
        },
        () => {},
        () => {
            rosterWatch.running = false;
            const box = harness.rosterBox();
            const list = harness.rosterList();
            const saw = harness.rosterSaw;
            console.log(`[PhoneTab] roster open: samples=${saw.samples} mid=${saw.mid}`
                + ` peak=${saw.maxHeight.toFixed(2)} settled=${box?.height} of list ${list?.implicitHeight}`);

            // The sample count first: a watch that never ran reports the same
            // "nothing was ever part way" a correct reveal does. Then the
            // mid-flight frames, because an unrolled reading and a snapped one
            // are the same reading once it settles - the two this repo has
            // shipped that mistake on are recorded in AGENT.md.
            harness.check(`the reveal was watched frame by frame, got ${saw.samples} samples`,
                          saw.samples > 10);
            harness.check(`the roster unrolls rather than appearing whole,`
                          + ` ${saw.mid} frames strictly between`, saw.mid > 0);
            harness.check(`...and settles at the group's own height, got ${box?.height}`
                          + ` against ${list?.implicitHeight}`,
                          box !== null && list !== null && list.implicitHeight > 0
                          && Math.abs(box.height - list.implicitHeight) < 1);

            const rows = harness.rosterRows();
            // The group's SHAPE, read off the rows as they are drawn rather
            // than off a property of a container. The check this replaces
            // asked a wrapper for its `radius` and was told 17 while the
            // screen showed four square corners: the rows were painting over
            // them, because `clip` on a Rectangle clips to the box and not to
            // the radius. A property is not a pixel.
            const first = rows[0] ?? null;
            const last = rows[rows.length - 1] ?? null;
            const inner = rows.length > 2 ? rows[1] : null;
            console.log(`[PhoneTab] roster corners first=${first?.cornerTopLeft}`
                        + `/${first?.cornerBottomLeft} last=${last?.cornerTopLeft}`
                        + `/${last?.cornerBottomLeft} inner=${inner?.cornerTopLeft}`);
            harness.check(`the group's outer corners are rounded, got`
                          + ` ${first?.cornerTopLeft} at the top and`
                          + ` ${last?.cornerBottomLeft} at the bottom of ${rows.length} rows`,
                          first !== null && last !== null
                          && first.cornerTopLeft === Appearance.rounding.normal
                          && last.cornerBottomLeft === Appearance.rounding.normal);
            harness.check(`...and the seams between them are not, got`
                          + ` ${first?.cornerBottomLeft} under the first row`,
                          first !== null
                          && first.cornerBottomLeft < Appearance.rounding.normal);
            harness.check(`opening the chip lists both devices, got ${rows.length}`, rows.length === 2);

            // ...and NOTHING is PAINTED behind them. A row that takes the
            // group's corners paints its own background, so the plate under it
            // is covered except for the inset, where it shows as a ring of
            // `bgcolor` around every row - which is what shipped. The inset
            // itself stays: it is the room the hover lift grows into.
            const plates = rows.map(r => harness.plateOf(r));
            console.log(`[PhoneTab] roster plates ${plates.map(p => p === null ? "none" : p.color.a)}`);
            harness.check(`the plate behind a self-painting row paints nothing,`
                          + ` got ${plates.map(p => p === null ? "no plate" : p.color.a)}`,
                          plates.length > 0 && plates.every(p => p !== null && p.color.a === 0));
            const laptop = rows.find(r => r.device?.id === harness.laptopId) ?? null;
            harness.rosterSaw = { samples: 0, mid: 0, maxHeight: 0 };
            if (laptop) harness.click(laptop);
            rosterWatch.running = true;
        },
        () => {},
        () => {
            rosterWatch.running = false;
            const box = harness.rosterBox();
            const saw = harness.rosterSaw;
            console.log(`[PhoneTab] roster fold: samples=${saw.samples} mid=${saw.mid}`
                + ` peak=${saw.maxHeight.toFixed(2)} progress=${loader.item.rosterProgress}`
                + ` visible=${box?.visible}`);

            harness.check(`the fold was watched frame by frame too, got ${saw.samples} samples`,
                          saw.samples > 10);
            harness.check(`picking a row folds the roster rather than cutting it,`
                          + ` ${saw.mid} frames strictly between`, saw.mid > 0);
            // The scalar, not the box's height: an excluded layout child keeps
            // the height its last laid-out frame left on it.
            harness.check(`...and it ends folded and out of the column,`
                          + ` progress ${loader.item.rosterProgress}`,
                          box !== null && !box.visible && loader.item.rosterProgress === 0
                          && harness.all("PhoneDeviceItem").every(i => !i.visible));

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
            // The middle slot's own label: every slot is the same component now,
            // and the two actions carry an empty one, so the first StyledText
            // under the bar is not the count.
            const countSlot = harness.footerSlots()[1] ?? null;
            const label = countSlot ? (harness.findAll(countSlot, "StyledText", [])[0] ?? null) : null;
            harness.check(`an offline device says so instead of counting, got "${label?.text}"`,
                          label !== null && label.text === "Device offline");
            loader.item.pickedDeviceId = harness.phoneId;
        },
        () => {
            const row = harness.footerRow();
            const slots = harness.footerSlots();
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
            // Against each other and against the component, not against a
            // phone-only token: this bar is the right sidebar's status row now,
            // and NotificationStatusButton states its own baseHeight. The width
            // follows the glyph, as it does over there.
            harness.check(`both actions are one shape, got ${buttons.map(b => `${b.width}x${b.height}`)}`,
                          buttons.length === 2
                          && buttons[0].width === buttons[1].width
                          && buttons[0].height === buttons[1].height
                          && buttons[0].height === buttons[0].baseHeight);
            const offsets = buttons.map(b => harness.glyphOffsetText(b));
            console.log(`[PhoneTab] glyph off centre by ${offsets}`);
            // A RippleButtonWithIcon's glyph was drawn 1.5px left of centre
            // here, because the empty label's Layout.fillWidth slot took the
            // rest of the row's width from inside the button.
            harness.check(`each glyph is centred in its action, off by ${offsets}`,
                          buttons.every(b => harness.glyphOffCentre(b) < 1));
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
                          buttons.every(b => b.width === b.baseWidth));
        },

        // ---- ...and they stay centred once the count moves ---------------
        //
        // The clear action is the one whose glyph is a ternary on the count,
        // so it is the only one of the two whose text ever changes - and a
        // reading taken before the first change is identical whether or not
        // the change displaces the glyph for the rest of the session. The
        // count is driven through the model, since the fake daemon serves no
        // notifications.
        () => {
            const clear = harness.footerButtons[1];
            harness.swapSaw = { samples: 0, maxOff: 0, minOpacity: 1 };
            harness.glyphBefore = harness.footerGlyph(clear)?.text ?? "";
            PhoneNotifications.notifications = [{
                publicId: "70",
                deviceId: harness.phoneId,
                internalId: "0|org.thunderdog.challegram|1|null|10248",
                package: "org.thunderdog.challegram",
                appName: "Telegram",
                title: "Alice",
                text: "on my way",
                ticker: "",
                iconPath: "",
                dismissable: true,
                replyId: "",
                actions: [],
                receivedAt: Date.now()
            }];
            swapWatch.running = true;
        },
        () => {},
        () => {
            swapWatch.running = false;
            const buttons = harness.footerButtons;
            const clear = buttons[1];
            const after = harness.footerGlyph(clear)?.text ?? "";
            const saw = harness.swapSaw;
            const offsets = buttons.map(b => harness.glyphOffsetText(b));
            console.log(`[PhoneTab] count 0 -> ${PhoneNotifications.count}:`
                + ` clear glyph "${harness.glyphBefore}" -> "${after}"`
                + ` off centre by ${offsets}; watched ${saw.samples} samples,`
                + ` worst ${saw.maxOff.toFixed(2)}px, min opacity ${saw.minOpacity.toFixed(2)}`);

            // The control first: everything below is vacuous on a swap that
            // never happened.
            harness.check(`the count change swapped the clear action's glyph,`
                          + ` got "${harness.glyphBefore}" -> "${after}"`,
                          harness.glyphBefore === "do_not_disturb_on" && after === "delete_sweep");
            harness.check(`the swap was watched frame by frame, got ${saw.samples} samples`,
                          saw.samples > 10);
            harness.check(`both glyphs settle back on their own centres, off by ${offsets}`,
                          buttons.every(b => harness.glyphOffCentre(b) < 1));
            // A `Behavior on text` animates the Text's own x and y and lands
            // it back on whatever those were when the item completed - which
            // for a Control's content item is BEFORE the Control has placed
            // it. The container behind the glyph does not fade with it
            // either, so the swap is an empty pill for its own length: the
            // same pair 3c82747df removed from the feature card's badge.
            harness.check(`neither glyph leaves its own centre during the swap,`
                          + ` worst ${saw.maxOff.toFixed(2)}px`,
                          saw.maxOff < 1);
            harness.check(`...nor fades inside a container that does not,`
                          + ` min opacity ${saw.minOpacity.toFixed(2)}`,
                          saw.minOpacity > 0.99);
            PhoneNotifications.notifications = [];
        },
        () => {
            harness.check(`clearing the model puts the count pill back, got "${harness.footerLabel?.text}"`,
                          harness.footerLabel?.text === "0 notifications");
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
            // card's own centre, and scored on the service - and then WATCHED
            // for a second, because what this branch exists to fix is what
            // the card said in between.
            //
            // The supervisor is the real one (Directories.scriptPath resolves
            // to this checkout's scripts/), so the click really does spawn
            // the fake scrcpy on PATH, which exits 1 with "Could not find any
            // ADB device" the way the real one does with no phone attached.
            const mirror = harness.cardTitled("scrcpy Mirror");
            const glyph = harness.cardGlyph(mirror);
            harness.check("the mirror is not already launching", !PhoneScrcpy.mirrorLaunching);
            harness.check(`the badge draws its offline glyph before the click, got "${glyph?.text}"`,
                          glyph !== null && glyph.text === "cast"
                          && harness.cardBadge(mirror).text === glyph.text);
            harness.launchSaw = { running: false, active: false, blankGlyph: "",
                                  minGlyphOpacity: 1, samples: 0 };
            harness.click(mirror);
            launchWatch.running = true;
        },
        () => {},
        () => {},
        () => {
            launchWatch.running = false;
            const saw = harness.launchSaw;
            const mirror = harness.cardTitled("scrcpy Mirror") ?? harness.cardTitled("Connecting");
            const glyph = harness.cardGlyph(mirror);
            console.log(`[PhoneTab] launch watch: samples=${saw.samples} sawRunning=${saw.running}`
                + ` sawActive=${saw.active} minGlyphOpacity=${saw.minGlyphOpacity.toFixed(2)}`
                + ` blank="${saw.blankGlyph}" state=${mirror?.cardState} "${mirror?.subtitle}"`);

            // A watch that never ran reports "nothing bad happened" just as
            // loudly as a correct one, so the sample count is asserted first.
            harness.check(`the launch was watched frame by frame, got ${saw.samples} samples`,
                          saw.samples > 20);
            harness.check("a click on the card's body reaches launchMirror()",
                          PhoneScrcpy.mirrorError.length > 0);

            // Defect 1: the supervisor answers `started` when it has SPAWNED
            // scrcpy. Reading that as a live mirror put "scrcpy Mirror /
            // Mirror is running - click to focus its window", a filled check
            // and "Active for 0s" on a card whose phone adb has never seen.
            harness.check("a launch with no ADB device is never read as a running mirror",
                          !saw.running);
            harness.check("...so the card never draws its active rung either", !saw.active);

            // Defect 2: the badge's glyph used to cross-fade to zero inside a
            // shape that does not fade with it, on a ladder that moves twice
            // inside one tier - so the icon simply went missing.
            harness.check(`the badge's glyph never blanks, min opacity ${saw.minGlyphOpacity.toFixed(2)}`,
                          saw.minGlyphOpacity > 0.99);
            harness.check(`the glyph and its shape never disagree or empty, got "${saw.blankGlyph}"`,
                          saw.blankGlyph === "");

            // And the failure is REPORTED rather than snapped back to the
            // line the card was already showing before the click.
            harness.check(`a failed launch leaves the card on the error, got "${mirror?.subtitle}"`,
                          mirror !== null && mirror.cardState === "offline"
                          && mirror.subtitle.indexOf("Could not find any ADB device") >= 0);
            harness.check(`...and the glyph is back to the offline one, got "${glyph?.text}"`,
                          glyph !== null && glyph.text === "cast");
        },
        () => {
            // The settings chip is a SECOND affordance on the same card, and
            // it must not be what the card's own click reaches.
            const webcam = harness.cardTitled("Webcam");
            // By name, not by position: the card's surface is a RippleButton
            // as well, so "the first one" is the surface rather than the chip.
            const chip = harness.findAll(webcam, "RippleButton", [])
                .find(b => b.objectName === "cardSettingsChip") ?? null;
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

        // ---- a running card's Stop button, read off the fixture window ----
        () => {
            const narrow = harness.stopButton(narrowStopCard);
            const wide = harness.stopButton(wideStopCard);
            const pairs = [harness.labelledPair(narrow), harness.labelledPair(wide)];
            const control = harness.labelledPair(labelledControl);
            console.log(`[PhoneTab] stop buttons ${narrow?.width}/${wide?.width}`
                + ` pairs ${pairs.map(p => harness.pairText(p))};`
                + ` ${harness.typeName(labelledControl)} ${labelledControl.width}`
                + ` pair ${harness.pairText(control)}`);

            // Two controls before the claim. The pair has to be found at all,
            // and each button has to be WIDER than it - a button the pair
            // fills is centred by construction and says nothing.
            harness.check(`the fixture drew a Stop button at two widths, got ${narrow?.width} and ${wide?.width}`,
                          narrow !== null && wide !== null && wide.width > narrow.width);
            harness.check(`...each with room around its pair, ${pairs.map(p => harness.pairText(p))}`,
                          pairs.every(p => p !== null && p.width > 0)
                          && narrow.width - pairs[0].width > 1
                          && wide.width - pairs[1].width > 1);

            // A Control stretches its content item to the padded rect and
            // positions it itself, so a RowLayout declared there lays its
            // children out from the LEFT edge of a button that fills its row.
            harness.check(`the glyph and its label centre in the button at both widths,`
                          + ` off by ${pairs.map(p => p.offset.toFixed(2))}`,
                          pairs.every(p => Math.abs(p.offset) < 1));

            // ...and why the shared component is not what does that. Its label
            // slot is `Layout.fillWidth: true`, so on a button wider than its
            // content the label absorbs the leftover from inside and the pair
            // is left-packed - the same shape bd35286c3 measured from the
            // other end, where the label was empty.
            harness.check(`the shared labelled-icon button left-packs the same pair instead,`
                          + ` off by ${control?.offset?.toFixed(2)}`,
                          control !== null && control.offset < -1);
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

        // ---- the toast stays inside the tab, however long the message ----
        () => {
            // The control, taken first: a short message must produce a toast
            // NARROWER than the cap, or the long-message check below passes
            // on a toast that was always full width.
            const toast = harness.toastCard();
            loader.item.showToast("Ringing", true);
            harness.shortToastWidth = 0;
            harness.toastCap = toast.maxWidth;
        },
        () => {
            const toast = harness.toastCard();
            harness.shortToastWidth = toast.width;
            console.log(`[PhoneTab] short toast ${toast.width} of cap ${harness.toastCap}`
                + ` in tab ${loader.item.width}`);
            harness.check(`a short message does not fill the tab, got ${toast.width} of ${harness.toastCap}`,
                          toast.width > 0 && toast.width < harness.toastCap);
            // The real string, from the screenshot the maintainer sent.
            loader.item.showToast("DroidCam did not start - is the DroidCam app open on the phone?", false);
        },
        () => {
            const toast = harness.toastCard();
            const label = harness.findAll(toast, "StyledText", [])[0] ?? null;
            const left = toast.mapToItem(loader.item, 0, 0).x;
            const right = left + toast.width;
            console.log(`[PhoneTab] long toast ${toast.width} at ${left}..${right}`
                + ` in tab ${loader.item.width}; label ${label?.width}`
                + ` lines=${label?.lineCount} truncated=${label?.truncated}`);

            harness.check(`the long message widened the toast, got ${toast.width}`
                          + ` against ${harness.shortToastWidth}`,
                          toast.width > harness.shortToastWidth);
            harness.check(`the toast stays inside the tab (${left}..${right} of ${loader.item.width})`,
                          left >= 0 && right <= loader.item.width);
            harness.check(`...and inside the cap the panel's own margins set, got ${toast.width}`,
                          toast.width <= harness.toastCap);
            harness.check(`the label is bounded and wraps rather than running off, got ${label?.width}`,
                          label !== null && label.width <= toast.width
                          && label.wrapMode !== Text.NoWrap && label.lineCount > 1);
            const labelRight = label.mapToItem(toast, label.width, 0).x;
            harness.check(`the label's own right edge is inside the toast, got ${labelRight}`,
                          labelRight <= toast.width);
        },

        // ---- the tab recedes as a sub-page slides in ---------------------
        () => {
            const column = harness.contentColumn();
            harness.check(`the tab rests at full strength, got ${column?.opacity} / ${column?.scale}`,
                          column !== null && column.opacity === 1 && column.scale === 1);
            harness.fadeSaw = { samples: 0, minOpacity: 2, maxOpacity: -1,
                                minScale: 2, maxScale: -1, mid: 0 };
            loader.item.openSubPage("contacts");
            fadeWatch.running = true;
        },
        () => {},
        () => {
            fadeWatch.running = false;
            const saw = harness.fadeSaw;
            const column = harness.contentColumn();
            console.log(`[PhoneTab] fade watch: samples=${saw.samples}`
                + ` opacity ${saw.minOpacity.toFixed(3)}..${saw.maxOpacity.toFixed(3)}`
                + ` scale ${saw.minScale.toFixed(4)}..${saw.maxScale.toFixed(4)}`
                + ` midFrames=${saw.mid} settled=${column?.opacity}/${column?.scale}`);

            harness.check(`the transition was watched frame by frame, got ${saw.samples} samples`,
                          saw.samples > 10);
            // A transition that never ran reports the same "nothing was ever
            // out of range" as one that ran correctly, so what is asserted is
            // that a MID-flight reading exists - the shape b2b5de2a1 records
            // for a step that measures the state it was supposed to change.
            harness.check(`the outgoing tab was caught mid-fade, ${saw.mid} frames strictly between`,
                          saw.mid > 0);
            harness.check(`...and it recedes rather than only fading, scale down to ${saw.minScale.toFixed(4)}`,
                          saw.minScale < 1);
            // The recede is DERIVED, not picked, and this is the check that
            // says so: the excursion may not exceed twice the derived one.
            // It is a band rather than the number itself because
            // `elementMove`'s expressiveDefaultSpatial curve leaves the unit
            // box - it peaks at 1.0139 - so the scale legitimately travels a
            // hair past its destination on the way there.
            const excursion = column !== null ? 1 - column.recedeTo : 0;
            harness.check(`the recede stays the derived size, ${saw.minScale.toFixed(4)}`
                          + ` against ${column?.recedeTo?.toFixed(4)}`,
                          column !== null && saw.minScale >= column.recedeTo - excursion);
            harness.check(`the tab ends the transition gone, got ${column?.opacity} / ${column?.scale}`,
                          column !== null && column.opacity < 0.001
                          && Math.abs(column.scale - column.recedeTo) < 0.001);
            loader.item.popSubPage();
        },
        () => {},
        () => {
            // Both channels come back, which is the half a one-way check
            // cannot see: a recede that never returned would leave the tab
            // permanently a hair small and permanently transparent.
            const column = harness.contentColumn();
            harness.check(`popping the page brings the tab back, got ${column?.opacity} / ${column?.scale}`,
                          column !== null && Math.abs(column.opacity - 1) < 0.001
                          && Math.abs(column.scale - 1) < 0.001);
        },

        // ---- a roster of ONE ---------------------------------------------
        //
        // The reported shape: with a single device the group was a ring of
        // `bgcolor` drawn around one row, because every row sat inset inside a
        // plate it painted over. With several rows that ring passes for seam
        // material, so two devices could not have caught it - a group of one is
        // the case where the plate has nothing to be except a frame.
        () => {
            PhoneConnect.applyDevices([PhoneConnect.devices[0]]);
            harness.click(harness.first("PhoneDeviceChip"));
        },
        () => {},
        () => {
            const rows = harness.rosterRows();
            const only = rows[0] ?? null;
            const listWidth = harness.rosterList()?.width ?? 0;
            const inset = only !== null
                ? only.mapToItem(harness.rosterList(), 0, 0).x : -1;
            console.log(`[PhoneTab] lone row corners ${only?.cornerTopLeft}/${only?.cornerTopRight}`
                        + `/${only?.cornerBottomLeft}/${only?.cornerBottomRight}`
                        + ` inset ${inset} of ${listWidth}`);
            harness.check(`one device draws one row, got ${rows.length}`, rows.length === 1);
            harness.check(`the lone row carries the group's rounding on all four corners, got`
                          + ` ${only?.cornerTopLeft}/${only?.cornerBottomRight}`,
                          only !== null
                          && only.cornerTopLeft === Appearance.rounding.normal
                          && only.cornerTopRight === Appearance.rounding.normal
                          && only.cornerBottomLeft === Appearance.rounding.normal
                          && only.cornerBottomRight === Appearance.rounding.normal);
            const lonePlate = harness.plateOf(only);
            harness.check(`...and no plate is painted behind it, got`
                          + ` ${lonePlate === null ? "no plate" : lonePlate.color.a}`,
                          lonePlate !== null && lonePlate.color.a === 0);
            harness.loneRow = only;
            harness.loneInset = inset;
            if (only) harness.hover(only);
        },
        () => {},
        () => {
            // The lift, MEASURED - `interactionMotion.scale` is the number the
            // transform is actually reading, not the token it was asked for.
            // A row grows about its own centre, so the width it gains is split
            // between its two sides and the inset has to cover half of it. The
            // roster had no inset for one build and the hovered row grew
            // straight past the panel's edge.
            const row = harness.loneRow;
            const scale = row?.interactionMotion?.scale ?? 1;
            const overhang = row !== null ? row.width * (scale - 1) / 2 : 0;
            console.log(`[PhoneTab] hovered scale ${scale} over width ${row?.width}`
                        + ` -> overhang ${overhang.toFixed(2)} against inset ${harness.loneInset}`);
            harness.check(`hovering a row lifts it, got scale ${scale}`,
                          scale > 1.001);
            harness.check(`...and the lift stays inside the group: overhang`
                          + ` ${overhang.toFixed(2)} within inset ${harness.loneInset}`,
                          overhang <= harness.loneInset + 0.01);
        },

        () => harness.finish()
    ]

    property var footerButtons: []
    property var footerPill: null
    property var footerLabel: null

    property var loneRow: null
    property real loneInset: 0

    property real listWithCard: 0
    property real cardHeight: 0
    property real columnSpacing: 0

    // What the launch watch saw. Written by the timer below, read by the
    // step after it - never re-read out of the harness's own log line.
    property var launchSaw: ({ running: false, active: false, blankGlyph: "",
                               minGlyphOpacity: 1, samples: 0 })

    Timer {
        id: launchWatch
        interval: 25
        repeat: true
        onTriggered: {
            const card = harness.cardTitled("scrcpy Mirror")
                ?? harness.cardTitled("Connecting") ?? harness.cardTitled("Mirror");
            if (!card) return;
            const badge = harness.cardBadge(card);
            const glyph = harness.cardGlyph(card);
            const saw = harness.launchSaw;
            saw.samples++;
            if (PhoneScrcpy.mirrorRunning) saw.running = true;
            if (card.cardState === "active") saw.active = true;
            if (glyph) {
                if (glyph.opacity < saw.minGlyphOpacity) saw.minGlyphOpacity = glyph.opacity;
                // Empty on either object, or the two disagreeing, is a badge
                // with nothing in it - recorded as the offending pair rather
                // than as a bool, so a failure names what was on screen.
                if (`${glyph.text}`.length === 0 || `${badge?.text}` !== `${glyph.text}`)
                    saw.blankGlyph = `${badge?.text}|${glyph.text}`;
            }
            harness.launchSaw = saw;
        }
    }

    property var rosterSaw: ({ samples: 0, mid: 0, maxHeight: 0 })

    Timer {
        id: rosterWatch
        interval: 25
        repeat: true
        onTriggered: {
            const box = harness.rosterBox();
            const list = harness.rosterList();
            if (!box || !list) return;
            const saw = harness.rosterSaw;
            saw.samples++;
            // Only while the box is DRAWN. A QQuickLayout excludes an
            // invisible child and stops writing its height, so a folded box
            // keeps whatever height its last laid-out frame left on it - read
            // ungated, that stale number sits in the mid-flight band for the
            // rest of the run and the fold's own check passes on a snap.
            if (box.visible) {
                saw.maxHeight = Math.max(saw.maxHeight, box.height);
                // The settled height is the group's own. It was the list
                // view's `contentHeight` while the roster was one; a
                // GroupedList has no such property, and `undefined` in this
                // comparison is a silent false - the mid-flight band empties
                // and the reveal reads as a snap it is not.
                if (box.height > 1 && box.height < list.implicitHeight - 1) saw.mid++;
            }
            harness.rosterSaw = saw;
        }
    }

    property string glyphBefore: ""
    property var swapSaw: ({ samples: 0, maxOff: 0, minOpacity: 1 })

    Timer {
        id: swapWatch
        interval: 25
        repeat: true
        onTriggered: {
            const buttons = harness.footerButtons;
            if (buttons.length !== 2) return;
            const saw = harness.swapSaw;
            saw.samples++;
            for (const button of buttons) {
                saw.maxOff = Math.max(saw.maxOff, harness.glyphOffCentre(button));
                const glyph = harness.footerGlyph(button);
                if (glyph) saw.minOpacity = Math.min(saw.minOpacity, glyph.opacity);
            }
            harness.swapSaw = saw;
        }
    }

    property real shortToastWidth: 0
    property real toastCap: 0

    property var fadeSaw: ({ samples: 0, minOpacity: 2, maxOpacity: -1,
                             minScale: 2, maxScale: -1, mid: 0 })

    Timer {
        id: fadeWatch
        interval: 25
        repeat: true
        onTriggered: {
            const column = harness.contentColumn();
            if (!column) return;
            const saw = harness.fadeSaw;
            saw.samples++;
            saw.minOpacity = Math.min(saw.minOpacity, column.opacity);
            saw.maxOpacity = Math.max(saw.maxOpacity, column.opacity);
            saw.minScale = Math.min(saw.minScale, column.scale);
            saw.maxScale = Math.max(saw.maxScale, column.scale);
            if (column.opacity > 0.001 && column.opacity < 0.999) saw.mid++;
            harness.fadeSaw = saw;
        }
    }

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
