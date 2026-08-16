pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.plugins
import qs.modules.common.plugins.designsystem.widgets as Expressive
import "world_clock_geometry.js" as Geometry

Item {
    id: root

    // The host's resolved lock (PluginNode forwards AbstractBackgroundWidget's
    // `interactionLocked`). The size-toggle handle gates on this rather than on
    // the global `background.widgetsLocked` it used to read, so a widget the
    // user pinned on its own cannot still be reshaped. False with no host, for
    // a bare `qs -p` probe of this file, the same as `screenName: ""`.
    property bool hostInteractionLocked: false

    // The host's drag, forwarded to the card so it lifts while it is handled.
    // A card never told about the drag silently never lifts.
    property bool hostDragging: false
    // ...and the host's own box animation, which is always false here: the
    // host only reports motion for a box it sizes itself, and this widget
    // declares no `grid`. It publishes its own `boxInMotion` below.
    property bool hostBoxInMotion: false

    // The card fills the whole widget, so the host's default region already has
    // the right extent - but not the right corner radius (it falls back to
    // `Appearance.rounding.large`, 7px tighter than the card's `verylarge`),
    // which would leave frosted slivers outside the four corners. Naming the
    // card is the only way to hand the host its actual radius, and `blurRegion`
    // is the record WidgetCard builds for exactly that.
    readonly property bool blurEnabled: PluginState.option("world-clock", "blurEnabled", false)
    readonly property real backgroundOpacity: PluginState.effectiveBackgroundOpacity("world-clock")
    readonly property bool managesBlurTint: true
    readonly property var blurRegions: [contentRect.blurRegion]

    function tinted(surfaceColor) {
        return root.blurEnabled
            ? ColorUtils.transparentize(surfaceColor, 1 - root.backgroundOpacity)
            : surfaceColor;
    }

    // The corner handle switches the widget between a 2x2 card and a 3x1 row of
    // dials, so the manifest can declare no `grid`: a span is a fixed pixel size
    // the host assigns, and it would overwrite the toggled size on every load.
    // The widget stays content-sized instead, which is also why its root must
    // not `anchors.fill: parent` (PluginNode derives its own size from this
    // one - anchoring is a binding loop). Both sizes come from the component
    // grid helpers rather than pixel literals, so they land on the lattice and
    // follow effectiveScale. See docs/widget-grid.md.
    //
    // The wide mode was called "4x1" and sized 420x120, but 420 is spanX(3) and
    // no row is 120 tall - the grid cell is 132x108. Normalising on read keeps
    // an install that persisted "4x1" on the same mode; without it the string
    // matches neither branch and the card renders empty with no error.
    function normalizeSizeMode(mode) {
        return (mode === "3x1" || mode === "4x1") ? "3x1" : "2x2";
    }

    property string sizeMode: root.normalizeSizeMode(PluginState.option("world-clock", "sizeMode", "2x2"))

    // ---- the span, and the box travelling towards it ---------------------
    //
    // Geometry evaluates at the span's SETTLED box; the Behaviors below carry
    // the travel. Reading `implicitWidth` here instead would retarget every
    // element on every frame, and a Behavior whose target keeps moving never
    // converges (test_geometry_rects_come_from_the_settled_span_not_the_
    // animating_box).
    function spanWidthOf(span) {
        return span === "3x1"
            ? Appearance.sizes.widgetGridSpanX(3) : Appearance.sizes.widgetGridSpanX(2);
    }
    function spanHeightOf(span) {
        return span === "3x1"
            ? Appearance.sizes.widgetGridSpanY(1) : Appearance.sizes.widgetGridSpanY(2);
    }
    readonly property real spanW: root.spanWidthOf(root.sizeMode)
    readonly property real spanH: root.spanHeightOf(root.sizeMode)
    readonly property real uiScale: Appearance.effectiveScale

    property real widgetWidth: root.spanW
    property real widgetHeight: root.spanH
    Behavior on widgetWidth { Expressive.SpanTravel {} }
    Behavior on widgetHeight { Expressive.SpanTravel {} }

    readonly property bool boxInMotion: Math.abs(root.widgetWidth - root.spanW) > 0.5
        || Math.abs(root.widgetHeight - root.spanH) > 0.5

    implicitWidth: root.widgetWidth
    implicitHeight: root.widgetHeight

    // The card's own padding, shared by the 2x2 face and its settings back.
    // The wide mode deliberately does not use it - see world_clock_geometry.js.
    readonly property real cardInset: Appearance.spacing.space150

    property string localCityName: Weather.data?.city ?? "..."
    property string localTime: DateTime.time
    property string localDate: Qt.locale().toString(new Date(), "dddd, MMMM dd yyyy")
    // The timezone list lives in this plugin's own options, but the service
    // owns it rather than the widget: it feeds one offset process and one
    // shared model, and this component is instantiated once per monitor. The
    // pickers below therefore read and write it through WorldClock, not through
    // PluginState directly.
    property var worldCities: WorldClock.entries
    property bool showingSettings: false

    // The settings face is reachable only from the 2x2's own settings button,
    // and it is drawn at the 2x2 box. Leaving it up while the card becomes a
    // row of dials would show four timezone pickers inside a 108px strip.
    onSizeModeChanged: if (root.sizeMode !== "2x2") root.showingSettings = false

    function toggleFlip() { flipAnim.start() }

    // The host (PluginWidget) is the MouseArea that drags this widget; a
    // HoverHandler reads hover without taking press events away from it.
    HoverHandler {
        id: widgetHover
    }

    Item {
        id: cardWrapper
        anchors.fill: parent

        transform: Scale {
            id: flipScale
            origin.x: cardWrapper.width  / 2
            origin.y: cardWrapper.height / 2
            xScale: 1
        }

        SequentialAnimation {
            id: flipAnim
            NumberAnimation {
                target: flipScale; property: "xScale"
                to: 0; duration: Appearance.animation.elementMoveFaster.duration; easing.type: Easing.InQuad
            }
            ScriptAction {
                script: root.showingSettings = !root.showingSettings
            }
            NumberAnimation {
                target: flipScale; property: "xScale"
                to: 1; duration: Appearance.animation.elementMoveFaster.duration; easing.type: Easing.OutQuad
            }
        }

        // The one widget of the five that is genuinely card-shaped: a rounded
        // rectangle filling the widget with everything drawn inside it. It
        // takes the component rather than only the tokens, so its surface,
        // its rounding and its shadow are the ones every other card has.
        //
        // `clipContent`, because a one-tree widget's elements do not stop
        // existing when the card shrinks past them: the local time, the date
        // and the bottom row of chips all fade out below a 3x1 card's bottom
        // edge, and an unclipped fade paints them onto the wallpaper for the
        // length of the morph.
        Expressive.WidgetCard {
            id: contentRect
            anchors.fill: parent
            clipContent: true
            tint: Appearance.colors.colPrimaryContainer
            useBlurBackground: root.blurEnabled
            backgroundOpacity: root.backgroundOpacity
            dragging: root.hostDragging
            hostMotionActive: root.hostBoxInMotion || root.boxInMotion

            // ---- the 2x2's own chrome ------------------------------------
            //
            // Place, time and date have no home on a row of dials, so they
            // fade - and a fade happens where the element stands, which is why
            // this block is pinned to the 2x2 box rather than anchored to a
            // card that is on its way to 420x108. Anchored, it would reflow
            // through every intermediate size while fading out, which reads as
            // the text being squeezed rather than as it leaving.
            Item {
                id: localChrome
                width: root.spanWidthOf("2x2")
                height: root.spanHeightOf("2x2")
                opacity: (root.sizeMode === "2x2" && !root.showingSettings) ? 1 : 0
                Behavior on opacity { Expressive.SpanFade {} }
                visible: opacity > 0

                // Two steps of the scale: cardInset (space150) at the card
                // edge, space100 between the blocks inside it. The inset is
                // what keeps the four city chips clear of a 30px corner radius
                // - at the space100 it had, the bottom two chips ran into the
                // rounding.
                //
                // The local time is 36 rather than the 42 it was: at 42 the
                // content came to 234 in a 228 card and the bottom row of chips
                // sat 2px off the card edge. It is still 2.4x the largest text
                // under it, so it still reads as the hero.
                ColumnLayout {
                    id: mainColumn
                    anchors { fill: parent; margins: root.cardInset }
                    spacing: Appearance.spacing.space100

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Appearance.spacing.space50

                        MaterialSymbol {
                            iconSize: Appearance.font.pixelSize.hugeass
                            text: "location_on"
                            color: Appearance.colors.colOnPrimaryContainer
                            opacity: 0.6
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: -Appearance.spacing.space25
                            StyledText {
                                // Carries the weather provider's own city string, so
                                // it must not be parsed as markup.
                                textFormat: Text.PlainText
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnPrimaryContainer
                                text: root.localCityName
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            id: settingsButton
                            radius: Appearance.rounding.full
                            color: root.tinted(Appearance.colors.colSurfaceContainerLow)
                            implicitWidth: 24; implicitHeight: 24
                            MaterialSymbol {
                                anchors.centerIn: parent
                                iconSize: Appearance.font.pixelSize.normal
                                text: "settings"
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleFlip()
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignRight
                        spacing: -Appearance.spacing.space50
                        StyledText {
                            Layout.alignment: Qt.AlignRight
                            font.pixelSize: 36; font.weight: Font.Bold
                            font.features: { "tnum": 1 }
                            color: Appearance.colors.colOnPrimaryContainer
                            text: root.localTime
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignRight
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnPrimaryContainer
                            opacity: 0.7
                            text: root.localDate
                        }
                    }

                    // The chip grid used to be the third child and took the
                    // leftover height; the chips are absolutely placed elements
                    // of the one tree now, so something still has to absorb it
                    // or the two blocks above are stretched down the card.
                    Item { Layout.fillWidth: true; Layout.fillHeight: true }
                }
            }

            // ---- the four cities, which are the morph ---------------------
            //
            // One tile per city, declared once: a chip in the 2x2's grid and a
            // dial in the 3x1's row are the same element in two places, so the
            // surface travels and changes shape while the words it carries fade
            // out and the hands fade in.
            Repeater {
                model: Geometry.TILES
                delegate: Item {
                    id: cityTile
                    required property int index
                    readonly property var city: root.worldCities[cityTile.index] ?? null

                    function tileBox(span) {
                        return Geometry.cityTileRect(cityTile.index, span,
                            root.spanWidthOf(span), root.spanHeightOf(span), root.uiScale);
                    }
                    readonly property var slot: cityTile.tileBox(root.sizeMode)
                    readonly property var chipBox: cityTile.tileBox("2x2")

                    readonly property bool isDay: cityTile.city?.isDay ?? true
                    readonly property color ink: cityTile.isDay
                        ? Appearance.colors.colOnPrimary
                        : Appearance.colors.colOnLayer0

                    x: slot.x
                    y: slot.y
                    width: slot.width
                    height: slot.height
                    Behavior on x { Expressive.SpanTravel {} }
                    Behavior on y { Expressive.SpanTravel {} }
                    Behavior on width { Expressive.SpanTravel {} }
                    Behavior on height { Expressive.SpanTravel {} }

                    // The offset's own width decides where the name has to
                    // stop, and it has to be the SETTLED width - a ruler at the
                    // chip's font, not the label itself, which is mid-fade
                    // exactly when the name is deciding where to sit.
                    StyledText {
                        id: offsetRuler
                        visible: false
                        text: cityTile.city?.offset ?? ""
                        font.pixelSize: Math.round(Geometry.OFFSET_FONT * root.uiScale)
                    }

                    Rectangle {
                        id: tileSurface
                        anchors.fill: parent
                        property real corner: cityTile.slot.radius
                        Behavior on corner { Expressive.SpanTravel {} }
                        radius: tileSurface.corner
                        color: root.tinted(cityTile.isDay
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colSurfaceContainerLow)
                        Behavior on color { ColorAnimation { duration: 400 } }
                    }

                    // The hands. They have a rect at both spans - the chip's
                    // own box at 2x2 - so they grow out of the tile rather than
                    // arriving at full size over one that is still small.
                    AndroidClock {
                        id: dial
                        readonly property var slot: Geometry.dialRect(root.sizeMode,
                            cityTile.slot.width, cityTile.slot.height, root.uiScale)
                        x: dial.slot.x
                        y: dial.slot.y
                        width: dial.slot.width
                        height: dial.slot.height
                        Behavior on width { Expressive.SpanTravel {} }
                        Behavior on height { Expressive.SpanTravel {} }

                        // The tile paints the surface and carries the name, so
                        // the component draws neither: its own label band would
                        // be a second copy of an element that already travels.
                        backgroundColor: "transparent"
                        label: ""
                        contentInset: Geometry.DIAL_INSET * root.uiScale
                        handColor: cityTile.ink
                        centerDotColor: cityTile.ink
                        autoTime: false
                        hourAngle: {
                            if (!cityTile.city?.time) return 0;
                            const parts = cityTile.city.time.split(":");
                            return (parseInt(parts[0]) % 12) * 30 + parseInt(parts[1]) * 0.5;
                        }
                        minuteAngle: {
                            if (!cityTile.city?.time) return 0;
                            const parts = cityTile.city.time.split(":");
                            return parseInt(parts[1]) * 6;
                        }
                        opacity: Geometry.dialShown(root.sizeMode) ? 1 : 0
                        Behavior on opacity { Expressive.SpanFade {} }
                        visible: opacity > 0
                    }

                    // The city name: the one thing a chip and a dial both say,
                    // and so the one element inside the tile that travels.
                    StyledText {
                        id: cityName
                        objectName: "worldClockCityName" + cityTile.index
                        readonly property var slot: Geometry.tileNameRect(root.sizeMode,
                            cityTile.slot.width, cityTile.slot.height, root.uiScale,
                            offsetRuler.paintedWidth)
                        x: cityName.slot.x
                        y: cityName.slot.y
                        width: cityName.slot.width
                        height: cityName.slot.height
                        Behavior on x { Expressive.SpanTravel {} }
                        Behavior on y { Expressive.SpanTravel {} }
                        Behavior on width { Expressive.SpanTravel {} }

                        // Derived from a timezone id in the user's config, so it
                        // must not render as markup.
                        textFormat: Text.PlainText
                        text: cityTile.city?.name ?? ""
                        elide: Text.ElideRight
                        horizontalAlignment: cityName.slot.centred
                            ? Text.AlignHCenter : Text.AlignLeft
                        font.pixelSize: Math.round(cityName.slot.size)
                        Behavior on font.pixelSize { Expressive.SpanTravel {} }
                        // A chip names its city in the same weight as the
                        // reading beside it; the dial's own label was drawn at
                        // the family's default, and matching it is what keeps
                        // the settled 3x1 the picture it always was.
                        font.weight: cityName.slot.centred ? Font.Normal : Font.Medium
                        Behavior on font.weight { Expressive.SpanTravel {} }
                        color: cityTile.ink
                        opacity: cityName.slot.centred ? 0.75 : 1
                        Behavior on opacity { Expressive.SpanFade {} }
                    }

                    // ---- what only a chip says ------------------------------
                    StyledText {
                        id: cityOffset
                        readonly property var slot: Geometry.tileOffsetRect("2x2",
                            cityTile.chipBox.width, cityTile.chipBox.height, root.uiScale,
                            offsetRuler.paintedWidth)
                        x: cityOffset.slot.x
                        y: cityOffset.slot.y
                        height: cityOffset.slot.height
                        text: cityTile.city?.offset ?? ""
                        font.pixelSize: Math.round(cityOffset.slot.size)
                        color: cityTile.ink
                        opacity: root.sizeMode === "2x2" ? 0.6 : 0
                        Behavior on opacity { Expressive.SpanFade {} }
                        visible: opacity > 0
                    }

                    StyledText {
                        id: cityTime
                        readonly property var slot: Geometry.tileTimeRect("2x2",
                            cityTile.chipBox.width, cityTile.chipBox.height, root.uiScale)
                        x: cityTime.slot.x
                        y: cityTime.slot.y
                        height: cityTime.slot.height
                        text: cityTile.city?.time ?? ""
                        font.pixelSize: Math.round(cityTime.slot.size)
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                        color: cityTile.ink
                        opacity: root.sizeMode === "2x2" ? 1 : 0
                        Behavior on opacity { Expressive.SpanFade {} }
                        visible: opacity > 0
                    }

                    MaterialSymbol {
                        id: cityDayIcon
                        readonly property var slot: Geometry.tileIconRect("2x2",
                            cityTile.chipBox.width, cityTile.chipBox.height, root.uiScale)
                        x: cityDayIcon.slot.x
                        y: cityDayIcon.slot.y
                        iconSize: Appearance.font.pixelSize.smaller
                        text: cityTile.isDay ? "wb_sunny" : "bedtime"
                        color: cityTile.ink
                        opacity: root.sizeMode === "2x2" ? 1 : 0
                        Behavior on opacity { Expressive.SpanFade {} }
                        visible: opacity > 0
                    }
                }
            }

            // ---- the settings back, which the flip shows -------------------
            //
            // Gated on the flip alone: it is reachable only from the 2x2's
            // settings button, and `sizeMode` clears it on the way out of 2x2.
            // Pinned to the 2x2 box for the same reason the front chrome is.
            Item {
                width: root.spanWidthOf("2x2")
                height: root.spanHeightOf("2x2")
                visible: root.showingSettings

                // Four 40px pickers plus a 24px header row is 184px of content
                // that cannot shrink, which leaves 20px to spend inside a 228
                // card. So this side gets the same cardInset as the face - the
                // two are the same card and must not breathe differently when
                // it flips - and the four pickers, a homogeneous list, sit at
                // the tightest step. That is 224 of 228: no picker is cut off
                // (the fourth one was, before the card was even resized) and
                // nothing is squeezed to make it fit.
                ColumnLayout {
                    anchors { fill: parent; margins: root.cardInset }
                    spacing: Appearance.spacing.space50

                    RowLayout {
                        Layout.fillWidth: true; spacing: Appearance.spacing.space100
                        Rectangle {
                            id: backButton
                            radius: Appearance.rounding.full
                            color: "transparent"
                            implicitWidth: 24; implicitHeight: 24
                            MaterialSymbol {
                                anchors.centerIn: parent
                                iconSize: Appearance.font.pixelSize.normal
                                text: "arrow_back"
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleFlip()
                            }
                        }
                        // The back arrow used to sit alone against a whole row
                        // of empty card. Naming the side is what the row is
                        // for, and it costs no height.
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Time zones")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }

                    StyledComboBoxSearch {
                        id: firstZonePicker
                        model: WorldClock.comboModel
                        colBackground: Appearance.colors.colSurfaceContainerLow
                        textRole: "label"
                        currentIndex: WorldClock.comboModel.findIndex(m => m.tz === WorldClock.timezones[0])
                        onActivated: (idx) => WorldClock.setTimezone(0, WorldClock.comboModel[idx].tz)
                    }
                    StyledComboBoxSearch {
                        id: secondZonePicker
                        model: WorldClock.comboModel; textRole: "label"
                        colBackground: Appearance.colors.colSurfaceContainerLow
                        currentIndex: WorldClock.comboModel.findIndex(m => m.tz === WorldClock.timezones[1])
                        onActivated: (idx) => WorldClock.setTimezone(1, WorldClock.comboModel[idx].tz)
                    }
                    StyledComboBoxSearch {
                        id: thirdZonePicker
                        model: WorldClock.comboModel; textRole: "label"
                        colBackground: Appearance.colors.colSurfaceContainerLow
                        currentIndex: WorldClock.comboModel.findIndex(m => m.tz === WorldClock.timezones[2])
                        onActivated: (idx) => WorldClock.setTimezone(2, WorldClock.comboModel[idx].tz)
                    }
                    StyledComboBoxSearch {
                        id: fourthZonePicker
                        model: WorldClock.comboModel; textRole: "label"
                        colBackground: Appearance.colors.colSurfaceContainerLow
                        currentIndex: WorldClock.comboModel.findIndex(m => m.tz === WorldClock.timezones[3])
                        onActivated: (idx) => WorldClock.setTimezone(3, WorldClock.comboModel[idx].tz)
                    }
                }
            }

            Rectangle {
                id: toggleHandle
                width: 16; height: 16; radius: Appearance.rounding.unsharpenslight
                color: Appearance.colors.colOnPrimaryContainer
                anchors { right: parent.right; bottom: parent.bottom; margins: Appearance.spacing.space50 }
                opacity: (widgetHover.hovered || toggleArea.containsMouse || toggleArea.pressed) ? 0.5 : 0
                visible: opacity > 0 && !root.hostInteractionLocked

                Behavior on opacity { NumberAnimation { duration: Appearance.animation.elementMoveFaster.duration } }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.sizeMode === "2x2" ? "calendar_view_month" : "calendar_view_week"
                    iconSize: 11
                    color: Appearance.colors.colPrimaryContainer
                }

                MouseArea {
                    id: toggleArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: PluginState.setOption("world-clock", "sizeMode",
                        root.sizeMode === "2x2" ? "3x1" : "2x2")
                }
            }
        }
    }
}
