pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    implicitHeight: col.implicitHeight + 16

    // Empty since the clock became a bundled plugin. This Repeater can only
    // drive `background.widgets.<key>.enable`, and no widget is stored there
    // any more - every desktop widget is enabled from Settings > Widgets. The
    // submenu still renders "Lock widget positions", which is real and still
    // lives in Config; what to do with the rest of it is Task 6's call.
    readonly property var widgetList: []

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer0
    }

    ColumnLayout {
        id: col
        anchors { fill: parent; margins: Appearance.spacing.space100 }
        spacing: Appearance.spacing.space25

        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: "lock"
            text: Translation.tr("Lock widget positions")
            checked: Config.options.background.widgetsLocked
            onCheckedChanged: Config.options.background.widgetsLocked = checked
        }

        Rectangle {
            visible: root.widgetList.length > 0
            Layout.fillWidth: true
            Layout.topMargin: Appearance.spacing.space50
            Layout.bottomMargin: Appearance.spacing.space50
            implicitHeight: 1
            color: Appearance.colors.colOutlineVariant
            opacity: 0.4
        }

        Repeater {
            model: root.widgetList
            delegate: ConfigSwitch {
                required property var modelData
                Layout.fillWidth: true
                buttonIcon: modelData.icon
                text: modelData.name
                checked: Config.options.background.widgets[modelData.key].enable
                onCheckedChanged: Config.options.background.widgets[modelData.key].enable = checked
            }
        }
    }
}