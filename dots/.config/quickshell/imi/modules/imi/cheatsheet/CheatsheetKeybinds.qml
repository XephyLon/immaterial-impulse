pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import "../../common/functions/cheatsheetLayout.js" as CheatsheetLayout

Item {
    id: root
    readonly property var keybinds: HyprlandKeybinds.keybinds
    // Raised with the annotated binding (identity, chord, editability) when a
    // row's edit affordance is clicked; Cheatsheet.qml opens the shared
    // KeybindEditor on it.
    signal editRequested(var bindingData)
    property real spacing: Appearance.spacing.space250
    property real titleSpacing: Appearance.spacing.space100
    property real padding: Appearance.spacing.space50

    // Every node that actually holds keybinds, flattened out of the tree. The
    // renderer used to walk `children` only, so a group holding binds at its
    // own level drew nothing - 48 of them on this machine.
    readonly property var sections: CheatsheetLayout.sections(root.keybinds)
    // Rough row budget: how many keybind rows fit in the space the cheatsheet
    // may occupy before it starts growing past the screen. Approximate on
    // purpose - it only decides how many columns to ask for, and being one out
    // costs a slightly taller card, not a broken layout.
    // Set by the cheatsheet to the height it may use before growing past the
    // screen; 0 means "unknown", which falls back to a sane budget.
    property real maxContentHeight: 0
    // The width the card may use before it runs off the screen. Columns trade
    // height for width, so the row budget alone can ask for more columns than
    // there is room for - on a small display that pushed the card past both
    // screen edges and simply cut the outer columns off.
    property real maxContentWidth: 0
    // Deliberately budgets less height than there is. Filling the screen
    // vertically is what the single column already did; the point of columns is
    // to trade height for width on a display that has width to spare. Two
    // thirds keeps the card comfortably clear of the screen edges and, on this
    // 5120x1440 desktop, turns two tall columns into three shorter ones.
    readonly property real rowHeight: 30
    readonly property int availableRows: Math.max(
        8, Math.floor((root.maxContentHeight > 0 ? root.maxContentHeight : 900) * 0.66 / root.rowHeight))
    // Ceiling on the column count, lowered until the laid-out row fits the
    // width budget. Measured rather than predicted: a column is as wide as its
    // widest section, which is not known until the text has been shaped.
    readonly property int maxColumns: 4
    property int columnCap: root.maxColumns
    readonly property var columns: CheatsheetLayout.balance(
        root.sections, CheatsheetLayout.columnCount(root.sections, root.availableRows, root.columnCap))

    function fitToWidth() {
        if (root.maxContentWidth <= 0 || root.columnCap <= 1)
            return;
        if (root.implicitWidth > root.maxContentWidth)
            root.columnCap -= 1;
    }

    // Only ever shrinks, so this settles: each drop narrows the row, and the
    // guard stops at a single column. Anything that changes what is being laid
    // out starts the search again from the top.
    onImplicitWidthChanged: Qt.callLater(root.fitToWidth)
    onMaxContentWidthChanged: {
        root.columnCap = root.maxColumns;
        Qt.callLater(root.fitToWidth);
    }
    onSectionsChanged: {
        root.columnCap = root.maxColumns;
        Qt.callLater(root.fitToWidth);
    }
    implicitWidth: row.implicitWidth + padding * 2
    implicitHeight: row.implicitHeight + padding * 2
    // Excellent symbol explaination and source :
    // http://xahlee.info/comp/unicode_computing_symbols.html
    // https://www.nerdfonts.com/cheat-sheet
    property var macSymbolMap: ({
        "Ctrl": "󰘴",
        "Alt": "󰘵",
        "Shift": "󰘶",
        "Space": "󱁐",
        "Tab": "↹",
        "Equal": "󰇼",
        "Minus": "",
        "Print": "",
        "BackSpace": "󰭜",
        "Delete": "⌦",
        "Return": "󰌑",
        "Period": ".",
        "Escape": "⎋"
      })
    property var functionSymbolMap: ({
        "F1":  "󱊫",
        "F2":  "󱊬",
        "F3":  "󱊭",
        "F4":  "󱊮",
        "F5":  "󱊯",
        "F6":  "󱊰",
        "F7":  "󱊱",
        "F8":  "󱊲",
        "F9":  "󱊳",
        "F10": "󱊴",
        "F11": "󱊵",
        "F12": "󱊶",
    })

    property var mouseSymbolMap: ({
        "mouse_up": "󱕐",
        "mouse_down": "󱕑",
        "mouse:272": "L󰍽",
        "mouse:273": "R󰍽",
        "Scroll ↑/↓": "󱕒",
        "Page_↑/↓": "⇞/⇟",
    })

    property var keyBlacklist: ["Super_L"]
    property var keySubstitutions: Object.assign({
        "Super": "",
        "mouse_up": "Scroll ↓",    // ikr, weird
        "mouse_down": "Scroll ↑",  // trust me bro
        "mouse:272": "LMB",
        "mouse:273": "RMB",
        "mouse:275": "MouseBack",
        "Slash": "/",
        "Hash": "#",
        "Return": "Enter",
        // "Shift": "",
      },
      !!Config.options.cheatsheet.superKey ? {
          "Super": Config.options.cheatsheet.superKey,
      }: {},
      Config.options.cheatsheet.useMacSymbol ? macSymbolMap : {},
      Config.options.cheatsheet.useFnSymbol ? functionSymbolMap : {},
      Config.options.cheatsheet.useMouseSymbol ? mouseSymbolMap : {},
    )

    Row { // Keybind columns
        id: row
        spacing: root.spacing
        
        Repeater {
            model: root.columns

            delegate: Column { // One balanced column of sections
                spacing: root.spacing
                required property var modelData
                anchors.top: row.top

                Repeater {
                    model: modelData

                    delegate: Item { // Section with real keybinds
                        id: keybindSection
                        required property var modelData
                        implicitWidth: sectionColumn.implicitWidth
                        implicitHeight: sectionColumn.implicitHeight

                        Column {
                            id: sectionColumn
                            anchors.centerIn: parent
                            spacing: root.titleSpacing
                            
                            StyledText {
                                id: sectionTitle
                                visible: text.length > 0
                                font {
                                    family: Appearance.font.family.title
                                    pixelSize: Appearance.font.pixelSize.title
                                    variableAxes: Appearance.font.variableAxes.title
                                }
                                color: Appearance.colors.colOnLayer0
                                text: keybindSection.modelData.name
                            }

                            GridLayout {
                                id: keybindGrid
                                columns: 2
                                columnSpacing: Appearance.spacing.space50
                                rowSpacing: Appearance.spacing.space50

                                Repeater {
                                    model: {
                                        var result = [];
                                        for (var i = 0; i < keybindSection.modelData.keybinds.length; i++) {
                                            const binding = keybindSection.modelData.keybinds[i];
                                            // Substitutions below are display-only; mutate a copy so
                                            // the annotated tree entry keeps the real chord for the
                                            // editor (and for the next model rebuild).
                                            const keybind = Object.assign({}, binding);
                                            keybind.mods = (binding.mods ?? []).slice();

                                            if (!Config.options.cheatsheet.splitButtons) {
                                                for (var j = 0; j < keybind.mods.length; j++) {
                                                    keybind.mods[j] = keySubstitutions[keybind.mods[j]] || keybind.mods[j];
                                                }
                                                keybind.mods = [keybind.mods.join(' ') ]
                                                keybind.mods[0] += !keyBlacklist.includes(keybind.key) && keybind.mods[0].length ? ' ' : ''
                                                keybind.mods[0] += !keyBlacklist.includes(keybind.key) ? (keySubstitutions[keybind.key] || keybind.key) : ''
                                            }

                                            result.push({
                                                "type": "keys",
                                                "mods": keybind.mods,
                                                "key": keybind.key,
                                                "binding": binding,
                                            });
                                            result.push({
                                                "type": "comment",
                                                "comment": keybind.comment,
                                            });
                                        }
                                        return result;
                                    }
                                    delegate: Item {
                                        id: keybindCell
                                        required property var modelData
                                        implicitWidth: keybindLoader.implicitWidth
                                        implicitHeight: keybindLoader.implicitHeight

                                        // Only chords open the editor. Comment cells and
                                        // documentation rows are text, and highlighting
                                        // them would promise a click that does nothing.
                                        readonly property bool editable: keybindCell.modelData.type === "keys"
                                            && keybindCell.modelData.binding !== undefined
                                            && !(keybindCell.modelData.binding?.flags?.documentation ?? false)

                                        // The keycaps are drawings of keys, not controls, so
                                        // the row needs its own hover to show where the click
                                        // target is.
                                        //
                                        // It fills the grid CELL rather than the keycap Row:
                                        // a Row positions its children, so a child anchored to
                                        // fill it corrupts the row's layout, and padding the
                                        // fill outwards with a negative margin overflows into
                                        // the neighbouring cell instead of being clipped -
                                        // which drew the hovered row on top of the one above.
                                        Rectangle {
                                            anchors.fill: parent
                                            z: -1
                                            radius: Appearance.rounding.small
                                            visible: keybindCellHover.hovered && keybindCell.editable
                                            color: Appearance.colors.colLayer1Hover
                                        }

                                        HoverHandler {
                                            id: keybindCellHover
                                        }

                                        Loader {
                                            id: keybindLoader
                                            sourceComponent: (modelData.type === "keys") ? keysComponent : commentComponent
                                        }

                                        Component {
                                            id: keysComponent
                                            Row {
                                                id: keysRow
                                                spacing: Appearance.spacing.space50

                                                // The whole chord is the edit
                                                // affordance, not just the pencil:
                                                // a hover-only target on a dense
                                                // list is hard to find and
                                                // impossible to discover.
                                                TapHandler {
                                                    acceptedButtons: Qt.LeftButton
                                                    enabled: keybindCell.editable
                                                    onTapped: root.editRequested(keybindCell.modelData.binding)
                                                }

                                                Repeater {
                                                    model: modelData.mods
                                                    delegate: KeyboardKey {
                                                        required property var modelData
                                                        key: keySubstitutions[modelData] || modelData
                                                        pixelSize: Config.options.cheatsheet.fontSize.key
                                                    }
                                                }
                                                StyledText {
                                                    id: keybindPlus
                                                    visible: Config.options.cheatsheet.splitButtons && !keyBlacklist.includes(modelData.key) && modelData.mods.length > 0
                                                    text: "+"
                                                }
                                                KeyboardKey {
                                                    id: keybindKey
                                                    visible: Config.options.cheatsheet.splitButtons && !keyBlacklist.includes(modelData.key)
                                                    key: keySubstitutions[modelData.key] || modelData.key
                                                    pixelSize: Config.options.cheatsheet.fontSize.key
                                                    color: Appearance.colors.colOnLayer0
                                                }
                                                RippleButton {
                                                    id: editBindingButton
                                                    // Space is always reserved so hovering cannot
                                                    // reflow the grid; only the icon fades in.
                                                    visible: keybindCell.editable
                                                    opacity: (keybindCellHover.hovered || editBindingButton.hovered) ? 1 : 0
                                                    enabled: opacity > 0
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    implicitWidth: 22
                                                    implicitHeight: 22
                                                    buttonRadius: Appearance.rounding.full
                                                    onClicked: root.editRequested(modelData.binding)

                                                    Behavior on opacity {
                                                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                                    }

                                                    contentItem: MaterialSymbol {
                                                        verticalAlignment: Text.AlignVCenter
                                                        anchors.centerIn: parent
                                                        horizontalAlignment: Text.AlignHCenter
                                                        iconSize: Appearance.font.pixelSize.normal
                                                        text: "edit"
                                                        color: modelData.binding?.overridden
                                                            ? Appearance.colors.colPrimary
                                                            : Appearance.colors.colOnLayer0
                                                    }
                                                }
                                            }
                                        }

                                        Component {
                                            id: commentComponent
                                            Item {
                                                id: commentItem
                                                implicitWidth: commentText.implicitWidth + 8 * 2
                                                implicitHeight: commentText.implicitHeight

                                                StyledText {
                                                    id: commentText
                                                    anchors.centerIn: parent
                                                    font.pixelSize: Config.options.cheatsheet.fontSize.comment || Appearance.font.pixelSize.smaller
                                                    text: modelData.comment
                                                }
                                            }
                                        }
                                    }

                                }
                            }
                        }
                    }

                }
            }
            
        }
    }
    
}
