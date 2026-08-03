import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

import qs.modules.imi.sidebarRight.quickToggles.androidStyle

AbstractQuickPanel {
    id: root
    property bool editMode: false
    Layout.fillWidth: true

    implicitHeight: (editMode ? contentItem.implicitHeight : usedRows.implicitHeight) + root.padding * 2
    Behavior on implicitHeight {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    property real spacing: Appearance.spacing.space100
    property real padding: Appearance.spacing.space100
    readonly property real baseCellWidth: {
        const availableWidth = root.width - (root.padding * 2) - (root.spacing * (root.columns))
        return availableWidth / root.columns
    }
    readonly property real baseCellHeight: 56

    readonly property list<string> availableToggleTypes: ["network", "bluetooth", "vpn", "tailscale", "idleInhibitor", "easyEffects", "nightLight", "darkMode", "cloudflareWarp", "gameMode", "screenSnip", "colorPicker", "onScreenKeyboard", "mic", "audio", "notifications", "powerProfile","musicRecognition", "antiFlashbang", "instantReplay"]
    readonly property int columns: Config.options.sidebar.quickToggles.android.columns
    readonly property list<var> toggles: Config.ready ? Config.options.sidebar.quickToggles.android.toggles : []
    readonly property list<var> toggleRows: toggleRowsForList(toggles)
    readonly property list<var> unusedToggles: {
        const types = availableToggleTypes.filter(type => !toggles.some(toggle => (toggle && toggle.type === type)))
        return types.map(type => { return { type: type, size: 1 } })
    }
    readonly property list<var> unusedToggleRows: toggleRowsForList(unusedToggles)

    property alias dropIndicator: dropIndicator

    // Config and unusedToggles hand out freshly allocated entry objects on every
    // re-evaluation. ScriptModel only reaches for objectProp once two entries are
    // already known to differ by strict equality, so brand new objects make it
    // report "rows 0..n changed" instead of an insert/remove/move -- and
    // DelegateChooser never re-picks a delegate for a row that merely changed
    // data, so every toggle after the edit point keeps the previous toggle's
    // icon, name and action. Handing out one canonical object per (type, size)
    // keeps identities stable so the diff, and the delegates, stay honest.
    property var toggleEntryCache: ({})
    function canonicalToggleEntry(entry) {
        if (!entry) return entry;
        const key = entry.type + " " + entry.size;
        const cached = root.toggleEntryCache[key];
        if (cached) return cached;
        const fresh = { type: entry.type, size: entry.size };
        root.toggleEntryCache[key] = fresh;
        return fresh;
    }

    function toggleRowsForList(togglesList) {
        var rows = [];
        var row = [];
        var totalSize = 0;
        for (var i = 0; i < togglesList.length; i++) {
            if (!togglesList[i]) continue;
            if (totalSize + togglesList[i].size > columns) {
                rows.push(row);
                row = [];
                totalSize = 0;
            }
            row.push(root.canonicalToggleEntry(togglesList[i]));
            totalSize += togglesList[i].size;
        }
        if (row.length > 0) rows.push(row);
        return rows;
    }

    Column {
        id: contentItem
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: Appearance.spacing.space150

        Column {
            id: usedRows
            spacing: root.spacing

            Repeater {
                id: usedRowsRepeater
                model: ScriptModel {
                    values: Array(root.toggleRows.length)
                }
                delegate: ButtonGroup {
                    id: toggleRow
                    required property int index
                    property var modelData: root.toggleRows[index]
                    property int startingIndex: {
                        const rows = root.toggleRows;
                        let sum = 0;
                        for (let i = 0; i < index; i++) sum += rows[i].length;
                        return sum;
                    }
                    spacing: root.spacing

                    Repeater {
                        // A plain array, deliberately, not a ScriptModel.
                        //
                        // DelegateChooser picks a component when a delegate is
                        // *created* and never re-picks for one that survives.
                        // ScriptModel exists to keep delegates alive across
                        // model updates, so the two together mean a row entry
                        // that changes identity in place keeps the previous
                        // toggle's component - and therefore its QuickToggleModel,
                        // icon, name and action - while showing the new entry's
                        // data. A plain array model resets the Repeater instead,
                        // so every entry gets a delegate chosen for the type it
                        // actually holds.
                        //
                        // Keeping the identities stable (canonicalToggleEntry
                        // above) is not enough on its own and was the earlier,
                        // incomplete fix: it makes a *reorder within one row*
                        // diff as a move, which is correct, but rows are laid
                        // out by size and nearly every edit reflows them. Once
                        // an entry crosses a row boundary it leaves one row's
                        // model and lands in another's at some index that was
                        // occupied by something else, which is not a move in
                        // either model - so the stale-component case survived
                        // and only pure same-row swaps looked fixed.
                        //
                        // The cost is that a layout edit recreates the row's
                        // delegates. That is fine here: this model changes only
                        // when the layout does, not when a toggle turns on or
                        // off, and layout edits are deliberate user actions in
                        // edit mode.
                        model: toggleRow?.modelData ?? []
                        delegate: AndroidToggleDelegateChooser {
                            startingIndex: toggleRow.startingIndex
                            editMode: root.editMode
                            gridRef: usedRows
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
                        }
                    }
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
            sourceComponent: Column {
                id: unusedRows
                spacing: root.spacing

                Repeater {
                    model: ScriptModel {
                        values: Array(root.unusedToggleRows.length)
                    }
                    delegate: ButtonGroup {
                        id: unusedToggleRow
                        required property int index
                        property var modelData: root.unusedToggleRows[index]
                        spacing: root.spacing

                        Repeater {
                            // A plain array, for the reason spelled out on the
                            // used-rows Repeater above.
                            model: unusedToggleRow?.modelData ?? []
                            delegate: AndroidToggleDelegateChooser {
                                startingIndex: -1
                                editMode: root.editMode
                                isUnused: true
                                baseCellWidth: root.baseCellWidth
                                baseCellHeight: root.baseCellHeight
                                spacing: root.spacing
                            }
                        }
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