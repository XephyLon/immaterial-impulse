import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

import qs.modules.imi.sidebarRight.quickToggles.androidStyle
import "../../../common/functions/quick_toggle_layout.js" as QuickToggleLayout

AbstractQuickPanel {
    id: root
    property bool editMode: false
    Layout.fillWidth: true

    implicitHeight: (editMode ? contentItem.implicitHeight : usedGrid.implicitHeight) + root.padding * 2
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
    readonly property list<var> toggles: Config.ready ? Config.options.sidebar.quickToggles.android.toggles : []
    readonly property list<var> unusedToggles: {
        const types = availableToggleTypes.filter(type => !toggles.some(toggle => (toggle && toggle.type === type)))
        return types.map(type => { return { type: type, size: 1 } })
    }

    property alias dropIndicator: dropIndicator

    // The models are poked from a SIGNATURE rather than bound to the lists,
    // because neither list can be observed by identity. The quick toggles
    // mutate the live `Config` array in place on purpose (26b625905), so that
    // array is the same object before and after an edit, and `unusedToggles` is
    // the opposite problem - a fresh array of fresh objects on every
    // re-evaluation. A string that changes exactly when a sync would do
    // something answers both, and `sync` is idempotent, so observing generously
    // costs a compare.
    readonly property string usedSignature: QuickToggleLayout.signatureOf(root.toggles, root.columns)
    readonly property string unusedSignature: QuickToggleLayout.signatureOf(root.unusedToggles, root.columns)
    onUsedSignatureChanged: root.requestSync()
    onUnusedSignatureChanged: root.requestSync()
    Component.onCompleted: root.requestSync()

    // ...and the sync itself waits for the turn to finish, because a live
    // `list<var>` notifies per ELEMENT written. Measured: one
    // `layout_ops.moveInPlace` on the stored list - the splice-out and
    // splice-in a drop commits - was observed in nine intermediate states, each
    // one a list with a toggle duplicated or missing, and each one a plan that
    // removes and re-inserts rows rather than moving them. Syncing on every
    // notification therefore destroys most of the grid's delegates in the
    // middle of the one gesture they exist to survive; syncing once, after the
    // stack that is mutating the array has unwound, sees the reorder the user
    // performed and emits it as a move.
    property bool syncPending: false
    function requestSync() {
        if (root.syncPending) return;
        root.syncPending = true;
        Qt.callLater(() => {
            root.syncPending = false;
            usedModel.sync(root.toggles, root.columns);
            unusedModel.sync(root.unusedToggles, root.columns);
        });
    }

    StableQuickToggleModel { id: usedModel }
    StableQuickToggleModel { id: unusedModel }

    function gridHeight(model) {
        return model.gridRows * root.baseCellHeight + Math.max(0, model.gridRows - 1) * root.spacing;
    }

    Column {
        id: contentItem
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: Appearance.spacing.space150

        // One flat grid rather than a Column of row containers, because a row
        // is not something a model can move a delegate between: an entry
        // crossing a row boundary leaves one row's model and lands in
        // another's, at an index some other toggle held. A row is a coordinate
        // here, not a container.
        Item {
            id: usedGrid
            width: contentItem.width
            implicitHeight: root.gridHeight(usedModel)

            Repeater {
                model: usedModel
                delegate: AndroidToggleDelegateChooser {
                    editMode: root.editMode
                    gridRef: usedGrid
                    dropIndicatorRef: dropIndicator
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
                    onOpenPhoneConnectDialog: root.openPhoneConnectDialog()
                }
            }

            Rectangle {
                id: dropIndicator
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
                implicitHeight: root.gridHeight(unusedModel)

                Repeater {
                    model: unusedModel
                    delegate: AndroidToggleDelegateChooser {
                        editMode: root.editMode
                        gridRef: unusedGrid
                        isUnused: true
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
