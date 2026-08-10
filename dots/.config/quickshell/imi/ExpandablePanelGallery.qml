import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

/**
 * Interactive gallery for ExpandablePanel. Not shipped - excluded from the
 * deploy in sdata/lib/deploy-exclude.txt.
 *
 *   qs -p ExpandablePanelGallery.qml
 *
 * Left panel follows the switches; right panel stays on the component's
 * defaults so any trait can be compared against a baseline. Click a header to
 * expand, or use the buttons under the title.
 */
ShellRoot {
    id: gallery

    property bool useOutline: false
    property bool useDivider: true
    property bool useShapeMorph: false
    property bool useTonalLift: false
    property int useStagger: 0

    FloatingWindow {
        visible: true
        implicitWidth: 1120
        implicitHeight: 720
        // Same rule as the Settings window: a window's clear colour is constant
        // and the backdrop is painted, so an alpha-255 clear colour can never
        // latch the surface's Wayland opaque region. See AGENT.md.
        color: "transparent"

        Rectangle {
            id: galleryBackdrop
            anchors.fill: parent
            color: Appearance.colors.colLayer0
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Appearance.spacing.space300
            spacing: Appearance.spacing.space200

            StyledText {
                text: "ExpandablePanel — trait gallery"
                font.pixelSize: Appearance.font.pixelSize.huge
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                text: "Left follows the switches. Right stays on defaults. Click any header to toggle."
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            // ── trait switches ────────────────────────────────────────────
            FlowButtonGroup {
                Layout.fillWidth: true
                spacing: Appearance.spacing.space100

                TraitButton {
                    label: "Outline"; symbolName: "check_box_outline_blank"
                    active: gallery.useOutline
                    onClicked: gallery.useOutline = !gallery.useOutline
                }
                TraitButton {
                    label: "Hairline rule"; symbolName: "horizontal_rule"
                    active: gallery.useDivider
                    onClicked: gallery.useDivider = !gallery.useDivider
                }
                TraitButton {
                    label: "Shape morph"; symbolName: "rounded_corner"
                    active: gallery.useShapeMorph
                    onClicked: gallery.useShapeMorph = !gallery.useShapeMorph
                }
                TraitButton {
                    label: "Tonal lift"; symbolName: "layers"
                    active: gallery.useTonalLift
                    onClicked: gallery.useTonalLift = !gallery.useTonalLift
                }
                TraitButton {
                    label: "Stagger " + (gallery.useStagger === 0 ? "off" : gallery.useStagger + "ms")
                    symbolName: "animation"
                    active: gallery.useStagger > 0
                    onClicked: gallery.useStagger = gallery.useStagger === 0 ? 40
                             : gallery.useStagger === 40 ? 80
                             : gallery.useStagger === 80 ? 120 : 0
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.space200

                TraitButton {
                    label: "Expand both"; symbolName: "unfold_more"; active: false
                    onClicked: { left.expanded = true; right.expanded = true; }
                }
                TraitButton {
                    label: "Collapse both"; symbolName: "unfold_less"; active: false
                    onClicked: { left.expanded = false; right.expanded = false; }
                }
                Item { Layout.fillWidth: true }
            }

            // ── the two panels ────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: Appearance.spacing.space300

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: Appearance.spacing.space100
                    StyledText {
                        text: "Configured"
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colPrimary
                    }
                    DemoPanel {
                        id: left
                        Layout.fillWidth: true
                        outline: gallery.useOutline
                        divider: gallery.useDivider
                        shapeMorph: gallery.useShapeMorph
                        tonalLift: gallery.useTonalLift
                        staggerStep: gallery.useStagger
                        title: "Configured panel"
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: Appearance.spacing.space100
                    StyledText {
                        text: "Defaults"
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colSubtext
                    }
                    DemoPanel {
                        id: right
                        Layout.fillWidth: true
                        title: "Reference panel"
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }
    }

    component TraitButton: RippleButtonWithIcon {
        property string label: ""
        // NOT `icon`: that is FINAL on QQC2 Control and overriding it is a
        // hard compile failure (see AGENT.md).
        property string symbolName: ""
        property bool active: false
        materialIcon: symbolName
        mainText: label
        toggled: active
        colBackground: Appearance.colors.colLayer2
        colBackgroundToggled: Appearance.colors.colPrimary
    }

    // A panel with enough content that the motion is unmistakable, and a Flow
    // of buttons so the stagger has something to cascade through.
    component DemoPanel: ExpandablePanel {
        id: demo
        property string title: ""

        surfaceLayer: StyledRectangle.ContentLayer.Group
        headerClickable: true
        onHeaderClicked: demo.expanded = !demo.expanded
        staggerTarget: demoFlow

        header: [
            MaterialSymbol {
                text: demo.expanded ? "folder_open" : "folder"
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colPrimary
            },
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    text: demo.title
                    font.weight: Font.DemiBold
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    text: demo.expanded ? "expanded" : "collapsed"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            },
            IconToolbarButton {
                Layout.fillHeight: false
                implicitHeight: 36
                text: demo.expanded ? "expand_less" : "expand_more"
                onClicked: demo.expanded = !demo.expanded
            }
        ]

        StyledText {
            Layout.fillWidth: true
            text: "Revealed content. The leading edge is indented; the trailing edge stays aligned with the header above."
            wrapMode: Text.Wrap
            color: Appearance.colors.colOnLayer1
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 56
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer3
            StyledText {
                anchors.centerIn: parent
                text: "a block of content"
                color: Appearance.colors.colSubtext
            }
        }
        FlowButtonGroup {
            id: demoFlow
            Layout.fillWidth: true
            spacing: Appearance.spacing.space50
            Repeater {
                model: [
                    { icon: "play_arrow", label: "Start", on: true },
                    { icon: "pause", label: "Pause", on: false },
                    { icon: "stop", label: "Stop", on: false },
                    { icon: "terminal", label: "Shell", on: true },
                    { icon: "description", label: "Logs", on: true },
                    { icon: "delete", label: "Remove", on: true }
                ]
                delegate: RippleButtonWithIcon {
                    required property var modelData
                    materialIcon: modelData.icon
                    mainText: modelData.label
                    materialIconFill: false
                    enabled: modelData.on
                    colBackground: Appearance.colors.colLayer2
                }
            }
        }
    }
}
