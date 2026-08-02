pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.plugins

Item {
    id: root

    // The card fills the whole widget, so the host's default region already has
    // the right extent - but not the right corner radius (it falls back to
    // `Appearance.rounding.large`, 7px tighter than the card's `verylarge`),
    // which would leave frosted slivers outside the four corners. Naming the
    // card is the only way to hand the host its actual radius.
    readonly property bool blurEnabled: PluginState.option("world-clock", "blurEnabled", false)
    readonly property real backgroundOpacity: Config.options.plugins.blurOpacity
    readonly property bool managesBlurTint: true
    readonly property var blurRegions: [
        { x: contentRect.x, y: contentRect.y, width: contentRect.width,
            height: contentRect.height, radius: contentRect.radius }
    ]

    function tinted(surfaceColor) {
        return root.blurEnabled
            ? ColorUtils.transparentize(surfaceColor, 1 - root.backgroundOpacity)
            : surfaceColor;
    }

    // The corner handle switches the widget between a 2x2 card and a 4x1 row of
    // dials, so the manifest can declare no `grid`: a span is a fixed pixel size
    // the host assigns, and it would overwrite the toggled size on every load.
    // The widget stays content-sized instead, which is also why its root must
    // not `anchors.fill: parent` (PluginNode derives its own size from this
    // one - anchoring is a binding loop). Both sizes are unchanged from the
    // built-in and both are whole 12px steps, so the widget still tiles flush
    // against grid widgets. See docs/widget-grid.md.
    property string sizeMode: PluginState.option("world-clock", "sizeMode", "2x2")

    property real widgetWidth:  sizeMode === "2x2" ? 276 : 420
    property real widgetHeight: sizeMode === "2x2" ? 252 : 120

    Behavior on widgetWidth  { animation: Appearance.animation.elementResize.numberAnimation.createObject(this) }
    Behavior on widgetHeight { animation: Appearance.animation.elementResize.numberAnimation.createObject(this) }

    implicitWidth:  widgetWidth
    implicitHeight: widgetHeight

    property string localCityName: Weather.data?.city ?? "..."
    property string localTime: DateTime.time
    property string localDate: Qt.locale().toString(new Date(), "dddd, MMMM dd yyyy")
    // The timezone list itself stays in Config, owned by the WorldClock service:
    // it is shell-wide service state rather than per-widget state, so the port
    // leaves it exactly where an existing install already has it.
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

        StyledDropShadow { target: contentRect }

        Rectangle {
            id: contentRect
            anchors.fill: parent
            color:  root.tinted(Appearance.colors.colPrimaryContainer)
            radius: Appearance.rounding?.verylarge ?? 30

            // 2x2
            ColumnLayout {
                id: mainColumn
                anchors { fill: parent; margins: Appearance.spacing.space150 }
                spacing: Appearance.spacing.space150
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
                        implicitWidth: 28; implicitHeight: 28
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
                        font.pixelSize: 42; font.weight: Font.Bold
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

                GridLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    columns: 2; rowSpacing: 6; columnSpacing: 6

                    Repeater {
                        model: root.worldCities
                        delegate: Rectangle {
                            id: cityCard
                            required property var modelData
                            required property int index
                            Layout.preferredWidth: 120; Layout.preferredHeight: 54
                            radius: Appearance.rounding.normal
                            color: root.tinted(cityCard.modelData.isDay
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colSurfaceContainerLow)
                            property color fg: cityCard.modelData.isDay
                                ? Appearance.colors.colOnPrimary
                                : Appearance.colors.colOnLayer0
                            Behavior on color { ColorAnimation { duration: 400 } }

                            ColumnLayout {
                                anchors { fill: parent; margins: Appearance.spacing.space100 }
                                spacing: Appearance.spacing.space25
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

                ColumnLayout {
                    anchors { fill: parent; margins: Appearance.spacing.space150 }
                    spacing: Appearance.spacing.space150

                    RowLayout {
                        Layout.fillWidth: true; spacing: Appearance.spacing.space100
                        Rectangle {
                            id: backButton
                            radius: Appearance.rounding.full
                            color: "transparent"
                            implicitWidth: 28; implicitHeight: 28
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
                        Item { Layout.fillWidth: true }
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

            // 4x1
            RowLayout {
                anchors { fill: parent; margins: Appearance.spacing.space100 }
                spacing: Appearance.spacing.space100
                visible: root.sizeMode === "4x1"

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
                        labelSpacing: 6
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
                visible: opacity > 0 && !Config.options.background.widgetsLocked

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
                            root.sizeMode === "2x2" ? "4x1" : "2x2")
                    }
                }
            }
        }
    }
}
