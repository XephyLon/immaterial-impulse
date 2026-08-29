import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * One widget, on its own, with the controls a design review actually needs:
 * the surface it is drawn on, the states it can be put into, live knobs for
 * whatever it declares, and what it measured out to.
 *
 * The surface switcher is the point of the whole page. Nearly every colour
 * mistake this shell has shipped was a widget that looked right on the layer
 * it was written against and wrong on the one it got used on, and there was
 * nowhere to see that except by building the other screen.
 */
Item {
    id: root

    required property var entry

    // Knobs write here; ComponentStage merges them over the catalogue's props
    // and rebuilds. Reset when the selection changes, or a text knob typed for
    // one widget would follow you to the next.
    property var overrides: ({})
    // The switch below expresses INTENT and this holds the state, rather than
    // the switch answering its own click with `checked = !checked` - which
    // destroys the binding every settings page puts on that property. 159 call
    // sites shipped that once; lint_config_switch_intent.py is why, and it
    // caught this one.
    property bool showBounds: false
    onEntryChanged: {
        root.overrides = ({});
        surfaces.currentIndex = 2;
    }

    readonly property var surfaceTokens: [
        { name: "Layer 0", colour: Appearance.colors.colLayer0 },
        { name: "Layer 1", colour: Appearance.colors.colLayer1 },
        { name: "Layer 2", colour: Appearance.colors.colLayer2 },
        { name: "Layer 3", colour: Appearance.colors.colLayer3 },
        { name: "Surface", colour: Appearance.m3colors.m3surface },
    ]

    // Knobs are derived, not written per entry: the catalogue's own props say
    // what a widget takes, and their JS types say how to edit them. A knob
    // list maintained by hand beside a 60-entry catalogue is a list that goes
    // stale on the first new widget.
    readonly property var knobs: {
        const out = [];
        const props = root.entry?.props ?? {};
        for (const name of Object.keys(props)) {
            const value = props[name];
            const kind = typeof value === "boolean" ? "bool"
                : typeof value === "number" ? "number" : "text";
            out.push({ name: name, kind: kind, initial: value });
        }
        // `toggled` only where the type MEANS it.
        //
        // Every RippleButton descendant inherits the property, so offering it
        // wherever it exists put a toggle switch on 46 of 62 component pages
        // that changed nothing visible - a control claiming a state it has no
        // appearance for. The catalogue names the sixteen that read it, and
        // lint_component_gallery.py checks that claim against the source.
        //
        // `enabled` is different and stays everywhere: disabled is a real M3
        // state with a defined appearance, and every one of these has it.
        if (root.entry?.toggles)
            out.push({ name: "toggled", kind: "bool", initial: false });
        if (stage.measurements?.hasEnabled)
            out.push({ name: "enabled", kind: "bool", initial: true });
        return out;
    }

    function setOverride(name, value) {
        const next = Object.assign({}, root.overrides);
        next[name] = value;
        root.overrides = next;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Appearance.spacing.space150

        // ---- the canvas -------------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 220
            radius: Appearance.rounding.normal
            // The one place an explicit colour is right: the canvas IS the
            // surface under test, so it paints whichever layer token the
            // switcher names rather than a role of its own.
            color: root.surfaceTokens[surfaces.currentIndex]?.colour
                ?? Appearance.colors.colLayer2
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant

            ComponentStage {
                id: stage
                anchors.centerIn: parent
                width: Math.min(parent.width - Appearance.spacing.space300 * 2,
                                Math.max(implicitWidth, 120))
                height: Math.max(implicitHeight, 48)
                entry: root.entry
                overrides: root.overrides
            }

            // The box the widget claims, drawn around what it drew. A control
            // whose implicit size does not match its content is the shape of
            // half the alignment bugs in this repo, and it is invisible until
            // something outlines it.
            Rectangle {
                visible: stage.control !== null && root.showBounds
                anchors.centerIn: stage
                width: stage.control?.implicitWidth ?? 0
                height: stage.control?.implicitHeight ?? 0
                color: "transparent"
                border.width: 1
                border.color: Appearance.colors.colPrimary
                radius: 2
            }
        }

        Toolbar {
            Layout.fillWidth: true
            enableShadow: false

            ToolbarTabBar {
                id: surfaces
                currentIndex: 2
                tabButtonList: root.surfaceTokens.map(surface => ({
                    "icon": "layers", "name": surface.name
                }))
            }
            Item { Layout.fillWidth: true }
            ConfigSwitch {
                text: Translation.tr("Implicit size")
                checked: root.showBounds
                onToggleRequested: root.showBounds = !root.showBounds
            }
        }

        // ---- knobs and measurements, side by side -------------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Appearance.spacing.space150

            ColumnLayout {
                Layout.preferredWidth: 320
                Layout.alignment: Qt.AlignTop
                spacing: Appearance.spacing.space50

                ContentSubsection {
                    Layout.fillWidth: true
                    title: Translation.tr("Knobs")
                    icon: "tune"
                }
                StyledText {
                    visible: root.knobs.length === 0
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("This widget takes nothing the catalogue knows how to edit.")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Repeater {
                    model: root.knobs
                    delegate: RowLayout {
                        id: knob
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Appearance.spacing.space100

                        StyledText {
                            Layout.preferredWidth: 120
                            elide: Text.ElideRight
                            color: Appearance.colors.colOnLayer1
                            text: knob.modelData.name
                        }

                        MaterialTextField {
                            visible: knob.modelData.kind === "text"
                            Layout.fillWidth: true
                            text: `${knob.modelData.initial}`
                            onTextChanged: root.setOverride(knob.modelData.name, text)
                        }
                        ConfigSpinBox {
                            visible: knob.modelData.kind === "number"
                            Layout.fillWidth: true
                            value: knob.modelData.kind === "number" ? knob.modelData.initial : 0
                            onValueModified: newValue => root.setOverride(knob.modelData.name, newValue)
                        }
                        StyledSwitch {
                            visible: knob.modelData.kind === "bool"
                            checked: knob.modelData.initial === true
                            onCheckedChanged: root.setOverride(knob.modelData.name, checked)
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: Appearance.spacing.space50

                ContentSubsection {
                    Layout.fillWidth: true
                    title: Translation.tr("Measured")
                    icon: "straighten"
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("Read off the built widget, not off the tokens its file names — a control that computes its size from a font reports neither.")
                }

                GroupedList {
                    Layout.fillWidth: true
                    model: {
                        const measured = stage.measurements;
                        if (!measured)
                            return [];
                        const rows = [{
                            name: Translation.tr("implicit size"),
                            value: `${measured.width?.toFixed(1)} × ${measured.height?.toFixed(1)}`
                        }];
                        const maybe = (label, value) => {
                            if (value !== undefined)
                                rows.push({ name: label,
                                            value: `${value.toFixed ? value.toFixed(1) : value}` });
                        };
                        maybe(Translation.tr("corner radius"), measured.radius);
                        maybe(Translation.tr("...held"), measured.radiusPressed);
                        maybe(Translation.tr("drawing now"), measured.cornerTopLeft);
                        maybe(Translation.tr("padding across"), measured.horizontalPadding);
                        maybe(Translation.tr("padding down"), measured.verticalPadding);
                        maybe(Translation.tr("font size"), measured.fontSize);
                        if (measured.background !== undefined)
                            rows.push({ name: Translation.tr("background"),
                                        value: `${measured.background}` });
                        return rows;
                    }
                    rowDelegate: Component {
                        CatalogueRow {
                            property var modelData: null
                            title: modelData?.name ?? ""
                            trailingContent: StyledText {
                                color: Appearance.colors.colOnLayer2
                                text: modelData?.value ?? ""
                            }
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.topMargin: Appearance.spacing.space100
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                    text: root.entry?.type ?? ""
                }
            }
        }
    }
}
