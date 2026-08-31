pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../../../common/functions/quick_toggle_pages.js" as QuickTogglePages
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

DelegateChooser {
    id: root
    property bool editMode: false
    required property real baseCellWidth
    required property real baseCellHeight
    required property real spacing
    property var dropIndicatorRef: null 
    property bool isUnused: false
    property var gridRef: null 
    // Which page this chooser's tiles live on, and the panel that owns the
    // pager - handed down to every tile for the drag protocol.
    property var pagerRef: null
    property int pageIndex: 0
    signal openAudioOutputDialog()
    signal openAudioInputDialog()
    signal openBluetoothDialog()
    signal openNightLightDialog()
    signal openWifiDialog()
    signal openTailscaleDialog()
    signal openPhoneTab()

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

    // The role a choice is picked by is the one `StableQuickToggleModel`
    // binds permanently to a row's id, and it is the whole reason a delegate
    // may be reused across a reorder: a chooser reading anything a surviving
    // row can be rewritten with is a delegate left showing the toggle that
    // used to be in that slot.
    role: "type"

    DelegateChoice { roleValue: "antiFlashbang"; AndroidAntiFlashbangToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex
        buttonData: modelData
        editMode: root.editMode
        gridRef: root.gridRef
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        dropIndicatorRef: root.dropIndicatorRef
        pagerRef: root.pagerRef
        pageIndex: root.pageIndex
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
        onMoveAcrossRequested: (fromIndex, toPage, toIndex) => root.moveToggleAcross(fromIndex, toPage, toIndex)
        onAddRequested: type => root.addToggle(type)
        onRemoveRequested: index => root.removeToggle(index)
        onResizeRequested: (index, size) => root.resizeToggle(index, size)
        onOpenMenu: root.openNightLightDialog()
    } }

    DelegateChoice { roleValue: "instantReplay"; AndroidInstantReplayToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex
        buttonData: modelData
        editMode: root.editMode
        gridRef: root.gridRef
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        dropIndicatorRef: root.dropIndicatorRef
        pagerRef: root.pagerRef
        pageIndex: root.pageIndex
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
        onMoveAcrossRequested: (fromIndex, toPage, toIndex) => root.moveToggleAcross(fromIndex, toPage, toIndex)
        onAddRequested: type => root.addToggle(type)
        onRemoveRequested: index => root.removeToggle(index)
        onResizeRequested: (index, size) => root.resizeToggle(index, size)
    } }

    DelegateChoice { roleValue: "audio"; AndroidAudioToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex
        buttonData: modelData
        editMode: root.editMode
        gridRef: root.gridRef
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        dropIndicatorRef: root.dropIndicatorRef
        pagerRef: root.pagerRef
        pageIndex: root.pageIndex
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
        onMoveAcrossRequested: (fromIndex, toPage, toIndex) => root.moveToggleAcross(fromIndex, toPage, toIndex)
        onAddRequested: type => root.addToggle(type)
        onRemoveRequested: index => root.removeToggle(index)
        onResizeRequested: (index, size) => root.resizeToggle(index, size)
        onOpenMenu: root.openAudioOutputDialog()
    } }

    DelegateChoice { roleValue: "bluetooth"; AndroidBluetoothToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex
        buttonData: modelData
        editMode: root.editMode
        gridRef: root.gridRef
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        dropIndicatorRef: root.dropIndicatorRef
        pagerRef: root.pagerRef
        pageIndex: root.pageIndex
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
        onMoveAcrossRequested: (fromIndex, toPage, toIndex) => root.moveToggleAcross(fromIndex, toPage, toIndex)
        onAddRequested: type => root.addToggle(type)
        onRemoveRequested: index => root.removeToggle(index)
        onResizeRequested: (index, size) => root.resizeToggle(index, size)
        onOpenMenu: root.openBluetoothDialog()
    } }

    DelegateChoice { roleValue: "tailscale"; AndroidTailscaleToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex
        buttonData: modelData
        editMode: root.editMode
        gridRef: root.gridRef
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        dropIndicatorRef: root.dropIndicatorRef
        pagerRef: root.pagerRef
        pageIndex: root.pageIndex
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
        onMoveAcrossRequested: (fromIndex, toPage, toIndex) => root.moveToggleAcross(fromIndex, toPage, toIndex)
        onAddRequested: type => root.addToggle(type)
        onRemoveRequested: index => root.removeToggle(index)
        onResizeRequested: (index, size) => root.resizeToggle(index, size)
        onOpenMenu: root.openTailscaleDialog()
    } }

    DelegateChoice { roleValue: "phoneConnect"; AndroidPhoneConnectToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex
        buttonData: modelData
        editMode: root.editMode
        gridRef: root.gridRef
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        dropIndicatorRef: root.dropIndicatorRef
        pagerRef: root.pagerRef
        pageIndex: root.pageIndex
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
        onMoveAcrossRequested: (fromIndex, toPage, toIndex) => root.moveToggleAcross(fromIndex, toPage, toIndex)
        onAddRequested: type => root.addToggle(type)
        onRemoveRequested: index => root.removeToggle(index)
        onResizeRequested: (index, size) => root.resizeToggle(index, size)
        onOpenMenu: root.openPhoneTab()
    } }

    DelegateChoice { roleValue: "vpn"; AndroidVpnToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex
        buttonData: modelData
        editMode: root.editMode
        gridRef: root.gridRef
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        dropIndicatorRef: root.dropIndicatorRef
        pagerRef: root.pagerRef
        pageIndex: root.pageIndex
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
        onMoveAcrossRequested: (fromIndex, toPage, toIndex) => root.moveToggleAcross(fromIndex, toPage, toIndex)
        onAddRequested: type => root.addToggle(type)
        onRemoveRequested: index => root.removeToggle(index)
        onResizeRequested: (index, size) => root.resizeToggle(index, size)
    } }

    DelegateChoice { roleValue: "cloudflareWarp"; AndroidCloudflareWarpToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex
        buttonData: modelData
        editMode: root.editMode
        gridRef: root.gridRef
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        dropIndicatorRef: root.dropIndicatorRef
        pagerRef: root.pagerRef
        pageIndex: root.pageIndex
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
        onMoveAcrossRequested: (fromIndex, toPage, toIndex) => root.moveToggleAcross(fromIndex, toPage, toIndex)
        onAddRequested: type => root.addToggle(type)
        onRemoveRequested: index => root.removeToggle(index)
        onResizeRequested: (index, size) => root.resizeToggle(index, size)
    } }

    DelegateChoice { roleValue: "colorPicker"; AndroidColorPickerToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex
        buttonData: modelData
        editMode: root.editMode
        gridRef: root.gridRef
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        dropIndicatorRef: root.dropIndicatorRef
        pagerRef: root.pagerRef
        pageIndex: root.pageIndex
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
        onMoveAcrossRequested: (fromIndex, toPage, toIndex) => root.moveToggleAcross(fromIndex, toPage, toIndex)
        onAddRequested: type => root.addToggle(type)
        onRemoveRequested: index => root.removeToggle(index)
        onResizeRequested: (index, size) => root.resizeToggle(index, size)
    } }

    DelegateChoice { roleValue: "darkMode"; AndroidDarkModeToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex
        buttonData: modelData
        editMode: root.editMode
        gridRef: root.gridRef
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        dropIndicatorRef: root.dropIndicatorRef
        pagerRef: root.pagerRef
        pageIndex: root.pageIndex
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
        onMoveAcrossRequested: (fromIndex, toPage, toIndex) => root.moveToggleAcross(fromIndex, toPage, toIndex)
        onAddRequested: type => root.addToggle(type)
        onRemoveRequested: index => root.removeToggle(index)
        onResizeRequested: (index, size) => root.resizeToggle(index, size)
    } }

    DelegateChoice { roleValue: "easyEffects"; AndroidEasyEffectsToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex
        buttonData: modelData
        editMode: root.editMode
        gridRef: root.gridRef
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        dropIndicatorRef: root.dropIndicatorRef
        pagerRef: root.pagerRef
        pageIndex: root.pageIndex
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
        onMoveAcrossRequested: (fromIndex, toPage, toIndex) => root.moveToggleAcross(fromIndex, toPage, toIndex)
        onAddRequested: type => root.addToggle(type)
        onRemoveRequested: index => root.removeToggle(index)
        onResizeRequested: (index, size) => root.resizeToggle(index, size)
    } }

    DelegateChoice { roleValue: "gameMode"; AndroidGameModeToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex
        buttonData: modelData
        editMode: root.editMode
        gridRef: root.gridRef
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        dropIndicatorRef: root.dropIndicatorRef
        pagerRef: root.pagerRef
        pageIndex: root.pageIndex
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
        onMoveAcrossRequested: (fromIndex, toPage, toIndex) => root.moveToggleAcross(fromIndex, toPage, toIndex)
        onAddRequested: type => root.addToggle(type)
        onRemoveRequested: index => root.removeToggle(index)
        onResizeRequested: (index, size) => root.resizeToggle(index, size)
    } }

    DelegateChoice { roleValue: "idleInhibitor"; AndroidIdleInhibitorToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex
        buttonData: modelData
        editMode: root.editMode
        gridRef: root.gridRef
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        dropIndicatorRef: root.dropIndicatorRef
        pagerRef: root.pagerRef
        pageIndex: root.pageIndex
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
        onMoveAcrossRequested: (fromIndex, toPage, toIndex) => root.moveToggleAcross(fromIndex, toPage, toIndex)
        onAddRequested: type => root.addToggle(type)
        onRemoveRequested: index => root.removeToggle(index)
        onResizeRequested: (index, size) => root.resizeToggle(index, size)
    } }

    DelegateChoice { roleValue: "mic"; AndroidMicToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex
        buttonData: modelData
        editMode: root.editMode
        gridRef: root.gridRef
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
        onMoveAcrossRequested: (fromIndex, toPage, toIndex) => root.moveToggleAcross(fromIndex, toPage, toIndex)
        onAddRequested: type => root.addToggle(type)
        onRemoveRequested: index => root.removeToggle(index)
        onResizeRequested: (index, size) => root.resizeToggle(index, size)
        dropIndicatorRef: root.dropIndicatorRef
        pagerRef: root.pagerRef
        pageIndex: root.pageIndex
        onOpenMenu: root.openAudioInputDialog()
    } }

    DelegateChoice { roleValue: "musicRecognition"; AndroidMusicRecognition {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex
        buttonData: modelData
        editMode: root.editMode
        gridRef: root.gridRef
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        dropIndicatorRef: root.dropIndicatorRef
        pagerRef: root.pagerRef
        pageIndex: root.pageIndex
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
        onMoveAcrossRequested: (fromIndex, toPage, toIndex) => root.moveToggleAcross(fromIndex, toPage, toIndex)
        onAddRequested: type => root.addToggle(type)
        onRemoveRequested: index => root.removeToggle(index)
        onResizeRequested: (index, size) => root.resizeToggle(index, size)
    } }

    DelegateChoice { roleValue: "network"; AndroidNetworkToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex
        buttonData: modelData
        editMode: root.editMode
        gridRef: root.gridRef
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
        onMoveAcrossRequested: (fromIndex, toPage, toIndex) => root.moveToggleAcross(fromIndex, toPage, toIndex)
        onAddRequested: type => root.addToggle(type)
        onRemoveRequested: index => root.removeToggle(index)
        onResizeRequested: (index, size) => root.resizeToggle(index, size)
        dropIndicatorRef: root.dropIndicatorRef
        pagerRef: root.pagerRef
        pageIndex: root.pageIndex
        onOpenMenu: root.openWifiDialog()
    } }

    DelegateChoice { roleValue: "nightLight"; AndroidNightLightToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex
        buttonData: modelData
        editMode: root.editMode
        gridRef: root.gridRef
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
        onMoveAcrossRequested: (fromIndex, toPage, toIndex) => root.moveToggleAcross(fromIndex, toPage, toIndex)
        onAddRequested: type => root.addToggle(type)
        onRemoveRequested: index => root.removeToggle(index)
        onResizeRequested: (index, size) => root.resizeToggle(index, size)
        dropIndicatorRef: root.dropIndicatorRef
        pagerRef: root.pagerRef
        pageIndex: root.pageIndex
        onOpenMenu: root.openNightLightDialog()
    } }

    DelegateChoice { roleValue: "notifications"; AndroidNotificationToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex
        buttonData: modelData
        editMode: root.editMode
        gridRef: root.gridRef
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        dropIndicatorRef: root.dropIndicatorRef
        pagerRef: root.pagerRef
        pageIndex: root.pageIndex
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
        onMoveAcrossRequested: (fromIndex, toPage, toIndex) => root.moveToggleAcross(fromIndex, toPage, toIndex)
        onAddRequested: type => root.addToggle(type)
        onRemoveRequested: index => root.removeToggle(index)
        onResizeRequested: (index, size) => root.resizeToggle(index, size)
    } }

    DelegateChoice { roleValue: "onScreenKeyboard"; AndroidOnScreenKeyboardToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex
        buttonData: modelData
        editMode: root.editMode
        gridRef: root.gridRef
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        dropIndicatorRef: root.dropIndicatorRef
        pagerRef: root.pagerRef
        pageIndex: root.pageIndex
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
        onMoveAcrossRequested: (fromIndex, toPage, toIndex) => root.moveToggleAcross(fromIndex, toPage, toIndex)
        onAddRequested: type => root.addToggle(type)
        onRemoveRequested: index => root.removeToggle(index)
        onResizeRequested: (index, size) => root.resizeToggle(index, size)
    } }

    DelegateChoice { roleValue: "powerProfile"; AndroidPowerProfileToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex
        buttonData: modelData
        editMode: root.editMode
        gridRef: root.gridRef
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        dropIndicatorRef: root.dropIndicatorRef
        pagerRef: root.pagerRef
        pageIndex: root.pageIndex
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
        onMoveAcrossRequested: (fromIndex, toPage, toIndex) => root.moveToggleAcross(fromIndex, toPage, toIndex)
        onAddRequested: type => root.addToggle(type)
        onRemoveRequested: index => root.removeToggle(index)
        onResizeRequested: (index, size) => root.resizeToggle(index, size)
    } }

    DelegateChoice { roleValue: "screenSnip"; AndroidScreenSnipToggle {
        required property int index
        required property var modelData
        buttonIndex: modelData.sourceIndex
        buttonData: modelData
        editMode: root.editMode
        gridRef: root.gridRef
        expandedSize: modelData.size > 1
        baseCellWidth: root.baseCellWidth
        baseCellHeight: root.baseCellHeight
        cellSpacing: root.spacing
        cellSize: modelData.size
        dropIndicatorRef: root.dropIndicatorRef
        pagerRef: root.pagerRef
        pageIndex: root.pageIndex
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
        onMoveAcrossRequested: (fromIndex, toPage, toIndex) => root.moveToggleAcross(fromIndex, toPage, toIndex)
        onAddRequested: type => root.addToggle(type)
        onRemoveRequested: index => root.removeToggle(index)
        onResizeRequested: (index, size) => root.resizeToggle(index, size)
    } }
}