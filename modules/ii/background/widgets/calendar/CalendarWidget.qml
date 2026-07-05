import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root
    configEntryName: "calendar"
    implicitHeight: contentRect.implicitHeight
    implicitWidth: contentRect.implicitWidth

    property int monthShift: 0
    property var viewingDate: {
        let d = new Date();
        d.setDate(1);
        d.setMonth(d.getMonth() + monthShift);
        return d;
    }

    function getMonthMatrix(date) {
        const year = date.getFullYear();
        const month = date.getMonth();
        const firstOfMonth = new Date(year, month, 1);
        const startOffset = (firstOfMonth.getDay() + 6) % 7;
        const daysInMonth = new Date(year, month + 1, 0).getDate();
        const daysInPrevMonth = new Date(year, month, 0).getDate();
        const today = new Date();

        let cells = [];
        for (let i = 0; i < startOffset; i++) {
            cells.push({ day: daysInPrevMonth - startOffset + i + 1, currentMonth: false, isToday: false });
        }
        for (let d = 1; d <= daysInMonth; d++) {
            const isToday = (root.monthShift === 0)
                && d === today.getDate()
                && month === today.getMonth()
                && year === today.getFullYear();
            cells.push({ day: d, currentMonth: true, isToday: isToday });
        }
        let nextDay = 1;
        while (cells.length < 42) {
            cells.push({ day: nextDay, currentMonth: false, isToday: false });
            nextDay++;
        }

        let weeks = [];
        for (let i = 0; i < cells.length; i += 7) {
            weeks.push(cells.slice(i, i + 7));
        }
        return weeks;
    }

    property var weeks: getMonthMatrix(viewingDate)

    StyledDropShadow {
        target: contentRect
    }

    Rectangle {
        id: contentRect
        anchors.fill: parent
        color: Appearance.colors.colPrimaryContainer
        radius: Appearance.rounding.normal
        implicitWidth: calendarColumn.implicitWidth + 40
        implicitHeight: calendarColumn.implicitHeight + 40

        ColumnLayout {
            id: calendarColumn
            anchors {
                fill: parent
                margins: 20
            }
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnPrimaryContainer
                    text: root.viewingDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")
                }

                MaterialShape {
                    shape: MaterialShape.Shape.Circle
                    color: "transparent"
                    implicitSize: 26
                    MaterialSymbol {
                        iconSize: Appearance.font.pixelSize.normal
                        text: "chevron_left"
                        color: Appearance.colors.colOnPrimaryContainer
                        anchors.centerIn: parent
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.monthShift--
                    }
                }

                MaterialShape {
                    shape: MaterialShape.Shape.Circle
                    color: "transparent"
                    implicitSize: 26
                    MaterialSymbol {
                        iconSize: Appearance.font.pixelSize.normal
                        text: "chevron_right"
                        color: Appearance.colors.colOnPrimaryContainer
                        anchors.centerIn: parent
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.monthShift++
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: false
                Layout.alignment: Qt.AlignHCenter
                spacing: 4
                Repeater {
                    model: ["Mo","Tu","We","Th","Fr","Sa","Su"]
                    delegate: StyledText {
                        Layout.preferredWidth: 28
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnPrimaryContainer
                        text: modelData
                    }
                }
            }

            Rectangle {
                color: Appearance.colors.colLayer0
                radius: Appearance.rounding.normal
                implicitWidth: weeksColumn.implicitWidth + 16
                implicitHeight: weeksColumn.implicitHeight + 16

                ColumnLayout {
                    id: weeksColumn
                    anchors.centerIn: parent
                    spacing: 2

                    Repeater {
                        model: root.weeks
                        delegate: RowLayout {
                            required property var modelData
                            spacing: 4
                            Repeater {
                                model: parent.modelData
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28
                                    radius: 14
                                    color: modelData.isToday ? Appearance.colors.colPrimary : "transparent"
                                    StyledText {
                                        anchors.centerIn: parent
                                        text: modelData.day
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: modelData.isToday
                                            ? Appearance.colors.colOnPrimary
                                            : Appearance.colors.colOnLayer0
                                        opacity: modelData.currentMonth ? 1.0 : 0.35
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