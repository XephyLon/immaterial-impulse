# Quick-Toggle Pages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The android quick-toggle grid becomes explicit, swipeable pages with a dot indicator, a `+` in edit mode, empty-page pruning, and drag-past-edge cross-page moves.

**Architecture:** A pure-JS pages lib (`quick_toggle_pages.js`) owns the nested list's arithmetic copy-on-write; the panel renders a clipped `Flickable` pager of page grids, one `StableQuickToggleModel` per page (the existing per-list sync machinery unchanged); every write REASSIGNS `Config.options.sidebar.quickToggles.android.pages` — an inner array mutated in place is invisible to the outer `pages` property, so the flat list's mutate-in-place spelling (26b625905) does not carry over. Spec: `docs/superpowers/specs/2026-08-31-quick-toggle-pages-design.md`.

**Tech Stack:** QML (Quickshell), qmltestrunner, python contract tests. Paths relative to `dots/.config/quickshell/imi/` unless starting with `docs/`.

**Conventions that bind every task:** commit with `git commit --only -F - -- <paths>` (new files need `git add -N` first); no Claude/agent attribution; comments explain *why*; run only the named tests, never `run_tests.sh` (suite is parked by the maintainer).

**Verify-before-trust points:** (a) `tests/test_quick_toggles_layout_runtime.py` drives the real panel — read it fully before Task 2; where its probe names `usedGrid` or panel internals, adapt its selectors to the page grid in Task 4. (b) `property alias dropIndicator` on the old panel — grep `\.dropIndicator` outside the panel before deleting it; nothing was found at plan time. (c) Delegate survival across the reassign spelling is asserted by the runtime harness, not assumed.

**One deliberate spec deviation:** free swipe is disabled for the whole of edit mode, not only while a drag is live — a horizontal `Flickable` steals the tile `DragHandler`'s gesture, so in edit mode navigation is dots + drag-past-edge. Dots stay clickable throughout.

---

### Task 1: the pages arithmetic

**Files:**
- Create: `modules/common/functions/quick_toggle_pages.js`
- Test: `tests/tst_quick_toggle_pages.qml`

- [ ] **Step 1: Write the failing test**

`tests/tst_quick_toggle_pages.qml`:

```qml
import QtTest
import "../modules/common/functions/quick_toggle_pages.js" as Pages

// The quick-toggle PAGES, as arithmetic: migration, one-home-per-toggle,
// add/prune, cross-page moves, and the one signature the panel observes.
// Everything is copy-on-write - the store is a nested list<var>, and an
// inner array mutated in place never notifies the outer property.
TestCase {
    name: "QuickTogglePagesTest"

    function entry(type, size) { return { type: type, size: size ?? 1 }; }

    function test_migration_wraps_the_legacy_flat_list_as_one_page() {
        const pages = Pages.normalise([], [entry("network", 2), entry("mic")]);
        compare(pages.length, 1);
        compare(pages[0].map(e => e.type).join(","), "network,mic");
        compare(pages[0][0].size, 2);
    }

    function test_no_pages_and_no_legacy_is_one_empty_page() {
        compare(Pages.normalise([], []).length, 1);
        compare(Pages.normalise([], [])[0].length, 0);
        compare(Pages.normalise(null, undefined).length, 1);
    }

    function test_stored_pages_win_over_the_legacy_list() {
        const pages = Pages.normalise([[entry("audio")]], [entry("network")]);
        compare(pages.length, 1);
        compare(pages[0][0].type, "audio");
    }

    function test_one_home_per_toggle_first_occurrence_wins() {
        const pages = Pages.normalise(
            [[entry("network"), entry("mic")], [entry("mic"), entry("audio")]], []);
        compare(pages[0].map(e => e.type).join(","), "network,mic");
        compare(pages[1].map(e => e.type).join(","), "audio");
    }

    function test_malformed_entries_and_pages_are_dropped() {
        const pages = Pages.normalise(
            [[entry("network"), null, { size: 2 }], "junk", [entry("mic")]], []);
        compare(pages.length, 2);
        compare(pages[0].map(e => e.type).join(","), "network");
        compare(pages[1][0].type, "mic");
    }

    function test_add_and_prune() {
        const added = Pages.withAddedPage([[entry("network")]]);
        compare(added.length, 2);
        compare(added[1].length, 0);
        const pruned = Pages.pruned([[], [entry("network")], []]);
        compare(pruned.length, 1);
        compare(pruned[0][0].type, "network");
        compare(Pages.pruned([[], []]).length, 1, "never fewer than one page");
    }

    function test_cross_page_move_keeps_both_orders() {
        const pages = [[entry("network"), entry("mic"), entry("audio")], [entry("bluetooth")]];
        const moved = Pages.withMove(pages, 0, 1, 1, 0);
        compare(moved[0].map(e => e.type).join(","), "network,audio");
        compare(moved[1].map(e => e.type).join(","), "mic,bluetooth");
        // ...and the source is untouched (copy-on-write).
        compare(pages[0].length, 3);
    }

    function test_same_page_move_is_layout_ops_move() {
        const moved = Pages.withMove(
            [[entry("a1"), entry("b2"), entry("c3")]], 0, 2, 0, 0);
        compare(moved[0].map(e => e.type).join(","), "c3,a1,b2");
    }

    function test_insert_remove_resize() {
        const pages = [[entry("network")], []];
        const inserted = Pages.withInsert(pages, 1, entry("mic"));
        compare(inserted[1][0].type, "mic");
        const rejected = Pages.withInsert(inserted, 0, entry("mic"));
        compare(rejected[0].length, 1, "a second home is refused");
        const resized = Pages.withResize(inserted, 1, 0, 3);
        compare(resized[1][0].size, 3);
        const removed = Pages.withRemove(inserted, 0, 0);
        compare(removed[0].length, 0);
    }

    function test_used_types_and_clamp() {
        const used = Pages.usedTypes([[entry("network")], [entry("mic")]]);
        verify(used.network && used.mic && !used.audio);
        compare(Pages.clampPage([[], []], 5), 1);
        compare(Pages.clampPage([[], []], -1), 0);
    }

    function test_signature_covers_every_page() {
        const a = Pages.signatureOf([[entry("network")], [entry("mic")]], 5);
        const b = Pages.signatureOf([[entry("network")], [entry("mic", 2)]], 5);
        const c = Pages.signatureOf([[entry("network"), entry("mic")]], 5);
        verify(a !== b, "a size change on page 2 changes the signature");
        verify(a !== c, "the page split itself is part of the signature");
    }
}
```

- [ ] **Step 2: Run — must fail**

Run: `cd dots/.config/quickshell/imi && QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/mocks -import tests/imports -input tests/tst_quick_toggle_pages.qml`
Expected: compile FAIL (quick_toggle_pages.js missing).

- [ ] **Step 3: Write `modules/common/functions/quick_toggle_pages.js`**

```js
.pragma library

.import "quick_toggle_layout.js" as Layout
.import "layout_ops.js" as LayoutOps

// The quick-toggle grid's PAGES (spec 2026-08-31): a list of pages, each a
// list of {type, size} entries, stored at
// Config.options.sidebar.quickToggles.android.pages.
//
// Everything here is COPY-ON-WRITE, which is not a style choice: the store
// is a nested list<var>, and mutating an inner array in place never
// notifies the outer `pages` property - the panel's signature would go
// stale and the grid would not follow the edit. The flat list's
// mutate-in-place spelling (26b625905) measured a FLAT list<var>; it does
// not carry over. Every editor builds a new pages value and assigns it.
//
// Delegates still survive edits: ids are stable and StableQuickToggleModel
// diffs, so a reassigned list that reorders one entry still syncs as a
// `move`.

function _isList(value) {
    return !!value && typeof value.length === "number";
}

// One page's entries, cleaned: malformed entries dropped, sizes normalised
// through the layout lib's one normaliser, and any type already seen (on an
// earlier page, or earlier in this one) dropped - one home per toggle,
// first occurrence wins, the same spirit as quick_toggle_layout.idFor.
function _entries(rawList, seen) {
    var out = [];
    if (!_isList(rawList)) return out;
    for (var i = 0; i < rawList.length; i++) {
        var raw = rawList[i];
        if (!raw || typeof raw.type !== "string" || raw.type.length === 0) continue;
        if (seen[raw.type]) continue;
        seen[raw.type] = true;
        out.push({ type: raw.type, size: Layout.sizeOf(raw) });
    }
    return out;
}

// The one reader of the store. The stored `pages` when it holds any list at
// all, else the legacy flat `toggles` wrapped as one page; never fewer than
// one page, so the pager always has a current page to stand on.
function normalise(pagesRaw, legacyToggles) {
    var seen = {};
    var pages = [];
    if (_isList(pagesRaw)) {
        for (var i = 0; i < pagesRaw.length; i++) {
            if (_isList(pagesRaw[i])) pages.push(_entries(pagesRaw[i], seen));
        }
    }
    if (pages.length === 0) {
        var legacy = _entries(legacyToggles, seen);
        return legacy.length > 0 ? [legacy] : [[]];
    }
    return pages;
}

// Plain new arrays and objects, so what lands in Config is JSON-clean and
// no editor below can alias the store it is replacing.
function _copy(pages) {
    return (pages || []).map(function (page) {
        return (page || []).map(function (entry) {
            return { type: entry.type, size: entry.size };
        });
    });
}

function withAddedPage(pages) {
    var next = _copy(pages);
    next.push([]);
    return next;
}

// Edit-mode exit sweeps the blanks; at least one page always remains.
function pruned(pages) {
    var next = _copy(pages).filter(function (page) { return page.length > 0; });
    return next.length > 0 ? next : [[]];
}

function clampPage(pages, current) {
    var last = (pages ? pages.length : 1) - 1;
    return Math.max(0, Math.min(typeof current === "number" ? current : 0, last));
}

function usedTypes(pages) {
    var used = {};
    for (var i = 0; i < (pages ? pages.length : 0); i++)
        for (var j = 0; j < pages[i].length; j++)
            used[pages[i][j].type] = true;
    return used;
}

// A same-page move is layout_ops' move (the drag semantics that module
// exists to keep singular); a cross-page move splices out of one page and
// inserts into the other at an INSERTION index (0..length, clamped).
function withMove(pages, fromPage, fromIndex, toPage, toIndex) {
    var next = _copy(pages);
    if (fromPage < 0 || fromPage >= next.length) return next;
    if (toPage < 0 || toPage >= next.length) return next;
    if (fromPage === toPage) {
        next[fromPage] = LayoutOps.move(next[fromPage], fromIndex, toIndex);
        return next;
    }
    if (fromIndex < 0 || fromIndex >= next[fromPage].length) return next;
    var entry = next[fromPage].splice(fromIndex, 1)[0];
    var at = Math.max(0, Math.min(typeof toIndex === "number" ? toIndex : 0,
        next[toPage].length));
    next[toPage].splice(at, 0, entry);
    return next;
}

// A second home is refused rather than deduped later: the unused shelf is
// derived from usedTypes, so a type already placed is never offered - this
// guard is for the hand-written call.
function withInsert(pages, pageIndex, entry) {
    var next = _copy(pages);
    if (pageIndex < 0 || pageIndex >= next.length) return next;
    if (!entry || typeof entry.type !== "string") return next;
    if (usedTypes(next)[entry.type]) return next;
    next[pageIndex].push({ type: entry.type, size: Layout.sizeOf(entry) });
    return next;
}

function withRemove(pages, pageIndex, index) {
    var next = _copy(pages);
    if (pageIndex < 0 || pageIndex >= next.length) return next;
    next[pageIndex] = LayoutOps.remove(next[pageIndex], index);
    return next;
}

function withResize(pages, pageIndex, index, size) {
    var next = _copy(pages);
    if (pageIndex < 0 || pageIndex >= next.length) return next;
    if (index < 0 || index >= next[pageIndex].length) return next;
    next[pageIndex][index].size = size;
    return next;
}

// One string over every page, "|"-joined per-page layout signatures: it
// changes exactly when some page's sync would do something, or when the
// page split itself changes - the same observe-generously trick the flat
// panel used, extended over the nesting the store cannot notify through.
function signatureOf(pages, columns) {
    return (pages || []).map(function (page) {
        return Layout.signatureOf(page, columns);
    }).join("|");
}
```

- [ ] **Step 4: Run the test — must pass**

Same command as Step 2. Expected: `Totals: 11 passed`.
Also rerun the layout suite it leans on: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/mocks -import tests/imports -input tests/tst_quick_toggle_layout.qml` — unchanged pass.

- [ ] **Step 5: Commit**

```bash
cd ~/dev/imi-unify
git add -N dots/.config/quickshell/imi/modules/common/functions/quick_toggle_pages.js \
  dots/.config/quickshell/imi/tests/tst_quick_toggle_pages.qml
git commit --only -F - -- \
  dots/.config/quickshell/imi/modules/common/functions/quick_toggle_pages.js \
  dots/.config/quickshell/imi/tests/tst_quick_toggle_pages.qml <<'MSG'
feat(sidebar): the quick-toggle pages arithmetic

Copy-on-write ops over the nested pages list (spec 2026-08-31):
legacy-list migration, one home per toggle with first occurrence
winning, add/prune, same-page moves through layout_ops and cross-page
moves at an insertion index, and one signature over every page.
Copy-on-write because an inner array mutated in place never notifies
the outer list<var> - the flat list's in-place spelling (26b625905)
measured a flat store and does not carry over.
MSG
```

---

### Task 2: pages land — config key, panel pager, page-aware writes

One commit: the panel, the chooser and the tile plumbing are one seam, and no intermediate state of it compiles as a working grid.

**Files:**
- Modify: `modules/common/Config.qml` (~line 1521, the `android` JsonObject)
- Modify: `modules/imi/sidebarRight/quickToggles/AndroidQuickPanel.qml` (full rewrite)
- Modify: `modules/imi/sidebarRight/quickToggles/androidStyle/AndroidToggleDelegateChooser.qml` (root properties + write functions + scripted per-choice wiring)
- Modify: `modules/imi/sidebarRight/quickToggles/androidStyle/AndroidQuickToggleButton.qml` (pagerRef/pageIndex properties + signal, drag body untouched until Task 3)
- Modify: `tests/test_quick_toggle_model_contract.py` (the Repeater-shape and sync pins follow the new shape)

- [ ] **Step 0: Read `tests/test_quick_toggles_layout_runtime.py` in full.** Note every selector that names panel internals (`usedGrid`, model ids, config keys) — Task 4 adapts them.

- [ ] **Step 1: Config key**

In `modules/common/Config.qml`, inside `property JsonObject android: JsonObject {`, add ABOVE `property int columns: 5`:

```qml
                        // The paged layout (spec 2026-08-31). Each page is a
                        // list of {type, size}. Empty means "not migrated
                        // yet": the panel then reads the legacy `toggles`
                        // below as one page and writes this key back once.
                        property list<var> pages: []
```

The legacy `toggles` property stays exactly as it is — the migration source, no longer written.

- [ ] **Step 2: Rewrite `AndroidQuickPanel.qml`**

Replace the file's entire contents with:

```qml
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

import qs.modules.imi.sidebarRight.quickToggles.androidStyle
import "../../../common/functions/quick_toggle_layout.js" as QuickToggleLayout
import "../../../common/functions/quick_toggle_pages.js" as QuickTogglePages

AbstractQuickPanel {
    id: root
    property bool editMode: false
    Layout.fillWidth: true

    // The pager's height is bound to the CURRENT page's packed rows, so the
    // column's implicit height is right in both modes and one Behavior
    // animates every cause: a page flip, an edit, edit mode's extra
    // sections.
    implicitHeight: contentItem.implicitHeight + root.padding * 2
    Behavior on implicitHeight {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    property real spacing: Appearance.spacing.space100
    property real padding: Appearance.spacing.space100
    readonly property real baseCellWidth: QuickToggleLayout.cellWidth(
        root.width - root.padding * 2, root.spacing, root.columns)
    readonly property real baseCellHeight: 56

    readonly property list<string> availableToggleTypes: ["network", "bluetooth", "vpn", "tailscale", "phoneConnect", "idleInhibitor", "easyEffects", "nightLight", "darkMode", "cloudflareWarp", "gameMode", "screenSnip", "colorPicker", "onScreenKeyboard", "mic", "audio", "notifications", "powerProfile","musicRecognition", "antiFlashbang", "instantReplay"]
    readonly property int columns: Config.options.sidebar.quickToggles.android.columns

    // The pages, normalised through the one reader: the stored `pages` when
    // it holds any, else the legacy flat `toggles` wrapped as one page.
    readonly property list<var> pages: Config.ready
        ? QuickTogglePages.normalise(
              Config.options.sidebar.quickToggles.android.pages,
              Config.options.sidebar.quickToggles.android.toggles)
        : [[]]
    readonly property int pageCount: root.pages.length
    property int currentPage: 0
    onPageCountChanged: root.currentPage = QuickTogglePages.clampPage(root.pages, root.currentPage)
    onCurrentPageChanged: pager.snapTo(root.currentPage)

    // Migration write-back, once: presets saved after this carry `pages`.
    // The legacy key is left standing (downgrade path), and once `pages`
    // holds anything this is permanently false.
    readonly property bool needsMigration: Config.ready
        && (Config.options.sidebar.quickToggles.android.pages?.length ?? 0) === 0
        && (Config.options.sidebar.quickToggles.android.toggles?.length ?? 0) > 0
    onNeedsMigrationChanged: if (root.needsMigration)
        Config.options.sidebar.quickToggles.android.pages = root.pages

    readonly property list<var> unusedToggles: {
        const used = QuickTogglePages.usedTypes(root.pages)
        const types = availableToggleTypes.filter(type => !used[type])
        return types.map(type => { return { type: type, size: 1 } })
    }

    // The models are poked from a SIGNATURE rather than bound to the lists:
    // `pages` is a fresh array of fresh objects on every re-evaluation, so
    // its identity says nothing, and a string that changes exactly when a
    // sync would do something is free to observe generously. `sync` is
    // idempotent.
    readonly property string pagesSignature: QuickTogglePages.signatureOf(root.pages, root.columns)
    readonly property string unusedSignature: QuickToggleLayout.signatureOf(root.unusedToggles, root.columns)
    onPagesSignatureChanged: root.requestSync()
    onUnusedSignatureChanged: root.requestSync()

    // Deferred a turn, same reason as before the pages: a burst of change
    // notifications inside one gesture must land as one sync.
    property bool syncPending: false
    function requestSync() {
        if (root.syncPending) return;
        root.syncPending = true;
        Qt.callLater(() => {
            root.syncPending = false;
            for (let i = 0; i < pageRepeater.count; i++)
                pageRepeater.itemAt(i)?.syncNow();
            unusedModel.sync(root.unusedToggles, root.columns);
        });
    }

    // The second arm mirrors SidebarRightContent's: a panel born open runs
    // its wave itself, one turn later, after the sync above has built the
    // tiles the wave walks.
    Component.onCompleted: {
        if (root.needsMigration)
            Config.options.sidebar.quickToggles.android.pages = root.pages;
        root.requestSync();
        if (GlobalStates.sidebarRightOpen)
            Qt.callLater(() => {
                if (GlobalStates.sidebarRightOpen) root.enterWave();
            });
    }

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (GlobalStates.sidebarRightOpen) root.enterWave();
        }
    }

    // The open's wave runs on the CURRENT page only - the others are off
    // stage behind the clip and enter drawn when swiped to.
    function enterWave() {
        const page = pageRepeater.itemAt(root.currentPage);
        if (!page) return;
        page.wave.park();
        page.wave.enter();
    }

    // ---- what a live tile drag asks of the pager (used from Task 3) ----
    property bool dragActive: false
    property int edgeDirection: 0
    function currentGrid() { return pageRepeater.itemAt(root.currentPage)?.grid ?? null; }
    function currentIndicator() { return pageRepeater.itemAt(root.currentPage)?.indicator ?? null; }
    function dragHoverAt(sceneX) {
        const localX = pager.mapFromItem(null, sceneX, 0).x;
        const band = 28;
        const direction = localX < band ? -1 : (localX > pager.width - band ? 1 : 0);
        if (direction === root.edgeDirection) return;
        root.edgeDirection = direction;
        if (direction === 0) edgeHold.stop(); else edgeHold.restart();
    }
    function dragEnded() {
        root.edgeDirection = 0;
        edgeHold.stop();
        root.dragActive = false;
    }
    Timer {
        id: edgeHold
        interval: 300
        onTriggered: {
            const next = root.currentPage + root.edgeDirection;
            if (next < 0 || next >= root.pageCount) return;
            root.currentPage = next;
            // Held at the band, the drag keeps walking - one page per
            // interval, stopping at the ends or when the pointer leaves it.
            edgeHold.restart();
        }
    }

    // Exiting edit mode sweeps the blanks the + created and nothing filled.
    onEditModeChanged: if (!root.editMode) {
        const pruned = QuickTogglePages.pruned(root.pages);
        root.currentPage = QuickTogglePages.clampPage(pruned, root.currentPage);
        Config.options.sidebar.quickToggles.android.pages = pruned;
    }

    StableQuickToggleModel { id: unusedModel }

    function gridHeight(rows) {
        // An empty page keeps one row of height: it is a drop target, and a
        // zero-height page under a drag is a target nothing can hit.
        return Math.max(rows, 1) * root.baseCellHeight
            + Math.max(0, Math.max(rows, 1) - 1) * root.spacing;
    }
    readonly property int currentRows: QuickToggleLayout.rowCount(
        QuickToggleLayout.pack(root.pages[root.currentPage] ?? [], root.columns))

    function unusedGridHeight() {
        return unusedModel.gridRows * root.baseCellHeight
            + Math.max(0, unusedModel.gridRows - 1) * root.spacing;
    }

    Column {
        id: contentItem
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: Appearance.spacing.space150

        Item {
            id: pagerArea
            width: contentItem.width
            height: root.gridHeight(root.currentRows)
            clip: true

            Flickable {
                id: pager
                anchors.fill: parent
                contentWidth: root.pageCount * pager.width
                contentHeight: pager.height
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                // Edit mode navigates by dots and drag-past-edge: a
                // horizontal flickable steals the tile DragHandler's
                // gesture, so free swipe and edit cannot share the surface.
                interactive: root.pageCount > 1 && !root.editMode
                onWidthChanged: contentX = root.currentPage * width
                onMovementEnded: {
                    // One page per gesture: a hard fling must not sail past
                    // the neighbour.
                    const raw = Math.round(pager.contentX / pager.width);
                    const step = Math.max(root.currentPage - 1,
                        Math.min(root.currentPage + 1, raw));
                    const page = QuickTogglePages.clampPage(root.pages, step);
                    if (page === root.currentPage) pager.snapTo(page);
                    else root.currentPage = page;
                }

                NumberAnimation {
                    id: snapAnim
                    target: pager
                    property: "contentX"
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                }
                function snapTo(page) {
                    snapAnim.stop();
                    snapAnim.to = page * pager.width;
                    snapAnim.start();
                }

                Row {
                    Repeater {
                        id: pageRepeater
                        // The COUNT, not the pages array: normalise returns
                        // a fresh array every evaluation, and a Repeater
                        // over it would rebuild every page's delegates on
                        // every edit - the exact rebuild the keyed models
                        // exist to avoid. Keyed by index, a page item
                        // survives and its model diffs.
                        model: root.pageCount
                        delegate: Item {
                            id: pageItem
                            required property int index
                            width: pager.width
                            height: pagerArea.height

                            property alias wave: tileWave
                            property alias grid: pageGrid
                            property alias indicator: pageDropIndicator

                            function syncNow() {
                                pageModel.sync(root.pages[pageItem.index] ?? [], root.columns);
                            }
                            Component.onCompleted: syncNow()

                            StableQuickToggleModel { id: pageModel }

                            Item {
                                id: pageGrid
                                width: pageItem.width
                                height: pageItem.height
                                property StaggerWave entranceWave: tileWave

                                // The fork's tile cadence, per page: 80ms
                                // head start, 25ms per tile (see the flat
                                // panel's history for why the head start is
                                // load-bearing).
                                StaggerWave {
                                    id: tileWave
                                    target: pageGrid
                                    leadIn: 80
                                    step: 25
                                }
                                StaggerEntrance {
                                    target: pageGrid
                                    convergent: true
                                }

                                Repeater {
                                    model: pageModel
                                    delegate: AndroidToggleDelegateChooser {
                                        editMode: root.editMode
                                        gridRef: pageGrid
                                        dropIndicatorRef: pageDropIndicator
                                        pagerRef: root
                                        pageIndex: pageItem.index
                                        isUnused: false
                                        baseCellWidth: root.baseCellWidth
                                        baseCellHeight: root.baseCellHeight
                                        spacing: root.spacing
                                        onOpenAudioOutputDialog: root.openAudioOutputDialog()
                                        onOpenAudioInputDialog: root.openAudioInputDialog()
                                        onOpenBluetoothDialog: root.openBluetoothDialog()
                                        onOpenNightLightDialog: root.openNightLightDialog()
                                        onOpenWifiDialog: root.openWifiDialog()
                                        onOpenTailscaleDialog: root.openTailscaleDialog()
                                        onOpenPhoneTab: root.openPhoneTab()
                                    }
                                }

                                Rectangle {
                                    id: pageDropIndicator
                                    visible: false
                                    z: 99
                                    width: 3
                                    radius: Appearance.rounding.unsharpen
                                    color: Appearance.colors.colPrimary

                                    Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                    Behavior on y { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.top: parent.top
                                        anchors.topMargin: -Appearance.spacing.space50
                                        width: 8; height: 8; radius: Appearance.rounding.full
                                        color: Appearance.colors.colPrimary
                                    }
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: -Appearance.spacing.space50
                                        width: 8; height: 8; radius: Appearance.rounding.full
                                        color: Appearance.colors.colPrimary
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // The dot rail: one dot per page, the current one stretched, a `+`
        // while editing. Hidden entirely for the common one-page,
        // not-editing case so nothing changes for a user who never pages.
        Row {
            visible: root.pageCount > 1 || root.editMode
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Appearance.spacing.space100

            Repeater {
                model: root.pageCount
                delegate: Rectangle {
                    id: dot
                    required property int index
                    readonly property bool current: dot.index === root.currentPage
                    anchors.verticalCenter: parent.verticalCenter
                    width: dot.current ? 18 : 6
                    height: 6
                    radius: Appearance.rounding.full
                    color: dot.current ? Appearance.colors.colPrimary
                                       : Appearance.colors.colOutlineVariant
                    Behavior on width {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Appearance.spacing.space50
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.currentPage = dot.index
                    }
                }
            }

            FadeLoader {
                shown: root.editMode
                anchors.verticalCenter: parent.verticalCenter
                sourceComponent: MaterialSymbol {
                    text: "add"
                    iconSize: 16
                    color: addArea.containsMouse ? Appearance.colors.colPrimary
                                                 : Appearance.colors.colOnLayer1
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                    MouseArea {
                        id: addArea
                        anchors.fill: parent
                        anchors.margins: -Appearance.spacing.space50
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const next = root.pageCount;
                            Config.options.sidebar.quickToggles.android.pages =
                                QuickTogglePages.withAddedPage(root.pages);
                            root.currentPage = next;
                        }
                    }
                }
            }
        }

        FadeLoader {
            shown: root.editMode
            anchors {
                left: parent.left
                right: parent.right
                leftMargin: root.baseCellHeight / 2
                rightMargin: root.baseCellHeight / 2
            }
            sourceComponent: Rectangle {
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
            }
        }

        FadeLoader {
            shown: root.editMode
            sourceComponent: Item {
                id: unusedGrid
                width: contentItem.width
                implicitHeight: root.unusedGridHeight()

                Repeater {
                    model: unusedModel
                    delegate: AndroidToggleDelegateChooser {
                        editMode: root.editMode
                        gridRef: unusedGrid
                        isUnused: true
                        // The shelf inserts onto whichever page is showing.
                        pagerRef: root
                        pageIndex: root.currentPage
                        baseCellWidth: root.baseCellWidth
                        baseCellHeight: root.baseCellHeight
                        spacing: root.spacing
                    }
                }
            }
        }

        ConfigSpinBox {
            visible: root.editMode
            width: parent.width
            enabled: Config.options.sidebar.quickToggles.style === "android"
            icon: "add_column_left"
            text: Translation.tr("Columns")
            value: Config.options.sidebar.quickToggles.android.columns
            from: 1
            to: 8
            stepSize: 1
            onValueModified: {
                Config.options.sidebar.quickToggles.android.columns = newValue;
            }
        }
    }
}
```

Notes against the old file: `property alias dropIndicator` is deleted (no external reader — re-verify with `grep -rn "\.dropIndicator" modules/ | grep -v quickToggles`); `gridHeight(model)` became `gridHeight(rows)` + `unusedGridHeight()`; the `toggles`/`usedSignature` properties are gone.

- [ ] **Step 3: Chooser — page-aware writes**

In `AndroidToggleDelegateChooser.qml`, after `property var gridRef: null `, add:

```qml
    // Which page this chooser's tiles live on, and the panel that owns the
    // pager - handed down to every tile for the drag protocol.
    property var pagerRef: null
    property int pageIndex: 0
```

Replace the four write functions (the block from `function moveToggle` through the end of `function resizeToggle`) with:

```qml
    // The stored PAGES are written HERE, on a tile's request, not by the
    // tile. Every edit REASSIGNS the pages key: the store is a nested
    // list<var>, and an inner array mutated in place never notifies the
    // outer property - the in-place spelling 26b625905 measured was a FLAT
    // list and does not carry over. Delegates still survive: ids are stable
    // and the keyed model diffs the reassigned value into moves.
    function currentPages() {
        return QuickTogglePages.normalise(
            Config.options.sidebar.quickToggles.android.pages,
            Config.options.sidebar.quickToggles.android.toggles);
    }
    function writePages(next) {
        Config.options.sidebar.quickToggles.android.pages = next;
    }
    function moveToggle(fromIndex, toIndex) {
        writePages(QuickTogglePages.withMove(currentPages(),
            root.pageIndex, fromIndex, root.pageIndex, toIndex));
    }
    function moveToggleAcross(fromIndex, toPage, toIndex) {
        writePages(QuickTogglePages.withMove(currentPages(),
            root.pageIndex, fromIndex, toPage, toIndex));
    }
    function addToggle(type) {
        writePages(QuickTogglePages.withInsert(currentPages(),
            root.pageIndex, { type: type, size: 1 }));
    }
    function removeToggle(index) {
        writePages(QuickTogglePages.withRemove(currentPages(), root.pageIndex, index));
    }
    function resizeToggle(index, size) {
        writePages(QuickTogglePages.withResize(currentPages(), root.pageIndex, index, size));
    }
```

Add the import at the top, beside the layout_ops import:

```qml
import "../../../../common/functions/quick_toggle_pages.js" as QuickTogglePages
```

(`layout_ops.js`'s import becomes unused in this file once `moveInPlace` goes — delete it.)

Then the scripted per-choice wiring — run from `dots/.config/quickshell/imi`:

```bash
python3 - <<'PYEOF'
from pathlib import Path
p = Path("modules/imi/sidebarRight/quickToggles/androidStyle/AndroidToggleDelegateChooser.qml")
text = p.read_text()
n = text.count("dropIndicatorRef: root.dropIndicatorRef")
text = text.replace(
    "dropIndicatorRef: root.dropIndicatorRef",
    "dropIndicatorRef: root.dropIndicatorRef\n        pagerRef: root.pagerRef\n        pageIndex: root.pageIndex")
m = text.count("onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)")
text = text.replace(
    "onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)",
    "onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)\n        onMoveAcrossRequested: (fromIndex, toPage, toIndex) => root.moveToggleAcross(fromIndex, toPage, toIndex)")
assert n == m and n >= 20, f"choice blocks out of step: {n} indicators vs {m} move handlers"
p.write_text(text)
print(f"wired {n} choices")
PYEOF
```

- [ ] **Step 4: Tile — the pager protocol's properties**

In `AndroidQuickToggleButton.qml`, after `property var gridRef: null`, add:

```qml
    // The pager protocol (spec 2026-08-31): the panel owning the pages, and
    // which page this tile calls home. Task 3 gives the drag its cross-page
    // half; until then these only ride along.
    property var pagerRef: null
    property int pageIndex: 0
```

and after the `signal resizeRequested(int index, int size)` line:

```qml
    signal moveAcrossRequested(int fromIndex, int toPage, int toIndex)
```

- [ ] **Step 5: Contract test follows the shape**

In `tests/test_quick_toggle_model_contract.py`, replace `test_the_grid_is_one_flat_keyed_model_per_section` and `test_the_panel_syncs_once_per_turn_and_not_per_notification` with:

```python
def test_the_grid_is_one_flat_keyed_model_per_page():
    """A per-row model cannot move a delegate between rows; with pages the
    same rule holds per page: each page draws from ONE keyed model declared
    in its delegate, the unused shelf from its own, and no Repeater may draw
    from the raw pages value - normalise returns a fresh array every
    evaluation, so that Repeater would rebuild every delegate on every
    edit."""
    body = PANEL.read_text(encoding="utf-8")
    models = [match.group("model") for match in REPEATER_MODEL.finditer(body)]
    toggle_models = sorted(set(m for m in models if m in ("pageModel", "unusedModel")))
    assert toggle_models == ["pageModel", "unusedModel"], (
        f"the panel's toggle Repeaters draw from {models}, expected pageModel "
        f"and unusedModel")
    for name in ("pageModel", "unusedModel"):
        assert re.search(rf'StableQuickToggleModel\s*\{{\s*id:\s*{name}\b', body), (
            f"{name} is not a StableQuickToggleModel")
    for model in models:
        assert "pages" not in model, (
            f"a Repeater draws from {model}; the raw pages value rebuilds "
            f"every delegate on every edit")


def test_the_panel_syncs_once_per_turn_and_not_per_notification():
    """A burst of change notifications inside one gesture must land as one
    sync - the signature handlers go through requestSync, which coalesces
    the turn."""
    body = PANEL.read_text(encoding="utf-8")
    handlers = re.findall(r'^\s*on(?:Pages|Unused)SignatureChanged:(.*)$', body, re.MULTILINE)
    assert len(handlers) == 2, "the panel no longer observes both signatures"
    for handler in handlers:
        assert "requestSync" in handler, (
            "a signature handler syncs a model directly; it must go through "
            "requestSync, which coalesces the turn")
    assert re.search(r'function requestSync\(\)[^}]*Qt\.callLater', body, re.DOTALL), (
        "requestSync no longer defers the sync to the end of the turn")


def test_every_page_write_reassigns_the_store():
    """An inner array of a nested list<var> mutated in place never notifies
    the outer property, so the one legal write spelling is reassignment of
    the pages key. moveInPlace on the store is the regression shape."""
    chooser = CHOOSER.read_text(encoding="utf-8")
    assert "moveInPlace" not in chooser, (
        "the chooser mutates the stored list in place; nested pages must be "
        "reassigned")
    assert "Config.options.sidebar.quickToggles.android.pages =" in chooser
    panel = PANEL.read_text(encoding="utf-8")
    assert "Config.options.sidebar.quickToggles.android.toggles =" not in panel, (
        "the legacy key is the migration source and is never written")
```

- [ ] **Step 6: Run everything named**

```
python3 tests/test_quick_toggle_model_contract.py                          -> OK
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/mocks -import tests/imports -input tests/tst_quick_toggle_pages.qml   -> pass
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/mocks -import tests/imports -input tests/tst_quick_toggle_layout.qml  -> pass
/usr/lib/qt6/bin/qmllint -I . -I /usr/lib/qt6/qml modules/imi/sidebarRight/quickToggles/AndroidQuickPanel.qml 2>&1 | grep -v import          -> no new warnings
```

- [ ] **Step 7: Commit**

```bash
cd ~/dev/imi-unify
git commit --only -F - -- \
  dots/.config/quickshell/imi/modules/common/Config.qml \
  dots/.config/quickshell/imi/modules/imi/sidebarRight/quickToggles/AndroidQuickPanel.qml \
  dots/.config/quickshell/imi/modules/imi/sidebarRight/quickToggles/androidStyle/AndroidToggleDelegateChooser.qml \
  dots/.config/quickshell/imi/modules/imi/sidebarRight/quickToggles/androidStyle/AndroidQuickToggleButton.qml \
  dots/.config/quickshell/imi/tests/test_quick_toggle_model_contract.py <<'MSG'
feat(sidebar): the quick-toggle grid takes pages

Explicit pages under a clipped pager - one keyed model per page, the
existing sync machinery per list - with a dot rail, a + while editing,
empty pages pruned on edit-mode exit, and the legacy flat list
migrated as page one with a single write-back. Every edit reassigns
the pages key: an inner array of a nested list<var> mutated in place
never notifies the outer property, so 26b625905's in-place spelling
stops at the flat list it measured. The contract pins follow.
MSG
```

---

### Task 3: drag past the page edge

**Files:**
- Modify: `modules/imi/sidebarRight/quickToggles/androidStyle/AndroidQuickToggleButton.qml` (the `DragHandler` inside `editModeInteraction`)

- [ ] **Step 1: Generalise the nearest-tile helpers and add the cross-page drop**

Replace the whole `DragHandler { ... }` block inside `editModeInteraction` with:

```qml
        DragHandler {
            id: dragHandler
            target: null

            // Every tile is a direct child of one flat page grid, so this
            // is a filter rather than a walk - parameterised by GRID now,
            // because a drag that crossed a page edge scores its drop
            // against the page under the pointer, not the one it left.
            function siblingsIn(grid) {
                const siblings = [];
                if (!grid) return siblings;
                for (let i = 0; i < grid.children.length; i++) {
                    const sib = grid.children[i];
                    if (!sib || !sib.visible || !sib.buttonData) continue;
                    siblings.push(sib);
                }
                return siblings;
            }

            // The dragged tile is a hole rather than a candidate on its own
            // page; on another page it is simply absent.
            function findNearestIn(grid, sceneX, sceneY) {
                const siblings = siblingsIn(grid);
                const centres = siblings.map(sib =>
                    sib.buttonData.itemId === root.buttonData.itemId
                        ? null
                        : sib.mapToItem(null, sib.width / 2, sib.height / 2));
                const nearest = LayoutOps.indexAt(centres, Qt.point(sceneX, sceneY), null);
                return nearest === -1 ? null : siblings[nearest];
            }

            function crossingPages() {
                return root.pagerRef && root.pagerRef.currentPage !== root.pageIndex;
            }

            onActiveChanged: {
                editModeInteraction.isDragging = active;
                if (root.pagerRef) root.pagerRef.dragActive = active;

                if (!active) {
                    if (root.dropIndicatorRef) root.dropIndicatorRef.visible = false;
                    const landing = root.pagerRef?.currentIndicator() ?? null;
                    if (landing) landing.visible = false;
                    const sceneX = centroid.scenePosition.x;
                    const sceneY = centroid.scenePosition.y;
                    if (crossingPages()) {
                        // The drop commits an insertion index into the page
                        // under the pointer; an empty page takes index 0.
                        const grid = root.pagerRef.currentGrid();
                        const nearest = grid ? findNearestIn(grid, sceneX, sceneY) : null;
                        let insertAt = 0;
                        if (nearest) {
                            const centre = nearest.mapToItem(null, nearest.width / 2, 0).x;
                            insertAt = nearest.buttonIndex + (sceneX > centre ? 1 : 0);
                        }
                        root.moveAcrossRequested(root.buttonIndex,
                            root.pagerRef.currentPage, insertAt);
                    } else {
                        const nearest = findNearestIn(root.gridRef, sceneX, sceneY);
                        if (nearest)
                            root.moveRequested(root.buttonIndex, nearest.buttonIndex);
                    }
                    if (root.pagerRef) root.pagerRef.dragEnded();
                }
            }

            onCentroidChanged: {
                if (!active) return;
                const sceneX = centroid.scenePosition.x;
                const sceneY = centroid.scenePosition.y;
                if (root.pagerRef) root.pagerRef.dragHoverAt(sceneX);

                const crossing = crossingPages();
                const grid = crossing ? root.pagerRef.currentGrid() : root.gridRef;
                const indicator = crossing ? root.pagerRef.currentIndicator()
                                           : root.dropIndicatorRef;
                if (root.dropIndicatorRef && indicator !== root.dropIndicatorRef)
                    root.dropIndicatorRef.visible = false;
                if (!grid || !indicator) return;

                const nearest = findNearestIn(grid, sceneX, sceneY);
                if (nearest) {
                    const centre = nearest.mapToItem(null, nearest.width / 2, 0).x;
                    const goesAfter = sceneX > centre;
                    const nearestLocal = nearest.mapToItem(grid, 0, 0);
                    indicator.x = goesAfter
                        ? nearestLocal.x + nearest.width + 1
                        : nearestLocal.x - 5;
                    indicator.y = nearestLocal.y;
                    indicator.height = nearest.height;
                    indicator.visible = true;
                } else if (crossing) {
                    // An empty page: the indicator stands at its origin so
                    // the drop has a visible home.
                    indicator.x = 0;
                    indicator.y = 0;
                    indicator.height = root.baseCellHeight;
                    indicator.visible = true;
                } else {
                    indicator.visible = false;
                }
            }
        }
```

(Same-page before/after used to compare the NEAREST tile's corner against the dragged tile's — with the drop score now taken against pointer-vs-centre for the cross-page case, both cases use pointer-vs-centre; the committed move still goes through the same `moveRequested`/`layout_ops` path, so the reorder semantics are unchanged.)

- [ ] **Step 2: Compile + named tests**

```
/usr/lib/qt6/bin/qmllint -I . -I /usr/lib/qt6/qml modules/imi/sidebarRight/quickToggles/androidStyle/AndroidQuickToggleButton.qml 2>&1 | grep -v import
python3 tests/test_quick_toggle_model_contract.py   -> OK
```

- [ ] **Step 3: Commit**

```bash
git commit --only -F - -- \
  dots/.config/quickshell/imi/modules/imi/sidebarRight/quickToggles/androidStyle/AndroidQuickToggleButton.qml <<'MSG'
feat(sidebar): a dragged tile crosses the page edge

Holding a drag in the pager's edge band walks one page per 300ms; the
drop scores against the page under the pointer - nearest tile's centre
decides before/after, an empty page takes the origin - and commits as
a cross-page move at an insertion index. The tile's own page keeps the
old reorder path untouched.
MSG
```

---

### Task 4: the runtime harness follows

**Files:**
- Modify: `tests/test_quick_toggles_layout_runtime.py` (only where Step 0 of Task 2 found selectors naming the old panel shape)

- [ ] **Step 1: Adapt selectors.** Wherever the harness addresses `usedGrid`, the panel's `toggles` config key, or the flat model: point it at page one's grid/model and let the migration wrap its seeded `toggles` config. Seed configs stay on the legacy key on purpose — the harness then also exercises the migration.

- [ ] **Step 2: Run it**

Run: `python3 tests/test_quick_toggles_layout_runtime.py`
Expected: OK (it needs a Wayland session; if it skips, note that in the task report and rely on the maintainer's visual pass).

- [ ] **Step 3: Commit** (skip if no changes were needed)

```bash
git commit --only -F - -- dots/.config/quickshell/imi/tests/test_quick_toggles_layout_runtime.py <<'MSG'
test(sidebar): the runtime harness drives page one

The panel's grid lives in a pager now; the harness addresses page
one's grid and keeps seeding the legacy toggles key, which also
exercises the migration wrap.
MSG
```

---

### Task 5: receipts, deploy, eyes

**Files:**
- Modify: `CHANGELOG.md` (repo root, under `### Added`), `docs/tests-README.md`

- [ ] **Step 1: CHANGELOG entry (top of `### Added`)**

```markdown
- **The quick toggles take pages.** The android grid becomes swipeable
  pages with a dot rail - compose each page deliberately in edit mode,
  add one with the + beside the dots, and empty pages sweep themselves
  away when editing ends. A dragged tile held against the pager's edge
  walks onto the neighbouring page. Existing layouts carry over as
  page one.
```

- [ ] **Step 2: docs/tests-README.md entry** (beside the other quick-toggle entries)

```markdown
* **Quick-toggle pages tests (`tst_quick_toggle_pages.qml`)**: the pages arithmetic - legacy-list migration wraps as page one, one home per toggle with first occurrence winning, add/prune, cross-page moves at an insertion index, and a signature that changes exactly when some page's sync would do something. `test_quick_toggle_model_contract.py` grew the paged pins: one keyed model per page, no Repeater over the raw pages value, and every write reassigning the pages key (an inner array of a nested list<var> mutated in place never notifies).
```

- [ ] **Step 3: Commit, deploy, restart**

```bash
git commit --only -F - -- CHANGELOG.md docs/tests-README.md <<'MSG'
docs: receipts for quick-toggle pages
MSG
cd ~/dev/imi-unify && ./deploy-shell
qs kill -c imi; sleep 1; setsid -f qs -c imi
```

(Full restart, not hot reload: the panel gained a new JS module import.)

- [ ] **Step 4: Maintainer visual pass.** Open the right sidebar: one page, no dots (unchanged look). Enter edit mode: dots + `+` appear; add a page, drop tiles on it, drag one against the edge, exit edit mode and confirm an emptied page vanishes. The maintainer drives this; no captures without asking.

---

## Self-review notes

- Spec coverage: config+migration (T2 Step 1-2), one-home + lib (T1), pager/dots/height/wave (T2), `+`/prune (T2 panel), drag-past-edge (T3), error handling (normalise, T1), tests (T1/T2/T4), receipts (T5).
- Deviation logged up top: no free swipe during edit mode (Flickable vs DragHandler gesture theft), navigation there is dots + edge-drag.
- Type consistency: `withMove(pages, fromPage, fromIndex, toPage, toIndex)` spelled identically in lib, chooser, tile; `pagerRef`/`pageIndex` identical across chooser/tile/panel; `currentGrid()`/`currentIndicator()`/`dragHoverAt()`/`dragEnded()` defined in T2's panel before T3 uses them.
- The reassign-vs-mutate claim is arithmetic-level certain for the copy (fresh arrays each read) and pinned by `test_every_page_write_reassigns_the_store`; delegate survival under it is what Task 4's runtime harness exists to catch.
