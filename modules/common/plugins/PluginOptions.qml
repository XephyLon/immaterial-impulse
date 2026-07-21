pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root

    required property var manifest
    spacing: Appearance.spacing.space25

    readonly property var optionRows: [{
        key: "blurEnabled",
        type: "boolean",
        label: "Blur background",
        icon: "blur_on",
        default: manifest.blur?.default ?? (manifest.desktopWidget?.blur === true)
    }].concat(manifest.options || [])

    Repeater {
        model: root.optionRows

        Loader {
            id: optionLoader
            required property var modelData
            Layout.fillWidth: true
            property var optionData: modelData
            visible: !optionData.enabledWhen
                || PluginState.option(root.manifest.id, optionData.enabledWhen, false)
            enabled: visible
            Layout.preferredHeight: visible ? implicitHeight : 0

            sourceComponent: {
                switch (optionData.type) {
                case "boolean": return booleanOption;
                case "choice": return choiceOption;
                case "number": return numberOption;
                case "text": return textOption;
                default: return null;
                }
            }

            Component {
                id: booleanOption
                ConfigSwitch {
                    Layout.fillWidth: true
                    leftPadding: 0
                    rightPadding: 0
                    buttonIcon: optionLoader.optionData.icon || "tune"
                    text: optionLoader.optionData.label
                    checked: PluginState.option(root.manifest.id, optionLoader.optionData.key, optionLoader.optionData.default)
                    onCheckedChanged: {
                        if (checked !== PluginState.option(root.manifest.id, optionLoader.optionData.key, optionLoader.optionData.default))
                            PluginState.setOption(root.manifest.id, optionLoader.optionData.key, checked);
                    }
                }
            }

            Component {
                id: choiceOption
                ConfigSelectionArray {
                    Layout.fillWidth: true
                    text: optionLoader.optionData.label
                    icon: optionLoader.optionData.icon || "tune"
                    options: optionLoader.optionData.choices || []
                    currentValue: PluginState.option(root.manifest.id, optionLoader.optionData.key, optionLoader.optionData.default)
                    onSelected: value => PluginState.setOption(root.manifest.id, optionLoader.optionData.key, value)
                }
            }

            Component {
                id: numberOption
                ConfigSlider {
                    Layout.fillWidth: true
                    text: optionLoader.optionData.label
                    textWidth: optionLoader.optionData.labelWidth ?? 176
                    buttonIcon: optionLoader.optionData.icon || "tune"
                    usePercentTooltip: optionLoader.optionData.usePercentTooltip === true
                    from: optionLoader.optionData.from ?? 0
                    to: optionLoader.optionData.to ?? 100
                    value: PluginState.option(root.manifest.id, optionLoader.optionData.key, optionLoader.optionData.default)
                    onValueChanged: {
                        const step = optionLoader.optionData.step ?? 1;
                        const rounded = Math.round(value / step) * step;
                        if (rounded !== PluginState.option(root.manifest.id, optionLoader.optionData.key, optionLoader.optionData.default))
                            PluginState.setOption(root.manifest.id, optionLoader.optionData.key, rounded);
                    }
                }
            }

            Component {
                id: textOption
                ConfigTextArea {
                    Layout.fillWidth: true
                    buttonIcon: optionLoader.optionData.icon || "text_fields"
                    text: optionLoader.optionData.label
                    placeholderText: optionLoader.optionData.placeholder || ""
                    fieldWidth: 160
                    value: String(PluginState.option(root.manifest.id,
                        optionLoader.optionData.key, optionLoader.optionData.default))
                    onValueChanged: {
                        const trimmed = value.trim();
                        if (trimmed.length === 0) return;
                        const transformed = optionLoader.optionData.uppercase === true
                            ? trimmed.toUpperCase() : trimmed;
                        const normalized = transformed.slice(0, optionLoader.optionData.maxLength ?? 64);
                        if (normalized !== PluginState.option(root.manifest.id,
                                optionLoader.optionData.key, optionLoader.optionData.default))
                            PluginState.setOption(root.manifest.id, optionLoader.optionData.key, normalized);
                    }
                }
            }
        }
    }
}
