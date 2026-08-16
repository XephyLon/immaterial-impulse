pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.plugins
import "../../designsystem/widgets" as Expressive
import "calendar_geometry.js" as Geometry

Item {
    id: root

    // The host's resolved lock (PluginNode forwards AbstractBackgroundWidget's
    // `interactionLocked`). The grips below gate on this, not on the global
    // `background.widgetsLocked` they used to read: a widget pinned on its own
    // was still resizable, so the lock held for dragging and not for the two
    // handles that change the widget's size. False when there is no host at all
    // (a bare `qs -p` probe of this file), same as `screenName: ""`.
    property bool hostInteractionLocked: false

    // Set by the host while this widget is being dragged, and handed straight
    // to the card: the shadow lifts on hover and lifts further on a drag, and
    // a link that forgets to forward this produces a card that silently never
    // rises (tests/test_expressive_design_system.py pins the chain).
    property bool hostDragging: false
    // Set by the host while its own box is animating; the cards drop their
    // shadow for the duration rather than re-blurring into a resizing FBO.
    // It is always false here - the host only animates a box it sizes itself,
    // and this widget declares no `grid` - so the widget publishes its own
    // `boxInMotion` below and the card takes both.
    property bool hostBoxInMotion: false

    // The card fills the whole widget, so the host's default frost region has
    // the right extent - but not the right corner radius (PluginWidget falls
    // back to `Appearance.rounding.large`, 7px tighter than the card's own),
    // which would leave blurred slivers outside the four corners. The record
    // comes from the card itself, so the widget cannot disagree with its own
    // surface about where the frost goes.
    readonly property bool blurEnabled: PluginState.option("calendar", "blurEnabled", false)
    readonly property real backgroundOpacity: PluginState.effectiveBackgroundOpacity("calendar")
    readonly property bool managesBlurTint: true
    readonly property var blurRegions: [card.blurRegion]

    // The card's own surface is the card's business now; this stays for the
    // surfaces drawn *inside* it - the month band, the month pill, the day
    // grid and today's highlight - which thin with the card so the frost
    // reads through the whole widget rather than through its edges only.
    // `transparentize` rather than the card's `applyAlpha` because two of
    // those colours (colLayer1 most of all) already carry an alpha that the
    // widget must scale, not overwrite.
    function tinted(surfaceColor) {
        return root.blurEnabled ? ColorUtils.transparentize(surfaceColor, 1 - root.backgroundOpacity) : surfaceColor;
    }

    // Every size is a real component-grid span rather than a pixel literal, so
    // the three modes land on the lattice and follow effectiveScale.
    // See docs/widget-grid.md.
    readonly property real snapWidth1: Appearance.sizes.widgetGridSpanX(1)   // 132
    readonly property real snapWidth2: Appearance.sizes.widgetGridSpanX(2)   // 276
    readonly property real shortHeight: Appearance.sizes.widgetGridSpanY(1)  // 108
    readonly property real tallHeight: Appearance.sizes.widgetGridSpanY(2)   // 228

    // The corner handle resizes this widget and the opposite handle flips the
    // wide size between a month and a week, so the manifest declares no `grid`:
    // a span is a fixed pixel size the host assigns on every load, and it would
    // overwrite whichever size the handles last chose. The widget stays
    // content-sized instead, which is also why this root must not
    // `anchors.fill: parent` - the host derives its own size from this one, so
    // anchoring is a binding loop (see PluginNode.qml).
    //
    // The wide-short mode was called "1x2" while being two columns by one row,
    // and every mode was 120 tall on the assumption of a 120px cell - the cell
    // is 108. Normalising on read maps the legacy string onto the mode it
    // actually described; without it "1x2" falls through the switch default
    // below and silently promotes the user's week strip to the full month.
    function normalizeSizeMode(mode) {
        if (mode === "1x1")
            return "1x1";
        if (mode === "2x1" || mode === "1x2")
            return "2x1";
        return "2x2";
    }

    property string sizeMode: root.normalizeSizeMode(PluginState.option("calendar", "sizeMode", "2x2"))

    // The handles assign `sizeMode` directly for live feedback, which breaks
    // the binding above on purpose (the same trade custom-image makes), so
    // persisting has to write the property as well as the option.
    function setSizeMode(mode) {
        root.sizeMode = mode;
        PluginState.setOption("calendar", "sizeMode", mode);
    }

    // The month steppers only exist at 2x2, and the two smaller spans are both
    // about *today* - the hero date and the current week. Leaving a shift on
    // when the card shrinks would show a week of some other month with today's
    // date nowhere in it, and would leave the hero cell with no home at all.
    onSizeModeChanged: if (root.sizeMode !== "2x2") root.monthShift = 0

    // ---- the span, and the box travelling towards it ---------------------
    //
    // Geometry evaluates at the span's SETTLED box; the Behaviors below carry
    // the travel. Reading `implicitWidth` here instead would retarget every
    // element on every frame, and a Behavior whose target keeps moving never
    // converges (test_geometry_rects_come_from_the_settled_span_not_the_
    // animating_box).
    function spanWidthOf(span) {
        return span === "1x1" ? root.snapWidth1 : root.snapWidth2;
    }
    function spanHeightOf(span) {
        return span === "2x2" ? root.tallHeight : root.shortHeight;
    }
    readonly property real spanW: root.spanWidthOf(root.sizeMode)
    readonly property real spanH: root.spanHeightOf(root.sizeMode)
    readonly property real uiScale: Appearance.effectiveScale

    property real widgetWidth: root.spanW
    property real widgetHeight: root.spanH
    Behavior on widgetWidth { Expressive.SpanTravel {} }
    Behavior on widgetHeight { Expressive.SpanTravel {} }

    // The host publishes `boxInMotion` only for a box it sizes itself, and a
    // content-sized widget's box is this one - so the card would never drop its
    // shadow for the one motion that reallocates the layer every frame.
    readonly property bool boxInMotion: Math.abs(root.widgetWidth - root.spanW) > 0.5
        || Math.abs(root.widgetHeight - root.spanH) > 0.5

    implicitWidth: root.widgetWidth
    implicitHeight: root.widgetHeight

    // ---- the month matrix ------------------------------------------------

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
        while (cells.length < Geometry.CELLS)
            cells.push({
                day: nextDay++,
                currentMonth: false,
                isToday: false
            });
        return cells;
    }

    // A flat forty-two, because the cells are the shared elements: the same
    // delegate has to be the one in the month grid, the one in the week strip
    // and - for today's - the hero date. A model of six week rows would give
    // each span a different set of items to destroy and rebuild, which is the
    // whole thing this replaces.
    property var cells: root.getMonthMatrix(root.viewingDate)

    readonly property int todayIndex: {
        for (let i = 0; i < root.cells.length; i++)
            if (root.cells[i].isToday)
                return i;
        return -1;
    }
    // The row the 2x1 span keeps. Today's, whenever today is on the card at
    // all; the first otherwise, which is what the destroyed layout's
    // `getCurrentWeek()` fell back to.
    readonly property int weekRow: root.todayIndex >= 0
        ? Math.floor(root.todayIndex / Geometry.COLUMNS) : 0

    readonly property string monthLongText: root.viewingDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")

    // The pill hugs its label, so it needs the label's width at the pill's OWN
    // font rather than at the animating one a morph is part-way through. Same
    // component and so the same metrics, which a TextMetrics with hand-copied
    // font settings would only approximate.
    StyledText {
        id: monthPillRuler
        visible: false
        text: root.monthLongText
        font.pixelSize: Math.round(Geometry.MONTH_FONT_PILL * root.uiScale)
        font.weight: Font.Bold
    }

    // The host (PluginWidget) is the MouseArea that drags this widget; a
    // HoverHandler reads hover without taking press events away from it.
    HoverHandler {
        id: widgetHover
    }

    // The surface every other desktop widget already composes. It owns the
    // tint pair, the rounding (this widget's own `verylarge` was the token the
    // shared card's 30 had drifted from), the frost record above, and the drop
    // shadow with its hover and drag lift.
    //
    // `clipContent`, because a one-tree widget's elements do not stop existing
    // when the card shrinks past them: the day grid's surface and five of its
    // six rows fade out below a 2x1 card's bottom edge, and an unclipped fade
    // paints them onto the wallpaper for the length of the morph.
    //
    // No `tensionX`/`tensionY`: the manifest declares no `grid`, so the host
    // draws no resize grip here and there is never a bow to render.
    Expressive.WidgetCard {
        id: card
        anchors.fill: parent
        clipContent: true
        tint: Appearance.colors.colPrimaryContainer
        useBlurBackground: root.blurEnabled
        backgroundOpacity: root.backgroundOpacity
        dragging: root.hostDragging
        hostMotionActive: root.hostBoxInMotion || root.boxInMotion

        // ---- the month surface: the 1x1 band, the 2x1 pill ---------------
        //
        // One element with two homes and one absence. At 2x2 the month is a
        // plain title on the card, so the surface fades out where it stood
        // rather than travelling to a place it does not have.
        Rectangle {
            id: monthSurface
            readonly property bool present: root.sizeMode !== "2x2"
            readonly property string homeSpan: root.sizeMode === "2x2" ? "2x1" : root.sizeMode
            readonly property var slot: Geometry.monthSurfaceRect(
                monthSurface.homeSpan,
                root.spanWidthOf(monthSurface.homeSpan),
                root.spanHeightOf(monthSurface.homeSpan),
                root.uiScale,
                monthPillRuler.paintedWidth,
                card.radius)

            x: slot.x
            y: slot.y
            width: slot.width
            height: slot.height
            Behavior on x { Expressive.SpanTravel {} }
            Behavior on y { Expressive.SpanTravel {} }
            Behavior on width { Expressive.SpanTravel {} }
            Behavior on height { Expressive.SpanTravel {} }

            // The corners ARE the morph: a band whose top corners are the
            // card's own and whose bottom edge is square becomes a stadium.
            property real cornerTop: monthSurface.slot.radiusTop
            property real cornerBottom: monthSurface.slot.radiusBottom
            Behavior on cornerTop { Expressive.SpanTravel {} }
            Behavior on cornerBottom { Expressive.SpanTravel {} }
            topLeftRadius: monthSurface.cornerTop
            topRightRadius: monthSurface.cornerTop
            bottomLeftRadius: monthSurface.cornerBottom
            bottomRightRadius: monthSurface.cornerBottom

            color: root.tinted(Appearance.colors.colPrimary)
            opacity: monthSurface.present ? 1 : 0
            Behavior on opacity { Expressive.SpanFade {} }
            visible: opacity > 0

            // The band's own label, which says the month in short form beside
            // the weekday. It is not the long month name travelling in from
            // 2x1 - one element cannot swap its text mid-morph without a
            // content snap - so it is its own pair, riding the surface.
            Row {
                anchors.centerIn: parent
                spacing: Appearance.spacing.space50
                opacity: root.sizeMode === "1x1" ? 1 : 0
                Behavior on opacity { Expressive.SpanFade {} }
                visible: opacity > 0

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

        // ---- the long month name, out of the pill and up to the title ----
        StyledText {
            id: monthLabel
            objectName: "calendarMonthLabel"
            readonly property bool present: root.sizeMode !== "1x1"
            readonly property string homeSpan: root.sizeMode === "1x1" ? "2x2" : root.sizeMode
            readonly property var slot: Geometry.monthLabelRect(
                monthLabel.homeSpan,
                root.spanWidthOf(monthLabel.homeSpan),
                root.spanHeightOf(monthLabel.homeSpan),
                root.uiScale)

            x: slot.x
            y: slot.y
            height: slot.height
            Behavior on x { Expressive.SpanTravel {} }
            Behavior on y { Expressive.SpanTravel {} }
            Behavior on height { Expressive.SpanTravel {} }

            text: root.monthLongText
            font.pixelSize: Math.round(monthLabel.slot.size)
            Behavior on font.pixelSize { Expressive.SpanTravel {} }
            font.weight: root.sizeMode === "2x2" ? Font.Medium : Font.Bold
            Behavior on font.weight { Expressive.SpanTravel {} }
            color: root.sizeMode === "2x1"
                ? Appearance.colors.colOnPrimary
                : Appearance.colors.colOnPrimaryContainer
            Behavior on color { ColorAnimation { duration: Appearance.animation.elementMove.duration } }
            opacity: monthLabel.present ? 1 : 0
            Behavior on opacity { Expressive.SpanFade {} }
            visible: opacity > 0
        }

        // ---- the two month steppers, 2x2 only ----------------------------
        Repeater {
            model: 2
            delegate: Rectangle {
                id: navButton
                required property int index
                readonly property bool present: root.sizeMode === "2x2"
                readonly property var slot: Geometry.navButtonRect(
                    navButton.index, "2x2", root.snapWidth2, root.tallHeight, root.uiScale)

                x: slot.x
                y: slot.y
                width: slot.width
                height: slot.height
                Behavior on x { Expressive.SpanTravel {} }
                Behavior on y { Expressive.SpanTravel {} }

                radius: Appearance.rounding.full
                color: "transparent"
                border.width: Appearance.borderWidth.standard
                border.color: Appearance.colors.colPrimary
                opacity: navButton.present ? 1 : 0
                Behavior on opacity { Expressive.SpanFade {} }
                visible: opacity > 0

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: navButton.index === 0 ? "chevron_left" : "chevron_right"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnPrimaryContainer
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.monthShift += navButton.index === 0 ? -1 : 1
                }
            }
        }

        // ---- the seven weekday letters -----------------------------------
        Repeater {
            model: Geometry.COLUMNS
            delegate: StyledText {
                id: weekdayHeader
                required property int index
                readonly property bool present: root.sizeMode !== "1x1"
                readonly property string homeSpan: root.sizeMode === "1x1" ? "2x2" : root.sizeMode
                readonly property var slot: Geometry.weekdayHeaderRect(
                    weekdayHeader.index, weekdayHeader.homeSpan,
                    root.spanWidthOf(weekdayHeader.homeSpan),
                    root.spanHeightOf(weekdayHeader.homeSpan),
                    root.uiScale)

                x: slot.x
                y: slot.y
                width: slot.width
                height: slot.height
                Behavior on x { Expressive.SpanTravel {} }
                Behavior on y { Expressive.SpanTravel {} }
                Behavior on width { Expressive.SpanTravel {} }

                horizontalAlignment: Text.AlignHCenter
                text: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"][weekdayHeader.index]
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: Appearance.colors.colOnPrimaryContainer
                opacity: weekdayHeader.present ? (root.sizeMode === "2x2" ? 0.6 : 0.5) : 0
                Behavior on opacity { Expressive.SpanFade {} }
                visible: opacity > 0
            }
        }

        // ---- the surface the month grid is drawn on, 2x2 only ------------
        Rectangle {
            id: dayGridSurface
            readonly property var slot: Geometry.dayGridSurfaceRect(
                "2x2", root.snapWidth2, root.tallHeight, root.uiScale, card.radius)

            x: slot.x
            y: slot.y
            width: slot.width
            height: slot.height
            radius: slot.radius
            color: root.tinted(Appearance.colors.colLayer1)
            opacity: root.sizeMode === "2x2" ? 1 : 0
            Behavior on opacity { Expressive.SpanFade {} }
            visible: opacity > 0
        }

        // ---- the forty-two day cells -------------------------------------
        //
        // The morph itself. Every cell has a home at 2x2; the current week's
        // seven travel up into the 2x1 row while the other thirty-five fade
        // where they stand; and at 1x1 today's alone survives, growing into
        // the hero date as its highlight shrinks away under it.
        Repeater {
            model: Geometry.CELLS
            delegate: Item {
                id: dayCell
                required property int index
                readonly property var cell: root.cells[dayCell.index]
                readonly property var slot: Geometry.dayCellRect(
                    dayCell.index, root.sizeMode, root.spanW, root.spanH,
                    root.uiScale, root.weekRow, root.todayIndex)
                readonly property bool present: dayCell.slot !== null
                // A fade happens where the element stands, so a cell with no
                // home still needs somewhere to be - and 2x2 is where every
                // cell has one, which is also the span the corner handle
                // reaches from 1x1.
                readonly property var homeSlot: dayCell.present ? dayCell.slot
                    : Geometry.dayCellRect(dayCell.index, "2x2", root.snapWidth2,
                        root.tallHeight, root.uiScale, root.weekRow, root.todayIndex)

                x: homeSlot.x
                y: homeSlot.y
                width: homeSlot.width
                height: homeSlot.height
                Behavior on x { Expressive.SpanTravel {} }
                Behavior on y { Expressive.SpanTravel {} }
                Behavior on width { Expressive.SpanTravel {} }
                Behavior on height { Expressive.SpanTravel {} }
                opacity: dayCell.present ? 1 : 0
                Behavior on opacity { Expressive.SpanFade {} }
                visible: opacity > 0

                // Today's highlight, which is a box rather than a flag: on the
                // way to the hero date it shrinks to nothing under the growing
                // number instead of blinking off at the far end of the morph.
                Rectangle {
                    id: todayPill
                    property real pill: dayCell.homeSlot.pill
                    Behavior on pill { Expressive.SpanTravel {} }
                    anchors.centerIn: parent
                    width: todayPill.pill
                    height: todayPill.pill
                    radius: Appearance.rounding.full
                    color: root.tinted(Appearance.colors.colPrimary)
                    visible: dayCell.cell.isToday && todayPill.pill > 0.5
                }

                StyledText {
                    anchors.centerIn: parent
                    text: dayCell.cell.day
                    font.pixelSize: Math.round(dayCell.homeSlot.size)
                    Behavior on font.pixelSize { Expressive.SpanTravel {} }
                    font.weight: dayCell.cell.isToday ? Font.Bold : Font.Normal
                    // Off the SETTLED slot, not off the shrinking pill: keyed
                    // on the live one the ink would hold its on-primary colour
                    // over a highlight that is already most of the way gone,
                    // and flip in the last frames of the morph.
                    color: dayCell.cell.isToday && dayCell.present && dayCell.slot.pill > 0
                        ? Appearance.colors.colOnPrimary
                        : Appearance.colors.colOnPrimaryContainer
                    Behavior on color { ColorAnimation { duration: Appearance.animation.elementMove.duration } }
                    opacity: dayCell.cell.currentMonth ? 1.0 : 0.3
                }
            }
        }

        Rectangle {
            id: resizeHandle
            width: 16
            height: 16
            radius: Appearance.rounding.unsharpenslight
            color: Appearance.colors.colOnPrimaryContainer
            // The card routes its children into its own content item, so the
            // handles anchor to that rather than reaching back up to `card` -
            // an anchor may only name a parent or a sibling. It fills the
            // card, so the corner is the same corner.
            anchors {
                right: parent.right
                bottom: parent.bottom
                margins: Appearance.spacing.space50
            }
            opacity: (widgetHover.hovered || resizeArea.containsMouse || resizeArea.pressed) ? 0.5 : 0
            visible: opacity > 0 && !root.hostInteractionLocked
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
                    // The SETTLED width, never the animating one: a press
                    // landing mid-morph would otherwise measure the gesture
                    // against a box that is still moving.
                    resizeArea.startWidth = root.spanW;
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
                left: parent.left
                bottom: parent.bottom
                margins: Appearance.spacing.space50
            }
            opacity: (widgetHover.hovered || toggleArea.containsMouse) && root.sizeMode !== "1x1" ? 0.5 : 0
            visible: opacity > 0 && !root.hostInteractionLocked
            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFaster.duration
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.sizeMode === "2x1" ? "calendar_view_month" : "calendar_view_week"
                iconSize: 11
                color: Appearance.colors.colPrimaryContainer
            }

            MouseArea {
                id: toggleArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setSizeMode(root.sizeMode === "2x2" ? "2x1" : "2x2")
            }
        }
    }
}
