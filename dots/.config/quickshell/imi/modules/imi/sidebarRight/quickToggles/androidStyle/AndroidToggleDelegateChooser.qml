pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
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
    signal openPhoneConnectDialog()

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
        onOpenMenu: root.openPhoneConnectDialog()
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
    } }
}