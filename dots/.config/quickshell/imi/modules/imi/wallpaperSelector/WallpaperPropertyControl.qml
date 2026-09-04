import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import "we_color.js" as WeColor

// One row of a Wallpaper Engine project's own settings (project.json
// general.properties): a control per property type, in the sidebar's rail
// width. The five types are the reference app's PROPERTY_CONTROL_TYPES;
// anything else never reaches this file (the scanner filters).
//
// Values are the strings WE's --set-property takes (booleans "1"/"0", colors
// "r g b" floats, the rest verbatim) - this control converts for display and
// commits back in that form. Every commit reloads the wallpaper (a load-time
// argument), so the slider and the color channels commit on RELEASE, never
// per drag tick.
ColumnLayout {
    id: root

    // {name, type, text, value, min?, max?, step?, options?} from the scanner.
    property var definition: ({})
    // The value on screen: the user's edit if there is one, else the
    // wallpaper's own default.
    property string currentValue: ""
    property bool edited: false

    signal committed(var value)

    spacing: Appearance.spacing.space50

    readonly property string kind: root.definition?.type ?? ""
    property bool colorExpanded: false

    // Parse an "r g b" float triplet; a garbage value degrades to black
    // rather than NaN channels (Math.max(0, NaN) is NaN - guard with
    // comparisons, the Appearance-token lesson). we_color reads a dot-less
    // triplet as 0..255 (WE's own convention), so an integer project default
    // like "255 128 0" is not clamped flat to (1,1,0).
    function channel(index) {
        return WeColor.parseChannel(root.currentValue, index)
    }

    // ---- bool: a switch row --------------------------------------------
    Loader {
        Layout.fillWidth: true
        active: root.kind === "bool"
        visible: active
        sourceComponent: RowLayout {
            spacing: Appearance.spacing.space100
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.definition.text
                font.pixelSize: Appearance.font.pixelSize.small
            }
            StyledSwitch {
                checkable: false
                checked: root.currentValue === "1"
                onClicked: root.committed(root.currentValue === "1" ? "0" : "1")
            }
        }
    }

    // ---- slider ---------------------------------------------------------
    Loader {
        Layout.fillWidth: true
        active: root.kind === "slider"
        visible: active
        sourceComponent: ColumnLayout {
            spacing: Appearance.spacing.space25
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.definition.text
                font.pixelSize: Appearance.font.pixelSize.small
            }
            StyledSlider {
                Layout.fillWidth: true
                from: root.definition.min ?? 0
                to: root.definition.max ?? 100
                stepSize: root.definition.step ?? 0
                value: parseFloat(root.currentValue) || 0
                onPressedChanged: {
                    if (!pressed)
                        root.committed(String(value));
                }
            }
        }
    }

    // ---- combo ----------------------------------------------------------
    Loader {
        Layout.fillWidth: true
        active: root.kind === "combo"
        visible: active
        sourceComponent: RowLayout {
            spacing: Appearance.spacing.space100
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.definition.text
                font.pixelSize: Appearance.font.pixelSize.small
            }
            StyledComboBox {
                id: comboBox
                implicitWidth: 104
                readonly property var opts: root.definition.options ?? []
                model: comboBox.opts.map(option => ({ displayName: option.label }))
                textRole: "displayName"
                currentIndex: Math.max(0,
                    comboBox.opts.findIndex(option => option.value === root.currentValue))
                onActivated: index => root.committed(comboBox.opts[index].value)
            }
        }
    }

    // ---- color: a swatch that unfolds three channel sliders -------------
    // The repo has no free-RGB picker (ColorSelectionArray picks theme
    // tokens), and a WE scheme color is an arbitrary "r g b" triplet, so the
    // control is the smallest honest one: the current color as a swatch,
    // three 0..255 channel sliders while it is open.
    Loader {
        Layout.fillWidth: true
        active: root.kind === "color"
        visible: active
        sourceComponent: ColumnLayout {
            spacing: Appearance.spacing.space50
            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.space100
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.definition.text
                    font.pixelSize: Appearance.font.pixelSize.small
                }
                RippleButton {
                    implicitWidth: 46
                    implicitHeight: 26
                    buttonRadius: Appearance.rounding.small
                    toggled: root.colorExpanded
                    onClicked: root.colorExpanded = !root.colorExpanded
                    contentItem: Rectangle {
                        anchors.fill: parent
                        anchors.margins: Appearance.spacing.space25
                        radius: Appearance.rounding.unsharpen
                        border.width: Appearance.borderWidth.standard
                        border.color: Appearance.colors.colOutlineVariant
                        color: Qt.rgba(root.channel(0), root.channel(1), root.channel(2), 1)
                    }
                }
            }
            Loader {
                Layout.fillWidth: true
                active: root.colorExpanded
                visible: active
                sourceComponent: ColumnLayout {
                    spacing: Appearance.spacing.space25
                    Repeater {
                        model: [
                            { label: "R", index: 0 },
                            { label: "G", index: 1 },
                            { label: "B", index: 2 }
                        ]
                        delegate: RowLayout {
                            id: channelRow
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Appearance.spacing.space100
                            StyledText {
                                text: channelRow.modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                            StyledSlider {
                                Layout.fillWidth: true
                                from: 0
                                to: 1
                                value: root.channel(channelRow.modelData.index)
                                onPressedChanged: {
                                    if (pressed)
                                        return;
                                    const channels = [root.channel(0), root.channel(1), root.channel(2)]
                                    channels[channelRow.modelData.index] = value
                                    // Serialized at a precision WE round-trips;
                                    // full doubles make the stored file churn.
                                    root.committed(WeColor.formatChannels(channels))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- textinput -------------------------------------------------------
    Loader {
        Layout.fillWidth: true
        active: root.kind === "textinput"
        visible: active
        sourceComponent: ColumnLayout {
            spacing: Appearance.spacing.space25
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.definition.text
                font.pixelSize: Appearance.font.pixelSize.small
            }
            ToolbarTextField {
                Layout.fillWidth: true
                text: root.currentValue
                font.pixelSize: Appearance.font.pixelSize.small
                // Commit when editing finishes, not per keystroke: every
                // commit is a wallpaper reload.
                onEditingFinished: {
                    if (text !== root.currentValue)
                        root.committed(text);
                }
            }
        }
    }
}
