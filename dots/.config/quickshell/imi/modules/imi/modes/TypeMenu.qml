pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * The "add condition" / "add action" menu: a grouped, filterable list of
 * kinds. Rows that cannot be added here stay visible but greyed, with the
 * reason — hiding them would make the catalogue look smaller than it is.
 *
 * `choices`: [{ key, label, icon, group, enabled, hint }]
 */
Popup {
    id: root

    property var choices: []
    property string query: ""

    signal picked(string key)

    readonly property var filtered: {
        const q = root.query.trim().toLowerCase();
        const list = q.length
            ? root.choices.filter(c => c.label.toLowerCase().indexOf(q) !== -1
                || (c.group ?? "").toLowerCase().indexOf(q) !== -1)
            : root.choices;
        // Flatten into rows with group headers where the group changes.
        const out = [];
        let last = null;
        for (const c of list) {
            if ((c.group ?? "") !== last && (c.group ?? "").length) {
                out.push({ header: true, label: c.group });
                last = c.group;
            }
            out.push(Object.assign({ header: false }, c));
        }
        return out;
    }

    function openAt(item) {
        const pos = item.mapToItem(root.parent, 0, item.height);
        const width = 360;
        const height = Math.min(440, root.implicitHeight);
        root.x = Math.max(8, Math.min(root.parent.width - width - 8, pos.x));
        // Below the button if it fits, else above it.
        root.y = pos.y + height + 8 <= root.parent.height ? pos.y + 4 : Math.max(8, pos.y - item.height - height - 4);
        root.query = "";
        root.open();
        Qt.callLater(() => searchField.forceActiveFocus());
    }

    width: 360
    height: Math.min(440, implicitHeight)
    implicitHeight: contentColumn.implicitHeight + Appearance.spacing.space300
    padding: Appearance.spacing.space150
    modal: false
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0
            to: 1
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
        NumberAnimation {
            property: "scale"
            from: 0.96
            to: 1
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
    }

    exit: Transition {
        NumberAnimation {
            property: "opacity"
            to: 0
            duration: Appearance.animation.elementMoveExit.duration
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
    }

    background: Rectangle {
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        StyledRectangularShadow {
            target: parent
        }
    }

    contentItem: ColumnLayout {
        id: contentColumn
        spacing: Appearance.spacing.space100

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 40
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer2

            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: Appearance.spacing.space150
                    rightMargin: Appearance.spacing.space150
                }
                spacing: Appearance.spacing.space100

                MaterialSymbol {
                    text: "search"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colSubtext
                }

                StyledTextInput {
                    id: searchField
                    Layout.fillWidth: true
                    text: root.query
                    onTextChanged: root.query = text
                    color: Appearance.colors.colOnLayer2
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            root.close();
                            event.accepted = true;
                        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                            const first = root.filtered.find(c => !c.header && c.enabled);
                            if (first) {
                                root.picked(first.key);
                                root.close();
                            }
                            event.accepted = true;
                        }
                    }

                    StyledText {
                        anchors.fill: parent
                        visible: !searchField.text.length
                        text: Translation.tr("Search")
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }

        StyledListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: Math.min(360, contentHeight)
            clip: true
            spacing: Appearance.spacing.space25
            popin: false
            animateAppearance: false
            model: root.filtered

            delegate: Item {
                id: row
                required property var modelData

                width: list.width
                implicitHeight: row.modelData.header ? 28 : 44

                StyledText {
                    visible: row.modelData.header
                    anchors {
                        left: parent.left
                        leftMargin: Appearance.spacing.space125
                        verticalCenter: parent.verticalCenter
                    }
                    text: row.modelData.label
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Medium
                    color: Appearance.colors.colPrimary
                }

                RippleButton {
                    visible: !row.modelData.header
                    anchors.fill: parent
                    enabled: row.modelData.enabled !== false
                    buttonRadius: Appearance.rounding.small
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: {
                        root.picked(row.modelData.key);
                        root.close();
                    }

                    contentItem: RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: Appearance.spacing.space125
                            rightMargin: Appearance.spacing.space125
                        }
                        spacing: Appearance.spacing.space125

                        MaterialSymbol {
                            text: row.modelData.icon ?? "bolt"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer2
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.label
                            elide: Text.ElideRight
                            color: Appearance.colors.colOnLayer2
                        }

                        StyledText {
                            visible: (row.modelData.hint ?? "").length > 0
                            text: row.modelData.hint ?? ""
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }
    }
}
