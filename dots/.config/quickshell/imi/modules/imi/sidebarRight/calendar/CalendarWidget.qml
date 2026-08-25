import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "calendar_layout.js" as CalendarLayout
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property int monthShift: 0
    // The sidebar's open counter; the ripple also re-runs on month
    // navigation, which is the fork's own behavior.
    property int entranceTrigger: -1
    property int _entranceKey: 0
    // The counter arrives as a late Qt.binding from the tab Loader's
    // onLoaded, so a widget created mid-open sees one jump from -1 to the
    // current count in its creation turn - that is the binding catching up,
    // not the sidebar opening, and it replayed the ripple over every
    // Todo-to-Calendar switch. The handler arms one turn after creation:
    // a real open is always a later turn.
    property bool _entranceArmed: false
    Component.onCompleted: Qt.callLater(() => root._entranceArmed = true)
    onEntranceTriggerChanged: {
        if (root._entranceArmed)
            root._entranceKey++;
    }
    onMonthShiftChanged: _entranceKey++
    // One grid column, on the 4dp grid. Seven rows of this plus the 32px header,
    // the gaps and the padding have to fit BottomWidgetGroup's fixed height, or
    // the group grows and takes it straight out of the notification list below.
    readonly property int dayCellSize: 36
    readonly property int firstDayOfWeek: Config.options.calendar.firstDayOfWeek
    property var viewingDate: CalendarLayout.getDateInXMonthsTime(monthShift)
    property var calendarLayout: CalendarLayout.getCalendarLayout(viewingDate, monthShift === 0, firstDayOfWeek)
    readonly property int viewingYear: viewingDate.getFullYear()
    readonly property int viewingMonth: viewingDate.getMonth() + 1
    // Matches the navigation rail's top margin in BottomWidgetGroup: the header
    // row and the rail's collapse button are both 30px tall, so an equal inset
    // is what puts them on a shared centre line.
    readonly property int contentPadding: Appearance.spacing.space150

    width: calendarColumn.width
    implicitHeight: calendarColumn.height + contentPadding * 2

    Keys.onPressed: (event) => {
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp)
            && event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageDown) {
                monthShift++;
            } else if (event.key === Qt.Key_PageUp) {
                monthShift--;
            }
            event.accepted = true;
        }
    }
    MouseArea {
        anchors.fill: parent
        onWheel: (event) => {
            if (event.angleDelta.y > 0) {
                monthShift--;
            } else if (event.angleDelta.y < 0) {
                monthShift++;
            }
        }
    }

    ColumnLayout {
        id: calendarColumn
        // Top-anchored, not centred: the parent is stretched to the group's
        // fixed height, so centring would drift the header off the rail button
        // by half the leftover space.
        anchors.top: parent.top
        anchors.topMargin: root.contentPadding
        anchors.horizontalCenter: parent.horizontalCenter
        // Eight rows means seven gaps, so every step up this token costs the
        // notification list below seven pixels of height. space75 is the
        // scale's closest value to the 5px this grid was drawn at.
        spacing: Appearance.spacing.space75

        // Calendar header
        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space100
            CalendarHeaderButton {
                id: monthButton
                clip: true
                // Pull the button out by its own inset so the month label starts
                // on the first day column's left edge instead of 12px right of it.
                Layout.leftMargin: -labelInset
                buttonText: `${monthShift != 0 ? "• " : ""}${viewingDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")}`
                tooltipText: (monthShift === 0) ? "" : Translation.tr("Jump to current month")
                downAction: () => {
                    monthShift = 0;
                }
            }
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: false
            }
            CalendarHeaderButton {
                forceCircle: true
                downAction: () => {
                    monthShift--;
                }
                contentItem: MaterialSymbol {
                    text: "chevron_left"
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                }
            }
            CalendarHeaderButton {
                forceCircle: true
                downAction: () => {
                    monthShift++;
                }
                contentItem: MaterialSymbol {
                    text: "chevron_right"
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                }
            }
        }

        // Week days row
        RowLayout {
            id: weekDaysRow
            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: false
            spacing: Appearance.spacing.space75
            Repeater {
                model: CalendarLayout.getWeekDays(root.firstDayOfWeek)
                delegate: CalendarDayButton {
                    implicitWidth: root.dayCellSize
                    implicitHeight: root.dayCellSize
                    day: Translation.tr(modelData.day)
                    isToday: modelData.today
                    bold: true
                    enabled: false
                }
            }
        }

        // Real week rows
        Repeater {
            id: calendarRows
            // model: calendarLayout
            model: 6
            delegate: RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: false
                spacing: Appearance.spacing.space75
                Repeater {
                    model: Array(7).fill(modelData)
                    delegate: CalendarDayButton {
                        implicitWidth: root.dayCellSize
                        implicitHeight: root.dayCellSize
                        gridRow: modelData
                        gridCol: index
                        entranceKey: root._entranceKey
                        day: calendarLayout[modelData][index].day
                        isToday: calendarLayout[modelData][index].today
                        // Only in-viewing-month cells (today !== -1) map cleanly
                        // to viewingYear/Month; spillover days stay undotted in v1.
                        hasEvent: calendarLayout[modelData][index].today !== -1
                            && IcsCalendar.hasEventsOn(root.viewingYear, root.viewingMonth,
                                calendarLayout[modelData][index].day)
                    }
                }
            }
        }
    }
}
