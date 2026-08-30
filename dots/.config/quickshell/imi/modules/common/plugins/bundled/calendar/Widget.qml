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
    // The manifest declares a grid now, so the box is the host's.
    property bool hostBoxInMotion: false

    // The span the host resolved (docs/widget-grid.md): the stored choice,
    // then the manifest default. Empty until the host answers, and for a
    // bare `qs -p` probe of this file.
    property string hostGridSize: ""
    // This tree has no destroy on a span change - every element travels or
    // fades on its own Behaviors - so the host's midpoint cross-fade would
    // be a dissolve on top of a morph (the media widget's reasoning).
    readonly property bool handlesSpanTransition: true

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
    readonly property real snapWidth3: Appearance.sizes.widgetGridSpanX(3)   // 420
    readonly property real shortHeight: Appearance.sizes.widgetGridSpanY(1)  // 108
    readonly property real tallHeight: Appearance.sizes.widgetGridSpanY(2)   // 228

    // The manifest offers four spans, so the size is the HOST's
    // (`__gridSize`: the grip, the Size row and the edit-menu stepper are
    // its three faces) and the two corner handles this widget carried are
    // gone with the option they wrote. The old stored `sizeMode` is folded
    // into `__gridSize` by gridSizes.migrateSizeMode the moment the manifest
    // offers more than one span - which is now.
    //
    // Normalising still guards the probe's empty string and any span this
    // manifest stops offering: an unknown mode falls to the default rather
    // than to a branch nothing draws.
    function normalizeSizeMode(mode) {
        if (mode === "1x1" || mode === "2x1" || mode === "3x2")
            return mode;
        return "2x2";
    }

    readonly property string sizeMode: root.normalizeSizeMode(root.hostGridSize)

    // The month steppers exist at the two spans that show a whole month
    // (2x2, 3x2); the two smaller spans are about *today* - the hero date
    // and the current week. Leaving a shift on when the card shrinks to
    // them would show a week of some other month with today's date nowhere
    // in it.
    onSizeModeChanged: {
        if (root.sizeMode !== "2x2" && root.sizeMode !== "3x2")
            root.monthShift = 0;
    }

    // ---- the span, and the box travelling towards it ---------------------
    //
    // Geometry evaluates at the span's SETTLED box; the Behaviors below carry
    // the travel. Reading `implicitWidth` here instead would retarget every
    // element on every frame, and a Behavior whose target keeps moving never
    // converges (test_geometry_rects_come_from_the_settled_span_not_the_
    // animating_box).
    function spanWidthOf(span) {
        return span === "1x1" ? root.snapWidth1
            : span === "3x2" ? root.snapWidth3 : root.snapWidth2;
    }
    function spanHeightOf(span) {
        return span === "2x2" || span === "3x2" ? root.tallHeight : root.shortHeight;
    }
    readonly property real spanW: root.spanWidthOf(root.sizeMode)
    readonly property real spanH: root.spanHeightOf(root.sizeMode)
    readonly property real uiScale: Appearance.effectiveScale

    // The box is the host's now (the manifest declares a grid): it animates
    // between spans and publishes hostBoxInMotion for the length of it. The
    // implicit size is the settled span - a fallback for a bare probe; the
    // host sizes the node to its own animating box.
    implicitWidth: root.spanW
    implicitHeight: root.spanH

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
    // The band pair's centring, off the settled short forms - same reasoning
    // as the pill ruler: the pair must centre at the band's OWN metrics, not
    // at whatever the travelling elements currently measure.
    StyledText {
        id: monthShortRuler
        visible: false
        text: root.today.toLocaleDateString(Qt.locale(), "MMM").toUpperCase()
        font.pixelSize: Math.round(Geometry.MONTH_FONT_PILL * root.uiScale)
        font.weight: Font.Bold
    }
    StyledText {
        id: weekdayShortRuler
        visible: false
        text: root.today.toLocaleDateString(Qt.locale(), "ddd").toUpperCase()
        font.pixelSize: Math.round(Geometry.MONTH_FONT_PILL * root.uiScale)
        font.weight: Font.Bold
    }
    readonly property real bandPairGap: Appearance.spacing.space50
    readonly property real bandPairX: (root.snapWidth1
        - (monthShortRuler.paintedWidth + root.bandPairGap + weekdayShortRuler.paintedWidth)) / 2

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
        hostMotionActive: root.hostBoxInMotion

        // ---- the month surface: the 1x1 band, the 2x1 pill ---------------
        //
        // One element with two homes and one absence. At 2x2 the month is a
        // plain title on the card, so the surface fades out where it stood
        // rather than travelling to a place it does not have.
        Rectangle {
            id: monthSurface
            readonly property bool present: root.sizeMode === "1x1" || root.sizeMode === "2x1"
            readonly property string homeSpan: monthSurface.present ? root.sizeMode : "2x1"
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

        }

        // ---- THE month text: one element, a home at every span ------------
        //
        // The maintainer's rule: an element is never hidden and replaced by
        // another with the same purpose - it morphs to fit the layout. So
        // the band's short form, the pill label, the 2x2 title and the hero
        // column's small caps are ONE StyledText whose position, size and
        // ink travel, and whose SPELLING follows the span (a rewrite at the
        // commit, inside one moving element - not two elements crossfading).
        StyledText {
            id: monthText
            objectName: "calendarMonthLabel"
            readonly property var slot: Geometry.monthTextRect(
                root.sizeMode, root.spanW, root.spanH, root.uiScale)

            x: slot.form === "short" ? root.bandPairX : slot.x
            y: slot.y
            height: slot.height
            Behavior on x { Expressive.SpanTravel {} }
            Behavior on y { Expressive.SpanTravel {} }
            Behavior on height { Expressive.SpanTravel {} }
            verticalAlignment: Text.AlignVCenter

            text: monthText.slot.form === "short"
                ? root.today.toLocaleDateString(Qt.locale(), "MMM").toUpperCase()
                : monthText.slot.form === "hero"
                    ? root.viewingDate.toLocaleDateString(Qt.locale(), "MMMM").toUpperCase()
                    : root.monthLongText
            font.pixelSize: Math.round(monthText.slot.size)
            Behavior on font.pixelSize { Expressive.SpanTravel {} }
            font.weight: root.sizeMode === "2x2" ? Font.Medium : Font.Bold
            Behavior on font.weight { Expressive.SpanTravel {} }
            color: root.sizeMode === "2x1" || root.sizeMode === "1x1"
                ? Appearance.colors.colOnPrimary
                : Appearance.colors.colOnPrimaryContainer
            Behavior on color {
                ColorAnimation {
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }
            opacity: monthText.slot.form === "hero" ? 0.6 : 1
            Behavior on opacity { Expressive.SpanFade {} }
        }

        // ---- the weekday name: the band's "SUN", the hero's "Sunday" ------
        StyledText {
            id: weekdayText
            readonly property bool present: root.sizeMode === "1x1" || root.sizeMode === "3x2"
            // Fades where it last stood: a fixed fallback home would march
            // it across the card before disappearing.
            property string lastHome: "1x1"
            onPresentChanged: if (present) weekdayText.lastHome = root.sizeMode
            Component.onCompleted: if (present) weekdayText.lastHome = root.sizeMode
            readonly property string homeSpan: weekdayText.present ? root.sizeMode : weekdayText.lastHome
            readonly property var slot: Geometry.weekdayTextRect(
                weekdayText.homeSpan,
                root.spanWidthOf(weekdayText.homeSpan),
                root.spanHeightOf(weekdayText.homeSpan),
                root.uiScale)

            x: slot.form === "short"
                ? root.bandPairX + monthShortRuler.paintedWidth + root.bandPairGap
                : slot.x
            y: slot.y
            height: slot.height
            Behavior on x { Expressive.SpanTravel {} }
            Behavior on y { Expressive.SpanTravel {} }
            Behavior on height { Expressive.SpanTravel {} }
            verticalAlignment: Text.AlignVCenter

            text: weekdayText.slot.form === "short"
                ? root.today.toLocaleDateString(Qt.locale(), "ddd").toUpperCase()
                : root.today.toLocaleDateString(Qt.locale(), "dddd")
            font.pixelSize: Math.round(weekdayText.slot.size)
            Behavior on font.pixelSize { Expressive.SpanTravel {} }
            font.weight: weekdayText.slot.form === "short" ? Font.Bold : Font.Medium
            color: root.sizeMode === "1x1"
                ? Appearance.colors.colOnPrimary
                : Appearance.colors.colOnPrimaryContainer
            Behavior on color {
                ColorAnimation {
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }
            opacity: weekdayText.present ? (weekdayText.slot.form === "short" ? 0.7 : 1) : 0
            Behavior on opacity { Expressive.SpanFade {} }
            visible: opacity > 0
        }

        // ---- TODAY, written large: one hero from 1x1 to 3x2 ---------------
        //
        // Its fade-home is today's own grid cell (heroDayRect), so leaving
        // 1x1 for 2x2 still reads as the big date shrinking into its circle
        // - and the element doing it is the same one the 3x2 shows, never a
        // twin.
        StyledText {
            id: heroDay
            readonly property var slot: Geometry.heroDayRect(
                root.sizeMode, root.spanW, root.spanH, root.uiScale,
                root.weekRow, root.todayIndex)

            x: slot.x
            y: slot.y
            width: slot.width
            height: slot.height
            Behavior on x { Expressive.SpanTravel {} }
            Behavior on y { Expressive.SpanTravel {} }
            Behavior on width { Expressive.SpanTravel {} }
            Behavior on height { Expressive.SpanTravel {} }

            text: root.today.getDate()
            font.pixelSize: Math.round(heroDay.slot.size)
            Behavior on font.pixelSize { Expressive.SpanTravel {} }
            font.weight: Font.Medium
            color: Appearance.colors.colOnPrimaryContainer
            horizontalAlignment: root.sizeMode === "3x2" ? Text.AlignLeft : Text.AlignHCenter
            verticalAlignment: root.sizeMode === "3x2" ? Text.AlignTop : Text.AlignVCenter
            opacity: heroDay.slot.present ? 1 : 0
            Behavior on opacity { Expressive.SpanFade {} }
            visible: opacity > 0
        }

        // ---- the two month steppers: the title row's pair, and the hero
        // column's - one pair, travelling between its two homes ------------
        Repeater {
            model: 2
            delegate: Rectangle {
                id: navButton
                required property int index
                readonly property bool present: root.sizeMode === "2x2" || root.sizeMode === "3x2"
                property string lastHome: "2x2"
                onPresentChanged: if (present) navButton.lastHome = root.sizeMode
                Component.onCompleted: if (present) navButton.lastHome = root.sizeMode
                readonly property string homeSpan: navButton.present ? root.sizeMode : navButton.lastHome
                readonly property var slot: Geometry.navButtonRect(
                    navButton.index, navButton.homeSpan,
                    root.spanWidthOf(navButton.homeSpan),
                    root.spanHeightOf(navButton.homeSpan), root.uiScale)

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
                    Behavior on color {
                        ColorAnimation {
                            duration: Appearance.animation.elementMove.duration
                            easing.type: Appearance.animation.elementMove.type
                            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                        }
                    }
                    opacity: dayCell.cell.currentMonth ? 1.0 : 0.3
                }
            }
        }

        // ---- the 3x2 hero column: today, written large ---------------------
        //
        // Four elements with one home each (the maintainer's reference
        // shot): the icon-in-shape, the month in small caps, the weekday,
        // and the big date. They fade in place - nothing at another span
        // morphs into them, and today's GRID cell keeps its own circled
        // home on the surface beside them.
        MaterialShapeWrappedMaterialSymbol {
            readonly property var slot: Geometry.heroRect("chip", "3x2",
                root.snapWidth3, root.tallHeight, root.uiScale)
            x: slot.x
            y: slot.y
            width: slot.width
            height: slot.height
            wrappedShape: MaterialShape.Shape.Cookie12Sided
            colSymbol: root.tinted(Appearance.colors.colPrimary)
            color: Appearance.colors.colOnPrimary
            text: "calendar_month"
            iconSize: slot.height * 0.5
            opacity: root.sizeMode === "3x2" ? 1 : 0
            Behavior on opacity { Expressive.SpanFade {} }
            visible: opacity > 0
        }

    }
}
