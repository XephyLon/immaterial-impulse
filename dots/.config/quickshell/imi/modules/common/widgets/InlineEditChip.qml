import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A value chip that edits in place: click it and the value becomes a text
 * input in the same footprint; Enter commits, Escape or leaving cancels.
 *
 * ONE element carries the value in both states - a TextInput that is
 * readOnly until clicked - never a label crossfading with an input twin
 * (the one-element-per-purpose rule). Dumb on purpose: the caller owns
 * the value, validates in `committed`, and writes its own store.
 */
RippleButton {
    id: root

    property string chipIcon: ""
    /** The settled display value; the caller rebinds it after a commit. */
    property string value: ""
    property string hint: ""
    property color chipInk: Appearance.colors.colOnLayer1
    /** How wide the input opens while editing, in characters-ish. */
    property real editWidth: Appearance.font.pixelSize.smaller * 5

    readonly property bool editing: root._editing
    property bool _editing: false

    signal committed(string text)

    implicitHeight: 32
    implicitWidth: chipContent.implicitWidth + Appearance.spacing.space200 * 2
    Behavior on implicitWidth {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    buttonRadius: Appearance.rounding.full
    colBackground: Appearance.colors.colLayer2
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active

    function beginEdit() {
        if (root._editing) return;
        root._editing = true;
        valueInput.text = root.value;
        valueInput.forceActiveFocus();
        valueInput.selectAll();
    }
    function endEdit(commit) {
        if (!root._editing) return;
        root._editing = false;
        if (commit) root.committed(valueInput.text);
        valueInput.text = Qt.binding(() => root._editing ? valueInput.text : root.value);
    }

    onClicked: root.beginEdit()

    contentItem: Item {
        implicitWidth: chipContent.implicitWidth
        implicitHeight: chipContent.implicitHeight

        RowLayout {
            id: chipContent
            anchors.centerIn: parent
            spacing: Appearance.spacing.space50

            MaterialSymbol {
                text: root.chipIcon
                iconSize: Appearance.font.pixelSize.larger
                color: root.chipInk
            }

            TextInput {
                id: valueInput
                // The one element: read-only display until the chip is
                // clicked, an input after - the value never swaps to a twin.
                Layout.preferredWidth: root._editing
                    ? Math.max(root.editWidth, contentWidth)
                    : contentWidth
                readOnly: !root._editing
                text: root.value
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.chipInk
                selectionColor: Appearance.colors.colPrimary
                selectedTextColor: Appearance.m3colors.m3onPrimary
                horizontalAlignment: TextInput.AlignHCenter
                // Clicks on the settled chip belong to the RippleButton (the
                // whole chip is the affordance); while editing the input owns
                // its pointer for cursor placement and selection.
                enabled: root._editing

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.endEdit(true);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        root.endEdit(false);
                        event.accepted = true;
                    }
                }
                onActiveFocusChanged: {
                    // Leaving the field is a cancel, not a commit: an edit
                    // abandoned mid-thought must not store half a number.
                    if (!activeFocus && root._editing) root.endEdit(false);
                }
            }
        }
    }

    StyledToolTip {
        text: root.hint
        extraVisibleCondition: root.hint.length > 0 && root.hovered && !root._editing
    }
}
