pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.plugins
import qs.modules.common.plugins.designsystem.widgets as Expressive

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

    property real widgetWidth:  sizeMode === "2x2" ? Appearance.sizes.widgetGridSpanX(2) : Appearance.sizes.widgetGridSpanX(3)
    property real widgetHeight: sizeMode === "2x2" ? Appearance.sizes.widgetGridSpanY(2) : Appearance.sizes.widgetGridSpanY(1)

    // The card's own padding, shared by the 2x2 face and its settings back.
    // The wide mode deliberately does not use it - see the 3x1 layout below.
    readonly property real cardInset: Appearance.spacing.space150

    Behavior on widgetWidth  { animation: Appearance.animation.elementResize.numberAnimation.createObject(this) }
    Behavior on widgetHeight { animation: Appearance.animation.elementResize.numberAnimation.createObject(this) }

    implicitWidth:  widgetWidth
    implicitHeight: widgetHeight

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
        Expressive.WidgetCard {
            id: contentRect
            anchors.fill: parent
            tint: Appearance.colors.colPrimaryContainer
            useBlurBackground: root.blurEnabled
            backgroundOpacity: root.backgroundOpacity
            dragging: root.hostDragging
            radius: Appearance.rounding?.verylarge ?? 30

            // 2x2. Two steps of the scale: cardInset (space150) at the card
            // edge, space100 between the three blocks inside it. The inset is
            // what keeps the four city chips clear of a 30px corner radius -
            // at the space100 it had, the bottom two chips ran into the
            // rounding.
            //
            // This side has always been over-budget: at the built-in's 252 the
            // content came to 258, and at 228 it came to 234, so the bottom
            // row of chips sat 2px off the card edge instead of on the margin.
            // Two things fix that rather than shaving gaps again. The chip
            // grid is Layout.fillHeight, so it takes whatever is left over
            // instead of pushing past the bottom margin whenever a font is a
            // little taller than the one this was tuned against; and the local
            // time drops 42 -> 36, which is where the room actually comes from.
            // It is still 2.4x the largest text under it, so it still reads as
            // the hero.
            ColumnLayout {
                id: mainColumn
                anchors { fill: parent; margins: root.cardInset }
                spacing: Appearance.spacing.space100
                visible: root.sizeMode === "2x2" && !root.showingSettings

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

                // The chips used to be a fixed 120px wide, centred - 246px of
                // grid inside 260px of content, so they sat 7px inboard of the
                // header and the time above them and nothing lined up down
                // either edge. They divide the content width instead now, and
                // take the column's leftover height rather than a fixed 50,
                // which is what stops the bottom row overshooting the margin.
                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: 2
                    rowSpacing: Appearance.spacing.space75
                    columnSpacing: Appearance.spacing.space75

                    Repeater {
                        model: root.worldCities
                        delegate: Rectangle {
                            id: cityCard
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Appearance.rounding.normal
                            color: root.tinted(cityCard.modelData.isDay
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colSurfaceContainerLow)
                            property color fg: cityCard.modelData.isDay
                                ? Appearance.colors.colOnPrimary
                                : Appearance.colors.colOnLayer0
                            Behavior on color { ColorAnimation { duration: 400 } }

                            ColumnLayout {
                                // A chip inside the card, so its padding is a
                                // step under the card's own inset. The two text
                                // rows carry their own leading, so they need no
                                // gap between them on top of that.
                                //
                                // Horizontally it takes a step more than that:
                                // the chip's `normal` radius is 17px, so at a
                                // uniform space75 the city name and the offset
                                // start inside the corner curve and read as
                                // stuck to the edge. space150 clears the arc.
                                anchors {
                                    fill: parent
                                    topMargin: Appearance.spacing.space75
                                    bottomMargin: Appearance.spacing.space75
                                    leftMargin: Appearance.spacing.space150
                                    rightMargin: Appearance.spacing.space150
                                }
                                spacing: Appearance.spacing.space0
                                RowLayout {
                                    Layout.fillWidth: true
                                    StyledText {
                                        Layout.fillWidth: true
                                        // Derived from a timezone id in the user's
                                        // config, so it must not render as markup.
                                        textFormat: Text.PlainText
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.Medium
                                        color: cityCard.fg
                                        text: cityCard.modelData.name
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: cityCard.fg; opacity: 0.6
                                        text: cityCard.modelData.offset
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true; spacing: Appearance.spacing.space50
                                    StyledText {
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.weight: Font.Bold
                                        font.features: { "tnum": 1 }
                                        color: cityCard.fg
                                        text: cityCard.modelData.time
                                    }
                                    Item { Layout.fillWidth: true }
                                    MaterialSymbol {
                                        iconSize: Appearance.font.pixelSize.smaller
                                        text: cityCard.modelData.isDay ? "wb_sunny" : "bedtime"
                                        color: cityCard.fg
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: root.sizeMode === "2x2" && root.showingSettings

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

            // 3x1. Deliberately *not* cardInset: the dials are full-bleed
            // tiles rather than content on a surface, and at space100 the
            // card's 30px rounding minus the inset (22) lands on the dial's
            // own `large` radius (23), so the four tiles nest concentrically
            // in the corners. At cardInset they would be 30-12=18 against 23
            // and the corners would visibly fight.
            RowLayout {
                anchors { fill: parent; margins: Appearance.spacing.space100 }
                spacing: Appearance.spacing.space100
                visible: root.sizeMode !== "2x2"

                Repeater {
                    model: Math.min(root.worldCities.length, 4)
                    delegate: AndroidClock {
                        required property int index
                        property var cityData: root.worldCities[index] ?? null

                        Layout.fillHeight: true
                        Layout.fillWidth:  true

                        backgroundColor: root.tinted(cityData?.isDay ?? true
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colSurfaceContainerLow)
                        handColor: cityData?.isDay ?? true
                            ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colOnLayer0
                        centerDotColor: cityData?.isDay ?? true
                            ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colOnLayer0
                        label:       cityData?.name ?? ""
                        labelColor:  Qt.rgba(
                            (cityData?.isDay ?? true ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0).r,
                            (cityData?.isDay ?? true ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0).g,
                            (cityData?.isDay ?? true ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0).b,
                            0.75)
                        labelSpacing: Appearance.spacing.space75
                        autoTime:    false
                        hourAngle: {
                            if (!cityData?.time) return 0
                            const p = cityData.time.split(":")
                            return (parseInt(p[0]) % 12) * 30 + parseInt(p[1]) * 0.5
                        }
                        minuteAngle: {
                            if (!cityData?.time) return 0
                            const p = cityData.time.split(":")
                            return parseInt(p[1]) * 6
                        }
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
                    onClicked: {
                        if (root.showingSettings) root.showingSettings = false
                        PluginState.setOption("world-clock", "sizeMode",
                            root.sizeMode === "2x2" ? "3x1" : "2x2")
                    }
                }
            }
        }
    }
}
