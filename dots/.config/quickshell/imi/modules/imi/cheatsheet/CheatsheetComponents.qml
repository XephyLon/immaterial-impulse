import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

/**
 * The shared widget library, live, in the cheatsheet's Components tab.
 *
 * There was no way to see the shell's own vocabulary except by finding a
 * screen that happened to use it. That makes two things hard that this page
 * makes easy: choosing the right widget for a new surface, and judging a
 * change to a SHARED token - `Appearance.interaction.pressRadiusScale` reaches
 * 51 types, and reviewing it one screenshot at a time is how a press feel gets
 * changed by accident.
 *
 * Three rules hold it honest:
 *
 *   - every tile builds the REAL type, created at runtime from its own file.
 *     A mock would drift, and a mock cannot answer "what does this actually do
 *     under a press".
 *   - a type that cannot stand up without its surroundings says so IN PLACE.
 *     Runtime creation is what buys that: a failure here is a caught error and
 *     a line of text, not a compile error that takes the cheatsheet down.
 *   - the catalogue is checked. `tests/lint_component_gallery.py` fails when a
 *     widget under `modules/common/widgets` is neither listed here nor on the
 *     exclusion list with a reason, so "every component" stays true rather
 *     than being true on the day it was written.
 *
 * Behind Config.options.developer.enable - see Cheatsheet.qml for the tab.
 */
Item {
    id: root

    implicitWidth: Math.min(1500, (root.Window.window?.screen?.width ?? 1920) - 240)
    implicitHeight: Math.min(900, (root.Window.window?.screen?.height ?? 1080) - 260)

    readonly property real tileWidth: 236
    readonly property real tileHeight: 128
    readonly property real gap: Appearance.spacing.space150


    // Grouped by what the family is FOR, because that is the axis a decision
    // about a shared widget is taken on - a list row and a toolbar chip can
    // reasonably want different answers, a chip and another chip cannot.
    readonly property var families: [
        {
            name: Translation.tr("The interaction base"),
            icon: "touch_app",
            shape: MaterialShape.Shape.Clover4Leaf,
            note: Translation.tr("what every pressable tile below inherits"),
            entries: [
                { type: "modules/common/widgets/RippleButton.qml", props: { buttonText: "Button" }, toggles: true },
                { type: "modules/common/widgets/RippleButtonWithIcon.qml", props: { materialIcon: "download", mainText: "Install" } },
            ]
        },
        {
            name: Translation.tr("Buttons and chips"),
            icon: "smart_button",
            shape: MaterialShape.Shape.Gem,
            note: Translation.tr("dialogs, toolbars, the dock, the FAB"),
            entries: [
                { type: "modules/common/widgets/DialogButton.qml", props: { buttonText: "Cancel" } },
                { type: "modules/common/widgets/MenuButton.qml", props: { buttonText: "Open" } },
                { type: "modules/common/widgets/ToolbarButton.qml", props: { buttonText: "Bold" } },
                { type: "modules/common/widgets/IconToolbarButton.qml", props: { text: "edit" }, toggles: true },
                { type: "modules/common/widgets/IconAndTextToolbarButton.qml", props: { iconText: "save", buttonText: "Save" }, toggles: true },
                { type: "modules/common/widgets/VibrantToolbarButton.qml", props: { buttonText: "Star" } },
                { type: "modules/common/widgets/ToolbarTabButton.qml", props: { materialSymbol: "tab", current: true } },
                { type: "modules/common/widgets/FilterChip.qml", props: { label: "Unread", chipIcon: "filter_alt" }, toggles: true },
                { type: "modules/common/widgets/FloatingActionButton.qml", props: { iconText: "add" } },
                { type: "modules/common/widgets/DockButton.qml", props: { } },
                { type: "modules/common/widgets/EditRemoveBadge.qml", props: { } },
                { type: "modules/common/widgets/NavigationRailExpandButton.qml", props: { } },
                { type: "modules/common/widgets/LightDarkPreferenceButton.qml", props: { dark: true }, toggles: true },
                { type: "modules/common/widgets/NotificationActionButton.qml", props: { buttonText: "Reply" } },
                { type: "modules/common/widgets/NotificationGroupExpandButton.qml", props: { count: 3, expanded: false } },
            ]
        },
        {
            name: Translation.tr("The group family"),
            icon: "view_week",
            shape: MaterialShape.Shape.Clover8Leaf,
            note: Translation.tr("GroupButton and what sits on it - segmented ends, one shared morph"),
            entries: [
                { type: "modules/common/widgets/GroupButton.qml", props: { buttonText: "One" }, toggles: true },
                { type: "modules/common/widgets/SelectionGroupButton.qml", props: { buttonIcon: "check" }, toggles: true },
                { type: "modules/common/widgets/NotificationStatusButton.qml", props: { buttonIcon: "notifications", buttonText: "3" }, toggles: true },
                { type: "modules/common/widgets/ButtonGroup.qml", props: {} },
            ]
        },
        {
            name: Translation.tr("Rows and groups"),
            icon: "table_rows",
            shape: MaterialShape.Shape.Clover4Leaf,
            note: Translation.tr("the grouped-list vocabulary a settings page is built from"),
            entries: [
                { type: "modules/common/widgets/DialogListItem.qml", props: { } },
                { type: "modules/common/widgets/CatalogueRow.qml", props: { rowIcon: "info", title: "A row", description: "with a description" } },
                { type: "modules/common/widgets/ConfigRow.qml", props: {} },
                { type: "modules/common/widgets/GroupedList.qml", props: {}, toggles: true },
            ]
        },
        {
            name: Translation.tr("Settings controls"),
            icon: "tune",
            shape: MaterialShape.Shape.Gem,
            note: Translation.tr("what a ContentSection is made of"),
            entries: [
                { type: "modules/common/widgets/ConfigSwitch.qml", props: { text: "Enable", buttonIcon: "check" } },
                { type: "modules/common/widgets/ConfigSlider.qml", props: { text: "Volume", buttonIcon: "volume_up", value: 0.6 } },
                { type: "modules/common/widgets/ConfigSpinBox.qml", props: { text: "Count", icon: "tag", value: 3 } },
                { type: "modules/common/widgets/ConfigComboBox.qml", props: { text: "Choice", buttonIcon: "list" } },
                { type: "modules/common/widgets/ConfigTextArea.qml", props: { text: "Notes", placeholderText: "Type here" } },
                { type: "modules/common/widgets/ConfigSelectionArray.qml", props: { text: "Pick one", icon: "tune" }, toggles: true },
            ]
        },
        {
            name: Translation.tr("Quick toggles and chat controls"),
            icon: "toggle_on",
            shape: MaterialShape.Shape.Clover8Leaf,
            note: Translation.tr("the group vocabulary as the sidebars use it"),
            entries: [
                { type: "modules/imi/sidebarRight/quickToggles/classicStyle/QuickToggleButton.qml", props: { buttonIcon: "wifi" }, toggles: true },
                { type: "modules/imi/sidebarRight/quickToggles/androidStyle/AndroidQuickToggleButton.qml",
                  props: { buttonIcon: "bluetooth", buttonText: "Bluetooth" }, toggles: true },
                { type: "modules/imi/sidebarLeft/ApiCommandButton.qml", props: { buttonText: "/model" } },
                { type: "modules/imi/sidebarLeft/aiChat/AiMessageControlButton.qml", props: { buttonIcon: "content_copy" }, toggles: true },
                { type: "modules/imi/sidebarLeft/aiChat/SearchQueryButton.qml", props: { query: "wallpaper" } },
                { type: "modules/imi/sidebarLeft/aiChat/AnnotationSourceButton.qml", props: { displayText: "source", url: "https://example.invalid" } },
                { type: "modules/imi/sidebarLeft/ScrollToBottomButton.qml", props: {} },
                { type: "modules/imi/sidebarLeft/translator/LanguageSelectorButton.qml", props: { displayText: "EN" } },
            ]
        },
        {
            name: Translation.tr("Rows the shell fills from a service"),
            icon: "dns",
            shape: MaterialShape.Shape.Clover4Leaf,
            note: Translation.tr("each wants a model entry, so each says so here"),
            entries: [
                { type: "modules/imi/sidebarRight/wifiNetworks/WifiNetworkItem.qml", props: {} },
                { type: "modules/imi/sidebarRight/bluetoothDevices/BluetoothDeviceItem.qml", props: {} },
                { type: "modules/imi/sidebarRight/tailscale/TailscaleExitNodeItem.qml", props: {} },
                { type: "modules/imi/phone/PhoneDeviceItem.qml", props: {} },
                { type: "modules/imi/bar/SysTrayMenuEntry.qml", props: {} },
                { type: "modules/imi/overview/SearchItem.qml", props: {} },
                { type: "modules/imi/onScreenKeyboard/OskKey.qml", props: {}, toggles: true },
            ]
        },
        {
            name: Translation.tr("Elsewhere in the shell"),
            icon: "dashboard",
            shape: MaterialShape.Shape.Gem,
            note: Translation.tr("bar, phone, calendar, mixer, todo, session, cheatsheet"),
            entries: [
                { type: "modules/imi/bar/PowerButton.qml", props: { } },
                { type: "modules/imi/bar/LeftSidebarButton.qml", props: { }, toggles: true },
                { type: "modules/imi/bar/CircleUtilButton.qml", props: {}, glyph: "search" },
                { type: "modules/imi/phone/PhoneActionButton.qml", props: { glyph: "call", label: "Call" } },
                { type: "modules/imi/phone/PhoneDeviceChip.qml", props: {} },
                { type: "modules/imi/sidebarRight/calendar/CalendarHeaderButton.qml", props: { buttonText: "‹", tooltipText: "Previous month" } },
                { type: "modules/imi/sidebarRight/calendar/CalendarDayButton.qml", props: { day: 12, isToday: true }, toggles: true },
                { type: "modules/imi/sidebarRight/volumeMixer/AudioDeviceSelectorButton.qml", props: {} },
                { type: "modules/imi/sidebarRight/todo/TodoItemActionButton.qml", props: { buttonText: "Done", tooltipText: "Mark done" } },
                { type: "modules/imi/sessionScreen/SessionActionButton.qml", props: { buttonIcon: "logout", buttonText: "Log out" } },
                { type: "modules/imi/cheatsheet/ElementTile.qml", props: {} },
            ]
        },
        {
            name: Translation.tr("Indicators"),
            icon: "speed",
            shape: MaterialShape.Shape.Clover8Leaf,
            note: Translation.tr("progress, badges, state at a glance"),
            entries: [
                { type: "modules/common/widgets/Badge.qml", props: { label: "3", badgeIcon: "info" } },
                { type: "modules/common/widgets/CircularProgress.qml", props: { value: 0.6 } },
                { type: "modules/common/widgets/ClippedProgressBar.qml", props: { value: 0.4 } },
                { type: "modules/common/widgets/ClippedFilledCircularProgress.qml", props: { value: 0.7 } },
                { type: "modules/common/widgets/ClippedOutlineCircularProgress.qml", props: { value: 0.3 } },
            ]
        },
    ]

    // Bento: columns of family blocks, each as wide as the tiles it holds.
    // Packed by hand rather than balanced by a pass, because the arrangement's
    // job is to keep a family TOGETHER - a column that split one across two
    // would read as two families.
    readonly property var columns: [
        { span: 2, families: [1, 0] },        // buttons and chips, then the base
        { span: 2, families: [2, 3, 4] },     // group family, rows, settings controls
        { span: 2, families: [5, 6] },        // quick toggles, service-fed rows
        { span: 2, families: [7, 8] },        // elsewhere, indicators
    ]

    // ---- what the workbench is showing -----------------------------------
    //
    // Gallery answers "what do we have", Audit answers "do they agree", and
    // Detail answers "what does this one do" - three questions a design pass
    // asks in that order, so they are three modes over one catalogue rather
    // than three pages with three copies of it.
    // The tab bar OWNS which mode is showing; nothing binds its currentIndex.
    //
    // It used to be `currentIndex: root.mode` plus
    // `onCurrentIndexChanged: root.mode = currentIndex`, which is a binding and
    // an imperative write to the same property - the bar assigns its own index
    // on a click, that assignment destroys the binding, and from then on the
    // two disagree about which tab is open. It is the same fault
    // lint_config_switch_intent.py exists for, in a widget that lint does not
    // look at.
    readonly property int mode: modeBar.currentIndex
    property var selected: null
    property string filter: ""

    // Every entry, flat, for the audit table and the search.
    readonly property var allEntries: {
        const out = [];
        for (const family of root.families)
            for (const entry of family.entries)
                out.push(entry);
        return out;
    }

    readonly property var visibleEntries: {
        if (root.filter === "")
            return root.allEntries;
        const needle = root.filter.toLowerCase();
        return root.allEntries.filter(entry => root.nameOf(entry).toLowerCase().includes(needle));
    }

    function nameOf(entry) {
        return (entry?.type ?? "").split("/").pop().replace(".qml", "");
    }

    function show(entry) {
        root.selected = entry;
        modeBar.currentIndex = 2;
    }

    ColumnLayout {
        anchors { fill: parent; margins: Appearance.spacing.space150 }
        spacing: Appearance.spacing.space100

        Toolbar {
            Layout.fillWidth: true
            enableShadow: false

            ToolbarTabBar {
                id: modeBar
                tabButtonList: [
                    { "icon": "grid_view", "name": Translation.tr("Gallery") },
                    { "icon": "table_rows", "name": Translation.tr("Audit") },
                    { "icon": "page_info", "name": Translation.tr("Detail") },
                ]
            }

            ToolbarTextField {
                Layout.preferredWidth: 260
                placeholderText: Translation.tr("Filter by name…")
                onTextChanged: root.filter = text
            }

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                color: Appearance.colors.colSubtext
                text: root.mode === 2 && root.selected
                    ? root.selected.type
                    : Translation.tr("%1 widgets, built for real — hover and press to see their states")
                        .arg(root.allEntries.length)
            }
        }

        // ---- gallery -----------------------------------------------------
        ScrollView {
            id: scroller
            visible: root.mode === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth

            RowLayout {
                // Bound to the scroller, NOT to `parent`: a ScrollView's
                // content item has no width of its own, so a child sized from
                // it collapses and every wrapped row becomes a single column.
                width: scroller.availableWidth
                spacing: root.gap

                Repeater {
                    model: root.columns
                    delegate: ColumnLayout {
                        id: column
                        required property var modelData
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: column.modelData.span * root.tileWidth
                            + (column.modelData.span - 1) * root.gap
                            + Appearance.spacing.space200 * 2
                        spacing: root.gap

                        Repeater {
                            model: column.modelData.families
                            delegate: FamilyBlock {
                                required property var modelData
                                Layout.fillWidth: true
                                family: root.families[modelData]
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }

        // ---- audit -------------------------------------------------------
        ComponentAudit {
            visible: root.mode === 1
            Layout.fillWidth: true
            Layout.fillHeight: true
            entries: root.visibleEntries
            onPicked: entry => root.show(entry)
        }

        // ---- detail ------------------------------------------------------
        RowLayout {
            visible: root.mode === 2
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Appearance.spacing.space150

            // The picker stays beside the widget rather than sending you back
            // to the gallery: comparing two chips means switching between them
            // repeatedly, and a round trip through another mode loses the
            // surface and the knobs you had set.
            StyledFlickable {
                Layout.preferredWidth: 260
                Layout.fillHeight: true
                contentHeight: pickerGroup.implicitHeight
                clip: true

                GroupedList {
                    id: pickerGroup
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    model: root.visibleEntries
                    rowDelegate: Component {
                        DialogListItem {
                            property var modelData: null
                            active: root.selected?.type === modelData?.type
                            implicitHeight: 34
                            onClicked: root.selected = modelData
                            contentItem: StyledText {
                                anchors {
                                    fill: parent
                                    leftMargin: Appearance.spacing.space150
                                    rightMargin: Appearance.spacing.space150
                                }
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                                color: Appearance.colors.colOnLayer2
                                text: root.nameOf(modelData)
                            }
                        }
                    }
                }
            }

            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                active: root.selected !== null
                sourceComponent: ComponentDetail { entry: root.selected }
            }

            StyledText {
                visible: root.selected === null
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                color: Appearance.colors.colSubtext
                text: Translation.tr("Pick a widget from the list.")
            }
        }
    }

    // ---- one family, as a section ----------------------------------------
    component FamilyBlock: StyledRectangle {
        id: block
        required property var family

        implicitHeight: blockColumn.implicitHeight + Appearance.spacing.space200 * 2
        radius: Appearance.rounding.normal
        contentLayer: StyledRectangle.ContentLayer.Pane

        ColumnLayout {
            id: blockColumn
            anchors { fill: parent; margins: Appearance.spacing.space200 }
            spacing: Appearance.spacing.space100

            // The shell's own section header - the glyph in its Material
            // shape, the title beside it - rather than two StyledTexts of
            // hand-picked sizes, which is what this was and what made the
            // page look like a debug view of the shell instead of part of it.
            ContentSection {
                Layout.fillWidth: true
                icon: block.family.icon ?? "widgets"
                shape: block.family.shape ?? MaterialShape.Shape.Clover4Leaf
                title: block.family.name

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                    text: `${block.family.entries.length} — ${block.family.note}`
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: root.gap

                    Repeater {
                        model: block.family.entries
                        delegate: ComponentTile {
                            required property var modelData
                            entry: modelData
                        }
                    }
                }
            }
        }
    }

    // ---- one real widget, in a cell with an edge --------------------------
    component ComponentTile: StyledRectangle {
        id: tile
        required property var entry

        width: root.tileWidth
        height: root.tileHeight
        radius: Appearance.rounding.small
        contentLayer: StyledRectangle.ContentLayer.Group
        border.width: 1
        border.color: hoverArea.containsMouse
            ? Appearance.colors.colPrimary
            : "transparent"

        // Hover only, for the outline. The Gallery is DISPLAY: a tile shows
        // the widget and its hover and press states, and does nothing else -
        // it used to open the widget in Detail on release, which made one
        // gesture do two things and bounced you off the page on the first
        // press you wanted to watch. Detail has its own list; Audit's rows
        // open it too.
        MouseArea {
            id: hoverArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }

        ColumnLayout {
            anchors { fill: parent; margins: Appearance.spacing.space100 }
            spacing: Appearance.spacing.space50

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: nameLabel.implicitHeight + Appearance.spacing.space50 * 2
                radius: Appearance.rounding.unsharpenmore
                color: Appearance.colors.colLayer1

                StyledText {
                    id: nameLabel
                    anchors {
                        left: parent.left; right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: Appearance.spacing.space50
                        rightMargin: Appearance.spacing.space50
                    }
                    horizontalAlignment: Text.AlignHCenter
                    // From the right: two of these share a 26-character prefix
                    // and eliding the START turned NotificationGroupExpandButton
                    // into "…ificationGroupExpandButton", which names nothing.
                    elide: Text.ElideRight
                    color: Appearance.colors.colOnLayer1
                    text: root.nameOf(tile.entry)
                }
            }

            ComponentStage {
                id: stage
                Layout.fillWidth: true
                Layout.fillHeight: true
                entry: tile.entry
            }

            // The radius it is drawing, live. Reading `cornerTopLeft` rather
            // than the token is the point: a widget whose corners are pinned
            // from outside reports a number that never moves, which is exactly
            // the case a row inside a GroupedList is in.
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                visible: stage.measurements?.cornerTopLeft !== undefined
                color: (stage.control?.down ?? false)
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colSubtext
                text: {
                    const measured = stage.measurements;
                    if (!measured || measured.cornerTopLeft === undefined)
                        return "";
                    return `${(measured.radius ?? 0).toFixed(1)} → `
                        + `${(measured.radiusPressed ?? 0).toFixed(1)}   `
                        + `${measured.cornerTopLeft.toFixed(1)}`;
                }
            }
        }
    }
}
