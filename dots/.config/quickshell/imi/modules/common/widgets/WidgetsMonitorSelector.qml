import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import "../functions/screenSelection.js" as ScreenSelection

Flow {
    id: root
    required property var configEntry 
    Layout.fillWidth: true
    spacing: Appearance.spacing.space25

    SelectionGroupButton {
        leftmost: true
        rightmost: Hyprland.monitors.values.length === 0
        buttonIcon: "tv_displays"
        buttonText: Translation.tr("All")
        toggled: root.configEntry.screenList.length === 0
        onClicked: root.configEntry.screenList = []
    }

    Repeater {
        model: Hyprland.monitors
        delegate: SelectionGroupButton {
            required property var modelData
            required property int index
            leftmost: false
            rightmost: index === Hyprland.monitors.values.length - 1
            buttonIcon: "monitor"
            buttonText: modelData.name
            // An empty screenList means every screen, so each button has to
            // read as selected in that state - otherwise clicking one while
            // "All" is active takes the "add" branch and appends a name the
            // list already effectively contains.
            toggled: ScreenSelection.includes(root.configEntry.screenList, modelData.name)
            onClicked: {
                const allNames = Hyprland.monitors.values.map(monitor => monitor.name)
                const result = ScreenSelection.toggle(root.configEntry.screenList,
                    allNames, modelData.name, !toggled)
                // Refused when this is the last selected screen: an empty list
                // would mean every screen, turning the widget back on
                // everywhere instead of off.
                if (result.accepted)
                    root.configEntry.screenList = result.list
            }
        }
    }
    SelectionGroupButton {
        leftmost: false
        rightmost: true
        buttonIcon: "page_footer"
        buttonText: Translation.tr("")
    }
}