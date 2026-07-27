import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.plugins
import QtQuick
import QtQuick.Layouts

// Confirmation prompt for installing or updating a plugin from the store
// registry. Driven entirely by PluginStore.pendingInstallEntry so the store
// page only has to request the install; the window-level host in
// SettingsContent binds `show` and forwards dismissal, mirroring
// PluginUninstallDialog. Every entry-derived string comes from the fetched
// registry index, so each one renders with textFormat: Text.PlainText.
WindowDialog {
    id: root
    backgroundWidth: 420

    // Cached copy of the pending entry: PluginStore clears it on
    // confirm/cancel, and the dialog must keep its content readable through
    // the close animation instead of blanking out.
    property var entry: null
    property bool upgrading: false

    readonly property var pending: PluginStore.pendingInstallEntry
    onPendingChanged: root.syncPending()
    Component.onCompleted: root.syncPending()

    function syncPending() {
        if (root.pending === null)
            return;
        root.entry = root.pending;
        root.upgrading = PluginStore.pendingInstallIsUpgrade;
    }

    // Human descriptions for the registry's known permission names; an
    // unknown name falls back to the raw string (rendered as plain text).
    readonly property var permissionDescriptions: ({
        "process": Translation.tr("Can run system commands"),
        "network": Translation.tr("Can access the network"),
        "filesystem_read": Translation.tr("Can read your files"),
        "filesystem_write": Translation.tr("Can write to your files"),
        "settings_read": Translation.tr("Can read shell settings"),
        "settings_write": Translation.tr("Can change shell settings")
    })

    readonly property string sourceUrl: {
        const url = root.entry?.sourceUrl;
        return (typeof url === "string" && url.startsWith("https://")) ? url : "";
    }

    WindowDialogTitle {
        text: root.upgrading ? Translation.tr("Update plugin?") : Translation.tr("Install plugin?")
    }

    WindowDialogParagraph {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        font.weight: Font.DemiBold
        color: Appearance.colors.colOnSurface
        text: {
            const name = root.entry?.name ?? "";
            const version = root.entry?.version ?? "";
            return version.length > 0 ? `${name} · v${version}` : name;
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Appearance.spacing.space50
        visible: (root.entry?.permissions ?? []).length > 0

        Repeater {
            model: root.entry?.permissions ?? []

            RowLayout {
                required property string modelData
                Layout.fillWidth: true
                spacing: Appearance.spacing.space75

                MaterialSymbol {
                    text: "shield"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnSurfaceVariant
                }
                StyledText {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: root.permissionDescriptions[modelData] ?? modelData
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    WindowDialogParagraph {
        Layout.fillWidth: true
        visible: (root.entry?.dependencies ?? []).length > 0
        textFormat: Text.PlainText
        text: Translation.tr("Requires: %1").arg((root.entry?.dependencies ?? []).join(", "))
    }

    RippleButtonWithIcon {
        visible: root.sourceUrl.length > 0
        materialIcon: "code"
        mainText: Translation.tr("Review the code")
        onClicked: Qt.openUrlExternally(root.sourceUrl)
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Appearance.spacing.space75

        MaterialSymbol {
            Layout.alignment: Qt.AlignTop
            text: "warning"
            iconSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colError
        }
        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Plugins run with the same access as the shell itself. Only install plugins from authors you trust.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSurfaceVariant
            wrapMode: Text.Wrap
        }
    }

    WindowDialogButtonRow {
        Layout.fillWidth: true

        Item { Layout.fillWidth: true }

        DialogButton {
            buttonText: Translation.tr("Cancel")
            onClicked: PluginStore.cancelInstall()
        }

        DialogButton {
            buttonText: root.upgrading ? Translation.tr("Update") : Translation.tr("Install")
            enabled: !PluginManager.installing
            onClicked: PluginStore.confirmInstall()
        }
    }
}
