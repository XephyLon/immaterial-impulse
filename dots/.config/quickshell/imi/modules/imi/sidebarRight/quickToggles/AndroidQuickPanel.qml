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

    // ---- what a live tile drag asks of the pager ----
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
