pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../../../common/functions/layout_ops.js" as LayoutOps
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
    signal openAudioOutputDialog()
    signal openAudioInputDialog()
    signal openBluetoothDialog()
    signal openNightLightDialog()
    signal openWifiDialog()
    signal openTailscaleDialog()
    signal openPhoneTab()

    // The stored toggle list is written HERE, on a tile's request, not by the
    // tile: a tile that edits Config cannot be shown anywhere the config is
    // not the real one. The four bodies moved verbatim from the tile.
    function moveToggle(fromIndex, toIndex) {
        const toggleList = Config.options.sidebar.quickToggles.android.toggles;
        // Mutated in place, deliberately: 26b625905 measured that every
        // mutation form notifies and reverted the copy-and-reassign
        // indirection added on the belief that they do not. The dragged
        // toggle travels to the tile it was dropped on and the ones it passed
        // shift back one, instead of the two exchanging places.
        LayoutOps.moveInPlace(toggleList, fromIndex, toIndex);
    }
    function addToggle(type) {
        const toggleList = Config.options.sidebar.quickToggles.android.toggles;
        if (!toggleList.find(t => t.type === type))
            toggleList.push({ type: type, size: 1 });
    }
    function removeToggle(index) {
        const toggleList = Config.options.sidebar.quickToggles.android.toggles;
        if (index >= 0 && index < toggleList.length)
            toggleList.splice(index, 1);
    }
    function resizeToggle(index, size) {
        const toggleList = Config.options.sidebar.quickToggles.android.toggles;
        if (index >= 0 && index < toggleList.length)
            toggleList[index].size = size;
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
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
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
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
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
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
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
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
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
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
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
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
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
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
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
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
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
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
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
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
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
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
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
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
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
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
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
        onAddRequested: type => root.addToggle(type)
        onRemoveRequested: index => root.removeToggle(index)
        onResizeRequested: (index, size) => root.resizeToggle(index, size)
        dropIndicatorRef: root.dropIndicatorRef
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
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
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
        onAddRequested: type => root.addToggle(type)
        onRemoveRequested: index => root.removeToggle(index)
        onResizeRequested: (index, size) => root.resizeToggle(index, size)
        dropIndicatorRef: root.dropIndicatorRef
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
        onAddRequested: type => root.addToggle(type)
        onRemoveRequested: index => root.removeToggle(index)
        onResizeRequested: (index, size) => root.resizeToggle(index, size)
        dropIndicatorRef: root.dropIndicatorRef
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
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
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
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
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
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
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
        isUnused: root.isUnused
        panelOpen: GlobalStates.sidebarRightOpen
        onMoveRequested: (fromIndex, toIndex) => root.moveToggle(fromIndex, toIndex)
        onAddRequested: type => root.addToggle(type)
        onRemoveRequested: index => root.removeToggle(index)
        onResizeRequested: (index, size) => root.resizeToggle(index, size)
    } }
}