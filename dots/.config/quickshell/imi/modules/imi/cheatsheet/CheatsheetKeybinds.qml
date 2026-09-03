pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import "../../common/functions/cheatsheetLayout.js" as CheatsheetLayout
import "../../common/functions/cheatsheetFit.js" as CheatsheetFit

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
    // Ceiling on the column count. The height budget picks the count below it
    // (columnCount), so this only bounds a long list; a short one never fans
    // into slivers.
    readonly property int maxColumns: 4
    readonly property var columns: CheatsheetLayout.balance(
        root.sections, CheatsheetLayout.columnCount(root.sections, root.availableRows, root.maxColumns))

    // The columns are chosen to fit the HEIGHT budget, but a full keybind set
    // in four columns can still be wider than the screen (and, on a laptop,
    // marginally taller than the height budget once the section chips are drawn)
    // - and trading more columns for less height just makes it wider still.
    // So the page fits the same way the Elements page does: keep the columns and
    // the author order, and shrink the whole thing uniformly when it exceeds
    // either budget. fit is 1 whenever it already fits, so a roomy screen draws
    // full size.
    readonly property real contentWidth: row.implicitWidth + padding * 2
    readonly property real contentHeight: row.implicitHeight + padding * 2
    readonly property real fit: CheatsheetFit.fitScale(
        root.contentWidth, root.contentHeight, root.maxContentWidth, root.maxContentHeight)
    implicitWidth: root.contentWidth * root.fit
    implicitHeight: root.contentHeight * root.fit
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

    // Section glyphs, keyed on the group names keybinds.lua uses today,
    // with a neutral fallback for any group added later. Each glyph sits in
    // a Material shape chip, and the shape rotates per section - the design
    // language's way of making a list of headers scannable.
    property var sectionShapes: [
        MaterialShape.Shape.Cookie9Sided,
        MaterialShape.Shape.Clover4Leaf,
        MaterialShape.Shape.Sunny,
        MaterialShape.Shape.Gem,
        MaterialShape.Shape.Slanted,
        MaterialShape.Shape.Cookie6Sided,
        MaterialShape.Shape.Ghostish
    ]
    property var sectionIcons: ({
        "Utilities": "handyman",
        "Session": "power_settings_new",
        "Apps": "apps",
        "Screen": "desktop_windows",
        "Window": "select_window",
        "Media": "music_note",
        "Workspace": "workspaces"
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
        "XF86AudioRaiseVolume": Translation.tr("Volume Up"),
        "XF86AudioLowerVolume": Translation.tr("Volume Down"),
        "XF86AudioMute": Translation.tr("Mute"),
        "XF86AudioMicMute": Translation.tr("Mic Mute"),
        "XF86AudioPlay": Translation.tr("Play"),
        "XF86AudioPause": Translation.tr("Pause"),
        "XF86AudioNext": Translation.tr("Next Track"),
        "XF86AudioPrev": Translation.tr("Prev Track"),
        "XF86AudioStop": Translation.tr("Stop"),
        "XF86MonBrightnessUp": Translation.tr("Brightness Up"),
        "XF86MonBrightnessDown": Translation.tr("Brightness Down"),
        "XF86KbdBrightnessUp": Translation.tr("Kbd Light Up"),
        "XF86KbdBrightnessDown": Translation.tr("Kbd Light Down"),
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
        // Scaled about its own centre, which centerIn holds at the page's, so
        // the shrunk columns land exactly inside the box the page asks for -
        // the same arrangement CheatsheetPeriodicTable uses.
        anchors.centerIn: parent
        scale: root.fit

        Repeater {
            model: root.columns

            delegate: Column { // One balanced column of sections
                id: sectionsColumn
                spacing: root.spacing
                required property var modelData
                anchors.top: row.top

                // The widest section in this column decides the card width
                // for all of them, so the column reads as a stack of equal
                // cards. Computed from implicitWidth, never width: a
                // positioner Column takes its implicitWidth from its
                // children's WIDTH, so a card bound to parent.width is a
                // binding loop that silently collapses the whole sheet to
                // zero (it did).
                readonly property real cardWidth: {
                    let widest = 0;
                    for (let i = 0; i < children.length; i++)
                        widest = Math.max(widest, children[i].implicitWidth);
                    return widest;
                }

                Repeater {
                    model: modelData

                    delegate: Rectangle { // Section card
                        id: keybindSection
                        required property var modelData
                        required property int index
                        readonly property int sectionIndex: index
                        // Every section is its own surface rather than a
                        // heading floating on the sheet - the card is what
                        // separates one group of binds from the next. Width
                        // follows the widest sibling (see cardWidth), so a
                        // column reads as a stack of equal cards, not a
                        // ragged pile.
                        readonly property real cardPadding: Appearance.spacing.space150
                        width: sectionsColumn.cardWidth
                        color: Appearance.colors.colLayer1
                        radius: Appearance.rounding.normal
                        implicitWidth: sectionColumn.implicitWidth + cardPadding * 2
                        implicitHeight: sectionColumn.implicitHeight + cardPadding * 2

                        Column {
                            id: sectionColumn
                            // Left-anchored, not centered: the card is as wide
                            // as the column's widest section, and a narrower
                            // section centered in that width floats its title
                            // into the middle of the card.
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: keybindSection.cardPadding
                            spacing: root.titleSpacing
                            
                            Row {
                                visible: sectionTitle.text.length > 0
                                spacing: Appearance.spacing.space100
                                MaterialShapeWrappedMaterialSymbol {
                                    anchors.verticalCenter: sectionTitle.verticalCenter
                                    wrappedShape: root.sectionShapes[keybindSection.sectionIndex % root.sectionShapes.length]
                                    text: root.sectionIcons[keybindSection.modelData.name] ?? "keyboard"
                                    iconSize: Appearance.font.pixelSize.normal
                                    implicitSize: 32
                                    color: Appearance.colors.colPrimaryContainer
                                    colSymbol: Appearance.colors.colPrimary
                                }
                                StyledText {
                                    id: sectionTitle
                                    font {
                                        family: Appearance.font.family.title
                                        pixelSize: Appearance.font.pixelSize.title
                                        variableAxes: Appearance.font.variableAxes.title
                                    }
                                    color: Appearance.colors.colOnLayer1
                                    text: keybindSection.modelData.name
                                }
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
