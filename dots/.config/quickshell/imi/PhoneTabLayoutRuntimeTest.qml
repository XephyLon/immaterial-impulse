import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.imi.phone
import qs.modules.imi.sidebarLeft.phone

/**
 * What the Phone tab and its sub-pages actually DRAW, measured in a real
 * window rather than read off the source.
 *
 * Three classes of defect live here and none of them is reachable from
 * `qmltestrunner` or from a source check: a page whose content resolves to
 * zero height renders a header and nothing else, an empty state centred on
 * the wrong region paints itself over the header above it, and an icon that
 * is never drawn is indistinguishable in the source from one whose file
 * failed to load. Every check below is a number read back off an item that
 * is on screen.
 *
 * The tab is built over the REAL services, fed by a fake `busctl` on PATH
 * (one paired, reachable phone; two mirrored notifications, one carrying an
 * `iconPath` and one with none) and by a real `kpeoplevcard` fixture tree
 * that the real contacts monitor reads - so the Contacts page has rows to
 * lay out and the notification cards have an icon to resolve.
 *
 * A fake `adb` and a fake `scrcpy` are on the same PATH, answering off two
 * files this harness creates between steps, which is what lets the Android
 * Apps page be walked through its three states in one run - no phone on ADB,
 * a phone that answered with nothing, and a phone with apps - and what makes
 * the first of those a property of the test rather than of whichever machine
 * is running it.
 *
 * Driven by tests/test_phone_tab_layout_runtime.py, which brings the weston
 * and the session bus.
 *
 *   PATH=<dir with fake busctl>:$PATH qs -p PhoneTabLayoutRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int checksRun: 0
    property int elapsed: 0

    readonly property string phoneId: Quickshell.env("PHONE_ID") ?? ""
    // The two files the fake `adb` and the fake `scrcpy` read their answers
    // off. Nothing else in this harness can move the Apps page between its
    // three states: what the page draws is a consequence of what the tools
    // report, and the tools are asked again by the shell's own probes.
    readonly property string adbAttachedPath: Quickshell.env("PHONE_ADB_ATTACHED") ?? ""
    readonly property string appsFilePath: Quickshell.env("PHONE_APPS_FILE") ?? ""
    readonly property string appsSourcePath: Quickshell.env("PHONE_APPS_SOURCE") ?? ""
    // The file the fake daemon reports as the first notification's iconPath.
    readonly property string iconPath: Quickshell.env("PHONE_ICON_PATH") ?? ""
    // The two names in the vCard fixture, handed in rather than spelled a
    // second time here: a row is found by the name the fixture wrote, so the
    // harness and the fixture cannot disagree about which row is which.
    readonly property string latinName: Quickshell.env("PHONE_CONTACT_LATIN") ?? ""
    readonly property string arabicName: Quickshell.env("PHONE_CONTACT_ARABIC") ?? ""
    // What "a real gap" means for the avatar: the shell's base unit. Below
    // this the glyph reads as sitting on the card's edge - measured at 4px
    // with the old fixed row height, and photographed by the maintainer.
    readonly property real minAvatarGap: Appearance.spacing.space100

    property string arabicId: ""
    property real arabicCollapsedHeight: 0
    // How tall the tab's host is. The window cannot be resized under headless
    // weston - measured: assigning `implicitHeight` left the page at 880 and
    // the "cramped" step scored the tall page a second time - so the host's
    // own height is what the short-page step moves.
    property real viewportHeight: 900
    property real tallPageHeight: 0

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[PhoneTabLayout] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    function typeName(obj) {
        return `${obj}`.split("(")[0].split("_QML")[0].trim();
    }

    function findAll(item, type, out) {
        if (!item)
            return out;
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

    function findNamed(item, objName, out) {
        if (!item)
            return out;
        for (const child of item.children) {
            if (child.objectName === objName)
                out.push(child);
            harness.findNamed(child, objName, out);
        }
        return out;
    }

    function firstNamed(item, objName) {
        return harness.findNamed(item, objName, [])[0] ?? null;
    }

    // By the name the fixture wrote, never by index: the service sorts with
    // localeCompare, so which row an Arabic name lands on is the collation's
    // business and not something this harness may assume.
    function contactRowFor(list, displayName) {
        if (!list)
            return null;
        for (let i = 0; i < list.count; i++) {
            const row = list.itemAtIndex(i);
            if (row && String(row.modelData?.displayName ?? "") === displayName)
                return row;
        }
        return null;
    }

    // Everything about the row defect is a comparison between the card's own
    // box and the boxes of the three things it is supposed to contain.
    function scoreRow(tag, row) {
        const pad = row.rowPadding;
        const headerBox = harness.boxIn(harness.firstNamed(row, "contactHeader"), row);
        const avatarBox = harness.boxIn(harness.firstNamed(row, "contactAvatar"), row);
        const identityBox = harness.boxIn(harness.firstNamed(row, "contactIdentity"), row);
        console.log(`[PhoneTabLayout] ${tag} card h=${row.height} pad=${pad}`
                    + ` header ${headerBox.top}-${headerBox.bottom}`
                    + ` avatar ${avatarBox.top}-${avatarBox.bottom}`
                    + ` identity ${identityBox.top}-${identityBox.bottom}`);
        harness.check(`${tag}: the name and the number stay inside the card, got`
                      + ` ${identityBox.top}-${identityBox.bottom} of 0-${row.height}`,
                      identityBox.top >= -0.5 && identityBox.bottom <= row.height + 0.5);
        harness.check(`${tag}: the avatar's bottom edge clears the card's by a real gap,`
                      + ` got ${row.height - avatarBox.bottom} against`
                      + ` ${harness.minAvatarGap}`,
                      row.height - avatarBox.bottom >= harness.minAvatarGap);
        harness.check(`${tag}: ...and its top edge does too, got ${avatarBox.top}`
                      + ` against ${harness.minAvatarGap}`,
                      avatarBox.top >= harness.minAvatarGap);
        harness.check(`${tag}: the card is its content plus its own padding and nothing`
                      + ` else, got ${row.height} against ${headerBox.bottom + pad}`,
                      Math.abs(row.height - (headerBox.bottom + pad)) <= 1
                      && Math.abs(headerBox.top - pad) <= 1);
    }

    Process { id: fixtureStep }

    function writeFixture(argv) {
        fixtureStep.exec(argv);
    }

    // Whether an item is really on screen, which is not the same question as
    // `visible`: PagePlaceholder fades, so a placeholder standing down reports
    // `visible` false only once its opacity has finished leaving, and one that
    // is up at opacity 0 is a message nobody can read.
    function onScreen(item) {
        return item !== null && item.visible && item.opacity > 0.5
            && item.width > 0 && item.height > 0;
    }

    // Where an item is DRAWN, in another item's coordinates. Everything about
    // both defects is a comparison between two of these.
    function boxIn(item, reference) {
        const origin = item.mapToItem(reference, 0, 0);
        return {
            top: origin.y,
            left: origin.x,
            bottom: origin.y + item.height,
            right: origin.x + item.width
        };
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
            name: "PhoneTabLayoutDriver"
        }

        Loader {
            id: loader
            width: parent.width
            height: harness.viewportHeight
            active: false
            sourceComponent: Phone {}
        }
    }

    Component.onCompleted: {
        // A singleton is constructed on first use; these reads start the
        // presence probe, the first sweep and the contacts monitor.
        console.log(`[PhoneTabLayout] services constructed, installed=${PhoneConnect.installed}`
                    + ` contacts=${PhoneContacts.enabled}`);
    }

    Timer {
        id: waitForReady
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            harness.elapsed += waitForReady.interval;
            const ready = Config.ready && PhoneConnect.installed
                && PhoneConnect.devices.length === 1
                && PhoneNotifications.count === 2
                && PhoneContacts.ready && PhoneContacts.count > 0;
            if (!ready) {
                if (harness.elapsed >= 40000) {
                    harness.check(`the fake daemon and the contacts fixture both answered`
                                  + ` (devices ${PhoneConnect.devices.length},`
                                  + ` notifications ${PhoneNotifications.count},`
                                  + ` contacts ${PhoneContacts.count})`, false);
                    harness.finish();
                }
                return;
            }
            waitForReady.running = false;
            steps.running = true;
        }
    }

    function finish() {
        console.log(`[PhoneTabLayout] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }

    property var stepList: [
        () => {
            loader.active = true;
        },
        () => {},

        // ---- a notification card draws the posting app's icon -------------
        () => {
            const list = harness.first("PhoneNotificationList");
            const icons = harness.findAll(list, "NotificationAppIcon", []);
            harness.check(`every notification card carries an app icon, got ${icons.length} for`
                          + ` ${PhoneNotifications.appNameList.length} cards`,
                          icons.length === PhoneNotifications.appNameList.length && icons.length === 2);

            // The one whose group carries an iconPath must have RESOLVED it:
            // a card drawing a broken Image is the same source as one drawing
            // a good one, and only the status tells them apart.
            const withIcon = icons.find(i => String(i.image ?? "") !== "") ?? null;
            harness.check("the card for an app that sent an icon points at that file",
                          withIcon !== null
                          && String(withIcon.image).indexOf(harness.iconPath) >= 0);
            const drawn = withIcon === null ? [] : harness.findAll(withIcon, "QQuickImage", [])
                .filter(i => i.status === Image.Ready && i.width > 0);
            harness.check(`...and the picture loaded, got ${drawn.length} ready images`,
                          drawn.length >= 1);

            // The other one has no iconPath at all, and must fall back rather
            // than draw an empty box.
            const without = icons.find(i => String(i.image ?? "") === "") ?? null;
            const glyphs = without === null ? [] : harness.findAll(without, "MaterialSymbol", [])
                .filter(g => g.visible && String(g.text).length > 0);
            harness.check(`a notification with no icon falls back to a glyph, got ${glyphs.length}`,
                          without !== null && glyphs.length >= 1);
        },

        // ---- the Contacts page's list owns the room under the header ------
        () => loader.item.openSubPage("contacts"),
        () => {},
        () => {
            const page = harness.first("PhoneContactsPage");
            const list = harness.findAll(page, "StyledListView", [])[0] ?? null;
            // Structural, not by text: the region the list is anchored into,
            // the page's own content column above it, and the SLOT that
            // column sits in - which is what decides whether it fills.
            const region = list?.parent ?? null;
            const column = region?.parent ?? null;
            const slot = column?.parent ?? null;
            const field = harness.findAll(page, "ToolbarTextField", [])[0] ?? null;
            const counts = column?.children[1] ?? null;
            const delegate = list === null ? null : list.itemAtIndex(0);
            console.log(`[PhoneTabLayout] page=${page?.height} column=${column?.height}`
                        + ` slot=${harness.typeName(slot)} h=${slot?.height}`
                        + ` region=${region?.height} list h=${list?.height}`
                        + ` contentHeight=${list?.contentHeight} count=${list?.count}`
                        + ` delegate=${delegate?.height} filtered=${PhoneContacts.filtered.length}`);

            // The defect, stated as the thing that was wrong: the page's own
            // column sat at its IMPLICIT height (73) inside an 836px slot,
            // because the slot was a plain Item and `Layout.fillHeight` is
            // inert in one.
            harness.check(`the sub-page's content slot is a layout, got`
                          + ` ${harness.typeName(slot)}`,
                          harness.typeName(slot) === "QQuickColumnLayout");
            harness.check(`the page's content column fills that slot, got ${column?.height}`
                          + ` of ${slot?.height} in a ${page?.height} page`,
                          column !== null && slot !== null && page !== null
                          && Math.abs(column.height - slot.height) <= 1
                          && slot.height > page.height / 2);
            harness.check(`the contact list has a height to draw into, got ${list?.height}`,
                          list !== null && list.height > 0);
            harness.check(`the list holds every filtered contact, got ${list?.count}`
                          + ` of ${PhoneContacts.filtered.length}`,
                          list !== null && list.count === PhoneContacts.filtered.length
                          && list.count > 0);
            harness.check(`its content is taller than nothing, got ${list?.contentHeight}`,
                          list !== null && list.contentHeight > 0);
            harness.check(`and a row draws at a real height, got ${delegate?.height}`,
                          delegate !== null && delegate.height > 0);

            const listBox = harness.boxIn(list, page);
            const fieldBox = harness.boxIn(field, page);
            const countBox = harness.boxIn(counts, page);
            console.log(`[PhoneTabLayout] field ${fieldBox.top}-${fieldBox.bottom}`
                        + ` count ${countBox.top}-${countBox.bottom}`
                        + ` list ${listBox.top}-${listBox.bottom} of page ${page.height}`);
            harness.check("the list starts below the search row and the count line",
                          listBox.top >= fieldBox.bottom && listBox.top >= countBox.bottom);
            harness.check(`...and runs to the bottom of the page, got ${listBox.bottom}`
                          + ` of ${page.height}`,
                          Math.abs(listBox.bottom - page.height) <= 1);
        },

        // ---- a contact row fits its content, in either script ------------
        // The reported defect: an Arabic name is taller than a Latin one at
        // the same pixelSize, and a card sized from a constant fits one and
        // not the other. Both scripts are on screen at once, because "the
        // card is tall enough" is satisfied by a card that is tall enough for
        // everything.
        () => {
            const page = harness.first("PhoneContactsPage");
            const list = harness.findAll(page, "StyledListView", [])[0] ?? null;
            const latin = harness.contactRowFor(list, harness.latinName);
            const arabic = harness.contactRowFor(list, harness.arabicName);
            harness.check(`both scripts have a row to measure, latin=${latin !== null}`
                          + ` arabic=${arabic !== null} of ${list?.count} rows`,
                          latin !== null && arabic !== null);
            if (latin === null || arabic === null)
                return;
            harness.scoreRow("latin", latin);
            harness.scoreRow("arabic", arabic);
            // The half a per-row check cannot see: two cards that both fit
            // because both were made generously tall are still a constant.
            harness.check(`the card's height follows the script rather than a constant,`
                          + ` latin ${latin.height} against arabic ${arabic.height}`,
                          arabic.height > latin.height);
            harness.arabicCollapsedHeight = arabic.height;
            harness.arabicId = String(arabic.modelData.id);
        },

        // ---- ...and so does the stack it grows when it is expanded --------
        () => {
            harness.first("PhoneContactsPage").expandedId = harness.arabicId;
        },
        () => {},
        () => {
            const page = harness.first("PhoneContactsPage");
            const list = harness.findAll(page, "StyledListView", [])[0] ?? null;
            const arabic = harness.contactRowFor(list, harness.arabicName);
            const details = harness.firstNamed(arabic, "contactDetails");
            const detailsBox = harness.boxIn(details, arabic);
            console.log(`[PhoneTabLayout] arabic expanded card h=${arabic?.height}`
                        + ` details ${detailsBox.top}-${detailsBox.bottom}`
                        + ` rows=${details?.children.length}`);
            harness.check(`expanding the Arabic contact grows its card, got`
                          + ` ${arabic?.height} against ${harness.arabicCollapsedHeight}`,
                          arabic !== null && arabic.height > harness.arabicCollapsedHeight);
            harness.check(`the number and address rows stay inside the card, got`
                          + ` ${detailsBox.top}-${detailsBox.bottom} of 0-${arabic?.height}`,
                          details !== null && detailsBox.top >= -0.5
                          && detailsBox.bottom <= arabic.height + 0.5);
            // Per row as well as per column: a child overflowing its own
            // column still reports a column that fits.
            let escaped = 0;
            let drawn = 0;
            for (const child of (details?.children ?? [])) {
                if (!child.visible || child.height <= 0)
                    continue;
                drawn++;
                const box = harness.boxIn(child, arabic);
                if (box.top < -0.5 || box.bottom > arabic.height + 0.5)
                    escaped++;
            }
            harness.check(`...and so does every one of the ${drawn} rows in it,`
                          + ` ${escaped} escaped`,
                          drawn > 0 && escaped === 0);
        },
        () => {
            harness.first("PhoneContactsPage").expandedId = "";
        },
        () => {},

        () => loader.item.popSubPage(),
        () => {},

        // ---- the Apps page with no phone on ADB ---------------------------
        //
        // The state the maintainer photographed: a phone paired to KDE Connect
        // over the LAN, and `adb devices` listing nothing. What was on screen
        // was a line of red text and an empty state under it, neither of which
        // says what to do; what has to be on screen is one panel that does.
        () => loader.item.openSubPage("apps"),
        () => {},
        () => {},
        () => {
            const page = harness.first("PhoneAppsPage");
            const placeholder = harness.findAll(page, "PagePlaceholder", [])[0] ?? null;
            const notice = harness.findAll(page, "NoticeBox", [])[0] ?? null;
            const list = harness.findAll(page, "StyledListView", [])[0] ?? null;
            const region = placeholder?.parent ?? null;
            const column = region?.parent ?? null;
            const status = column?.children[1] ?? null;
            const noticeText = harness.findAll(notice, "StyledText", [])
                .map(t => String(t.text)).join(" | ");
            console.log(`[PhoneTabLayout] no-adb: ready=${PhoneDeps.ready} adb=${PhoneDeps.adb}`
                        + ` adbDevice=${PhoneDeps.adbDevice} appMode=${PhoneScrcpy.appModeSupported}`
                        + ` appsError="${PhoneScrcpy.appsError}" notice h=${notice?.height}`
                        + ` placeholderShown=${placeholder?.shown} status=${status?.visible}`
                        + ` list=${list?.visible}`);

            harness.check(`the fake tooling answered: app mode is supported and adb sees`
                          + ` no phone, got ready=${PhoneDeps.ready} adb=${PhoneDeps.adb}`
                          + ` device=${PhoneDeps.adbDevice} appMode=${PhoneScrcpy.appModeSupported}`,
                          PhoneDeps.ready && PhoneDeps.adb && !PhoneDeps.adbDevice
                          && PhoneScrcpy.appModeSupported);
            harness.check(`the page draws a panel, got ${notice?.height}px of one`,
                          harness.onScreen(notice));
            harness.check(`...in the error container role, got ${notice?.color}`,
                          notice !== null && String(notice.color)
                          === String(Appearance.colors.colErrorContainer));
            // Both routes, because the machine this was reported from has
            // neither: a panel naming only the cable is no use to someone
            // whose phone is across the room.
            harness.check("...naming USB debugging and wireless debugging both",
                          noticeText.indexOf("USB debugging") >= 0
                          && noticeText.indexOf("Wireless debugging") >= 0);
            harness.check("...and the pairing the wireless route needs by hand",
                          noticeText.indexOf("adb pair") >= 0
                          && noticeText.indexOf("adb connect") >= 0);
            // The two messages that used to say the same thing beside it.
            harness.check(`the empty state stands down, got shown=${placeholder?.shown}`,
                          placeholder !== null && !placeholder.shown);
            harness.check(`the status line's red duplicate stands down too, got`
                          + ` visible=${status?.visible} text="${status?.text}"`,
                          status !== null && !status.visible);
            harness.check(`and no list is drawn, got visible=${list?.visible}`,
                          list === null || !list.visible);
        },

        // ---- a phone appears on ADB, and the page asks for the list itself -
        () => harness.writeFixture(["touch", harness.adbAttachedPath]),
        () => PhoneDeps.refreshAdbDevices(),
        () => {},
        () => {},
        () => {
            const page = harness.first("PhoneAppsPage");
            const placeholder = harness.findAll(page, "PagePlaceholder", [])[0] ?? null;
            const notice = harness.findAll(page, "NoticeBox", [])[0] ?? null;
            const list = harness.findAll(page, "StyledListView", [])[0] ?? null;
            // The same structural walk as the Contacts step: the placeholder
            // is anchored into the leftover region, whose parent is the
            // page's content column, whose children are its rows in order.
            const region = placeholder?.parent ?? null;
            const column = region?.parent ?? null;
            const field = harness.findAll(page, "ToolbarTextField", [])[0] ?? null;
            // Row 0 is the search row; row 1 is the status line - the app
            // count, or the reason there is no count.
            const status = column?.children[1] ?? null;
            // PagePlaceholder centres one column in itself; that column is
            // what is actually painted, and it is free to reach outside.
            const drawn = placeholder?.children[0] ?? null;

            harness.check("the page has a search row, a status line and an empty state",
                          page !== null && field !== null && status !== null
                          && placeholder !== null && drawn !== null);
            if (page === null || field === null || status === null || drawn === null) {
                console.log(`[PhoneTabLayout] apps page=${page} field=${field}`
                            + ` status=${status} placeholder=${placeholder}`);
                return;
            }

            console.log(`[PhoneTabLayout] on-adb: adbDevice=${PhoneDeps.adbDevice}`
                        + ` apps=${PhoneScrcpy.apps.length} loading=${PhoneScrcpy.appsLoading}`
                        + ` appsError="${PhoneScrcpy.appsError}" notice=${notice?.height}`
                        + ` placeholderShown=${placeholder.shown} status="${status.text}"`);

            harness.check(`adb sees the phone now, got ${PhoneDeps.adbDevice}`,
                          PhoneDeps.adbDevice === true);
            harness.check(`the panel goes with it, got height=${notice?.height}`
                          + ` visible=${notice?.visible}`,
                          !harness.onScreen(notice));
            // The page asked for the list on its own when the device appeared:
            // the supervisor ran, the phone had nothing to give, and the error
            // that stood there while there was no transport is gone.
            harness.check(`...and the list was asked for without a click, got`
                          + ` error="${PhoneScrcpy.appsError}" loading=${PhoneScrcpy.appsLoading}`,
                          PhoneScrcpy.appsError === "" && !PhoneScrcpy.appsLoading);
            harness.check(`the empty state is the message now, got shown=${placeholder.shown}`
                          + ` title="${placeholder.title}"`,
                          placeholder.shown && harness.onScreen(drawn)
                          && String(placeholder.title).length > 0);

            const fieldBox = harness.boxIn(field, page);
            const statusBox = harness.boxIn(status, page);
            const regionBox = harness.boxIn(placeholder, page);
            const drawnBox = harness.boxIn(drawn, page);
            console.log(`[PhoneTabLayout] status text="${status.text}"`);
            console.log(`[PhoneTabLayout] field ${fieldBox.top}-${fieldBox.bottom}`
                        + ` status ${statusBox.top}-${statusBox.bottom}`
                        + ` placeholder region ${regionBox.top}-${regionBox.bottom}`
                        + ` drawn ${drawnBox.top}-${drawnBox.bottom}`
                        + ` of page ${page.height} x ${page.width}`);

            harness.check(`the empty state's region starts below the status line,`
                          + ` got ${regionBox.top} against ${statusBox.bottom}`,
                          regionBox.top >= statusBox.bottom);
            harness.check(`...and it is the leftover height, got ${regionBox.bottom}`
                          + ` of ${page.height}`,
                          Math.abs(regionBox.bottom - page.height) <= 1
                          && regionBox.bottom - regionBox.top > 0);
            // The one the maintainer saw: the glyph column is centred, so a
            // region of the wrong height paints it over the rows above.
            harness.check(`what the empty state DRAWS clears the search row,`
                          + ` got ${drawnBox.top} against ${fieldBox.bottom}`,
                          drawnBox.top >= fieldBox.bottom);
            harness.check(`...and clears the status line, got ${drawnBox.top}`
                          + ` against ${statusBox.bottom}`,
                          drawnBox.top >= statusBox.bottom);
            harness.check(`the status line stays inside the page, got`
                          + ` ${statusBox.left}-${statusBox.right} of ${page.width}`,
                          statusBox.left >= 0 && statusBox.right <= page.width + 1);

            // ---- and the description reads as a paragraph, not as a rule ---
            const texts = harness.findAll(placeholder, "StyledText", []);
            const description = texts.find(t => String(t.text)
                                           === String(placeholder.description)) ?? null;
            const descriptionBox = description === null ? null
                : harness.boxIn(description, page);
            console.log(`[PhoneTabLayout] description w=${description?.width}`
                        + ` implicit=${description?.implicitWidth}`
                        + ` ${descriptionBox?.left}-${descriptionBox?.right} of ${page.width}`);
            // Or the measure is vacuous: a string shorter than the clamp is
            // held to its own width whatever the clamp says.
            harness.check(`the description is longer than its measure, got`
                          + ` ${description?.implicitWidth} against ${description?.width}`,
                          description !== null
                          && description.implicitWidth > description.width);
            harness.check(`...so it is held short of the page, got`
                          + ` ${descriptionBox?.left}-${descriptionBox?.right}`
                          + ` of ${page.width}`,
                          descriptionBox !== null && descriptionBox.left > 0
                          && descriptionBox.right < page.width);
            harness.check(`...and centred in the region rather than left against it,`
                          + ` got ${(descriptionBox?.left + descriptionBox?.right) / 2}`
                          + ` against ${(regionBox.left + regionBox.right) / 2}`,
                          descriptionBox !== null
                          && Math.abs((descriptionBox.left + descriptionBox.right) / 2
                                      - (regionBox.left + regionBox.right) / 2) <= 1);
            harness.tallPageHeight = page.height;
        },

        // ---- and it still does at a page height that has nothing to spare -
        () => {
            harness.viewportHeight = 200;
        },
        () => {},
        () => {
            const page = harness.first("PhoneAppsPage");
            const placeholder = harness.findAll(page, "PagePlaceholder", [])[0] ?? null;
            const region = placeholder?.parent ?? null;
            const column = region?.parent ?? null;
            const status = column?.children[1] ?? null;
            const drawn = placeholder?.children[0] ?? null;
            const statusBox = harness.boxIn(status, page);
            const regionBox = harness.boxIn(placeholder, page);
            const drawnBox = harness.boxIn(drawn, page);
            console.log(`[PhoneTabLayout] cramped: status ${statusBox.top}-${statusBox.bottom}`
                        + ` region ${regionBox.top}-${regionBox.bottom}`
                        + ` drawn ${drawnBox.top}-${drawnBox.bottom} of page ${page.height}`);
            // Or the step scores the tall page a second time and says nothing.
            harness.check(`the page really did get shorter, got ${page.height}`
                          + ` against ${harness.tallPageHeight}`,
                          page.height < harness.tallPageHeight / 2);
            // `dropIconWhenCramped` is what makes this hold: the glyph gives
            // way and the two labels fit, rather than the column growing past
            // the region and painting over the header again.
            harness.check(`a short page still keeps the empty state under the status line,`
                          + ` got ${drawnBox.top} against ${statusBox.bottom}`,
                          drawnBox.top >= statusBox.bottom);
            // Centred in what is LEFT, which is the whole of what the empty
            // state owes and the only form of it that survives a region
            // smaller than the labels: at 180px the two labels are 70 in a
            // 63px region, so `dropIconWhenCramped` has already given up the
            // glyph and the remainder overhangs a few pixels at both ends -
            // symmetrically, which is what says it is centred on its own
            // region rather than on the page.
            harness.check(`...centred in the region it was given, got`
                          + ` ${(drawnBox.top + drawnBox.bottom) / 2} against`
                          + ` ${(regionBox.top + regionBox.bottom) / 2}`,
                          Math.abs((drawnBox.top + drawnBox.bottom) / 2
                                   - (regionBox.top + regionBox.bottom) / 2) <= 1);
        },

        // ---- the phone has apps: the list, and nothing else ----------------
        () => {
            harness.viewportHeight = 900;
            harness.writeFixture(["cp", harness.appsSourcePath, harness.appsFilePath]);
        },
        // The click the panel's last sentence points at, once there is a
        // device: the refresh button's own call.
        () => PhoneScrcpy.refreshApps(),
        () => {},
        () => {},
        () => {
            const page = harness.first("PhoneAppsPage");
            const placeholder = harness.findAll(page, "PagePlaceholder", [])[0] ?? null;
            const notice = harness.findAll(page, "NoticeBox", [])[0] ?? null;
            const list = harness.findAll(page, "StyledListView", [])[0] ?? null;
            const region = placeholder?.parent ?? null;
            const column = region?.parent ?? null;
            const status = column?.children[1] ?? null;
            const delegate = list === null ? null : list.itemAtIndex(0);
            console.log(`[PhoneTabLayout] with-apps: apps=${PhoneScrcpy.apps.length}`
                        + ` list count=${list?.count} h=${list?.height}`
                        + ` contentHeight=${list?.contentHeight} delegate=${delegate?.height}`
                        + ` placeholderShown=${placeholder?.shown} notice=${notice?.height}`
                        + ` status="${status?.text}"`);

            harness.check(`the phone's three apps arrived, got ${PhoneScrcpy.apps.length}`,
                          PhoneScrcpy.apps.length === 3);
            harness.check(`the list holds them, got ${list?.count}`,
                          list !== null && list.visible && list.count === 3);
            harness.check(`...at a height to draw into, got ${list?.height}`
                          + ` with a first row of ${delegate?.height}`,
                          list !== null && list.height > 0
                          && delegate !== null && delegate.height > 0);
            harness.check(`the empty state is gone, got shown=${placeholder?.shown}`,
                          placeholder !== null && !placeholder.shown);
            harness.check(`the panel is gone, got height=${notice?.height}`,
                          !harness.onScreen(notice));
            harness.check(`and the status line counts them, got "${status?.text}"`,
                          status !== null && status.visible
                          && String(status.text).indexOf("3 of 3") >= 0);
        },

        () => harness.finish()
    ]

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
