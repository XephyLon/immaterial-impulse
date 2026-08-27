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
    // The file the fake daemon reports as the first notification's iconPath.
    readonly property string iconPath: Quickshell.env("PHONE_ICON_PATH") ?? ""

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
            anchors.fill: parent
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
        () => loader.item.popSubPage(),
        () => {},

        // ---- the Apps page's empty state stays under its own header -------
        () => loader.item.openSubPage("apps"),
        () => {},
        () => {
            const page = harness.first("PhoneAppsPage");
            const placeholder = harness.findAll(page, "PagePlaceholder", [])[0] ?? null;
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
        },

        // ---- and it still does at a page height that has nothing to spare -
        () => {
            window.implicitHeight = 380;
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
            // `dropIconWhenCramped` is what makes this hold: the glyph gives
            // way and the two labels fit, rather than the column growing past
            // the region and painting over the header again.
            harness.check(`a short page still keeps the empty state under the status line,`
                          + ` got ${drawnBox.top} against ${statusBox.bottom}`,
                          drawnBox.top >= statusBox.bottom);
            harness.check(`...and inside the page, got ${drawnBox.bottom} of ${page.height}`,
                          drawnBox.bottom <= page.height + 1);
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
