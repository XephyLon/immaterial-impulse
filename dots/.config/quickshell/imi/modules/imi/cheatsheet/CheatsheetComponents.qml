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

    // The shell's surface tokens carry the panels' transparency. Inside a
    // panel that is the point; for a tile drawn on top of one it means no
    // ground of its own, and a label with nothing under it reads as the label
    // of the tile beside it.
    function solid(colour: color): color {
        return Qt.rgba(colour.r, colour.g, colour.b, 1);
    }

    // Grouped by what the family is FOR, because that is the axis a decision
    // about a shared widget is taken on - a list row and a toolbar chip can
    // reasonably want different answers, a chip and another chip cannot.
    readonly property var families: [
        {
            name: Translation.tr("The interaction base"),
            note: Translation.tr("what every pressable tile below inherits"),
            entries: [
                { type: "modules/common/widgets/RippleButton.qml", props: {} },
                { type: "modules/common/widgets/RippleButtonWithIcon.qml",
                  props: { buttonIcon: "download", buttonText: "Install" } },
            ]
        },
        {
            name: Translation.tr("Buttons and chips"),
            note: Translation.tr("dialogs, toolbars, the dock, the FAB"),
            entries: [
                { type: "modules/common/widgets/DialogButton.qml", props: { buttonText: "Cancel" } },
                { type: "modules/common/widgets/MenuButton.qml", props: { buttonText: "Open" } },
                { type: "modules/common/widgets/ToolbarButton.qml", props: {}, glyph: "format_bold" },
                { type: "modules/common/widgets/IconToolbarButton.qml", props: { buttonIcon: "edit" } },
                { type: "modules/common/widgets/IconAndTextToolbarButton.qml",
                  props: { buttonIcon: "save", buttonText: "Save" } },
                { type: "modules/common/widgets/VibrantToolbarButton.qml", props: { buttonIcon: "star" } },
                { type: "modules/common/widgets/ToolbarTabButton.qml", props: { buttonText: "Tab" } },
                { type: "modules/common/widgets/FilterChip.qml", props: { buttonText: "Unread" } },
                { type: "modules/common/widgets/FloatingActionButton.qml", props: { buttonIcon: "add" } },
                { type: "modules/common/widgets/CircleUtilButton.qml", props: {}, glyph: "refresh" },
                { type: "modules/common/widgets/DockButton.qml", props: {}, glyph: "apps" },
                { type: "modules/common/widgets/EditRemoveBadge.qml", props: {}, glyph: "close" },
                { type: "modules/common/widgets/NavigationRailExpandButton.qml", props: {}, glyph: "menu" },
                { type: "modules/common/widgets/LightDarkPreferenceButton.qml", props: { dark: true } },
                { type: "modules/common/widgets/NotificationActionButton.qml", props: { buttonText: "Reply" } },
                { type: "modules/common/widgets/NotificationGroupExpandButton.qml",
                  props: {}, glyph: "expand_more" },
            ]
        },
        {
            name: Translation.tr("The group family"),
            note: Translation.tr("GroupButton and what sits on it - segmented ends, one shared morph"),
            entries: [
                { type: "modules/common/widgets/GroupButton.qml", props: { buttonText: "One" } },
                { type: "modules/common/widgets/SelectionGroupButton.qml", props: { buttonText: "Pick" } },
                { type: "modules/common/widgets/NotificationStatusButton.qml",
                  props: {}, glyph: "notifications" },
                { type: "modules/common/widgets/ButtonGroup.qml", props: {} },
            ]
        },
        {
            name: Translation.tr("Rows and groups"),
            note: Translation.tr("the grouped-list vocabulary a settings page is built from"),
            entries: [
                { type: "modules/common/widgets/DialogListItem.qml", props: {} },
                { type: "modules/common/widgets/CatalogueRow.qml", props: {} },
                { type: "modules/common/widgets/ConfigRow.qml", props: {} },
                { type: "modules/common/widgets/GroupedList.qml", props: {} },
            ]
        },
        {
            name: Translation.tr("Settings controls"),
            note: Translation.tr("what a ContentSection is made of"),
            entries: [
                { type: "modules/common/widgets/ConfigSwitch.qml",
                  props: { text: "Enable", buttonIcon: "check" } },
                { type: "modules/common/widgets/ConfigSlider.qml", props: {} },
                { type: "modules/common/widgets/ConfigSpinBox.qml", props: {} },
                { type: "modules/common/widgets/ConfigComboBox.qml", props: { text: "Choice" } },
                { type: "modules/common/widgets/ConfigTextArea.qml", props: {} },
                { type: "modules/common/widgets/ConfigSelectionArray.qml", props: { text: "Pick one" } },
            ]
        },
        {
            name: Translation.tr("Quick toggles and chat controls"),
            note: Translation.tr("the group vocabulary as the sidebars use it"),
            entries: [
                { type: "modules/imi/sidebarRight/quickToggles/classicStyle/QuickToggleButton.qml",
                  props: { buttonIcon: "wifi" } },
                { type: "modules/imi/sidebarRight/quickToggles/androidStyle/AndroidQuickToggleButton.qml",
                  props: { buttonIcon: "bluetooth", buttonText: "Bluetooth" } },
                { type: "modules/imi/sidebarLeft/ApiCommandButton.qml", props: { buttonText: "/model" } },
                { type: "modules/imi/sidebarLeft/aiChat/AiMessageControlButton.qml",
                  props: { buttonIcon: "content_copy" } },
                { type: "modules/imi/sidebarLeft/aiChat/SearchQueryButton.qml", props: {}, glyph: "search" },
                { type: "modules/imi/sidebarLeft/aiChat/AnnotationSourceButton.qml", props: {}, glyph: "link" },
                { type: "modules/imi/sidebarLeft/ScrollToBottomButton.qml", props: {}, glyph: "arrow_downward" },
                { type: "modules/imi/sidebarLeft/translator/LanguageSelectorButton.qml",
                  props: {}, glyph: "translate" },
            ]
        },
        {
            name: Translation.tr("Rows the shell fills from a service"),
            note: Translation.tr("each wants a model entry, so each says so here"),
            entries: [
                { type: "modules/imi/sidebarRight/wifiNetworks/WifiNetworkItem.qml", props: {} },
                { type: "modules/imi/sidebarRight/bluetoothDevices/BluetoothDeviceItem.qml", props: {} },
                { type: "modules/imi/sidebarRight/tailscale/TailscaleExitNodeItem.qml", props: {} },
                { type: "modules/imi/phone/PhoneDeviceItem.qml", props: {} },
                { type: "modules/imi/bar/SysTrayMenuEntry.qml", props: {} },
                { type: "modules/imi/overview/SearchItem.qml", props: {} },
                { type: "modules/imi/onScreenKeyboard/OskKey.qml", props: {} },
            ]
        },
        {
            name: Translation.tr("Elsewhere in the shell"),
            note: Translation.tr("bar, phone, calendar, mixer, todo, session, cheatsheet"),
            entries: [
                { type: "modules/imi/bar/PowerButton.qml", props: {}, glyph: "power_settings_new" },
                { type: "modules/imi/bar/LeftSidebarButton.qml", props: {}, glyph: "dock_to_right" },
                { type: "modules/imi/bar/CircleUtilButton.qml", props: {}, glyph: "search" },
                { type: "modules/imi/phone/PhoneActionButton.qml", props: { buttonIcon: "call" } },
                { type: "modules/imi/phone/PhoneDeviceChip.qml", props: {} },
                { type: "modules/imi/sidebarRight/calendar/CalendarHeaderButton.qml",
                  props: {}, glyph: "chevron_left" },
                { type: "modules/imi/sidebarRight/calendar/CalendarDayButton.qml", props: {} },
                { type: "modules/imi/sidebarRight/volumeMixer/AudioDeviceSelectorButton.qml",
                  props: {}, glyph: "speaker" },
                { type: "modules/imi/sidebarRight/todo/TodoItemActionButton.qml", props: {}, glyph: "check" },
                { type: "modules/imi/sessionScreen/SessionActionButton.qml", props: {}, glyph: "logout" },
                { type: "modules/imi/cheatsheet/ElementTile.qml", props: {}, glyph: "keyboard" },
            ]
        },
        {
            name: Translation.tr("Indicators"),
            note: Translation.tr("progress, badges, state at a glance"),
            entries: [
                { type: "modules/common/widgets/Badge.qml", props: {} },
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

    ColumnLayout {
        anchors { fill: parent; margins: Appearance.spacing.space150 }
        spacing: Appearance.spacing.space100

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("Every tile is the real widget, built from its own file. Press one: the number under it is the corner radius it is drawing this frame, rest → held.")
        }

        ScrollView {
            id: scroller
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
    }

    // ---- one family, as a bento block ------------------------------------
    component FamilyBlock: Rectangle {
        id: block
        required property var family

        implicitHeight: blockColumn.implicitHeight + Appearance.spacing.space200 * 2
        radius: Appearance.rounding.normal
        color: root.solid(Appearance.colors.colLayer1)
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        ColumnLayout {
            id: blockColumn
            anchors { fill: parent; margins: Appearance.spacing.space200 }
            spacing: Appearance.spacing.space100

            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colPrimary
                text: block.family.name
            }
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

    // ---- one real widget, in a cell with an edge --------------------------
    component ComponentTile: Rectangle {
        id: tile
        required property var entry

        width: root.tileWidth
        height: root.tileHeight
        radius: Appearance.rounding.small
        color: root.solid(Appearance.colors.colLayer2)
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        ColumnLayout {
            anchors { fill: parent; margins: Appearance.spacing.space100 }
            spacing: Appearance.spacing.space50

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: nameLabel.implicitHeight + Appearance.spacing.space50 * 2
                radius: Appearance.rounding.unsharpenmore
                color: root.solid(Appearance.colors.colLayer1)

                StyledText {
                    id: nameLabel
                    anchors {
                        left: parent.left; right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: Appearance.spacing.space50
                        rightMargin: Appearance.spacing.space50
                    }
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideLeft
                    color: Appearance.colors.colOnLayer1
                    text: (tile.entry.type ?? "").split("/").pop().replace(".qml", "")
                }
            }

            Item {
                id: stage
                Layout.fillWidth: true
                Layout.fillHeight: true

                property var control: null
                property var symbol: null
                property string failure: ""

                // NO chrome of this page's own. A draft filled each control's
                // rect and traced it so the corners could be seen moving, and
                // the result looked like a debugger drawn over the shell
                // rather than like the shell. What a widget looks like at rest
                // IS part of the answer, transparent included; the numbers
                // underneath carry the corner values instead.

                Component {
                    id: symbolComponent
                    MaterialSymbol {
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer2
                    }
                }

                Component.onCompleted: {
                    const url = Quickshell.shellPath(tile.entry.type);
                    const component = Qt.createComponent(url);
                    if (component.status === Component.Error) {
                        stage.failure = component.errorString().split("\n")[0].split(":").pop().trim();
                        return;
                    }
                    try {
                        stage.control = component.createObject(stage, Object.assign({}, tile.entry.props));
                        if (!stage.control) {
                            stage.failure = Translation.tr("needs its surroundings");
                            return;
                        }
                        stage.control.anchors.centerIn = stage;
                        // Several of these take their content as a CHILD, not
                        // as a property - ToolbarButton, the badges, the
                        // expanders. Bare, they collapse to an empty box and
                        // read as a broken widget rather than an empty one, so
                        // the tile hands them the glyph their call sites do.
                        if (tile.entry.glyph)
                            stage.symbol = symbolComponent.createObject(
                                stage.control, { text: tile.entry.glyph });
                    } catch (error) {
                        stage.failure = `${error}`.split("\n")[0];
                    }
                }

                StyledText {
                    visible: stage.failure !== ""
                    anchors.centerIn: parent
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                    text: stage.failure
                }
            }

            // The radius it is drawing, live. Reading `cornerTopLeft` rather
            // than the token is the point: a widget whose corners are pinned
            // from outside reports a number that never moves, which is exactly
            // the case a row inside a GroupedList is in.
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                color: (stage.control?.down ?? false)
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colSubtext
                visible: stage.control?.cornerTopLeft !== undefined
                text: {
                    const control = stage.control;
                    if (!control || control.cornerTopLeft === undefined)
                        return "";
                    const rest = control.buttonRadius ?? 0;
                    const held = control.buttonRadiusPressed ?? 0;
                    return `${rest.toFixed(1)} → ${held.toFixed(1)}   ${control.cornerTopLeft.toFixed(1)}`;
                }
            }
        }
    }
}
