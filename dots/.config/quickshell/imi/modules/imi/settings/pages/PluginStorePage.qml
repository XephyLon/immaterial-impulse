import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.plugins

/**
 * Plugin store: a browsable catalog of the official registry served by
 * services/PluginStore.qml. Hosted inside PluginsPage the same way
 * IconPackSelector is hosted by InterfaceConfig - a plain component
 * instantiated by its parent page, no settings-navigation-host changes -
 * with a back button emitting closeRequested().
 *
 * Every registry-sourced string is rendered with textFormat: Text.PlainText
 * so a malicious index cannot inject rich text (contract-tested by
 * tests/test_plugin_store_contract.py).
 */
ContentPage {
    id: root
    forceWidth: true

    signal closeRequested()

    property string capabilityFilter: "" // "" = all capabilities
    property bool installedOnly: false

    // Refresh when the page is shown; refreshIfStale() no-ops on a warm cache.
    onVisibleChanged: if (visible) PluginStore.refreshIfStale()
    Component.onCompleted: if (visible) PluginStore.refreshIfStale()

    // Sequential update-all queue. PluginManager.runInstaller() refuses to
    // start while `installing` is true (a second call while one runs is
    // dropped and clobbers installMessage with an error), so queued upgrades
    // are chained on onInstallingChanged instead of iterated in a loop.
    property var upgradeQueue: []

    readonly property var filteredEntries: {
        const query = (searchField.value ?? "").trim().toLowerCase();
        const filtered = PluginStore.entries.filter(entry => {
            if (query.length > 0) {
                const haystack = [entry.name, entry.description ?? "",
                    (entry.tags ?? []).join("\n")].join("\n").toLowerCase();
                if (!haystack.includes(query))
                    return false;
            }
            if (root.capabilityFilter.length > 0
                    && !(entry.capabilities ?? []).includes(root.capabilityFilter))
                return false;
            if (root.installedOnly) {
                const status = PluginStore.statusForEntry(entry);
                if (status !== "installed" && status !== "update")
                    return false;
            }
            return true;
        });
        return filtered.sort((a, b) =>
            (b.featured === true) - (a.featured === true)
            || a.name.localeCompare(b.name));
    }

    function updateAll() {
        const updates = PluginStore.entries.filter(
            entry => PluginStore.statusForEntry(entry) === "update");
        if (updates.length === 0 || PluginManager.installing)
            return;
        root.upgradeQueue = updates.slice(1);
        PluginStore.upgrade(updates[0]);
    }

    Connections {
        target: PluginManager
        function onInstallingChanged() {
            if (PluginManager.installing)
                return;
            // Drain the queue, skipping entries whose status changed while
            // they waited (already updated elsewhere, uninstalled, ...).
            let queue = root.upgradeQueue;
            while (queue.length > 0) {
                const next = queue[0];
                queue = queue.slice(1);
                if (PluginStore.statusForEntry(next) === "update") {
                    root.upgradeQueue = queue;
                    PluginStore.upgrade(next);
                    return;
                }
            }
            root.upgradeQueue = [];
        }
    }

    ContentSection {
        title: Translation.tr("Widget store")
        Layout.fillWidth: true
        icon: "storefront"
        shape: MaterialShape.Shape.Diamond

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space100

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.space100

                RippleButtonWithIcon {
                    materialIcon: "arrow_back"
                    mainText: Translation.tr("Back to widgets")
                    onClicked: root.closeRequested()
                }

                Item { Layout.fillWidth: true }

                RippleButtonWithIcon {
                    visible: PluginStore.updatesAvailable >= 2
                    enabled: !PluginManager.installing && root.upgradeQueue.length === 0
                    materialIcon: "upgrade"
                    mainText: Translation.tr("Update all (%1)").arg(PluginStore.updatesAvailable)
                    onClicked: root.updateAll()
                }

                RippleButtonWithIcon {
                    enabled: !PluginStore.fetching
                    materialIcon: "refresh"
                    mainText: PluginStore.fetching
                        ? Translation.tr("Refreshing…") : Translation.tr("Refresh")
                    onClicked: PluginStore.refresh()
                }
            }

            ConfigTextArea {
                id: searchField
                Layout.fillWidth: true
                buttonIcon: "search"
                text: Translation.tr("Search widgets")
                placeholderText: Translation.tr("Name, description or tag")
                fieldWidth: 300
                singleLine: true
            }

            Flow {
                Layout.fillWidth: true
                spacing: Appearance.spacing.space50

                Repeater {
                    model: PluginManager.surfaceCapabilities

                    FilterChip {
                        required property var modelData
                        label: modelData.label
                        chipIcon: modelData.icon
                        toggled: root.capabilityFilter === modelData.value
                        onClicked: root.capabilityFilter =
                            root.capabilityFilter === modelData.value ? "" : modelData.value
                    }
                }

                FilterChip {
                    label: Translation.tr("Installed")
                    chipIcon: "download_done"
                    toggled: root.installedOnly
                    onClicked: root.installedOnly = !root.installedOnly
                }
            }

            // Fetch/parse failures. A parse error can quote registry content
            // (e.g. the unsupported version value), so render as plain text.
            StyledText {
                Layout.fillWidth: true
                visible: PluginStore.lastError.length > 0
                textFormat: Text.PlainText
                text: PluginStore.lastError
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colError
                wrapMode: Text.Wrap
            }

            // Install/update results, same plumbing as PluginsPage. The
            // message can embed installer output derived from package data.
            StyledText {
                Layout.fillWidth: true
                visible: PluginManager.installMessage.length > 0
                textFormat: Text.PlainText
                text: PluginManager.installMessage
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.filteredEntries.length === 0
                text: PluginStore.fetching
                    ? Translation.tr("Fetching widget catalog…")
                    : (PluginStore.entries.length === 0
                        ? Translation.tr("No widgets in the catalog yet.")
                        : Translation.tr("No widgets match the current filters."))
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }

            Repeater {
                model: root.filteredEntries

                Rectangle {
                    id: card
                    required property var modelData
                    readonly property string status: PluginStore.statusForEntry(modelData)
                    readonly property string screenshotUrl: {
                        const url = card.modelData.screenshot;
                        return (typeof url === "string" && url.startsWith("https://")) ? url : "";
                    }

                    Layout.fillWidth: true
                    Layout.topMargin: Appearance.spacing.space100
                    implicitHeight: cardColumn.implicitHeight + Appearance.spacing.space150 * 2
                    color: Appearance.colors.colLayer1
                    radius: Appearance.rounding.normal

                    ColumnLayout {
                        id: cardColumn
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: Appearance.spacing.space150
                        }
                        spacing: Appearance.spacing.space75

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Appearance.spacing.space100

                            // The icon name is registry-sourced but only ever
                            // rendered as a Material Symbols ligature; an
                            // unknown name shows nothing harmful. Plain text
                            // regardless.
                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                textFormat: Text.PlainText
                                text: (card.modelData.icon && card.modelData.icon.length > 0)
                                    ? card.modelData.icon : "extension"
                                iconSize: Appearance.font.pixelSize.hugeass
                                color: Appearance.colors.colOnLayer1
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Appearance.spacing.space75

                                    StyledText {
                                        textFormat: Text.PlainText
                                        text: card.modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.large
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colOnLayer1
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        textFormat: Text.PlainText
                                        text: `v${card.modelData.version}`
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                    }
                                    MaterialSymbol {
                                        visible: card.modelData.featured === true
                                        text: "star"
                                        fill: 1
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colPrimary
                                    }
                                    Item { Layout.fillWidth: true }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: Translation.tr("By %1")
                                        .arg(card.modelData.author ?? Translation.tr("Unknown creator"))
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                    elide: Text.ElideRight
                                }
                            }

                            RippleButton {
                                id: actionButton
                                readonly property var actionSpec: {
                                    switch (card.status) {
                                    case "available":
                                        return { label: Translation.tr("Install"), actionable: true };
                                    case "update":
                                        return { label: Translation.tr("Update"), actionable: true };
                                    case "installed":
                                        return { label: Translation.tr("Installed"), actionable: false };
                                    case "bundled":
                                        return { label: Translation.tr("Bundled"), actionable: false };
                                    default: // incompatible
                                        return { label: Translation.tr("Needs newer shell"), actionable: false };
                                    }
                                }
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: actionLabel.implicitWidth + Appearance.spacing.space300
                                implicitHeight: 36
                                enabled: actionSpec.actionable && !PluginManager.installing
                                buttonRadius: Appearance.rounding.full
                                colBackground: actionSpec.actionable
                                    ? Appearance.colors.colSecondaryContainer
                                    : Appearance.colors.colLayer2
                                onClicked: {
                                    if (card.status === "available")
                                        PluginStore.requestInstall(card.modelData);
                                    else if (card.status === "update")
                                        PluginStore.requestUpgrade(card.modelData);
                                }

                                contentItem: StyledText {
                                    id: actionLabel
                                    anchors.centerIn: parent
                                    text: actionButton.actionSpec.label
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: actionButton.enabled
                                        ? Appearance.colors.colOnSecondaryContainer
                                        : Appearance.colors.colSubtext
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: (card.modelData.description ?? "").length > 0
                            textFormat: Text.PlainText
                            text: card.modelData.description ?? ""
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSurfaceVariant
                            wrapMode: Text.Wrap
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: Appearance.spacing.space50

                            Repeater {
                                model: card.modelData.capabilities ?? []

                                Rectangle {
                                    required property string modelData
                                    implicitWidth: capabilityLabel.implicitWidth + Appearance.spacing.space150
                                    implicitHeight: capabilityLabel.implicitHeight + Appearance.spacing.space50
                                    radius: Appearance.rounding.full
                                    color: Appearance.colors.colSecondaryContainer

                                    StyledText {
                                        id: capabilityLabel
                                        anchors.centerIn: parent
                                        textFormat: Text.PlainText
                                        text: modelData
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnSecondaryContainer
                                    }
                                }
                            }

                            Repeater {
                                model: card.modelData.permissions ?? []

                                Rectangle {
                                    id: permissionChip
                                    required property string modelData
                                    implicitWidth: permissionRow.implicitWidth + Appearance.spacing.space150
                                    implicitHeight: permissionRow.implicitHeight + Appearance.spacing.space50
                                    radius: Appearance.rounding.full
                                    color: Appearance.colors.colLayer2

                                    RowLayout {
                                        id: permissionRow
                                        anchors.centerIn: parent
                                        spacing: Appearance.spacing.space25

                                        MaterialSymbol {
                                            text: "shield"
                                            iconSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colOnLayer2
                                        }
                                        StyledText {
                                            textFormat: Text.PlainText
                                            text: permissionChip.modelData
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colOnLayer2
                                        }
                                    }
                                }
                            }
                        }

                        // Screenshot: fixed slot so cards don't reflow while
                        // the network image loads; Qt handles the fetch and
                        // its disk cache. Only present when the entry has one.
                        Rectangle {
                            visible: card.screenshotUrl.length > 0
                            Layout.fillWidth: true
                            Layout.preferredHeight: card.screenshotUrl.length > 0 ? 160 : 0
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer2

                            Image {
                                id: screenshotImage
                                anchors.fill: parent
                                source: card.screenshotUrl
                                asynchronous: true
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: 800
                                layer.enabled: true
                                layer.effect: OpacityMask {
                                    maskSource: Rectangle {
                                        width: screenshotImage.width
                                        height: screenshotImage.height
                                        radius: Appearance.rounding.small
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
