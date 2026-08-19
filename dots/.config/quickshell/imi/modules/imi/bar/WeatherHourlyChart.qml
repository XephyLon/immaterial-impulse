import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../common/functions/weatherHourly.js" as WeatherHourly
import "../../common/functions/weatherForecast.js" as WeatherForecast

// The weather popup's hourly row: five three-hourly slots, each a bar grown
// from the axis. Every decision behind it is in weatherHourly.js, which is
// where the tests can reach them; this file owns the drawing and nothing else.
Rectangle {
    id: root
    // The objectNames are how WeatherPopupHeroRuntimeTest.qml finds the row and
    // its bars: it samples a bar mid-growth, and a settled bar is the same
    // height whether it animated or teleported.
    objectName: "hourlyChart"

    // The popup holding the card. The bars grow whenever this goes true, so a
    // card that is opened plays the growth and a card that is already open
    // plays it again when a refresh moves the temperatures - the tree this was
    // taken from animates on open only, by writing the heights from a
    // NumberAnimation that destroys the binding, so a refresh under an open
    // popup pops the bars with no motion at all
    // (docs/p3drovfx-animation-research-2026-08-16.md §3.3).
    required property bool charted

    // Written once per fetch, so which of the slots are still ahead is a
    // question about now rather than about the fetch. DateTime's clock is read
    // to re-cut the window every minute; the shell has exactly one of those
    // timers and this is how everything else borrows it.
    readonly property real nowMs: {
        DateTime.minutes;
        return Date.now();
    }
    readonly property var slots: WeatherHourly.upcoming(Weather.hourly, root.nowMs, WeatherHourly.SLOT_COUNT)
    readonly property var range: WeatherHourly.chartRange(root.slots)
    readonly property bool twelveHour: WeatherHourly.usesTwelveHourClock(Config.options.time.format)

    // A row of hour labels with nothing over them reads as a rendering fault
    // rather than as a provider that answered thinly.
    visible: WeatherHourly.isRenderable(root.slots)
    Layout.fillWidth: true
    implicitHeight: contentRow.implicitHeight + Appearance.spacing.space100 * 2

    radius: Appearance.rounding.small
    color: Appearance.colors.colSurfaceContainerHigh

    RowLayout {
        id: contentRow
        anchors {
            fill: parent
            margins: Appearance.spacing.space100
        }
        spacing: Appearance.spacing.space50
        uniformCellSizes: true

        Repeater {
            model: root.slots

            ColumnLayout {
                id: slotColumn
                required property var modelData
                Layout.fillWidth: true
                spacing: Appearance.spacing.space25

                readonly property var fraction: WeatherHourly.barFraction(slotColumn.modelData.temp,
                                                                         root.range.low, root.range.high)

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: slotColumn.modelData.temp === null
                        ? "–" : `${Math.round(slotColumn.modelData.temp)}°`
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurfaceVariant
                }

                Item {
                    id: track
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36

                    Rectangle {
                        id: bar
                        objectName: "hourlyBar"
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        width: Math.min(12, track.width)
                        radius: Appearance.rounding.verysmall
                        color: Appearance.colors.colPrimary
                        // A slot with no reading draws no bar; a zero-height one
                        // would read as the coldest hour of the window.
                        height: (root.charted && slotColumn.fraction !== null)
                            ? slotColumn.fraction * track.height : 0

                        Behavior on height {
                            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                        }
                    }
                }

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    // Night-aware on the SLOT's own hour, not on the current
                    // one: this row is drawn hours ahead of what it describes.
                    text: Icons.getProviderWeatherIcon(Weather.provider, slotColumn.modelData.wCode,
                                                       Icons.isNightAt(slotColumn.modelData.hour))
                    iconSize: Appearance.font.pixelSize.smaller
                    fill: 0
                    color: Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    // The weekday where the window crosses midnight: "00" alone
                    // could belong to either side of the boundary.
                    text: slotColumn.modelData.dayBreak
                        ? WeatherForecast.shortDayName(slotColumn.modelData.date, Qt.locale())
                        : WeatherHourly.hourLabel(slotColumn.modelData.hour, root.twelveHour)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnSurfaceVariant
                    opacity: 0.7
                }
            }
        }
    }
}
