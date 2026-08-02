pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.plugins

Item {
    id: root

    // The card fills the whole widget, so the host's default frost region has
    // the right extent - but not the right corner radius (PluginWidget falls
    // back to `Appearance.rounding.large`, 7px tighter than the card's
    // `verylarge`), which would leave blurred slivers outside the four corners.
    // Naming the card is the only way to hand the host the radius it has.
    readonly property bool blurEnabled: PluginState.option("calendar", "blurEnabled", false)
    readonly property real backgroundOpacity: Config.options.plugins.blurOpacity
    readonly property bool managesBlurTint: true
    readonly property var blurRegions: [
        {
            x: card.x,
            y: card.y,
            width: card.width,
            height: card.height,
            radius: card.radius
        }
    ]

    function tinted(surfaceColor) {
        return root.blurEnabled ? ColorUtils.transparentize(surfaceColor, 1 - root.backgroundOpacity) : surfaceColor;
    }

    readonly property real cardSpacing: Appearance.spacing.space150
    readonly property real singleWidth: 132
    readonly property real cardHeight: 120

    readonly property real snapWidth1: singleWidth
    readonly property real snapWidth2: singleWidth * 2 + cardSpacing
    readonly property real snapWidth3: singleWidth * 2 + cardSpacing

    // The corner handle resizes this widget and the opposite handle flips the
    // wide size between a month and a week, so the manifest declares no `grid`:
    // a span is a fixed pixel size the host assigns on every load, and it would
    // overwrite whichever size the handles last chose. The widget stays
    // content-sized instead, which is also why this root must not
    // `anchors.fill: parent` - the host derives its own size from this one, so
    // anchoring is a binding loop (see PluginNode.qml). All three sizes are
    // unchanged from the built-in and every one is a whole 12px step
    // (132 = 11x12, 276 = 23x12, 120 = 10x12, 252 = 21x12), so the widget still
    // tiles flush beside grid widgets. See docs/widget-grid.md.
    property string sizeMode: PluginState.option("calendar", "sizeMode", "2x2")

    // The handles assign `sizeMode` directly for live feedback, which breaks
    // the binding above on purpose (the same trade custom-image makes), so
    // persisting has to write the property as well as the option.
    function setSizeMode(mode) {
        root.sizeMode = mode;
        PluginState.setOption("calendar", "sizeMode", mode);
    }

    property real widgetWidth: {
        switch (root.sizeMode) {
        case "1x1":
            return snapWidth1;
        case "1x2":
            return snapWidth2;
        default:
            return snapWidth3;
        }
    }

    property int monthShift: 0
    readonly property var today: new Date()

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

        let cells = [];
        for (let i = 0; i < startOffset; i++)
            cells.push({
                day: daysInPrevMonth - startOffset + i + 1,
                currentMonth: false,
                isToday: false
            });

        for (let d = 1; d <= daysInMonth; d++) {
            const isToday = monthShift === 0 && d === today.getDate() && month === today.getMonth() && year === today.getFullYear();
            cells.push({
                day: d,
                currentMonth: true,
                isToday: isToday
            });
        }

        let nextDay = 1;
        while (cells.length < 42) {
            cells.push({
                day: nextDay++,
                currentMonth: false,
                isToday: false
            });
        }

        let weeks = [];
        for (let i = 0; i < cells.length; i += 7)
            weeks.push(cells.slice(i, i + 7));
        return weeks;
    }

    function getCurrentWeek() {
        const matrix = getMonthMatrix(viewingDate);
        for (let w = 0; w < matrix.length; w++) {
            if (matrix[w].some(c => c.isToday))
                return matrix[w];
        }
        return matrix[0];
    }

    property var weeks: getMonthMatrix(viewingDate)

    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight

    Behavior on widgetWidth {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    // The host (PluginWidget) is the MouseArea that drags this widget; a
    // HoverHandler reads hover without taking press events away from it.
    HoverHandler {
        id: widgetHover
    }

    component DayCell: Rectangle {
        id: dayCell
        property int day: 0
        property bool currentMonth: true
        property bool isToday: false
        property bool bold: false
        // Set by the caller so today's pill frosts with the rest of the card.
        property color highlightColor: Appearance.colors.colPrimary

        implicitWidth: 28
        implicitHeight: 28
        radius: Appearance.rounding.full
        color: dayCell.isToday ? dayCell.highlightColor : "transparent"

        StyledText {
            anchors.centerIn: parent
            text: dayCell.day
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: dayCell.bold || dayCell.isToday ? Font.Bold : Font.Normal
            color: dayCell.isToday ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
            opacity: dayCell.currentMonth ? 1.0 : 0.3
        }
    }

    Rectangle {
        id: card
        implicitWidth: root.widgetWidth
        implicitHeight: root.sizeMode === "1x1" ? root.cardHeight : root.sizeMode === "1x2" ? root.cardHeight : root.cardHeight * 2 + root.cardSpacing
        radius: Appearance.rounding?.verylarge ?? 30
        color: root.tinted(Appearance.colors.colPrimaryContainer)

        StyledRectangularShadow {
            target: card
            z: -2
        }

        Loader {
            anchors.fill: parent
            sourceComponent: {
                if (root.sizeMode === "1x1")
                    return oneByOneContent;
                if (root.sizeMode === "1x2")
                    return oneByTwoContent;
                return twoByTwoContent;
            }
        }

        // 1x1
        Component {
            id: oneByOneContent
            Rectangle {
                anchors.fill: parent
                radius: card.radius
                color: "transparent"

                ColumnLayout {
                    anchors {
                        fill: parent
                        margins: 0
                    }
                    spacing: 0

                    Rectangle {
                        id: todayBanner
                        Layout.fillWidth: true
                        implicitHeight: todayBanner.parent.height * 0.35
                        color: root.tinted(Appearance.colors.colPrimary)
                        topLeftRadius: card.radius
                        topRightRadius: card.radius

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: Appearance.spacing.space50
                            StyledText {
                                text: root.today.toLocaleDateString(Qt.locale(), "MMM").toUpperCase()
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnPrimary
                            }
                            StyledText {
                                text: root.today.toLocaleDateString(Qt.locale(), "ddd").toUpperCase()
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnPrimary
                                opacity: 0.7
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        StyledText {
                            anchors.centerIn: parent
                            text: root.today.getDate()
                            font.pixelSize: 60
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }
                }
            }
        }

        // 1x2
        Component {
            id: oneByTwoContent
            ColumnLayout {
                anchors {
                    fill: parent
                    margins: 14
                }
                spacing: Appearance.spacing.space100

                Rectangle {
                    Layout.leftMargin: Appearance.spacing.space50
                    implicitHeight: 28
                    implicitWidth: monthText.implicitWidth + 20
                    radius: Appearance.rounding.full
                    color: root.tinted(Appearance.colors.colPrimary)

                    StyledText {
                        id: monthText
                        anchors.centerIn: parent
                        text: root.today.toLocaleDateString(Qt.locale(), "MMMM yyyy")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnPrimary
                    }
                }

                Grid {
                    columns: 7
                    rowSpacing: Appearance.spacing.space50
                    columnSpacing: 0
                    Layout.fillWidth: true
                    Layout.topMargin: Appearance.spacing.space50

                    Repeater {
                        model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                        delegate: Item {
                            id: weekdayHeaderCell
                            required property var modelData
                            implicitWidth: (card.implicitWidth - 28) / 7
                            implicitHeight: 20
                            StyledText {
                                anchors.centerIn: parent
                                text: weekdayHeaderCell.modelData
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnPrimaryContainer
                                opacity: 0.5
                            }
                        }
                    }

                    Repeater {
                        model: root.getCurrentWeek()
                        delegate: Item {
                            id: weekDayCell
                            required property var modelData
                            implicitWidth: (card.implicitWidth - 28) / 7
                            implicitHeight: 28

                            Rectangle {
                                anchors.centerIn: parent
                                width: 28
                                height: 28
                                radius: Appearance.rounding.full
                                color: weekDayCell.modelData.isToday ? root.tinted(Appearance.colors.colPrimary) : "transparent"

                                StyledText {
                                    anchors.centerIn: parent
                                    text: weekDayCell.modelData.day
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: weekDayCell.modelData.isToday ? Font.Bold : Font.Normal
                                    color: weekDayCell.modelData.isToday ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
                                    opacity: weekDayCell.modelData.currentMonth ? 1.0 : 0.3
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillHeight: true
                }
            }
        }

        // 2x2
        Component {
            id: twoByTwoContent
            ColumnLayout {
                anchors {
                    fill: parent
                    margins: Appearance.spacing.space200
                }
                spacing: Appearance.spacing.space50

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.spacing.space50

                    StyledText {
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnPrimaryContainer
                        text: root.viewingDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")
                    }

                    Rectangle {
                        implicitWidth: 26
                        implicitHeight: 26
                        radius: Appearance.rounding.full
                        color: "transparent"
                        border.width: Appearance.borderWidth.standard
                        border.color: Appearance.colors.colPrimary
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "chevron_left"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.monthShift--
                        }
                    }

                    Rectangle {
                        implicitWidth: 26
                        implicitHeight: 26
                        radius: Appearance.rounding.full
                        color: "transparent"
                        border.width: Appearance.borderWidth.standard
                        border.color: Appearance.colors.colPrimary
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "chevron_right"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.monthShift++
                        }
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Appearance.spacing.space50
                    Repeater {
                        model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                        delegate: StyledText {
                            id: weekdayHeader
                            required property var modelData
                            Layout.preferredWidth: 28
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnPrimaryContainer
                            opacity: 0.6
                            text: weekdayHeader.modelData
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: root.tinted(Appearance.colors.colLayer1)
                    radius: (Appearance.rounding?.verylarge ?? 30) - 8

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: -Appearance.spacing.space50

                        Repeater {
                            model: root.weeks
                            delegate: RowLayout {
                                id: weekRow
                                required property var modelData
                                spacing: Appearance.spacing.space50
                                Repeater {
                                    model: weekRow.modelData
                                    delegate: DayCell {
                                        id: dayOfMonth
                                        required property var modelData
                                        day: dayOfMonth.modelData.day
                                        currentMonth: dayOfMonth.modelData.currentMonth
                                        isToday: dayOfMonth.modelData.isToday
                                        highlightColor: root.tinted(Appearance.colors.colPrimary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: resizeHandle
            width: 16
            height: 16
            radius: Appearance.rounding.unsharpenslight
            color: Appearance.colors.colOnPrimaryContainer
            anchors {
                right: card.right
                bottom: card.bottom
                margins: Appearance.spacing.space50
            }
            opacity: (widgetHover.hovered || resizeArea.containsMouse || resizeArea.pressed) ? 0.5 : 0
            visible: opacity > 0 && !Config.options.background.widgetsLocked
            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFaster.duration
                }
            }

            MouseArea {
                id: resizeArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.SizeHorCursor
                preventStealing: true
                property real startWidth: 0
                property real startX: 0
                onPressed: mouse => {
                    resizeArea.startWidth = root.widgetWidth;
                    resizeArea.startX = resizeArea.mapToItem(null, mouse.x, mouse.y).x;
                }
                onPositionChanged: mouse => {
                    if (!resizeArea.pressed)
                        return;
                    var globalX = resizeArea.mapToItem(null, mouse.x, mouse.y).x;
                    var dx = globalX - resizeArea.startX;
                    var newW = resizeArea.startWidth + dx;
                    var mid = (root.snapWidth1 + root.snapWidth2) / 2;
                    if (newW < mid)
                        root.sizeMode = "1x1";
                    else if (root.sizeMode === "1x1")
                        root.sizeMode = "2x2";
                }
                onReleased: root.setSizeMode(root.sizeMode)
            }
        }

        Rectangle {
            id: toggleHandle
            width: 16
            height: 16
            radius: Appearance.rounding.unsharpenslight
            color: Appearance.colors.colOnPrimaryContainer
            anchors {
                left: card.left
                bottom: card.bottom
                margins: Appearance.spacing.space50
            }
            opacity: (widgetHover.hovered || toggleArea.containsMouse) && root.sizeMode !== "1x1" ? 0.5 : 0
            visible: opacity > 0 && !Config.options.background.widgetsLocked
            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFaster.duration
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.sizeMode === "1x2" ? "calendar_view_month" : "calendar_view_week"
                iconSize: 11
                color: Appearance.colors.colPrimaryContainer
            }

            MouseArea {
                id: toggleArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setSizeMode(root.sizeMode === "2x2" ? "1x2" : "2x2")
            }
        }
    }
}
