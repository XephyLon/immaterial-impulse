pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import "gridSizes.js" as GridSizes

ColumnLayout {
    id: root

    required property var manifest
    spacing: Appearance.spacing.space25

    // The widget's own options come first, because they are what the user
    // opened this page for. The host's rows used to be concatenated in FRONT of
    // them - four identical switches before a widget's two or three real
    // settings, pushing them below the fold and reading as if the plugin had
    // declared them. They live in their own section below instead.
    readonly property var widgetOptions: manifest.options || []

    // Host blur is a desktop-widget mechanism (PluginWidget frost); bar/
    // overlay-only plugins were getting a dead "Blur background" toggle.
    readonly property bool hasBlurSurface: manifest.desktopWidget !== undefined
    // Lock and click-through are host behaviours too (AbstractBackgroundWidget),
    // not plugin-authored options, so they are synthesized here alongside the
    // blur row instead of being declared in a manifest `options` array. Their
    // manifest fields - `desktopWidget.locked` / `desktopWidget.clickThrough` -
    // only seed the default, which is what keeps a shipped default reversible.
    //
    // A row that cannot apply is omitted, not disabled: a control that can
    // never be enabled is noise. The greying-out this file does elsewhere is
    // for a row that is *temporarily* inert (`enabledWhen`), which is a
    // different thing.
    readonly property var behaviourRows: hasBlurSurface ? [{
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
    }, {
        // Turning transparency off makes every desktop widget's panel fully
        // opaque (PluginState.effectiveBackgroundOpacity). This is the escape
        // hatch for a widget whose whole point is to be see-through, and it is
        // the only way to undo a manifest that ships the exemption on.
        key: "keepTranslucent",
        type: "boolean",
        label: "Stay translucent",
        icon: "opacity",
        default: manifest.desktopWidget?.keepTranslucent === true
    }, {
        // The odd one out among the seeds: travelling with the desktop's
        // parallax pan is the default, so the manifest field can only turn it
        // OFF and the seed reads `!== false` rather than `=== true`.
        key: "followParallax",
        type: "boolean",
        label: "Follow parallax",
        icon: "panorama_horizontal",
        default: manifest.desktopWidget?.followParallax !== false
    }] : []

    // The size row and the drag grip are two faces of one value: both read and
    // write the host's `__gridSize`. The grip is what makes a resize quick; the
    // row is what makes it discoverable and reachable from the keyboard.
    //
    // Not every widget is resizable, and offering a size where the widget has
    // no layout for it is worse than offering nothing - so this is omitted
    // rather than disabled unless the manifest names more than one span.
    readonly property var offeredSizes: GridSizes.offeredSizes(manifest.grid)
    readonly property var sizeRows: root.offeredSizes.length > 1 ? [{
        key: "__gridSize",
        type: "choice",
        label: "Size",
        icon: "aspect_ratio",
        default: GridSizes.formatSize(GridSizes.defaultSize(manifest.grid)),
        choices: root.offeredSizes.map(size => ({
            displayName: `${size.cols} × ${size.rows}`,
            value: GridSizes.formatSize(size)
        }))
    }] : []

    Repeater {
        model: root.widgetOptions
        delegate: optionRow
    }

    // Every host row reads as one group rather than as more of the widget's own
    // settings. The same rows appear for every widget - that is the point, and
    // it is exactly why they should not sit among the plugin's.
    ContentSubsection {
        title: Translation.tr("Widget behaviour")

        // Not a pluginOption on purpose: preset application replaces those, and
        // this flag decides whether they get replaced (see presets.sh --apply).
        ConfigSwitch {
            id: presetPersistSwitch
            Layout.fillWidth: true
            leftPadding: 0
            rightPadding: 0
            buttonIcon: "push_pin"
            text: Translation.tr("Keep settings across presets")
            checked: PluginState.presetPersisted(root.manifest.id)
            onToggleRequested: PluginState.setPresetPersist(root.manifest.id,
                !PluginState.presetPersisted(root.manifest.id))
        }

        Repeater {
            model: root.sizeRows
            delegate: optionRow
        }

        Repeater {
            model: root.behaviourRows
            delegate: optionRow
        }
    }

    // One delegate for both groups: they differ in where they come from and
    // where they are drawn, never in how a row of a given type behaves.
    Component {
        id: optionRow

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
                    onToggleRequested: PluginState.setOption(root.manifest.id, optionLoader.optionData.key,
                        !PluginState.option(root.manifest.id, optionLoader.optionData.key, optionLoader.optionData.default))
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
