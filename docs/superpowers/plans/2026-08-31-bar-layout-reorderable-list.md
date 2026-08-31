# Bar Layout Reorderable List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Settings' Bar layout section becomes three draggable grouped row lists (fork's ConfigListView grammar on imi tokens) with cross-group drag, replacing the LayoutSection chip flows.

**Architecture:** One dumb widget (`ReorderableList`) renders a group's rows in GroupedList's plate vocabulary with explicit animated slots (the quick-toggle grid's technique) and relays its drag through `ReorderDragArea`; a thin coordinator in `BarConfig.qml` mirrors `BarEditController` - buckets to `layout_ops.dropTarget`, commits through `layout_ops` only. The parting arithmetic is one pure function added to `layout_ops.js`. Spec: `docs/superpowers/specs/2026-08-31-bar-layout-reorderable-list-design.md`.

**Tech Stack:** QML (Quickshell), qmltestrunner, python contract tests (`contract_runner`). Paths relative to `dots/.config/quickshell/imi/` unless starting with `docs/`.

**Conventions that bind every task:** commit with `git commit --only -F - -- <paths>` (new files need `git add -N` first); no Claude/agent attribution; comments explain *why*; run only the named tests, never `run_tests.sh` (suite is parked).

**Facts verified at plan time (do not re-derive):** `StyledComboBox` exists (QQC2 `ComboBox` base: `model`, `textRole`, `currentIndex`, inherited `activated`; icon read off object-model entries' `.icon`); `BarWidgets.available` is public `{id, name, icon}` rows and `nameFor(id)` falls back to the raw id; `LayoutSection`'s only consumer is `BarConfig.qml` (the other two grep hits are comments); `ReorderDragArea` (`modules/common/widgets/ReorderDragArea.qml`) exposes `bucketsProvider`/`axis`/`target`/`scenePosition`, signals `dragStarted`/`dropped(target)`/`dragEnded`, and cancel-not-commit; `layout_ops.dropTarget` buckets are `{centres:[point|null], anchor}` scene-space; the settings lists are UNFILTERED (visible == stored), so `nthVisible`/`insertionForVisible` are not needed here - only `moveTargetForInsertion`.

---

### Task 1: the parting arithmetic

**Files:**
- Modify: `modules/common/functions/layout_ops.js` (append)
- Test: `tests/tst_layout_ops.qml` (append one function)

- [ ] **Step 1: Append the failing test**

Append inside the `TestCase` of `tests/tst_layout_ops.qml` (before its closing brace):

```qml
    function test_parted_slot_closes_the_hole_and_opens_the_gap() {
        // No drag, no gap: identity.
        compare(LayoutOps.partedSlot(2, -1, -1), 2);
        // The dragged row's hole closes: rows past it shift up one.
        compare(LayoutOps.partedSlot(3, 1, -1), 2);
        compare(LayoutOps.partedSlot(0, 1, -1), 0);
        // The insertion gap opens: rows at/past it shift down one.
        compare(LayoutOps.partedSlot(2, -1, 2), 3);
        compare(LayoutOps.partedSlot(1, -1, 2), 1);
        // Both, in one list: hole first, then the gap against the PARTED
        // slot - dragging row 0 toward a gap at 2 leaves row 3 at 3
        // (3 -> 2 for the hole, 2 >= 2 so back down one).
        compare(LayoutOps.partedSlot(3, 0, 2), 3);
        compare(LayoutOps.partedSlot(1, 0, 0), 1);
    }
```

- [ ] **Step 2: Run — must fail**

Run: `cd dots/.config/quickshell/imi && QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/mocks -import tests/imports -input tests/tst_layout_ops.qml`
Expected: FAIL (`partedSlot` is not a function).

- [ ] **Step 3: Append to `modules/common/functions/layout_ops.js`**

```js
// Where row `index` DRAWS while a drag is in flight: the dragged row's own
// slot is a hole that closes under it, and the would-be insertion opens a
// gap. `dragIndex` is this list's dragged row (-1 when the drag is another
// list's), `gapIndex` the insertion slot among the REMAINING rows (-1 for
// no gap here). The gap compares against the parted slot, not the stored
// index - the hole has already closed by the time the gap opens.
function partedSlot(index, dragIndex, gapIndex) {
    var slot = index;
    if (dragIndex >= 0 && index > dragIndex) slot -= 1;
    if (gapIndex >= 0 && slot >= gapIndex) slot += 1;
    return slot;
}
```

- [ ] **Step 4: Run — must pass** (same command; all existing cases stay green).

- [ ] **Step 5: Commit**

```bash
cd ~/dev/imi-unify
git commit --only -F - -- \
  dots/.config/quickshell/imi/modules/common/functions/layout_ops.js \
  dots/.config/quickshell/imi/tests/tst_layout_ops.qml <<'MSG'
feat(widgets): partedSlot - where a row draws mid-drag

The reorderable list's live parting as arithmetic: the dragged row's
hole closes, the insertion gap opens, and the gap compares against the
parted slot because the hole has already closed by then.
MSG
```

---

### Task 2: the dumb widget

**Files:**
- Create: `modules/common/widgets/ReorderableList.qml`
- Verify: `tests/lint_dumb_widgets.py` (no edits - the new file must pass the scan as-is)

- [ ] **Step 1: Write `modules/common/widgets/ReorderableList.qml`**

```qml
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import "../functions/layout_ops.js" as LayoutOps

/**
 * One group's entries as a draggable grouped row list (spec 2026-08-31):
 * GroupedList's plate vocabulary - first/last rows carry the big radius,
 * re-rounding as rows move - with a drag handle, catalogue icon, title and
 * a trailing remove button per row, and a dropdown + Add row at the foot.
 *
 * Dumb on purpose (lint_dumb_widgets.py): entries are opaque, `rowFor`
 * resolves what a row shows, `available` fills the dropdown, and every
 * mutation leaves as a signal - the caller owns the store. The drag rides
 * ReorderDragArea, so the caller can span SEVERAL of these with one
 * bucket space (the bar's three layouts): it supplies `bucketsProvider`,
 * reads `bucketFor()` per list, distributes `gapIndex`, and commits drops.
 *
 * Rows are explicitly positioned with animated y (the quick-toggle grid's
 * settled-slot technique): while a drag is in flight the siblings PART
 * live - layout_ops.partedSlot - instead of waiting for an indicator.
 */
Item {
    id: root

    property var model: []
    // (entry) => ({ icon, title }) - the caller's catalogue lookup.
    property var rowFor: (entry) => ({ icon: "widgets", title: `${entry}` })
    // { id, name, icon } rows for the add dropdown; empty disables adding.
    property var available: []
    property string addButtonText: ""
    // () => layout_ops.dropTarget buckets, supplied by the coordinator.
    property var bucketsProvider: null

    property real entryHeight: 48
    property real listSpacing: Appearance.spacing.space25
    readonly property real slotPitch: root.entryHeight + root.listSpacing

    // The drag in flight: this list's own lifted row, and the insertion gap
    // the coordinator says is currently over THIS list (-1 otherwise).
    property int dragIndex: -1
    property int gapIndex: -1

    signal addRequested(var id)
    signal removeRequested(int index)
    signal rowDragStarted(int index)
    signal rowDragMoved(var target)
    signal rowDropped(int index, var target)
    signal rowDragEnded()

    readonly property int count: root.model?.length ?? 0
    // Visual rows while parted: the hole leaves, the gap arrives.
    readonly property int visualCount: root.count
        + (root.gapIndex >= 0 ? 1 : 0) - (root.dragIndex >= 0 ? 1 : 0)

    implicitHeight: rowsArea.height + Appearance.spacing.space100 + addRow.implicitHeight
    Layout.fillWidth: true

    // This list's half of the coordinator's bucket: scene centres with the
    // dragged row as a hole, and the rows area's centre as the anchor that
    // keeps an EMPTY list a valid drop target.
    function bucketFor(holeIndex) {
        const centres = [];
        for (let i = 0; i < root.count; i++) {
            const item = rowRepeater.itemAt(i);
            const hole = !item || i === holeIndex;
            centres.push(hole ? null : item.mapToItem(null, item.width / 2, item.height / 2));
        }
        return {
            centres: centres,
            anchor: rowsArea.mapToItem(null, rowsArea.width / 2, rowsArea.height / 2)
        };
    }

    Item {
        id: rowsArea
        width: root.width
        // An empty list keeps one row of height: it is a drop target, and a
        // zero-height target is one nothing can hit.
        height: Math.max(root.visualCount, 1) * root.slotPitch - root.listSpacing

        Behavior on height {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Repeater {
            id: rowRepeater
            model: root.model

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property var info: root.rowFor(row.modelData)
                readonly property bool lifted: root.dragIndex === row.index
                readonly property int slot: LayoutOps.partedSlot(
                    row.index, root.dragIndex, root.gapIndex)
                // First/last DRAWN slot carry the group's rounding - the
                // GroupedList rule, recomputed live as rows part.
                readonly property bool isFirst: !row.lifted && row.slot === 0
                readonly property bool isLast: !row.lifted
                    && row.slot === root.visualCount - 1

                width: rowsArea.width
                height: root.entryHeight
                y: row.lifted ? row.y : row.slot * root.slotPitch
                z: row.lifted ? 10 : 0
                Behavior on y {
                    enabled: !row.lifted
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                // The lifted row rides the pointer (list-local); siblings
                // part under it. Imperative, not a binding: the position is
                // a map of the pointer, which no binding dependency carries.
                Connections {
                    target: reorder
                    enabled: row.lifted
                    function onScenePositionChanged() {
                        const local = rowsArea.mapFromItem(null,
                            reorder.scenePosition.x, reorder.scenePosition.y);
                        row.y = local.y - root.entryHeight / 2;
                    }
                }

                color: row.lifted ? Appearance.colors.colLayer2Active
                                  : Appearance.colors.colLayer1
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                scale: row.lifted ? 1.02 : 1
                opacity: row.lifted ? 0.85 : 1
                Behavior on scale {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                topLeftRadius: row.isFirst ? Appearance.rounding.normal : Appearance.rounding.unsharpenmore
                topRightRadius: row.isFirst ? Appearance.rounding.normal : Appearance.rounding.unsharpenmore
                bottomLeftRadius: row.isLast ? Appearance.rounding.normal : Appearance.rounding.unsharpenmore
                bottomRightRadius: row.isLast ? Appearance.rounding.normal : Appearance.rounding.unsharpenmore
                Behavior on topLeftRadius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                Behavior on topRightRadius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                Behavior on bottomLeftRadius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                Behavior on bottomRightRadius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: Appearance.spacing.space150
                        rightMargin: Appearance.spacing.space100
                    }
                    spacing: Appearance.spacing.space150

                    MaterialSymbol {
                        id: handle
                        text: "drag_indicator"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOutline

                        // The gesture lives on the handle. A hold lifts the
                        // row before any movement (the affordance); the
                        // ReorderDragArea's own threshold starts the drag
                        // geometry either way, and its cancel path commits
                        // nothing - drop outside every bucket included.
                        MouseArea {
                            id: holdArea
                            anchors.fill: parent
                            anchors.margins: -Appearance.spacing.space100
                            hoverEnabled: true
                            cursorShape: row.lifted ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            pressAndHoldInterval: 200
                            onPressAndHold: if (root.dragIndex === -1) root.beginRow(row.index)
                        }
                        ReorderDragArea {
                            id: reorder
                            anchors.fill: holdArea
                            axis: "y"
                            bucketsProvider: root.bucketsProvider
                            onDragStarted: root.beginRow(row.index)
                            onTargetChanged: if (reorder.dragging) root.rowDragMoved(reorder.target)
                            onScenePositionChanged: if (reorder.dragging) root.rowDragMoved(reorder.target)
                            onDropped: target => root.rowDropped(row.index, target)
                            onDragEnded: {
                                root.dragIndex = -1;
                                root.rowDragEnded();
                            }
                        }
                    }

                    MaterialSymbol {
                        text: row.info?.icon ?? "widgets"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colPrimary
                        fill: 1
                    }

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.normal
                        text: row.info?.title ?? `${row.modelData}`
                    }

                    RippleButton {
                        implicitWidth: 32
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        onClicked: root.removeRequested(row.index)
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "close"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledToolTip { text: Translation.tr("Remove") }
                    }
                }
            }
        }
    }

    function beginRow(index) {
        if (root.dragIndex === index) return;
        root.dragIndex = index;
        root.rowDragStarted(index);
    }

    RowLayout {
        id: addRow
        anchors {
            top: rowsArea.bottom
            topMargin: Appearance.spacing.space100
            left: parent.left
            right: parent.right
        }
        spacing: Appearance.spacing.space50

        StyledComboBox {
            id: picker
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            model: root.available
            textRole: "name"
            enabled: root.available.length > 0
        }

        RippleButton {
            implicitHeight: picker.implicitHeight
            buttonRadius: Appearance.rounding.full
            enabled: root.available.length > 0
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            contentItem: StyledText {
                anchors.centerIn: parent
                leftPadding: Appearance.spacing.space200
                rightPadding: Appearance.spacing.space200
                horizontalAlignment: Text.AlignHCenter
                color: Appearance.colors.colOnSecondaryContainer
                font.pixelSize: Appearance.font.pixelSize.small
                text: root.addButtonText
            }
            onClicked: {
                const chosen = root.available[picker.currentIndex];
                if (chosen) root.addRequested(chosen.id);
            }
        }
    }
}
```

- [ ] **Step 2: Lint + dumb-widget scan**

```
/usr/lib/qt6/bin/qmllint -I . -I /usr/lib/qt6/qml modules/common/widgets/ReorderableList.qml 2>&1 | grep -viE "import|was not found|unqualified|unresolved-type"
python3 tests/lint_dumb_widgets.py    -> OK (the new file passes the scan untouched)
```

(If `RippleButton.contentItem`/`colRipple` spellings clash at lint or first render, read `modules/common/widgets/RippleButton.qml` and `DialogButton.qml` and match theirs - DialogButton is the reference for a labelled RippleButton.)

- [ ] **Step 3: Commit**

```bash
git add -N dots/.config/quickshell/imi/modules/common/widgets/ReorderableList.qml
git commit --only -F - -- \
  dots/.config/quickshell/imi/modules/common/widgets/ReorderableList.qml <<'MSG'
feat(widgets): ReorderableList - a draggable grouped row list

The fork's ConfigListView grammar on imi's tokens: grouped plates that
re-round live, a drag handle with hold-to-lift, siblings parting via
layout_ops.partedSlot, and a dropdown + Add foot. Dumb on purpose -
entries are opaque, rowFor resolves rows, every mutation leaves as a
signal, and the drag rides ReorderDragArea so a caller can span
several lists with one bucket space.
MSG
```

---

### Task 3: BarConfig rewires, LayoutSection retires

**Files:**
- Modify: `modules/imi/settings/pages/BarConfig.qml` (the "Bar layout" ContentSection, ~lines 171-201)
- Delete: `modules/common/widgets/LayoutSection.qml`
- Test: `tests/test_bar_layout_list_contract.py` (new)

- [ ] **Step 1: Write the failing contract pins**

`tests/test_bar_layout_list_contract.py`:

```python
#!/usr/bin/env python3
"""Source contract: the Bar layout section stays on the shared arithmetic.

The reorderable list is dumb and the section is its coordinator, which is
exactly the split BarEditController already proved for the same three
lists - so the rules are the same ones its contract states: every write
goes through layout_ops, the stored paths are literal, and no second copy
of the reorder arithmetic grows in the page.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
PAGE = ROOT / "modules/imi/settings/pages/BarConfig.qml"
WIDGET = ROOT / "modules/common/widgets/ReorderableList.qml"


def test_the_section_commits_only_through_layout_ops():
    body = PAGE.read_text(encoding="utf-8")
    writes = re.findall(r'Config\.options\.bar\.layouts\.\w+Layout\s*=\s*(.+)$',
                        body, re.MULTILINE)
    assert writes, "the page no longer writes the bar layouts at all"
    for rhs in writes:
        assert "LayoutOps." in rhs or rhs.strip() in ("list;", "list"), (
            f"a layout write bypasses layout_ops: {rhs.strip()}")
    assert "writeLayout" in body and "storedLayout" in body, (
        "the literal-path helpers are gone; a computed store key is not an "
        "allowlist")


def test_the_page_uses_the_reorderable_list_and_the_chips_are_gone():
    body = PAGE.read_text(encoding="utf-8")
    assert "ReorderableList" in body
    assert "LayoutSection" not in body, "the chip flows must be fully retired"
    assert not (ROOT / "modules/common/widgets/LayoutSection.qml").exists(), (
        "LayoutSection lost its only consumer and is deleted with this change")


def test_the_widget_stays_dumb():
    """Belt beside lint_dumb_widgets' braces: the widget the section leans
    on must never grow a store of its own."""
    body = WIDGET.read_text(encoding="utf-8")
    for forbidden in ("Config.options", "GlobalStates.", "execDetached", "Process {"):
        assert forbidden not in body, f"ReorderableList reaches for {forbidden}"


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from contract_runner import run
    sys.exit(run(globals()))
```

- [ ] **Step 2: Run — must fail** (`python3 tests/test_bar_layout_list_contract.py`: ReorderableList not in page, LayoutSection still present).

- [ ] **Step 3: Rewire the section**

In `modules/imi/settings/pages/BarConfig.qml`, replace the whole `ContentSection` titled "Bar layout" (the `GroupedList` holding three `LayoutSection`s) with:

```qml
        ContentSection {
            id: barLayoutSection
            icon: "splitscreen_add"
            shape: MaterialShape.Shape.Cookie6Sided
            title: Translation.tr("Bar layout")

            // The cross-group coordinator, BarEditController's shape at
            // settings scale: buckets to layout_ops.dropTarget, literal
            // stored paths, commits through layout_ops only. The settings
            // lists are unfiltered, so visible == stored and only
            // moveTargetForInsertion is needed.
            property int dragBucket: -1
            property int dragIndex: -1
            readonly property var layoutLists: [leftList, centerList, rightList]

            function storedLayout(bucket) {
                if (bucket === 0) return Config.options.bar.layouts.leftLayout;
                if (bucket === 1) return Config.options.bar.layouts.middleLayout;
                return Config.options.bar.layouts.rightLayout;
            }
            function writeLayout(bucket, list) {
                if (bucket === 0) Config.options.bar.layouts.leftLayout = list;
                else if (bucket === 1) Config.options.bar.layouts.middleLayout = list;
                else Config.options.bar.layouts.rightLayout = list;
            }
            function dropBuckets() {
                const buckets = [];
                for (let b = 0; b < 3; b++)
                    buckets.push(barLayoutSection.layoutLists[b].bucketFor(
                        b === barLayoutSection.dragBucket ? barLayoutSection.dragIndex : -1));
                return buckets;
            }
            function beginDrag(bucket, index) {
                barLayoutSection.dragBucket = bucket;
                barLayoutSection.dragIndex = index;
            }
            // Every pointer event: the gap opens in whichever list the drop
            // would land in, and closes everywhere else - a foreign list
            // parts too, which is what makes the drag legible before the
            // drop.
            function dragMoved(target) {
                for (let b = 0; b < 3; b++)
                    barLayoutSection.layoutLists[b].gapIndex =
                        (target && target.bucket === b) ? target.index : -1;
            }
            function endDrag() {
                barLayoutSection.dragBucket = -1;
                barLayoutSection.dragIndex = -1;
                for (let b = 0; b < 3; b++)
                    barLayoutSection.layoutLists[b].gapIndex = -1;
            }
            // A null target (dropped outside every bucket) commits nothing -
            // the ReorderDragArea cancel rule.
            function commitDrop(bucket, index, target) {
                if (!target) return;
                if (target.bucket === bucket) {
                    const dest = LayoutOps.moveTargetForInsertion(index, target.index);
                    if (dest === index) return;
                    barLayoutSection.writeLayout(bucket,
                        LayoutOps.move(barLayoutSection.storedLayout(bucket), index, dest));
                    return;
                }
                const source = barLayoutSection.storedLayout(bucket);
                const id = source[index];
                barLayoutSection.writeLayout(bucket, LayoutOps.remove(source, index));
                barLayoutSection.writeLayout(target.bucket, LayoutOps.insert(
                    barLayoutSection.storedLayout(target.bucket), id, target.index));
            }
            // A stale id (an uninstalled plugin's widget) keeps a readable
            // row: nameFor already falls back to the raw id, and the icon
            // falls back here.
            function rowInfoFor(id) {
                const found = BarWidgets.available.find(entry => entry.id === id);
                return { icon: found?.icon ?? "widgets", title: BarWidgets.nameFor(id) };
            }

            component BarLayoutList: ReorderableList {
                id: layoutList
                required property int bucket
                Layout.fillWidth: true
                rowFor: id => barLayoutSection.rowInfoFor(id)
                available: page.availableFor()
                addButtonText: Translation.tr("Add widget")
                bucketsProvider: () => barLayoutSection.dropBuckets()
                onRowDragStarted: index => barLayoutSection.beginDrag(layoutList.bucket, index)
                onRowDragMoved: target => barLayoutSection.dragMoved(target)
                onRowDropped: (index, target) => barLayoutSection.commitDrop(layoutList.bucket, index, target)
                onRowDragEnded: barLayoutSection.endDrag()
                onAddRequested: id => barLayoutSection.writeLayout(layoutList.bucket,
                    LayoutOps.insert(barLayoutSection.storedLayout(layoutList.bucket),
                        id, barLayoutSection.storedLayout(layoutList.bucket).length))
                onRemoveRequested: index => barLayoutSection.writeLayout(layoutList.bucket,
                    LayoutOps.remove(barLayoutSection.storedLayout(layoutList.bucket), index))
            }

            ContentSubsection {
                title: Config.options.bar.vertical ? Translation.tr("Top") : Translation.tr("Left")
                BarLayoutList {
                    id: leftList
                    bucket: 0
                    model: Config.options.bar.layouts.leftLayout
                }
            }
            ContentSubsection {
                title: Translation.tr("Center")
                BarLayoutList {
                    id: centerList
                    bucket: 1
                    model: Config.options.bar.layouts.middleLayout
                }
            }
            ContentSubsection {
                title: Config.options.bar.vertical ? Translation.tr("Bottom") : Translation.tr("Right")
                BarLayoutList {
                    id: rightList
                    bucket: 2
                    model: Config.options.bar.layouts.rightLayout
                }
            }
        }
```

Add the import at the top of `BarConfig.qml`, beside the other function imports:

```qml
import "../../../common/functions/layout_ops.js" as LayoutOps
```

Then delete the retired widget:

```bash
git rm dots/.config/quickshell/imi/modules/common/widgets/LayoutSection.qml
```

- [ ] **Step 4: Run everything named**

```
python3 tests/test_bar_layout_list_contract.py     -> OK
python3 tests/lint_dumb_widgets.py                  -> OK
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/mocks -import tests/imports -input tests/tst_layout_ops.qml   -> pass
/usr/lib/qt6/bin/qmllint -I . -I /usr/lib/qt6/qml modules/imi/settings/pages/BarConfig.qml 2>&1 | grep -viE "import|was not found|unqualified|unresolved-type"
```

Also grep for stragglers: `grep -rn "LayoutSection" modules/` → only comments in `layout_ops.js`/`ReorderDragArea.qml` remain (update those two comments to name `ReorderableList`'s section instead if they read as live references — judgement call, keep the diff minimal).

- [ ] **Step 5: Commit**

```bash
git add -N dots/.config/quickshell/imi/tests/test_bar_layout_list_contract.py
git commit --only -F - -- \
  dots/.config/quickshell/imi/modules/imi/settings/pages/BarConfig.qml \
  dots/.config/quickshell/imi/modules/common/widgets/LayoutSection.qml \
  dots/.config/quickshell/imi/tests/test_bar_layout_list_contract.py <<'MSG'
feat(settings): the Bar layout section becomes draggable row lists

Three ReorderableLists in one drag space - the section coordinates
buckets through layout_ops.dropTarget exactly as BarEditController
does for the same three stores, commits through layout_ops only, and
a foreign list parts live under a drag so the drop reads before it
lands. The LayoutSection chip flows lose their only consumer and
retire. Pins hold the layout_ops-only rule and the widget's dumbness.
MSG
```

---

### Task 4: receipts, deploy, eyes

**Files:**
- Modify: `CHANGELOG.md` (repo root, top of `### Added` under `[Unreleased]`), `docs/tests-README.md`

- [ ] **Step 1: CHANGELOG entry**

```markdown
- **The Bar layout section is a draggable list.** The chip flows become
  grouped rows - drag handle, icon, name, remove - that lift on hold and
  part live as you drag, including across Left/Center/Right. Adding a
  widget is a dropdown and an Add button at each group's foot.
```

- [ ] **Step 2: docs/tests-README.md entry** (beside the layout entries)

```markdown
* **Bar layout list contract (`test_bar_layout_list_contract.py`)**: the settings section commits only through `layout_ops` on literal stored paths, the chip-flow `LayoutSection` stayed retired, and `ReorderableList` stays dumb; the live-parting arithmetic itself (`partedSlot` - hole closes, gap opens against the parted slot) is pinned in `tst_layout_ops.qml`.
```

- [ ] **Step 3: Commit, deploy, restart**

```bash
git commit --only -F - -- CHANGELOG.md docs/tests-README.md <<'MSG'
docs: receipts for the bar layout reorderable list
MSG
cd ~/dev/imi-unify && ./deploy-shell
qs kill -c imi; sleep 1; setsid -f qs -c imi
```

(Full restart: a new widget file registers only on restart.)

- [ ] **Step 4: Maintainer visual pass.** Settings > Bar & Dock > Bar layout: rows with handles; hold a handle → lift; drag within a group → siblings part, corners re-round; drag into another group → that group parts, drop commits; drop in dead space → nothing changes; add via dropdown; remove via ×; bar itself follows every commit live. The maintainer drives; no captures without asking.

---

## Self-review notes

- Spec coverage: dumb widget + API + row grammar + motion (T2), parting arithmetic (T1), cross-group coordinator + literal paths + layout_ops-only (T3), add/remove flows (T2/T3), LayoutSection retirement (T3), stale-id fallback (T3 `rowInfoFor` + nameFor), empty-group drop target (T2 `rowsArea` min height + anchor), cancel-not-commit (null target, T3), pins (T1/T3), receipts (T4).
- Type consistency: `bucketFor(holeIndex)`/`gapIndex`/`dragIndex`/`rowDragStarted(index)`/`rowDragMoved(target)`/`rowDropped(index, target)`/`rowDragEnded()` spelled identically in T2's widget and T3's section; `partedSlot(index, dragIndex, gapIndex)` matches T1.
- Verify-before-trust, named inline: RippleButton `contentItem`/`colRipple` spellings (T2 Step 2 note); the two comment-only `LayoutSection` references (T3 Step 4).
- Known accepted rough edge: the lifted row is drawn by its own list and follows the pointer unclamped - crossing into another section it may draw over intervening rows, which is the intended reading (it is being carried).
