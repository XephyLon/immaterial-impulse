import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.plugins

// Plugin management page. Hosts two sibling views: the installed-plugin list
// and the plugin store (PluginStorePage), toggled by the "Browse plugins"
// button - the same host-a-component-in-the-parent-page mechanism that puts
// IconPackSelector inside InterfaceConfig, so the settings navigation host
// stays untouched.
Item {
    id: root

    // Store UI gate; the whole feature stays dormant while off (the flag is
    // config-file-only until the public registry exists).
    readonly property bool storeAvailable: Config.options.plugins.storeEnabled ?? false
    property bool showingStore: false
    onStoreAvailableChanged: if (!storeAvailable) showingStore = false

    // Filter state. Capability is single-select: clicking the active chip
    // clears it, matching the store's behaviour exactly.
    property string searchQuery: ""
    property string capabilityFilter: "" // "" = all surfaces
    property bool thirdPartyOnly: false

    // Filters combine with AND. Capability matching goes through
    // PluginManager.pluginSurfaces() rather than reading `capabilities`
    // directly, so manifests of the older declarative-JSON generation (clock)
    // still match the Desktop chip.
    readonly property var filteredPlugins: {
        const query = root.searchQuery.trim().toLowerCase();
        return PluginManager.availablePlugins.filter(plugin => {
            if (root.thirdPartyOnly && plugin._origin !== "installed")
                return false;
            if (root.capabilityFilter.length > 0
                    && !PluginManager.pluginSurfaces(plugin).includes(root.capabilityFilter))
                return false;
            if (query.length > 0) {
                const haystack = `${plugin.name ?? ""} ${plugin.description ?? ""}`.toLowerCase();
                if (!haystack.includes(query)) return false;
            }
            return true;
        });
    }

    // Forwarded so SettingsContent's section rail keeps tracking this page
    // exactly as it did when ContentPage was the root item.
    readonly property string currentSection: root.showingStore ? "" : listPage.currentSection
    readonly property var availableSections: listPage.availableSections

    // Section navigation from the rail always targets the list view. The
    // section itself is intentionally unused: ContentPage exposes no goTo,
    // and this page never scrolled to sections (only pages that implement
    // their own title-matching goTo, like QuickConfig, do).
    function goTo(section) {
        root.showingStore = false;
    }

    ContentPage {
        id: listPage
        anchors.fill: parent
        visible: !root.showingStore
        forceWidth: true

        ContentSection {
            title: Translation.tr("Available Plugins")
            Layout.fillWidth: true
            icon: "extension"
            shape: MaterialShape.Shape.Diamond

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.space25

                RowLayout {
                    // Store UI is gated off until the public registry goes
                    // live (config-file-only flag, no settings toggle).
                    visible: root.storeAvailable
                    Layout.fillWidth: true
                    Layout.bottomMargin: Appearance.spacing.space100
                    spacing: Appearance.spacing.space100

                    // M3 filled button: the store entry point is the page's
                    // primary action, so it gets full emphasis instead of the
                    // tonal RippleButtonWithIcon look used for inline actions.
                    RippleButton {
                        id: browseButton
                        implicitHeight: 44
                        horizontalPadding: Appearance.spacing.space250
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colRipple: Appearance.colors.colPrimaryActive
                        onClicked: root.showingStore = true

                        contentItem: RowLayout {
                            spacing: Appearance.spacing.space100

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: "storefront"
                                iconSize: Appearance.font.pixelSize.huge
                                fill: 1
                                color: Appearance.colors.colOnPrimary
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                text: Translation.tr("Browse plugins")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }

                    // Update-count pill: how many installed plugins have a
                    // newer version in the store registry.
                    Rectangle {
                        // storeAvailable first: && short-circuits, so a
                        // disabled store never touches the singleton.
                        visible: root.storeAvailable && PluginStore.updatesAvailable > 0
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: updateBadgeRow.implicitWidth + Appearance.spacing.space150
                        implicitHeight: updateBadgeRow.implicitHeight + Appearance.spacing.space50
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colPrimary

                        RowLayout {
                            id: updateBadgeRow
                            anchors.centerIn: parent
                            spacing: Appearance.spacing.space25

                            MaterialSymbol {
                                text: "upgrade"
                                iconSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnPrimary
                            }
                            StyledText {
                                text: root.storeAvailable ? PluginStore.updatesAvailable : 0
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnPrimary
                            }
                        }

                        HoverHandler { id: updateBadgeHover }
                        StyledToolTip {
                            extraVisibleCondition: updateBadgeHover.hovered
                            text: Translation.tr("Plugin updates available in the store")
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                GroupedList {
                    Layout.fillWidth: true

                    ConfigSelectionArray {
                        Layout.fillWidth: true
                        text: Translation.tr("Plugin frost")
                        icon: "blur_on"
                        currentValue: Config.options.plugins.frostMode
                        onSelected: newValue => {
                            if (newValue !== Config.options.plugins.frostMode)
                                Config.options.plugins.frostMode = newValue;
                        }
                        options: [
                            { displayName: Translation.tr("Tint"), icon: "format_color_fill", value: "tint" },
                            { displayName: Translation.tr("Blur"), icon: "blur_on", value: "blur" }
                        ]
                    }

                    ConfigSlider {
                        Layout.fillWidth: true
                        text: Translation.tr("Blurred plugin opacity")
                        buttonIcon: "opacity"
                        from: 0
                        to: 1
                        usePercentTooltip: true
                        value: Config.options.plugins.blurOpacity
                        onValueChanged: {
                            const rounded = Math.round(value * 20) / 20;
                            if (rounded !== Config.options.plugins.blurOpacity)
                                Config.options.plugins.blurOpacity = rounded;
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.spacing.space100

                    ConfigTextArea {
                        id: manifestUrl
                        Layout.fillWidth: true
                        buttonIcon: "extension"
                        text: Translation.tr("Plugin manifest URL")
                        placeholderText: Translation.tr("https://…/manifest.json")
                        fieldWidth: 300
                        singleLine: true
                    }
                    RippleButton {
                        implicitWidth: installLabel.implicitWidth + Appearance.spacing.space300
                        implicitHeight: 44
                        enabled: !PluginManager.installing
                        buttonRadius: Appearance.rounding.full
                        // ConfigTextArea.text is the row label; the field content is
                        // its `value` alias.
                        releaseAction: () => PluginManager.installFromManifest(manifestUrl.value.trim())
                        contentItem: StyledText {
                            id: installLabel
                            anchors.centerIn: parent
                            text: PluginManager.installing ? Translation.tr("Installing…") : Translation.tr("Install")
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: PluginManager.installMessage.length > 0
                    text: PluginManager.installMessage
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }

                ConfigTextArea {
                    id: searchField
                    Layout.fillWidth: true
                    Layout.bottomMargin: Appearance.spacing.space100
                    buttonIcon: "search"
                    text: Translation.tr("Search widgets")
                    placeholderText: Translation.tr("Name or description")
                    fieldWidth: 300
                    singleLine: true
                    // `text` is this control's label; `value` is what the user
                    // typed.
                    onValueChanged: root.searchQuery = searchField.value
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.bottomMargin: Appearance.spacing.space100
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
                        label: Translation.tr("Third-party")
                        chipIcon: "extension"
                        toggled: root.thirdPartyOnly
                        onClicked: root.thirdPartyOnly = !root.thirdPartyOnly
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.filteredPlugins.length === 0
                    text: Translation.tr("No widgets match these filters.")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }

                Repeater {
                    model: root.filteredPlugins

                    // One plugin = one bordered card: the enable header and its
                    // options live in a single rounded surface with a distinct
                    // accent border, and a clear gap separates each plugin from the
                    // next, so it is unambiguous which options belong to which plugin.
                    ExpandablePanel {
                        id: pluginCard
                        required property var modelData

                        // The matching registry entry, when this plugin is
                        // listed in the store: drives the Update button. The
                        // store gate short-circuits first so a disabled store
                        // never instantiates the PluginStore singleton here.
                        readonly property var storeEntry: {
                            if (!root.storeAvailable)
                                return null;
                            for (const entry of PluginStore.entries)
                                if (entry.id === pluginCard.modelData.id)
                                    return entry;
                            return null;
                        }
                        readonly property bool updateAvailable: storeEntry !== null
                            && PluginStore.statusForEntry(storeEntry) === "update"

                        Layout.fillWidth: true
                        Layout.topMargin: Appearance.spacing.space100
                        // The switch that enables the plugin is also what reveals
                        // its options; ExpandablePanel takes the state, not the
                        // control, so the trigger stays where it belongs.
                        expanded: configSwitch.checked

                        header: [
                                ConfigSwitch {
                                    id: configSwitch
                                    Layout.fillWidth: true

                                    property var modelData: pluginCard.modelData
                                    text: modelData.name
                                    // Larger + heavier than the option-row labels so
                                    // the plugin name reads as the card's heading.
                                    font.pixelSize: Appearance.font.pixelSize.large
                                    font.weight: Font.DemiBold
                                    description: {
                                        const summary = modelData.description || "";
                                        const creator = modelData.author || Translation.tr("Unknown creator");
                                        // Manifest version, when declared, rides on the creator line.
                                        const byline = modelData.version
                                            ? `${Translation.tr("By")} ${creator} · v${modelData.version}`
                                            : `${Translation.tr("By")} ${creator}`;
                                        return summary.length > 0 ? `${summary}\n${byline}` : byline;
                                    }

                                    property bool isEnabled: Config.options.plugins.enabled.includes(modelData.id)
                                    checked: isEnabled
                                    onCheckedChanged: {
                                        let newList = [];
                                        for (let i = 0; i < Config.options.plugins.enabled.length; i++) {
                                            newList.push(Config.options.plugins.enabled[i]);
                                        }
                                        if (checked && !isEnabled) {
                                            newList.push(modelData.id);
                                        } else if (!checked && isEnabled) {
                                            newList = newList.filter(id => id !== modelData.id);
                                        }
                                        Config.setNestedValue("plugins.enabled", newList);
                                    }
                                },

                                // A newer version exists in the store registry.
                                RippleButtonWithIcon {
                                    visible: pluginCard.updateAvailable
                                    enabled: !PluginManager.installing
                                    Layout.alignment: Qt.AlignVCenter
                                    materialIcon: "upgrade"
                                    mainText: Translation.tr("Update")
                                    onClicked: PluginStore.upgrade(pluginCard.storeEntry)

                                    StyledToolTip {
                                        text: Translation.tr("Update to v%1")
                                            .arg(pluginCard.storeEntry?.version ?? "")
                                    }
                                },

                                // Third-party badge: installed plugins come from an
                                // external source (not shipped with the shell), so flag
                                // them so the user knows to trust the source.
                                Rectangle {
                                    visible: pluginCard.modelData._origin === "installed"
                                    Layout.alignment: Qt.AlignVCenter
                                    implicitWidth: badgeRow.implicitWidth + Appearance.spacing.space150
                                    implicitHeight: badgeRow.implicitHeight + Appearance.spacing.space50
                                    radius: Appearance.rounding.full
                                    color: Appearance.colors.colSecondaryContainer

                                    RowLayout {
                                        id: badgeRow
                                        anchors.centerIn: parent
                                        spacing: Appearance.spacing.space25
                                        MaterialSymbol {
                                            text: "public"
                                            iconSize: Appearance.font.pixelSize.small
                                            color: Appearance.colors.colOnSecondaryContainer
                                        }
                                        StyledText {
                                            text: Translation.tr("Third-party")
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colOnSecondaryContainer
                                        }
                                    }

                                    HoverHandler { id: badgeHover }
                                    StyledToolTip {
                                        // Rectangle has no `hovered` property, so gate
                                        // explicitly or the tooltip stays visible.
                                        extraVisibleCondition: badgeHover.hovered
                                        text: Translation.tr("Installed from an external source — only enable plugins you trust")
                                    }
                                },

                                // Only installed packages live on disk and can be removed;
                                // bundled plugins ship with the shell. Removal is gated on
                                // the plugin being disabled so a running plugin is never
                                // pulled out from under itself.
                                RippleButton {
                                    id: deleteButton
                                    visible: pluginCard.modelData._origin === "installed"
                                    enabled: !configSwitch.isEnabled && !PluginManager.uninstalling
                                    Layout.alignment: Qt.AlignVCenter
                                    implicitWidth: 36
                                    implicitHeight: 36
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: "transparent"
                                    colBackgroundHover: Appearance.colors.colLayer2
                                    onClicked: PluginManager.requestUninstall(pluginCard.modelData.id)

                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "delete"
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: deleteButton.enabled
                                            ? Appearance.colors.colError : Appearance.colors.colSubtext
                                    }

                                    StyledToolTip {
                                        text: configSwitch.isEnabled
                                            ? Translation.tr("Disable the plugin before deleting")
                                            : Translation.tr("Delete plugin")
                                    }
                                }
                        ]

                        GroupedList {
                            id: optionsList
                            Layout.fillWidth: true
                            // Transparent so the option rows read as part of
                            // the unified card instead of nested sub-cards.
                            bgcolor: "transparent"

                            PluginOptions {
                                manifest: pluginCard.modelData
                            }
                        }
                    }
                }
            }
        }
    }

    // Loader (not a bare instance) so a gated-off store never constructs the
    // page or wakes the PluginStore singleton at all.
    Loader {
        active: root.storeAvailable
        anchors.fill: parent
        visible: root.showingStore
        sourceComponent: PluginStorePage {
            onCloseRequested: root.showingStore = false
        }
    }
}
