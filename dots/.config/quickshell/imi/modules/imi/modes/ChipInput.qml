pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * A list of short strings as removable chips, with a field to type another
 * and, when the caller can offer some, a menu of suggestions (running
 * windows, paired devices, known networks…) so the user rarely has to know
 * the exact spelling.
 */
ColumnLayout {
    id: root

    property var values: []
    property string placeholder: ""
    /// [{ label, value }] — shown under a "pick" button; empty hides it.
    property var suggestions: []
    /// Maps a stored value to what the chip shows.
    property var display: v => v

    signal changed(var list)

    spacing: Appearance.spacing.space75

    function add(value) {
        const v = String(value ?? "").trim();
        if (!v.length)
            return;
        const list = Array.from(root.values);
        if (list.indexOf(v) !== -1)
            return;
        list.push(v);
        root.changed(list);
    }

    function removeAt(index) {
        const list = Array.from(root.values);
        list.splice(index, 1);
        root.changed(list);
    }

    Flow {
        Layout.fillWidth: true
        visible: root.values.length > 0
        spacing: Appearance.spacing.space75

        Repeater {
            model: root.values

            // The shell's chip; its trailing glyph says what a press does.
            delegate: FilterChip {
                id: chip
                required property string modelData
                required property int index
                label: root.display(chip.modelData)
                trailingIcon: "close"
                onClicked: root.removeAt(chip.index)
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Appearance.spacing.space75

        EditorField {
            id: entry
            Layout.fillWidth: true
            placeholderText: root.placeholder
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.add(entry.text);
                    entry.text = "";
                    event.accepted = true;
                }
            }
            onEditingFinished: {
                if (entry.text.trim().length) {
                    root.add(entry.text);
                    entry.text = "";
                }
            }
        }

        RippleButton {
            id: pickButton
            visible: root.suggestions.length > 0
            implicitHeight: 36
            implicitWidth: pickRow.implicitWidth + Appearance.spacing.space300
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colLayer3
            colBackgroundHover: Appearance.colors.colLayer3Hover
            colRipple: Appearance.colors.colLayer3Active
            onClicked: suggestionLoader.item.open()

            contentItem: RowLayout {
                id: pickRow
                anchors.centerIn: parent
                spacing: Appearance.spacing.space50

                StyledText {
                    text: Translation.tr("Pick")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer3
                }

                MaterialSymbol {
                    text: "expand_more"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer3
                }
            }

            // Built only while there is something to suggest: most chip
            // inputs never are, and a popup is a plate, a shadow and a list.
            Loader {
                id: suggestionLoader
                active: root.suggestions.length > 0

                sourceComponent: EditorPopup {
                id: suggestionMenu
                // Anchored to the button itself, whatever the Loader ends up
                // a child of.
                parent: pickButton
                y: parent.height + Appearance.spacing.space50
                x: parent.width - width
                width: 300
                height: Math.min(320, suggestionList.contentHeight + Appearance.spacing.space200)
                padding: Appearance.spacing.space100

                contentItem: StyledListView {
                    id: suggestionList
                    clip: true
                    spacing: Appearance.spacing.space25
                    popin: false
                    animateAppearance: false
                    model: root.suggestions

                    delegate: RippleButton {
                        id: suggestion
                        required property var modelData

                        width: suggestionList.width
                        implicitHeight: 38
                        buttonRadius: Appearance.rounding.small
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colLayer2Active
                        onClicked: {
                            root.add(suggestion.modelData.value);
                            suggestionMenu.close();
                        }

                        contentItem: RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: Appearance.spacing.space125
                                rightMargin: Appearance.spacing.space125
                            }
                            spacing: Appearance.spacing.space100

                            StyledText {
                                Layout.fillWidth: true
                                text: suggestion.modelData.label
                                elide: Text.ElideRight
                                color: Appearance.colors.colOnLayer2
                            }

                            StyledText {
                                visible: suggestion.modelData.label !== suggestion.modelData.value
                                text: suggestion.modelData.value
                                elide: Text.ElideMiddle
                                Layout.maximumWidth: 120
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }
            }
            }
        }
    }
}
