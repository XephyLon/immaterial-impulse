pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.imi.modes
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Parameters of the `launch` action. `row` is the ActionRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    id: launchCol
    required property var row

    spacing: Appearance.spacing.space125

    property string appQuery: ""
    readonly property var appResults: {
        const q = appQuery.trim();
        if (!q.length)
            return [];
        return Array.from(AppSearch.fuzzyQuery(q)).slice(0, 6);
    }
    readonly property bool useCommand: (row.obj.command ?? "").length > 0 && !(row.obj.app ?? "").length

    FormChoice {
        text: Translation.tr("Launch")
        current: launchCol.useCommand ? "command" : "app"
        onPicked: v => row.patchValue(v === "command" ? { app: "", command: row.obj.command || "" }
                                                        : { command: "", app: row.obj.app || "" })
        options: [
            { displayName: Translation.tr("An app"), value: "app" },
            { displayName: Translation.tr("A command"), value: "command" }
        ]
    }

    // App: the chosen entry, or a search to choose one.
    ColumnLayout {
        id: appPicker
        Layout.fillWidth: true
        visible: !launchCol.useCommand
        spacing: Appearance.spacing.space75

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space100

            // The chosen entry as the shell's chip; its trailing glyph says
            // a press clears it.
            FilterChip {
                visible: (row.obj.app ?? "").length > 0
                label: DesktopEntries.byId(row.obj.app ?? "")?.name ?? (row.obj.app ?? "")
                trailingIcon: "close"
                onClicked: row.patchValue({ app: "" })
            }

            // A live search, so it is the shell's field directly rather than
            // the commit-on-finish PlainField.
            ToolbarTextField {
                id: appSearch
                Layout.fillWidth: true
                Layout.fillHeight: false
                implicitHeight: 36
                focusRing: true
                colBackground: Appearance.colors.colLayer3
                color: Appearance.colors.colOnLayer3
                placeholderText: (row.obj.app ?? "").length ? Translation.tr("Search to replace")
                                                            : Translation.tr("Search apps")
                onTextChanged: launchCol.appQuery = text
            }
        }

        Repeater {
            model: launchCol.appResults

            delegate: RippleButton {
                id: appResult
                required property var modelData

                Layout.fillWidth: true
                implicitHeight: 36
                buttonRadius: Appearance.rounding.small
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer3Hover
                colRipple: Appearance.colors.colLayer3Active
                onClicked: {
                    row.patchValue({ app: appResult.modelData.id, command: "" });
                    appSearch.text = "";
                }

                contentItem: RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: Appearance.spacing.space125
                        rightMargin: Appearance.spacing.space125
                    }
                    spacing: Appearance.spacing.space100

                    StyledText {
                        Layout.fillWidth: true
                        text: appResult.modelData.name
                        elide: Text.ElideRight
                        color: Appearance.colors.colOnLayer2
                    }

                    StyledText {
                        text: appResult.modelData.id
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }

    PlainField {
        Layout.fillWidth: true
        visible: launchCol.useCommand
        monospace: true
        value: String(row.obj.command ?? "")
        placeholder: Translation.tr("Command line, run with sh -c")
        onCommitted: v => row.patchValue({ command: v, app: "" })
    }

    RowLayout {
        spacing: Appearance.spacing.space125

        FormLabel {
            text: Translation.tr("When it ends")
        }

        FormChoice {
            current: row.obj.onEnd ?? "keep"
            onPicked: v => row.patchValue({ onEnd: v })
            options: [
                { displayName: Translation.tr("Leave it open"), value: "keep" },
                { displayName: Translation.tr("Close it"), value: "close" }
            ]
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: (row.obj.onEnd ?? "keep") === "close"
        spacing: Appearance.spacing.space125

        FormLabel {
            text: Translation.tr("Window class")
        }

        PlainField {
            Layout.fillWidth: true
            value: String(row.obj["class"] ?? "")
            placeholder: Translation.tr("Only if it differs from the app's own")
            onCommitted: v => row.patchValue({ "class": v })
        }
    }
}
