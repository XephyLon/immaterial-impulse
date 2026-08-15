pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.utils
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Qt.labs.synchronizer
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root
    visible: false
    color: "transparent"
    WlrLayershell.namespace: "quickshell:regionSelector"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore
    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    // Modes
    // TODO: Ask: sidebar AI
    enum SnipAction { Copy, Edit, Search, CharRecognition, Record, RecordWithSound } 
    enum SelectionMode { RectCorners, Circle }
    enum Phase { Select, Annotate, Post }
    property var action: RegionSelection.SnipAction.Copy
    property var selectionMode: RegionSelection.SelectionMode.RectCorners
    property var phase: RegionSelection.Phase.Select
    signal dismiss()

    // Styles
    property string screenshotDir: Directories.screenshotTemp
    property color overlayColor: ColorUtils.transparentize("#000000", 0.4)
    property color brightText: Appearance.m3colors.darkmode ? Appearance.colors.colOnLayer0 : Appearance.colors.colLayer0
    property color brightSecondary: Appearance.m3colors.darkmode ? Appearance.colors.colSecondary : Appearance.colors.colOnSecondary
    property color brightTertiary: Appearance.m3colors.darkmode ? Appearance.colors.colTertiary : Qt.lighter(Appearance.colors.colPrimary)
    property color selectionBorderColor: ColorUtils.mix(brightText, brightSecondary, 0.5)
    property color selectionFillColor: "#33ffffff"
    property color windowBorderColor: brightSecondary
    property color windowFillColor: ColorUtils.transparentize(windowBorderColor, 0.85)
    property color imageBorderColor: brightTertiary
    property color imageFillColor: ColorUtils.transparentize(imageBorderColor, 0.85)
    property color onBorderColor: "#ff000000"
    property real targetRegionOpacity: Config.options.regionSelector.targetRegions.opacity
    property bool contentRegionOpacity: Config.options.regionSelector.targetRegions.contentRegionOpacity

    // Vars for indicators
    readonly property var windows: [...HyprlandData.windowList].sort((a, b) => {
        // Sort floating=true windows before others
        if (a.floating === b.floating) return 0;
        return a.floating ? -1 : 1;
    })
    readonly property var layers: HyprlandData.layers
    readonly property real falsePositivePreventionRatio: 0.5

    // Screen & interaction vars
    readonly property var monitor: WM.monitorFor(screen)
    readonly property var monitorGeometry: WM.monitorGeometry(screen)
    readonly property real monitorScale: monitorGeometry.scale
    readonly property real monitorOffsetX: monitorGeometry.x
    readonly property real monitorOffsetY: monitorGeometry.y
    property int activeWorkspaceId: WM.activeWorkspaceForMonitor(root.monitor?.name)?.id ?? 0
    property string screenshotPath: `${root.screenshotDir}/image-${screen.name}`
    property url screenshotSource: ""
    property bool screenshotReady: false
    property real dragStartX: 0
    property real dragStartY: 0
    property real draggingX: 0
    property real draggingY: 0
    property real dragDiffX: 0
    property real dragDiffY: 0
    property bool draggedAway: (dragDiffX !== 0 || dragDiffY !== 0)
    property bool dragging: false
    property list<point> points: []
    property var mouseButton: null
    property var imageRegions: []
    readonly property list<var> windowRegions: RegionFunctions.filterWindowRegionsByLayers(
        root.windows.filter(w => w.workspace.id === root.activeWorkspaceId),
        root.layerRegions
    ).map(window => {
        return {
            at: [window.at[0] - root.monitorOffsetX, window.at[1] - root.monitorOffsetY],
            size: [window.size[0], window.size[1]],
            class: window.class,
            title: window.title,
        }
    })
    readonly property list<var> layerRegions: {
        const layersOfThisMonitor = root.layers[root.monitor?.name]
        const topLayers = layersOfThisMonitor?.levels["2"]
        if (!topLayers) return [];
        const nonBarTopLayers = topLayers
            .filter(layer => !(layer.namespace.includes(":bar") || layer.namespace.includes(":verticalBar") || layer.namespace.includes(":dock")))
            .map(layer => {
            return {
                at: [layer.x, layer.y],
                size: [layer.w, layer.h],
                namespace: layer.namespace,
            }
        })
        const offsetAdjustedLayers = nonBarTopLayers.map(layer => {
            return {
                at: [layer.at[0] - root.monitorOffsetX, layer.at[1] - root.monitorOffsetY],
                size: layer.size,
                namespace: layer.namespace,
            }
        });
        return offsetAdjustedLayers;
    }

    // Config
    property bool isCircleSelection: (root.selectionMode === RegionSelection.SelectionMode.Circle)
    property bool enableWindowRegions: Config.options.regionSelector.targetRegions.windows && !isCircleSelection
    property bool enableLayerRegions: Config.options.regionSelector.targetRegions.layers && !isCircleSelection
    property bool enableContentRegions: Config.options.regionSelector.targetRegions.content

    // Target
    property real targetedRegionX: -1
    property real targetedRegionY: -1
    property real targetedRegionWidth: 0
    property real targetedRegionHeight: 0
    function targetedRegionValid() {
        return (root.targetedRegionX >= 0 && root.targetedRegionY >= 0)
    }
    function setRegionToTargeted() {
        const padding = Config.options.regionSelector.targetRegions.selectionPadding; // Make borders not cut off n stuff
        root.regionX = root.targetedRegionX - padding;
        root.regionY = root.targetedRegionY - padding;
        root.regionWidth = root.targetedRegionWidth + padding * 2;
        root.regionHeight = root.targetedRegionHeight + padding * 2;
    }

    function updateTargetedRegion(x, y) {
        // Image regions
        const clickedRegion = root.imageRegions.find(region => {
            return region.at[0] <= x && x <= region.at[0] + region.size[0] && region.at[1] <= y && y <= region.at[1] + region.size[1];
        });
        if (clickedRegion) {
            root.targetedRegionX = clickedRegion.at[0];
            root.targetedRegionY = clickedRegion.at[1];
            root.targetedRegionWidth = clickedRegion.size[0];
            root.targetedRegionHeight = clickedRegion.size[1];
            return;
        }

        // Layer regions
        const clickedLayer = root.layerRegions.find(region => {
            return region.at[0] <= x && x <= region.at[0] + region.size[0] && region.at[1] <= y && y <= region.at[1] + region.size[1];
        });
        if (clickedLayer) {
            root.targetedRegionX = clickedLayer.at[0];
            root.targetedRegionY = clickedLayer.at[1];
            root.targetedRegionWidth = clickedLayer.size[0];
            root.targetedRegionHeight = clickedLayer.size[1];
            return;
        }

        // Window regions
        const clickedWindow = root.windowRegions.find(region => {
            return region.at[0] <= x && x <= region.at[0] + region.size[0] && region.at[1] <= y && y <= region.at[1] + region.size[1];
        });
        if (clickedWindow) {
            root.targetedRegionX = clickedWindow.at[0];
            root.targetedRegionY = clickedWindow.at[1];
            root.targetedRegionWidth = clickedWindow.size[0];
            root.targetedRegionHeight = clickedWindow.size[1];
            return;
        }

        root.targetedRegionX = -1;
        root.targetedRegionY = -1;
        root.targetedRegionWidth = 0;
        root.targetedRegionHeight = 0;
    }

    property real regionWidth: Math.abs(draggingX - dragStartX)
    property real regionHeight: Math.abs(draggingY - dragStartY)
    property real regionX: Math.min(dragStartX, draggingX)
    property real regionY: Math.min(dragStartY, draggingY)

    // Screenshot stuff
    TempScreenshotProcess {
        id: screenshotProc
        running: true
        screen: root.screen
        screenshotDir: root.screenshotDir
        screenshotPath: root.screenshotPath
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn(`[Region Selector] grim failed with exit code ${exitCode}; aborting capture.`);
                Quickshell.execDetached(["notify-send", "Screenshot failed", "Could not capture a fresh frame. Please try again.", "-a", "Quickshell"]);
                root.dismiss();
                return;
            }
            // Preview the exact file that later gets cropped. ScreencopyView's
            // independent frozen frame can come from an older compositor buffer.
            root.screenshotSource = Qt.resolvedUrl(root.screenshotPath)
                + `?capture=${Date.now()}`;
        }
    }
    property bool isRecording: root.action === RegionSelection.SnipAction.Record || root.action === RegionSelection.SnipAction.RecordWithSound

    // Whole-output capture: the same confirm path every other target takes,
    // handed the screen's own rect. There is no separate full-screen code -
    // `snip()` crops the frozen frame it already has, and a region covering
    // the output is a crop of everything.
    function snipFullScreen() {
        root.regionX = 0;
        root.regionY = 0;
        root.regionWidth = root.width;
        root.regionHeight = root.height;
        root.snip();
    }
    property bool recordingShouldStop: false
    Process {
        id: checkRecordingProc
        running: isRecording
        // Exit 0 while record.sh's recording is live (gsr-based; pidfile-scoped
        // so the instant-replay daemon never counts as "recording").
        command: ["bash", "-c", `kill -0 "$(cat "\${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/imi-screenrecord.pid" 2>/dev/null)" 2>/dev/null`]
        onExited: (exitCode, exitStatus) => {
            root.recordingShouldStop = (exitCode === 0);
            root.finishPreparationIfReady();
        }
    }
    property bool preparationDone: false
    function finishPreparationIfReady() {
        if (!root.screenshotReady || checkRecordingProc.running) return;
        root.preparationDone = true;
    }
    onPreparationDoneChanged: {
        if (!preparationDone) return;
        if (root.isRecording && root.recordingShouldStop) {
            Quickshell.execDetached([Directories.recordScriptPath]);
            root.dismiss();
            return;
        }
        root.visible = true;
    }

    Connections {
        target: Persistent.states.record
        function onEnableChanged() {
            if (!Persistent.states.record.enable && root.isRecording) {
                root.dismiss();
            }
        }
    }

    Process {
        id: imageDetectionProcess
        command: ["bash", "-c", `${Directories.scriptPath}/images/find-regions-venv.sh ` 
            + `--hyprctl ` 
            + `--image '${StringUtils.shellSingleQuoteEscape(root.screenshotPath)}' ` 
            + `--max-width ${Math.round(root.screen.width * root.falsePositivePreventionRatio)} ` 
            + `--max-height ${Math.round(root.screen.height * root.falsePositivePreventionRatio)} `]
        stdout: StdioCollector {
            id: imageDimensionCollector
            onStreamFinished: {
                imageRegions = RegionFunctions.filterImageRegions(
                    JSON.parse(imageDimensionCollector.text),
                    root.windowRegions
                );
            }
        }
    }

    function getScreenshotAction() {
        switch(root.action) {
            case RegionSelection.SnipAction.Copy:
                return ScreenshotAction.Action.Copy;
            case RegionSelection.SnipAction.Edit:
                return ScreenshotAction.Action.Edit;
            case RegionSelection.SnipAction.Search:
                return ScreenshotAction.Action.Search;
            case RegionSelection.SnipAction.CharRecognition:
                return ScreenshotAction.Action.CharRecognition;
            case RegionSelection.SnipAction.Record:
                return ScreenshotAction.Action.Record;
            case RegionSelection.SnipAction.RecordWithSound:
                return ScreenshotAction.Action.RecordWithSound;
            default:
                console.warn("[Region Selector] Unknown snip action, skipping snip.");
                root.dismiss();
                return;
        }
    }

    function clampRegion() {
        root.regionX = Math.max(0, Math.min(root.regionX, root.screen.width - root.regionWidth));
        root.regionY = Math.max(0, Math.min(root.regionY, root.screen.height - root.regionHeight));
        root.regionWidth = Math.max(0, Math.min(root.regionWidth, root.screen.width - root.regionX));
        root.regionHeight = Math.max(0, Math.min(root.regionHeight, root.screen.height - root.regionY));
    }

    // Annotated copy: composite the cropped screenshot + canvas at native
    // resolution via grabToImage, then reuse the observable copy pipeline.
    function finishAnnotated() {
        if (!annotationLoader.item || !annotationLoader.item.hasAnnotations) {
            // Nothing drawn: the plain pipeline crops losslessly with magick.
            root.snip();
            return;
        }
        const screenshotDir = Config.options.screenSnip.savePath !== ""
            ? Config.options.screenSnip.savePath : root.screenshotDir;
        const ts = new Date().toISOString().replace(/[:.]/g, "-");
        const resultPath = `${screenshotDir}/result-${ts}.png`;
        annotateComposite.grabToImage(result => {
            if (!result.saveToFile(resultPath)) {
                console.warn("[Region Selector] failed to save annotated grab");
                root.dismiss();
                return;
            }
            GlobalStates.snipCopyInFlight = true;
            copySnipProcess.resultPath = resultPath;
            copySnipProcess.command = ["bash", "-c",
                `wl-copy --type image/png < '${StringUtils.shellSingleQuoteEscape(resultPath)}' && notify-send 'Screenshot' 'Annotated snip copied' -a 'Quickshell'`];
            copySnipProcess.running = true;
            root.visible = false;
        }, Qt.size(Math.round(root.regionWidth * root.monitorScale),
                   Math.round(root.regionHeight * root.monitorScale)));
    }

    // Execution after selection
    function snip() {
        // Validity check
        if (root.regionWidth <= 0 || root.regionHeight <= 0) {
            console.warn("[Region Selector] Invalid region size, skipping snip.");
            root.dismiss();
        }

        root.clampRegion();

        // Adjust action
        if (root.action === RegionSelection.SnipAction.Copy || root.action === RegionSelection.SnipAction.Edit) {
            root.action = root.mouseButton === Qt.RightButton ? RegionSelection.SnipAction.Edit : RegionSelection.SnipAction.Copy;
        }
        
        const screenshotDir = Config.options.screenSnip.savePath !== "" ? //
            Config.options.screenSnip.savePath : "";
        var screenshotAction = root.getScreenshotAction();
        const isCopy = screenshotAction === ScreenshotAction.Action.Copy;
        let resultPath = "";
        if (isCopy) {
            const ts = new Date().toISOString().replace(/[:.]/g, "-");
            const dir = screenshotDir !== "" ? screenshotDir : root.screenshotDir;
            resultPath = `${dir}/result-${ts}.png`;
        }
        const command = ScreenshotAction.getCommand(
            root.regionX * root.monitorScale, //
            root.regionY * root.monitorScale, //
            root.regionWidth * root.monitorScale,//
            root.regionHeight * root.monitorScale, //
            root.screenshotPath, //
            screenshotAction, //
            screenshotDir, //
            resultPath
        )
        if (isCopy) {
            // Copy runs through a Process so completion is observable and the
            // result file can be announced. Dismissing now would destroy this
            // window (and kill the process with it), so hide the overlay
            // immediately and dismiss once the process exits.
            GlobalStates.snipCopyInFlight = true;
            copySnipProcess.resultPath = resultPath;
            copySnipProcess.command = command;
            copySnipProcess.running = true;
            root.visible = false;
        } else {
            Quickshell.execDetached(command);
            if (root.action == RegionSelection.SnipAction.Record || root.action == RegionSelection.SnipAction.RecordWithSound) {
                root.phase = RegionSelection.Phase.Post
                root.selectionMode = RegionSelection.SelectionMode.RectCorners
            } else {
                root.dismiss();
            }
        }
    }

    Process {
        id: copySnipProcess
        property string resultPath: ""
        onExited: (exitCode, exitStatus) => {
            GlobalStates.snipCopyInFlight = false;
            if (exitCode === 0 && copySnipProcess.resultPath !== "")
                ScreenshotEvents.emitIfValid(copySnipProcess.resultPath);
            root.dismiss();
        }
    }

    // Only clickable in Selection phase
    mask: Region {
        item: switch(root.phase) {
            case RegionSelection.Phase.Select: return mouseArea;
            case RegionSelection.Phase.Annotate: return screenshotImage;
            case RegionSelection.Phase.Post: return null;
        }
    }

    Image {
        id: screenshotImage
        anchors.fill: parent
        source: root.screenshotSource
        cache: false
        asynchronous: false
        fillMode: Image.Stretch
        visible: root.phase !== RegionSelection.Phase.Post

        onStatusChanged: {
            if (status === Image.Ready) {
                root.screenshotReady = true;
                if (root.enableContentRegions) imageDetectionProcess.running = true;
                root.finishPreparationIfReady();
            } else if (status === Image.Error) {
                console.warn(`[Region Selector] failed to decode fresh capture: ${source}`);
                Quickshell.execDetached(["notify-send", "Screenshot failed", "Could not load the fresh frame. Please try again.", "-a", "Quickshell"]);
                root.dismiss();
            }
        }

        focus: root.visible
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) { // Esc to close
                if (GlobalStates.snipCopyInFlight) return; // dismissing would kill the copy pipeline
                Qt.callLater(root.dismiss);
            } else if (root.phase === RegionSelection.Phase.Annotate
                    && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                root.finishAnnotated();
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: root.phase === RegionSelection.Phase.Select
        cursorShape: Qt.CrossCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true

        // Controls
        onPressed: (mouse) => {
            root.dragStartX = mouse.x;
            root.dragStartY = mouse.y;
            root.draggingX = mouse.x;
            root.draggingY = mouse.y;
            root.dragging = true;
            root.mouseButton = mouse.button;
        }
        onReleased: (mouse) => {
            // Detect if it was a click -> Try to select targeted region
            if (root.draggingX === root.dragStartX && root.draggingY === root.dragStartY) {
                if (root.targetedRegionValid()) {
                    root.setRegionToTargeted();
                }
            }
            // Circle dragging?
            else if (root.selectionMode === RegionSelection.SelectionMode.Circle) {
                const padding = Config.options.regionSelector.circle.padding + Config.options.regionSelector.circle.strokeWidth / 2;
                const dragPoints = (root.points.length > 0) ? root.points : [{ x: mouseArea.mouseX, y: mouseArea.mouseY }];
                const maxX = Math.max(...dragPoints.map(p => p.x));
                const minX = Math.min(...dragPoints.map(p => p.x));
                const maxY = Math.max(...dragPoints.map(p => p.y));
                const minY = Math.min(...dragPoints.map(p => p.y));
                root.regionX = minX - padding;
                root.regionY = minY - padding;
                root.regionWidth = maxX - minX + padding * 2;
                root.regionHeight = maxY - minY + padding * 2;
            }
            // Left-button Copy snips (rect mode) pause for annotation; the
            // circle mask and every other action keep the instant pipeline.
            if (root.action === RegionSelection.SnipAction.Copy
                    && root.mouseButton === Qt.LeftButton
                    && root.selectionMode === RegionSelection.SelectionMode.RectCorners
                    && root.regionWidth > 4 && root.regionHeight > 4) {
                root.clampRegion();
                root.phase = RegionSelection.Phase.Annotate;
            } else {
                root.snip();
            }
        }
        onPositionChanged: (mouse) => {
            root.updateTargetedRegion(mouse.x, mouse.y);
            if (!root.dragging) return;
            root.draggingX = mouse.x;
            root.draggingY = mouse.y;
            root.dragDiffX = mouse.x - root.dragStartX;
            root.dragDiffY = mouse.y - root.dragStartY;
            root.points.push({ x: mouse.x, y: mouse.y });
        }
        
        Loader {
            z: 2
            anchors.fill: parent
            active: root.selectionMode === RegionSelection.SelectionMode.RectCorners
            sourceComponent: RectCornersSelectionDetails {
                regionX: root.regionX
                regionY: root.regionY
                regionWidth: root.regionWidth
                regionHeight: root.regionHeight
                mouseX: mouseArea.mouseX
                mouseY: mouseArea.mouseY
                color: root.selectionBorderColor
                overlayColor: root.overlayColor
                breathingBorderOnly: root.phase === RegionSelection.Phase.Post
            }
        }

        Loader {
            z: 2
            anchors.fill: parent
            active: root.selectionMode === RegionSelection.SelectionMode.Circle
            sourceComponent: CircleSelectionDetails {
                color: root.selectionBorderColor
                overlayColor: root.overlayColor
                points: root.points
            }
        }

        // The loupe, so an edge can be framed by the pixel rather than by eye.
        // Samples the same frozen grim frame the crop will use - see
        // Magnifier.qml for why not a live screencopy.
        Magnifier {
            id: magnifier
            z: 10000
            shown: root.phase === RegionSelection.Phase.Select
                && root.screenshotReady
                && !mouseArea.pointerOverChrome
                && Config.options.regionSelector.magnifier.enable
            source: root.screenshotSource
            pointerX: mouseArea.mouseX
            pointerY: mouseArea.mouseY
            frameWidth: root.width
            frameHeight: root.height
            zoom: Config.options.regionSelector.magnifier.zoom
            // The shape says what a click would take: a region being dragged,
            // or the window the pointer has locked onto.
            framing: root.dragging
            onWindow: !root.dragging && root.targetedRegionValid()
        }

        // The thing to the bottom-right with an icon
        CursorGuide {
            id: cursorGuide
            z: 9999
            shown: root.phase === RegionSelection.Phase.Select && !mouseArea.pointerOverChrome
            x: root.dragging ? root.regionX + root.regionWidth : mouseArea.mouseX
            y: root.dragging ? root.regionY + root.regionHeight : mouseArea.mouseY
            action: root.action
            selectionMode: root.selectionMode
        }

        // Window regions
        Repeater {
            model: ScriptModel {
                values: {
                    if (root.phase === RegionSelection.Phase.Select && root.enableWindowRegions) {
                        return root.windowRegions
                    } else {
                        return []
                    }
                }
            }
            delegate: TargetRegion {
                z: 2
                required property var modelData
                clientDimensions: modelData
                showIcon: true
                targeted: !root.draggedAway && //
                    (root.targetedRegionX === modelData.at[0]  //
                    && root.targetedRegionY === modelData.at[1] //
                    && root.targetedRegionWidth === modelData.size[0] //
                    && root.targetedRegionHeight === modelData.size[1])

                opacity: root.draggedAway ? 0 : root.targetRegionOpacity
                borderColor: root.windowBorderColor
                fillColor: targeted ? root.windowFillColor : "transparent"
                text: `${modelData.class}`
                radius: Appearance.rounding.windowRounding
            }
        }

        // Layer regions
        Repeater {
            model: ScriptModel {
                values: {
                    if (root.phase === RegionSelection.Phase.Select && root.enableLayerRegions) {
                        return root.layerRegions
                    } else {
                        return []
                    }
                }
            }
            delegate: TargetRegion {
                z: 3
                required property var modelData
                clientDimensions: modelData
                targeted: !root.draggedAway &&
                    (root.targetedRegionX === modelData.at[0] 
                    && root.targetedRegionY === modelData.at[1]
                    && root.targetedRegionWidth === modelData.size[0]
                    && root.targetedRegionHeight === modelData.size[1])

                opacity: root.draggedAway ? 0 : root.targetRegionOpacity
                borderColor: root.windowBorderColor
                fillColor: targeted ? root.windowFillColor : "transparent"
                text: `${modelData.namespace}`
                radius: Appearance.rounding.windowRounding
            }
        }

        // Content regions
        Repeater {
            model: ScriptModel {
                values: {
                    if (root.phase === RegionSelection.Phase.Select && root.enableContentRegions) {
                        return root.imageRegions
                    } else {
                        return []
                    }
                }
            }
            delegate: TargetRegion {
                z: 4
                required property var modelData
                clientDimensions: modelData
                targeted: !root.draggedAway &&
                    (root.targetedRegionX === modelData.at[0] 
                    && root.targetedRegionY === modelData.at[1]
                    && root.targetedRegionWidth === modelData.size[0]
                    && root.targetedRegionHeight === modelData.size[1])

                opacity: root.draggedAway ? 0 : root.contentRegionOpacity
                borderColor: root.imageBorderColor
                fillColor: targeted ? root.imageFillColor : "transparent"
                text: Translation.tr("Content region")
            }
        }

        // Annotation phase: cropped backdrop + canvas (this exact group is
        // grabbed for the composite) and the Snagit-style tool bar under it.
        Item {
            id: annotateComposite
            z: 5
            visible: root.phase === RegionSelection.Phase.Annotate
            x: root.regionX
            y: root.regionY
            width: root.regionWidth
            height: root.regionHeight
            clip: true

            Image {
                x: -root.regionX
                y: -root.regionY
                width: root.width
                height: root.height
                source: root.screenshotSource
                cache: false
                fillMode: Image.Stretch
            }

            Loader {
                id: annotationLoader
                anchors.fill: parent
                active: root.phase === RegionSelection.Phase.Annotate
                sourceComponent: AnnotationLayer {}
            }
        }

        Loader {
            z: 10
            active: root.phase === RegionSelection.Phase.Annotate && annotationLoader.item !== null
            sourceComponent: AnnotationToolbar {
                annotationLayer: annotationLoader.item
                onConfirmed: root.finishAnnotated()
                onCancelled: if (!GlobalStates.snipCopyInFlight) root.dismiss()
                x: {
                    const preferred = root.regionX + root.regionWidth / 2 - implicitWidth / 2;
                    return Math.max(8, Math.min(preferred, root.width - implicitWidth - 8));
                }
                y: {
                    const below = root.regionY + root.regionHeight + 12;
                    if (below + implicitHeight + 8 <= root.height) return below;
                    const above = root.regionY - implicitHeight - 12;
                    if (above >= 8) return above;
                    return root.regionY + root.regionHeight - implicitHeight - 12; // inside, bottom
                }
            }
        }

        // While the pointer is on the chrome, the real cursor is what the user
        // is aiming with - so the crosshair's own markers get out of the way
        // rather than sitting on top of the buttons being pressed.
        //
        // Keyed to the POINTER being on the row, not to the markers coming
        // near it: they go away when the toolbar is being used, and at no
        // other time. Hiding them on approach makes them vanish over an
        // ordinary part of the canvas, which reads as a glitch.
        //
        // A point test on the row's rect rather than a HoverHandler on it,
        // because this MouseArea holds the pointer for the whole overlay and a
        // handler underneath it never fired. The position tested is the same
        // mouseX/mouseY the markers are placed with, so the test cannot
        // disagree with where they are drawn.
        property bool pointerOverChrome: regionSelectionControls.visible
            && mouseArea.mouseX >= regionSelectionControls.x
            && mouseArea.mouseX <= regionSelectionControls.x + regionSelectionControls.width
            && mouseArea.mouseY >= regionSelectionControls.y
            && mouseArea.mouseY <= regionSelectionControls.y + regionSelectionControls.height

        // Controls
        Row {
            id: regionSelectionControls
            z: 10
            visible: root.phase === RegionSelection.Phase.Select
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: -height
            }
            opacity: 0
            Connections {
                target: root
                function onVisibleChanged() {
                    if (!visible) return;
                    regionSelectionControls.anchors.bottomMargin = 8;
                    regionSelectionControls.opacity = 1;
                }
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on anchors.bottomMargin {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            spacing: Appearance.spacing.space100

            OptionsToolbar {
                Synchronizer on action {
                    property alias source: root.action
                }
                Synchronizer on selectionMode {
                    property alias source: root.selectionMode
                }
                windowTargeting: root.enableWindowRegions
                onDismiss: if (!GlobalStates.snipCopyInFlight) root.dismiss();
                onCaptureFullScreen: if (!GlobalStates.snipCopyInFlight) root.snipFullScreen();
            }
            ToolbarPairedFab {
                anchors.verticalCenter: parent.verticalCenter
                iconText: "close"
                onClicked: if (!GlobalStates.snipCopyInFlight) root.dismiss();
                StyledToolTip {
                    text: Translation.tr("Close")
                }
            }
        }
        
    }
}
