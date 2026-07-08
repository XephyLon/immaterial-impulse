import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import qs.modules.ii.bar

StyledPopup {
    id: root

    ColumnLayout {
        id: mainLayout
        implicitWidth: 340 
        spacing: 8

        Layout.topMargin: -8
        Layout.leftMargin: -8
        Layout.rightMargin: -8

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 125

            topLeftRadius: Appearance.rounding.normal - 2
            topRightRadius: Appearance.rounding.normal - 2
            bottomLeftRadius: Appearance.rounding.normal
            bottomRightRadius: Appearance.rounding.normal

            gradient: Gradient {
                GradientStop { position: 0.0; color: Appearance.colors.colPrimaryContainer }
                GradientStop { position: 1.0; color: Appearance.colors.colSurfaceContainerLow }
            }

            Item {
                anchors.fill: parent
                anchors.margins: 16 

                ColumnLayout {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.topMargin: -6
                    spacing: -2

                    StyledText {
                        text: Weather.data?.city ?? "Paris, France"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                    }

                    StyledText {
                        text: Weather.data?.description ?? "Cloudy"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer0
                        opacity: 0.6
                    }
                }

                RowLayout {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    spacing: 4

                    StyledText {
                        text: Weather.data?.temp ?? "3"
                        font.pixelSize: 48
                        font.weight: Font.Light
                        color: Appearance.colors.colOnLayer0
                    }
                }

                MaterialShapeWrappedMaterialSymbol {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    shape: MaterialShape.Shape.Sunny
                    text: Icons.getWeatherIcon(Weather.data.wCode) ?? "cloud"
                    iconSize: 40
                    implicitSize: 64
                    color: Qt.alpha(Appearance.colors.colOnLayer0, 0.15)
                    colSymbol: Appearance.colors.colPrimary
                }
            }
        }

        GridLayout {
            id: gridLayout
            columns: 2
            rowSpacing: 4
            columnSpacing: 4
            uniformCellWidths: true
            
            Layout.leftMargin: 2
            Layout.rightMargin: 2
            Layout.bottomMargin: 2
            Layout.fillWidth: true

            WeatherCard {
                title: Translation.tr("Rain?")
                symbol: "rainy"
                value: Weather.data?.cr ?? "24%"
            }
            WeatherCard {
                title: Translation.tr("Wind")
                symbol: "air"
                value: `${Weather.data?.wind ?? "1.2 km/h"}`
            }
            WeatherCard {
                title: Translation.tr("Precipitation")
                symbol: "rainy_light"
                value: Weather.data?.precip ?? "10%"
            }
            WeatherCard {
                title: Translation.tr("Humidity")
                symbol: "humidity_low"
                value: Weather.data?.humidity ?? "65%"
            }
            WeatherCard {
                title: Translation.tr("Visibility")
                symbol: "visibility"
                value: Weather.data?.visib ?? "10 km"
            }
            WeatherCard {
                title: Translation.tr("Pressure")
                symbol: "readiness_score"
                value: Weather.data?.press ?? "720 hpa"
            }
            WeatherCard {
                title: Translation.tr("Sunrise")
                symbol: "wb_twilight"
                value: Weather.data?.sunrise ?? "07:34 AM"
                fgColor: Appearance.colors.colLayer0
            }
            WeatherCard {
                title: Translation.tr("Sunset")
                symbol: "bedtime"
                value: Weather.data?.sunset ?? "05:21 PM"
                fgColor: Appearance.colors.colLayer0
            }
        }
    }
}