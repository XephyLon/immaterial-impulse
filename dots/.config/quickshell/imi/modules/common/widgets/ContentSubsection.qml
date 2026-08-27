import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    property string title: ""
    // A leading Material Symbol before the title - the subsection-header shape
    // of the settings row grammar (AGENT.md, design language). Empty draws
    // nothing and takes no width, which is what every subsection outside the
    // reference page still wants.
    property string icon: ""
    property string tooltip: ""
    // Named contentData rather than data: aliasing 'data' shadows Item's own
    // member, which Qt warns about on every instantiation.
    default property alias contentData: sectionContent.data

    Layout.fillWidth: true
    Layout.topMargin: Appearance.spacing.space50
    spacing: Appearance.spacing.space25

    RowLayout {
        spacing: Appearance.spacing.space50
        MaterialSymbol {
            visible: root.icon.length > 0
            Layout.leftMargin: Appearance.spacing.space25
            text: root.icon
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colSubtext
        }
        ContentSubsectionLabel {
            visible: root.title && root.title.length > 0
            text: root.title
        }
        MaterialSymbol {
            visible: root.tooltip && root.tooltip.length > 0
            text: "info"
            iconSize: Appearance.font.pixelSize.large
            
            color: Appearance.colors.colSubtext
            MouseArea {
                id: infoMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.WhatsThisCursor
                StyledToolTip {
                    extraVisibleCondition: false
                    alternativeVisibleCondition: infoMouseArea.containsMouse
                    text: root.tooltip
                }
            }
        }
        Item { Layout.fillWidth: true }
    }
    ColumnLayout {
        id: sectionContent
        Layout.fillWidth: true
        spacing: Appearance.spacing.space25
    }
}
