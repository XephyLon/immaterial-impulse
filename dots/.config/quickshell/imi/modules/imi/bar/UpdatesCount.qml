pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    property bool vertical: Config.options.bar.vertical
    property bool isMaterial: Config.options.bar.cornerStyle === 3
    property bool borderless: Config.options.bar.borderless

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : (contentLoader.item?.implicitWidth ?? 0) 
    implicitHeight: vertical ? (contentLoader.item?.implicitHeight ?? 0) : Appearance.sizes.barHeight

    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    // A view of the Updates service: the gestures call it, the state is read
    // from it, nothing runs here.
    onClicked: (mouse) => {
        if (mouse.button === Qt.LeftButton) Updates.runUpgrade()
    }

    onPressed: (mouse) => {
        if (mouse.button === Qt.RightButton) {
            Updates.checkNow()
            mouse.accepted = false
        }
    }

    Component {
        id: textComp
        StyledText {
            leftPadding: Appearance.spacing.space100
            rightPadding: Appearance.spacing.space50
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.isMaterial ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            text: Updates.count
        }
    }

    Component {
        id: spinnerComp
        MaterialSymbol {
            id: spinnerGlyph
            leftPadding: Appearance.spacing.space100
            rightPadding: Appearance.spacing.space50
            text: "progress_activity"
            iconSize: Appearance.font.pixelSize.normal
            color: root.isMaterial ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            // Effective visibility, not `true`: a running infinite animation
            // dirties the scene every frame, the shell commits, and the
            // compositor repaints the whole output - including while this
            // spinner's own Loader is inactive or the bar's surface is down.
            RotationAnimation on rotation {
                from: 0; to: 360
                duration: 1000
                loops: Animation.Infinite
                running: spinnerGlyph.visible
            }
        }
    }

    Loader {
        id: contentLoader
        anchors.centerIn: parent
        sourceComponent: root.vertical ? colContent : rowContent
    }

    Component {
        id: rowContent
        RowLayout {
            spacing: Appearance.spacing.space50

            // Default
            MaterialSymbol {
                visible: !root.isMaterial
                Layout.alignment: Qt.AlignVCenter
                text: "deployed_code_update"
                iconSize: Appearance.font.pixelSize.normal
                color: Updates.updateStronglyAdvised ? Appearance.m3colors.m3error
                    : Updates.updateAdvised ? Appearance.colors.colTertiary
                    : Appearance.colors.colOnLayer1
            }

            // Material
            Rectangle {
                visible: root.isMaterial
                width: 24
                height: 24
                radius: Appearance.rounding.full
                color: Updates.updateStronglyAdvised ? Appearance.m3colors.m3error
                    : Updates.updateAdvised ? Appearance.colors.colTertiary
                    : Appearance.colors.colPrimary

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "deployed_code_update"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnPrimary
                }
            }

            Loader {
                Layout.alignment: Qt.AlignVCenter
                sourceComponent: Updates.checking ? spinnerComp : textComp
            }
        }
    }

    Component {
        id: colContent
        ColumnLayout {
            spacing: Appearance.spacing.space50

            MaterialSymbol {
                visible: !root.isMaterial
                Layout.alignment: Qt.AlignHCenter
                text: "deployed_code_update"
                iconSize: Appearance.font.pixelSize.normal
                color: Updates.updateStronglyAdvised ? Appearance.m3colors.m3error
                    : Updates.updateAdvised ? Appearance.colors.colTertiary
                    : Appearance.colors.colOnLayer1
            }

            Rectangle {
                visible: root.isMaterial
                width: 24
                height: 24
                radius: Appearance.rounding.full
                color: Updates.updateStronglyAdvised ? Appearance.m3colors.m3error
                    : Updates.updateAdvised ? Appearance.colors.colTertiary
                    : Appearance.colors.colPrimary
                Layout.alignment: Qt.AlignHCenter

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "deployed_code_update"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnPrimary
                }
            }

            Loader {
                Layout.alignment: Qt.AlignHCenter
                sourceComponent: Updates.checking ? spinnerComp : textComp
            }
        }
    }
}