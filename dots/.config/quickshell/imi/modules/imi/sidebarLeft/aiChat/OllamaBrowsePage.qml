import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../../../services/ai/ollama_library.js" as Library
import QtQuick
import QtQuick.Layouts

/**
 * The Ollama page of the model browser (docs/proposals/ollama-catalog.md):
 * daemon status, what is installed and loaded, and the curated library with
 * a pull per tag. Every write goes through OllamaCatalog; a pull asks once,
 * stating the size and the free space, and streams its progress in the row.
 * The view counts itself into OllamaCatalog.watchers so the refresh timer
 * runs only while someone is looking.
 */
ColumnLayout {
    id: root
    spacing: Appearance.spacing.space100

    property string query: ""
    property string capability: "" // "" | tools | vision | embedding
    // The one tag awaiting confirmation, as "name:tag"; a second click pulls.
    property string armed: ""

    Component.onCompleted: OllamaCatalog.watchers++
    Component.onDestruction: OllamaCatalog.watchers--

    readonly property real freeVramGb: ResourceUsage.vramTotal > 1
        ? Math.max(0, (ResourceUsage.vramTotal - ResourceUsage.vramUsed) / 1024 / 1024) : 0
    readonly property real totalRamGb: ResourceUsage.memoryTotal > 1 ? ResourceUsage.memoryTotal / 1024 / 1024 : 0
    readonly property var filteredLibrary: Library.filterModels(OllamaCatalog.library, root.query, root.capability)
    readonly property var filteredInstalled: OllamaCatalog.installed.filter(m =>
        root.query.trim().length === 0 || m.name.toLowerCase().includes(root.query.trim().toLowerCase()))

    function fitColor(kind) {
        switch (kind) {
        case "vram": return Appearance.colors.colPrimary;
        case "ram": return Appearance.colors.colTertiary ?? Appearance.colors.colSubtext;
        case "no": return Appearance.m3colors.m3error;
        default: return Appearance.colors.colSubtext;
        }
    }
    function fitWord(kind) {
        switch (kind) {
        case "vram": return Translation.tr("fits GPU");
        case "ram": return Translation.tr("spills to RAM");
        case "no": return Translation.tr("too big");
        default: return "";
        }
    }
    function useModel(name) {
        Ai.refreshOllamaModels();
        Ai.setModel(Ai.safeModelName(name));
    }
    // Two clicks to pull: the first arms the tag and shows size + free space,
    // the second starts. Refused outright when it would not fit on disk.
    function requestPull(ref, gb) {
        if (root.armed !== ref) { root.armed = ref; return; }
        root.armed = "";
        const need = gb * 1e9;
        if (OllamaCatalog.diskFreeBytes >= 0 && need > OllamaCatalog.diskFreeBytes) {
            root.notice = Translation.tr("%1 needs about %2 and only %3 is free where Ollama stores models.")
                .arg(ref).arg(Library.sizeLabel(need)).arg(Library.sizeLabel(OllamaCatalog.diskFreeBytes));
            return;
        }
        const why = OllamaCatalog.pull(ref);
        root.notice = why;
    }
    property string notice: ""
    Connections {
        target: OllamaCatalog
        function onPullFinished(name, ok) {
            root.notice = ok ? Translation.tr("Pulled %1").arg(name)
                : Translation.tr("Pull of %1 failed: %2").arg(name).arg(OllamaCatalog.pullError);
            if (ok) Ai.refreshOllamaModels();
        }
        function onRemoved(name, ok) {
            root.notice = ok ? Translation.tr("Removed %1").arg(name) : Translation.tr("Could not remove %1").arg(name);
            if (ok) Ai.forgetOllamaModel(name);
        }
    }

    // ---- daemon status ----
    RowLayout {
        Layout.fillWidth: true
        spacing: Appearance.spacing.space100
        MaterialSymbol {
            text: OllamaCatalog.daemonUp ? "check_circle" : "error"
            fill: 1
            iconSize: Appearance.font.pixelSize.larger
            color: OllamaCatalog.daemonUp ? Appearance.colors.colPrimary : Appearance.m3colors.m3error
        }
        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: OllamaCatalog.daemonUp
                ? Translation.tr("Ollama running at %1 · %2 installed · %3 loaded").arg(OllamaCatalog.baseUrl)
                      .arg(OllamaCatalog.installed.length).arg(OllamaCatalog.running.length)
                : Translation.tr("Ollama is not running at %1").arg(OllamaCatalog.baseUrl)
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        DialogButton {
            visible: !OllamaCatalog.daemonUp
            buttonText: Translation.tr("Start")
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            colText: Appearance.colors.colOnPrimary
            onClicked: OllamaCatalog.startDaemon()
            StyledToolTip { text: "systemctl --user start ollama.service" }
        }
    }
    StyledText {
        visible: OllamaCatalog.startResult.length > 0 || root.notice.length > 0
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: OllamaCatalog.startResult.length > 0 ? OllamaCatalog.startResult : root.notice
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
    }

    // ---- pull in flight ----
    ColumnLayout {
        visible: OllamaCatalog.pulling || (OllamaCatalog.pullName.length > 0 && OllamaCatalog.pullError.length > 0)
        Layout.fillWidth: true
        spacing: Appearance.spacing.space50
        RowLayout {
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: OllamaCatalog.pullError.length > 0
                    ? Translation.tr("%1: %2").arg(OllamaCatalog.pullName).arg(OllamaCatalog.pullError)
                    : Translation.tr("Pulling %1 · %2").arg(OllamaCatalog.pullName).arg(OllamaCatalog.pullStatus)
                color: OllamaCatalog.pullError.length > 0 ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
            IconButton {
                visible: OllamaCatalog.pulling
                buttonIcon: "close"
                buttonSize: 28
                tooltip: Translation.tr("Cancel the pull")
                onClicked: OllamaCatalog.cancelPull()
            }
        }
        StyledProgressBar {
            visible: OllamaCatalog.pulling
            Layout.fillWidth: true
            valueBarWidth: parent.width
            value: OllamaCatalog.pullFraction >= 0 ? OllamaCatalog.pullFraction : 0
            indeterminate: OllamaCatalog.pullFraction < 0
        }
    }

    // ---- filters ----
    RowLayout {
        Layout.fillWidth: true
        spacing: Appearance.spacing.space50
        Repeater {
            model: [
                { id: "", label: Translation.tr("All") },
                { id: "tools", label: Translation.tr("Tools") },
                { id: "vision", label: Translation.tr("Vision") },
                { id: "embedding", label: Translation.tr("Embeddings") },
            ]
            delegate: FilterChip {
                required property var modelData
                label: modelData.label
                toggled: root.capability === modelData.id
                onClicked: root.capability = modelData.id
            }
        }
        Item { Layout.fillWidth: true }
        StyledText {
            text: Translation.tr("library %1").arg(OllamaCatalog.librarySnapshotDate)
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    // ---- pull by name ----
    RowLayout {
        Layout.fillWidth: true
        spacing: Appearance.spacing.space100
        ConfigTextArea {
            id: pullField
            Layout.fillWidth: true
            buttonIcon: "download"
            placeholderText: Translation.tr("Pull any model by name, e.g. qwen3:8b")
        }
        DialogButton {
            enabled: OllamaCatalog.daemonUp && !OllamaCatalog.pulling && pullField.value.trim().length > 0
            buttonText: Translation.tr("Pull")
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            colText: Appearance.colors.colOnSecondaryContainer
            onClicked: { root.notice = OllamaCatalog.pull(pullField.value.trim()); pullField.value = ""; }
        }
    }

    StyledFlickable {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentHeight: listColumn.implicitHeight

        ColumnLayout {
            id: listColumn
            width: parent.width
            spacing: Appearance.spacing.space25

            // ---- installed ----
            StyledText {
                visible: OllamaCatalog.daemonUp
                text: Translation.tr("Installed")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
            }
            StyledText {
                visible: OllamaCatalog.daemonUp && root.filteredInstalled.length === 0
                text: Translation.tr("Nothing installed yet - pull one from the library below.")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
            Repeater {
                model: root.filteredInstalled
                // The shell's catalogue row shape, drawn bare: this list is
                // not a control, the row's two actions are. The ink is
                // stated because the list sits on layer 1 rather than on a
                // tonal container.
                delegate: CatalogueRow {
                    id: installedRow
                    required property var modelData
                    readonly property bool loaded: OllamaCatalog.running.indexOf(installedRow.modelData.name) !== -1
                    readonly property bool current: Ai.currentModelId === Ai.safeModelName(installedRow.modelData.name)
                    readonly property bool armedForRemoval: root.armed === "remove:" + installedRow.modelData.name
                    Layout.fillWidth: true
                    rowSpacing: Appearance.spacing.space100

                    title: installedRow.modelData.name
                    titleFont.pixelSize: Appearance.font.pixelSize.small
                    titleColor: Appearance.colors.colOnLayer1
                    titleFillsWidth: true
                    titleElides: true
                    description: [Library.sizeLabel(installedRow.modelData.size), installedRow.modelData.parameterSize,
                        installedRow.modelData.quantization, installedRow.loaded ? Translation.tr("loaded") : ""]
                        .filter(s => s && s.length > 0).join(" · ")
                    descriptionColor: installedRow.loaded ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    descriptionWraps: false

                    trailingContent: [
                        DialogButton {
                            toggled: installedRow.current
                            buttonText: installedRow.current ? Translation.tr("In use") : Translation.tr("Use")
                            colBackground: installedRow.current ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                            colBackgroundHover: installedRow.current ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
                            colRipple: installedRow.current ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive
                            colText: installedRow.current ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                            onClicked: root.useModel(installedRow.modelData.name)
                        },
                        RippleButton {
                            implicitHeight: 28
                            padding: Appearance.spacing.space150
                            buttonRadius: Appearance.rounding.full
                            colBackground: installedRow.armedForRemoval ? Appearance.m3colors.m3error : "transparent"
                            colRipple: Appearance.colors.colErrorActive
                            onClicked: {
                                if (!installedRow.armedForRemoval) { root.armed = "remove:" + installedRow.modelData.name; return; }
                                root.armed = "";
                                OllamaCatalog.remove(installedRow.modelData.name);
                            }
                            contentItem: RowLayout {
                                spacing: Appearance.spacing.space50
                                MaterialSymbol {
                                    text: "delete"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: installedRow.armedForRemoval ? Appearance.m3colors.m3onError : Appearance.colors.colError
                                }
                                StyledText {
                                    visible: installedRow.armedForRemoval
                                    text: Translation.tr("Remove %1?").arg(Library.sizeLabel(installedRow.modelData.size))
                                    color: Appearance.m3colors.m3onError
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                }
                            }
                            StyledToolTip { text: installedRow.armedForRemoval ? Translation.tr("Click again to remove") : Translation.tr("Remove") }
                        }
                    ]
                }
            }

            // ---- library ----
            StyledText {
                Layout.topMargin: Appearance.spacing.space100
                text: Translation.tr("Library")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
            }
            Repeater {
                model: root.filteredLibrary
                delegate: ColumnLayout {
                    id: libRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Appearance.spacing.space25
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Appearance.spacing.space100
                        StyledText {
                            text: libRow.modelData.name
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: `${libRow.modelData.family} · ${libRow.modelData.description}`
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                        MaterialSymbol { visible: libRow.modelData.tools; text: "build"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colSubtext }
                        MaterialSymbol { visible: libRow.modelData.vision; text: "visibility"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colSubtext }
                        MaterialSymbol { visible: libRow.modelData.embedding; text: "scatter_plot"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colSubtext }
                        IconButton {
                            buttonIcon: "open_in_new"
                            buttonSize: 28
                            colText: Appearance.colors.colSubtext
                            tooltip: Translation.tr("Open on ollama.com")
                            onClicked: Qt.openUrlExternally(`https://ollama.com/library/${libRow.modelData.name}`)
                        }
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Appearance.spacing.space50
                        Repeater {
                            model: libRow.modelData.tags
                            delegate: RippleButton {
                                id: tagChip
                                required property var modelData
                                readonly property string ref: `${libRow.modelData.name}:${tagChip.modelData.tag}`
                                readonly property bool installed: OllamaCatalog.isInstalled(tagChip.ref)
                                readonly property bool isArmed: root.armed === tagChip.ref
                                readonly property string fitKind: Library.fit(tagChip.modelData.gb, root.freeVramGb, root.totalRamGb)
                                enabled: !tagChip.installed && !OllamaCatalog.pulling && OllamaCatalog.daemonUp
                                implicitHeight: 26
                                padding: Appearance.spacing.space100
                                buttonRadius: Appearance.rounding.full
                                colBackground: tagChip.installed ? Appearance.colors.colPrimary
                                    : tagChip.isArmed ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                                colRipple: Appearance.colors.colLayer2Active
                                onClicked: root.requestPull(tagChip.ref, tagChip.modelData.gb)
                                contentItem: RowLayout {
                                    spacing: Appearance.spacing.space50
                                    MaterialSymbol {
                                        visible: tagChip.installed
                                        text: "check"
                                        iconSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnPrimary
                                    }
                                    StyledText {
                                        text: tagChip.isArmed
                                            ? Translation.tr("Pull %1 (~%2 GB%3)? Click again").arg(tagChip.modelData.tag).arg(tagChip.modelData.gb)
                                                  .arg(OllamaCatalog.diskFreeBytes >= 0 ? ", " + Library.sizeLabel(OllamaCatalog.diskFreeBytes) + " " + Translation.tr("free") : "")
                                            : `${tagChip.modelData.tag} · ${tagChip.modelData.gb} GB`
                                        color: tagChip.installed ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                    }
                                    // The fit hint: a dot and a word, no tooltip (a
                                    // Rectangle has no `hovered` for one to bind to).
                                    Rectangle {
                                        visible: !tagChip.installed && tagChip.fitKind.length > 0 && !tagChip.isArmed
                                        width: 8; height: 8; radius: 4
                                        color: root.fitColor(tagChip.fitKind)
                                    }
                                    StyledText {
                                        visible: !tagChip.installed && tagChip.fitKind.length > 0 && !tagChip.isArmed
                                        text: root.fitWord(tagChip.fitKind)
                                        color: root.fitColor(tagChip.fitKind)
                                        font.pixelSize: Appearance.font.pixelSize.smaller
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
