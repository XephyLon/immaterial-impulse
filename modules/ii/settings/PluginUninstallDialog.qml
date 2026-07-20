import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.plugins
import QtQuick
import QtQuick.Layouts

// Confirmation prompt for removing an installed plugin package. Driven entirely
// by PluginManager.pendingUninstallId so the settings page only has to set that
// id; the window-level host binds `show` and forwards dismissal.
WindowDialog {
    id: root
    backgroundWidth: 380

    readonly property string pluginId: PluginManager.pendingUninstallId
    readonly property string pluginName: {
        for (const plugin of PluginManager.availablePlugins)
            if (plugin.id === root.pluginId)
                return plugin.name || root.pluginId;
        return root.pluginId;
    }

    WindowDialogTitle {
        text: Translation.tr("Delete plugin?")
    }

    WindowDialogParagraph {
        Layout.fillWidth: true
        text: Translation.tr("“%1” and its files will be permanently removed from disk. This cannot be undone.")
            .arg(root.pluginName)
    }

    WindowDialogButtonRow {
        Layout.fillWidth: true

        Item { Layout.fillWidth: true }

        DialogButton {
            buttonText: Translation.tr("Cancel")
            onClicked: PluginManager.cancelUninstall()
        }

        DialogButton {
            buttonText: Translation.tr("Delete")
            colText: Appearance.colors.colError
            enabled: !PluginManager.uninstalling
            onClicked: PluginManager.confirmUninstall()
        }
    }
}
