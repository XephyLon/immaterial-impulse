pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root

    required property var manifest
    spacing: Appearance.spacing.space25

    // Host blur is a desktop-widget mechanism (PluginWidget frost); bar/
    // overlay-only plugins were getting a dead "Blur background" toggle.
    readonly property bool hasBlurSurface: manifest.desktopWidget !== undefined
    // Lock and click-through are host behaviours too (AbstractBackgroundWidget),
    // not plugin-authored options, so they are synthesized here alongside the
    // blur row instead of being declared in a manifest `options` array. Their
    // manifest fields - `desktopWidget.locked` / `desktopWidget.clickThrough` -
    // only seed the default, which is what keeps a shipped default reversible.
    readonly property var optionRows: (hasBlurSurface ? [{
        key: "blurEnabled",
        type: "boolean",
        label: "Blur background",
        icon: "blur_on",
        default: manifest.blur?.default ?? (manifest.desktopWidget?.blur === true)
    }, {
        key: "positionLocked",
        type: "boolean",
        label: "Lock position",
        icon: "lock",
        default: manifest.desktopWidget?.locked === true
    }, {
        key: "clickThrough",
        type: "boolean",
        label: "Click through",
        icon: "do_not_touch",
        default: manifest.desktopWidget?.clickThrough === true
    }] : []).concat(manifest.options || [])

    // Not a pluginOption on purpose: preset application replaces those, and
    // this flag decides whether they get replaced (see presets.sh --apply).
    ConfigSwitch {
        Layout.fillWidth: true
        leftPadding: 0
        rightPadding: 0
        buttonIcon: "push_pin"
        text: Translation.tr("Keep settings across presets")
        checked: PluginState.presetPersisted(root.manifest.id)
        onCheckedChanged: {
            if (checked !== PluginState.presetPersisted(root.manifest.id))
                PluginState.setPresetPersist(root.manifest.id, checked);
        }
    }

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
                case "shape": return shapeOption;
                case "color": return colorOption;
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

            // Material shapes are their own preview: a name-chip row for 31
            // shapes is both unreadable and unlabelable (ConfigSelectionArray's
            // chip Flow only wraps when it has no label). Draw the shape.
            Component {
                id: shapeOption
                ConfigSelectionShapeArray {
                    options: (optionLoader.optionData.choices || [])
                        .map(choice => choice.value ?? choice)
                    currentValue: PluginState.option(root.manifest.id, optionLoader.optionData.key, optionLoader.optionData.default)
                    onSelected: value => PluginState.setOption(root.manifest.id, optionLoader.optionData.key, value)
                }
            }

            // A palette role is its own preview too, and the roles are fixed by
            // the theme rather than by the plugin - so there are no `choices`,
            // only the swatch row ColorSelectionArray already draws. The empty
            // string is a real value here: "no override, follow the widget's
            // own colour", which is why the row pairs with a boolean.
            Component {
                id: colorOption
                ColorSelectionArray {
                    icon: optionLoader.optionData.icon || "palette"
                    text: optionLoader.optionData.label
                    options: (optionLoader.optionData.choices || [])
                        .map(choice => choice.value ?? choice)
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
                    // A 0..1 (or smaller) range is a fraction; show it as a
                    // percent so the tooltip isn't int-rounded to 0/1.
                    usePercentTooltip: optionLoader.optionData.usePercentTooltip === true
                        || (optionLoader.optionData.to ?? 100) <= 1
                    from: optionLoader.optionData.from ?? 0
                    to: optionLoader.optionData.to ?? 100
                    value: PluginState.option(root.manifest.id, optionLoader.optionData.key, optionLoader.optionData.default)
                    onValueModified: {
                        const step = optionLoader.optionData.step ?? 1;
                        const rounded = Math.round(newValue / step) * step;
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
