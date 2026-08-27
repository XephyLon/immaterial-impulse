import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.imi.settings

/**
 * The settings page host, built for real, and read back for how it builds its
 * pages.
 *
 * What this exists to refuse, in the shape it was found: the host used to
 * assign `active = true` to all fifteen page loaders inside one `Qt.callLater`
 * at `Config.ready`. That destroyed the `active:` binding beside it and built
 * ~24500 items in ONE turn of the event loop - measured on this harness's own
 * heartbeat at 622ms of frozen GUI thread, paid by the whole shell at startup
 * whether or not the settings window was ever opened. Switching pages was
 * cheap only because nothing was ever left to build.
 *
 * So the checks are about WHEN a page is built and whether building it blocks:
 *
 *   - nothing but the page on screen is built while the window has never been
 *     opened (the eager loop coming back reddens here);
 *   - a page asked for is not built inside the write (removing
 *     `asynchronous: true` reddens here);
 *   - `GlobalStates.currentPageInstance` names nothing while a page incubates,
 *     rather than the page the user just left;
 *   - the placeholder knows a page is building and does not flash it;
 *   - the warm-up reaches the rest, one at a time, and a warmed page is on
 *     screen the moment it is asked for.
 *
 * The instrument for "blocks" is a 1ms heartbeat: the longest gap between two
 * of its ticks is how long the GUI thread was unavailable, which is what a
 * hitch IS. `sync` timings alone cannot see it - the old loop's cost lands in
 * the turn after the write, not inside it.
 *
 * The un-warmed state is read ONE TURN after the host is built rather than by
 * holding the warm-up off: the warm-up's first tick is a motion tier away,
 * while the loop this refuses queued its fifteen builds inside that same turn,
 * so the turn boundary is what tells the two apart. The harness's own window is
 * visible throughout, because a window nothing draws never polishes and every
 * measurement would be of nothing.
 *
 * Driven by tests/test_settings_page_incubation_runtime.py, which also fails
 * on a `Binding loop` line - the keep-alive term used to read `item`, which is
 * what `active` produces.
 *
 *   qs -p SettingsPageIncubationRuntimeTest.qml
 */
ShellRoot {
    id: harness

    property int failures: 0
    property int checksRun: 0

    // The page the far-jump check asks for. Deliberately not a neighbour of
    // the one on screen: a warm-up that quietly built everything would still
    // pass a jump of one.
    readonly property string farPage: "HyprlandConfig"
    readonly property int farPageIndex: 13

    // Measured on this harness: 622ms with the eager loop, 66ms without it.
    // A ceiling between them, nearer the broken side, so a machine slower than
    // this one still separates the two rather than reporting the fix as a
    // regression.
    readonly property int blockCeiling: 300

    function check(label, ok) {
        harness.checksRun++;
        console.log(`[SettingsIncubation] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    // ---- the heartbeat -------------------------------------------------
    property real hbLast: 0
    property real hbMax: 0

    function hbReset() {
        harness.hbMax = 0;
        harness.hbLast = Date.now();
    }

    Timer {
        interval: 1
        repeat: true
        running: true
        onTriggered: {
            const now = Date.now();
            const gap = now - harness.hbLast;
            if (gap > harness.hbMax)
                harness.hbMax = gap;
            harness.hbLast = now;
        }
    }

    // ---- reading the built tree ----------------------------------------
    function typeName(obj) {
        return `${obj}`.split("(")[0].split("_QML")[0].trim();
    }

    function walk(item, out) {
        for (const child of item.children) {
            out.push(child);
            harness.walk(child, out);
        }
        return out;
    }

    function everything() {
        return loader.item ? harness.walk(loader.item, []) : [];
    }

    readonly property var pageTypes: ["QuickConfig", "AppearanceConfig", "CursorConfig",
        "BackgroundConfig", "BarConfig", "SidebarsPanelsConfig", "NotificationsConfig",
        "LockIdleConfig", "CaptureConfig", "GeneralConfig", "PhoneConfig", "ServicesConfig",
        "PluginsPage", "HyprlandConfig", "About"]

    function builtPages() {
        return harness.everything()
            .map(harness.typeName)
            .filter(name => harness.pageTypes.includes(name));
    }

    // The page host's own loaders, found by what they load rather than by an
    // accessor the shell would carry only for this file.
    function pageLoader(pageType) {
        return harness.everything().find(obj =>
            harness.typeName(obj) === "QQuickLoader"
            && `${obj.source ?? ""}`.endsWith(`pages/${pageType}.qml`)) ?? null;
    }

    // How many of the fifteen page loaders have been asked for anything at
    // all. `Loader.Null` is "not active"; anything else is a build that has
    // started. Counting LOADERS rather than built pages is what makes this
    // independent of how long a build takes - with `asynchronous: true` the
    // eager loop's fifteen would be `Loading` rather than finished, and a
    // check counting finished pages would report the same 0 as the fix.
    function loadersAsked() {
        return harness.everything().filter(obj =>
            harness.typeName(obj) === "QQuickLoader"
            && `${obj.source ?? ""}`.includes("/settings/pages/")
            && obj.status !== Loader.Null).length;
    }

    function buildingPlaceholder() {
        return harness.everything().find(obj =>
            harness.typeName(obj) === "PagePlaceholder" && obj.building !== undefined) ?? null;
    }

    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 980
        implicitHeight: 665
        color: "black"

        Loader {
            id: loader
            anchors.fill: parent
            active: false
            sourceComponent: SettingsContent {}
        }
    }

    property int elapsed: 0
    Timer {
        id: waitForReady
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            harness.elapsed += waitForReady.interval;
            if (!Config.ready) {
                if (harness.elapsed >= 20000) {
                    harness.check("Config became ready", false);
                    harness.finish();
                }
                return;
            }
            waitForReady.running = false;
            steps.running = true;
        }
    }

    function finish() {
        console.log(`[SettingsIncubation] checks: ${harness.checksRun} failures: ${harness.failures}`);
        Qt.exit(harness.failures === 0 ? 0 : 1);
    }

    property real buildBlock: 0
    property int warmWaits: 0
    property int pagesOneTurnAfterBuild: -1

    property var stepList: [
        () => {
            harness.hbReset();
            loader.active = true;
            // The turn boundary is the measurement. The loop this refuses
            // queued its fifteen builds from the host's own
            // `Component.onCompleted`, i.e. before this callLater, so it has
            // finished by the time this runs; the warm-up's first tick is a
            // motion tier away and has not.
            Qt.callLater(() => { harness.pagesOneTurnAfterBuild = harness.loadersAsked(); });
        },

        // ---- what building the host cost, and what one turn had built ----
        () => {
            harness.buildBlock = harness.hbMax;
            const oneTurn = harness.pagesOneTurnAfterBuild ?? -1;
            console.log(`[SettingsIncubation] build blocked the GUI thread for ${harness.buildBlock}ms,`
                        + ` page loaders asked one turn after it: ${oneTurn}`);
            harness.check(`one turn after the host is built, only the page on screen has been asked`
                          + ` for - the rest arrive one at a time, got ${oneTurn}`,
                          oneTurn === 1);
            harness.check(`building the host blocked the GUI thread for less than ${harness.blockCeiling}ms,`
                          + ` measured ${harness.buildBlock}ms`,
                          harness.buildBlock < harness.blockCeiling);

            // ---- a page asked for is incubated, not built inside the write --
            const built = harness.builtPages();
            harness.check(`the warm-up has not reached ${harness.farPage} yet, so asking for it`
                          + ` is a real first visit (built so far: ${built.length})`,
                          !built.includes(harness.farPage));
            loader.item.currentPage = harness.farPageIndex;
            // Same turn as the write. A synchronous Loader has already
            // finished by now and hands back a whole page.
            const far = harness.pageLoader(harness.farPage);
            harness.check(`the ${harness.farPage} loader exists to be asked`, far !== null);
            harness.check(`asking for a page does not build it inside the write,`
                          + ` status=${far?.status} item=${far?.item}`,
                          far !== null && far.item === null && far.status === Loader.Loading);
            harness.check("...and nothing is named as the page on screen while it incubates",
                          GlobalStates.currentPageInstance === null);
            const placeholder = harness.buildingPlaceholder();
            harness.check("the placeholder knows a page is building",
                          placeholder !== null && placeholder.building);
            harness.check("...and does not draw it before the settle, so a page that arrives"
                          + " quickly never flashes one",
                          placeholder !== null && !placeholder.shown);
        },

        // ---- ...and it arrives ------------------------------------------
        () => {
            const far = harness.pageLoader(harness.farPage);
            const pages = harness.builtPages();
            harness.check(`the page arrives and is named as the one on screen, got`
                          + ` ${harness.typeName(GlobalStates.currentPageInstance)}`,
                          far?.item !== null && GlobalStates.currentPageInstance === far.item);
            harness.check(`...and the page left behind is kept rather than rebuilt, got`
                          + ` ${JSON.stringify(pages)}`,
                          pages.includes("QuickConfig") && pages.includes(harness.farPage));
        },

        // ---- the warm-up reaches every page ------------------------------
        () => {
            harness.hbReset();
            steps.running = false;
            warmWatch.running = true;
        },

        // ---- a warmed page is there the moment it is asked for -----------
        () => {
            loader.item.currentPage = 4;
            const bar = harness.pageLoader("BarConfig");
            harness.check(`a warmed page is on screen the moment it is asked for,`
                          + ` status=${bar?.status}`,
                          bar !== null && bar.item !== null && bar.status === Loader.Ready);
        },

        () => harness.finish()
    ]

    Timer {
        id: warmWatch
        interval: 250
        repeat: true
        onTriggered: {
            harness.warmWaits++;
            const through = loader.item?.warmedThrough ?? -1;
            const pages = harness.builtPages();
            if (pages.length < harness.pageTypes.length && harness.warmWaits < 120)
                return;
            warmWatch.running = false;
            console.log(`[SettingsIncubation] warm-up reached ${pages.length} pages`
                        + ` (warmedThrough=${through}), worst GUI block ${harness.hbMax}ms`);
            harness.check(`the warm-up reaches every page, got ${pages.length}`,
                          pages.length === harness.pageTypes.length);
            steps.running = true;
        }
    }

    property int stepIndex: 0
    Timer {
        id: steps
        interval: 900
        repeat: true
        onTriggered: {
            if (harness.stepIndex >= harness.stepList.length)
                return;
            harness.stepList[harness.stepIndex++]();
        }
    }
}
