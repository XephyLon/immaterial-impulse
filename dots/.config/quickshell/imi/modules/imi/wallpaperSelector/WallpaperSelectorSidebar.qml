import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Hyprland
import "./selector_places.js" as SelectorPlaces
import "./crop_picker.js" as CropPicker

// The selector's left sidebar. Two faces, decided by which grid is showing:
//
// - Local files: a places rail (the file-explorer shape) - folder shortcuts
//   with the directory on screen lit. The rows come from selector_places.js,
//   which is where the visibility rules and the current-place match live.
// - Wallpaper Engine: the engine's configuration, the reference app's
//   (jagrat7/linux-wallpaper-engine) settings-sidebar shape: the active
//   project's card, the engine's whole flag set (frame rate, scaling, audio
//   with its volume, the audio-reactive recorder, mouse/parallax/particles),
//   per-project overrides of all of it, and the wallpaper's own
//   project.json properties (bool/slider/combo/color/textinput). Only knobs
//   the embedded WallpaperEngineSurface actually answers are offered - the
//   extended set is gated on WallpaperEngineFeatures, so a shell running an
//   older renderer binary shows the controls it can honour and no fake
//   actions.
//
// The online sources get no sidebar: their controls (resolution, provider)
// already live in the top toolbar and there is nothing filesystem-shaped to
// navigate.
ColumnLayout {
    id: root

    // "local" | "wallpaperEngine" | an online provider - the content host's
    // own source string.
    property string source: "local"

    spacing: Appearance.spacing.space100

    readonly property var weConfig: Config.options.wallpaperSelector.wallpaperEngine
    readonly property string activeProjectId: root.weConfig.activeProject
    readonly property bool hasProjectOverride: WallpaperEngineOverrides.ready
        && WallpaperEngineOverrides.hasOverride(root.activeProjectId)
    // What the engine controls show and edit: the active project's own record
    // while the override switch is on, the globals otherwise.
    readonly property bool editingOverride: root.hasProjectOverride
    readonly property var effective: WallpaperEngineOverrides.active
    readonly property var activeProject: WallpaperEngine.projects.find(
        p => p.id === root.activeProjectId) ?? null
    readonly property var activeProperties: root.activeProject?.properties ?? []

    // The focused monitor's aspect - what a Fill crop is judged against.
    readonly property var focusedScreen: Quickshell.screens.find(
        s => s.name === (Hyprland.focusedMonitor?.name ?? "")) ?? Quickshell.screens[0]
    readonly property real screenAspect: (focusedScreen?.width > 0 && focusedScreen?.height > 0)
        ? focusedScreen.width / focusedScreen.height : 16 / 9
    // The content aspect the crop picker judges overflow by. The live scene's
    // REAL authored aspect when the renderer has published it
    // (GlobalStates.weContentAspect) - because the preview image's aspect is
    // NOT the scene's: a 32:9 ultrawide wallpaper commonly ships a portrait
    // preview, which would pick the wrong overflow axis. The preview aspect is
    // the fallback for a shell whose renderer does not report content size.
    property real previewAspect: 0
    readonly property real contentAspect: GlobalStates.weContentAspect > 0
        ? GlobalStates.weContentAspect : root.previewAspect
    // The renderer's grabbed full-scene image for THIS project - the real
    // 32:9 content, not the preview. Empty when it is for another project or
    // not grabbed (a video, an older binary): the picker then falls back to
    // the preview at its own aspect, honest but not the scene.
    readonly property string sceneImage: GlobalStates.weSceneGrabProject === root.activeProjectId
        ? GlobalStates.weSceneGrabPath : ""
    readonly property bool haveSceneImage: root.sceneImage !== ""
    readonly property bool canCrop: root.activeProjectId !== ""
        && root.effective.scaling === "fill"
        && WallpaperEngineFeatures.cropFocus
        && root.contentAspect > 0
        && Math.abs(root.contentAspect - root.screenAspect) > 0.01

    function writeSetting(key, value) {
        if (root.editingOverride) {
            WallpaperEngineOverrides.setOverride(root.activeProjectId, key, value);
            return;
        }
        if (key === "fps") root.weConfig.fps = value;
        else if (key === "scaling") root.weConfig.scaling = value;
        else if (key === "silent") root.weConfig.silent = value;
        else if (key === "volume") root.weConfig.volume = value;
        else if (key === "audioProcessing") root.weConfig.audioProcessing = value;
        else if (key === "disableMouse") root.weConfig.disableMouse = value;
        else if (key === "disableParallax") root.weConfig.disableParallax = value;
        else if (key === "disableParticles") root.weConfig.disableParticles = value;
        else if (key === "renderScale") root.weConfig.renderScale = value;
    }

    StyledText {
        Layout.leftMargin: Appearance.spacing.space150
        Layout.topMargin: Appearance.spacing.space100
        text: root.source === "wallpaperEngine"
            ? Translation.tr("Wallpaper Engine")
            : Translation.tr("Places")
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
    }

    // ---- Places rail (local files) -------------------------------------
    Loader {
        Layout.fillWidth: true
        Layout.fillHeight: true
        active: root.source === "local"
        visible: active

        sourceComponent: ColumnLayout {
            spacing: Appearance.spacing.space25

            Repeater {
                model: SelectorPlaces.places({
                    home: FileUtils.trimFileProtocol(Directories.home),
                    documents: FileUtils.trimFileProtocol(Directories.documents),
                    downloads: FileUtils.trimFileProtocol(Directories.downloads),
                    pictures: FileUtils.trimFileProtocol(Directories.pictures),
                    videos: FileUtils.trimFileProtocol(Directories.videos)
                }, {
                    showHomePath: Config.options.wallpaperSelector.showHomePath,
                    weeb: Config.options.policies.weeb,
                    userPath: Config.options.wallpaperSelector.userPath ?? ""
                })

                delegate: RippleButton {
                    id: placeButton
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 38
                    buttonRadius: height / 2
                    toggled: SelectorPlaces.isCurrent(placeButton.modelData.path,
                        Wallpapers.directory)
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                    colRippleToggled: Appearance.colors.colSecondaryContainerActive
                    onClicked: Wallpapers.setDirectory(placeButton.modelData.path)
                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Appearance.spacing.space150
                        anchors.rightMargin: Appearance.spacing.space150
                        spacing: Appearance.spacing.space100
                        MaterialSymbol {
                            text: placeButton.modelData.icon
                            iconSize: Appearance.font.pixelSize.larger
                            fill: placeButton.toggled ? 1 : 0
                            color: placeButton.toggled
                                ? Appearance.colors.colOnSecondaryContainer
                                : Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: placeButton.modelData.translate
                                ? Translation.tr(placeButton.modelData.name)
                                : placeButton.modelData.name
                            color: placeButton.toggled
                                ? Appearance.colors.colOnSecondaryContainer
                                : Appearance.colors.colOnLayer1
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }
    }

    // ---- Engine configuration (Wallpaper Engine) -----------------------
    Loader {
        Layout.fillWidth: true
        Layout.fillHeight: true
        active: root.source === "wallpaperEngine"
        visible: active

        sourceComponent: StyledFlickable {
            id: weFlickable
            contentHeight: weColumn.implicitHeight
            clip: true

            ColumnLayout {
                id: weColumn
                width: weFlickable.width
                spacing: Appearance.spacing.space100

                // The active project's card. Absent, the section simply is
                // not drawn - an empty preview frame is a promise about a
                // selection that does not exist.
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.activeProjectId !== ""
                    implicitHeight: activeCard.implicitHeight + Appearance.spacing.space150 * 2
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer2

                    ColumnLayout {
                        id: activeCard
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            margins: Appearance.spacing.space150
                        }
                        spacing: Appearance.spacing.space100

                        // The preview card. Normally a cropped thumbnail; when
                        // this wallpaper can be cropped (Fill, overflow, and a
                        // renderer that pans), it becomes a section picker - a
                        // box at the CONTENT's real aspect with the screen's
                        // viewport drawn over it and draggable.
                        Rectangle {
                            id: previewBox
                            Layout.fillWidth: true
                            Layout.preferredHeight: width * 9 / 16
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer1
                            clip: true

                            // The ordinary thumbnail, shown when there is
                            // nothing to crop. Also the source of the preview
                            // aspect fallback (weContentAspect is the real one).
                            StyledImage {
                                id: previewImage
                                anchors.fill: parent
                                visible: !root.canCrop
                                fillMode: Image.PreserveAspectCrop
                                source: root.weConfig.activePreview
                                // A thumbnail-sized decode of a preview drawn
                                // ~200px wide; the card is width-stable so the
                                // constant avoids the bound-to-geometry reload
                                // trap.
                                sourceSize.width: 400
                                sourceSize.height: 225
                                onStatusChanged: {
                                    if (status === Image.Ready && implicitHeight > 0)
                                        root.previewAspect = implicitWidth / implicitHeight;
                                }
                                layer.enabled: true
                                layer.effect: OpacityMask {
                                    maskSource: Rectangle {
                                        width: previewBox.width
                                        height: previewBox.height
                                        radius: Appearance.rounding.small
                                    }
                                }
                            }

                            // The picker: a box at the content's own aspect,
                            // fitted inside the card, holding the preview
                            // cropped to that aspect with the viewport
                            // rectangle over it. Everything - the viewport
                            // maths and the drag - works in THIS box's frame.
                            // The picker box is the CONTENT's real aspect
                            // (e.g. 32:9), filled with the renderer's grabbed
                            // scene image - the actual wallpaper, cropped to
                            // fill the box exactly because the grab IS at the
                            // content aspect. Only when that grab exists: it is
                            // the whole point, because the preview image does
                            // not depict the scene. Without it (a video, an
                            // older binary) the box falls back to the preview's
                            // own aspect, shown whole and honest but not the
                            // scene.
                            Item {
                                id: fittedBox
                                readonly property real boxAspect: root.haveSceneImage && root.contentAspect > 0
                                    ? root.contentAspect
                                    : (root.previewAspect > 0 ? root.previewAspect : 16 / 9)
                                readonly property real cardAspect: previewBox.width / previewBox.height
                                width: boxAspect >= cardAspect ? previewBox.width : previewBox.height * boxAspect
                                height: boxAspect >= cardAspect ? previewBox.width / boxAspect : previewBox.height
                                anchors.centerIn: parent
                                visible: root.canCrop

                                StyledImage {
                                    anchors.fill: parent
                                    // The grabbed scene fills its content-aspect
                                    // box exactly (crop); the preview fallback
                                    // is shown whole (fit) rather than butchered.
                                    fillMode: root.haveSceneImage ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                                    source: root.haveSceneImage ? root.sceneImage : root.weConfig.activePreview
                                    sourceSize.width: 640
                                    sourceSize.height: 360
                                }

                                // The viewport rectangle: the axis that
                                // overflows uses its focus, the other stays
                                // full-extent. The fraction is content-vs-
                                // screen (aspect only).
                                readonly property var vp: {
                                    const h = CropPicker.viewport(root.contentAspect,
                                        root.screenAspect, width, height, root.effective.focus.x);
                                    const v = CropPicker.viewport(root.contentAspect,
                                        root.screenAspect, width, height, root.effective.focus.y);
                                    return {
                                        x: h.overflowsX ? h.x : 0,
                                        y: v.overflowsY ? v.y : 0,
                                        width: h.overflowsX ? h.width : width,
                                        height: v.overflowsY ? v.height : height
                                    };
                                }

                                // Four dim panels around the viewport, so the
                                // shown slice reads bright and the cropped-out
                                // margins read dark.
                                readonly property color dim: ColorUtils.transparentize(Appearance.m3colors.m3scrim, 0.4)
                                Rectangle { // left
                                    x: 0; y: 0; width: fittedBox.vp.x; height: fittedBox.height
                                    color: fittedBox.dim
                                }
                                Rectangle { // right
                                    x: fittedBox.vp.x + fittedBox.vp.width; y: 0
                                    width: fittedBox.width - (fittedBox.vp.x + fittedBox.vp.width)
                                    height: fittedBox.height; color: fittedBox.dim
                                }
                                Rectangle { // top
                                    x: fittedBox.vp.x; y: 0; width: fittedBox.vp.width; height: fittedBox.vp.y
                                    color: fittedBox.dim
                                }
                                Rectangle { // bottom
                                    x: fittedBox.vp.x; y: fittedBox.vp.y + fittedBox.vp.height
                                    width: fittedBox.vp.width
                                    height: fittedBox.height - (fittedBox.vp.y + fittedBox.vp.height)
                                    color: fittedBox.dim
                                }
                                Rectangle { // the viewport outline
                                    x: fittedBox.vp.x; y: fittedBox.vp.y
                                    width: fittedBox.vp.width; height: fittedBox.vp.height
                                    color: "transparent"
                                    border.width: Appearance.borderWidth.emphasis
                                    border.color: Appearance.colors.colPrimary
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.SizeAllCursor
                                    function apply(mx, my) {
                                        const f = CropPicker.focusFromPointer(
                                            root.contentAspect, root.screenAspect,
                                            fittedBox.width, fittedBox.height, mx, my);
                                        WallpaperEngineOverrides.setFocus(root.activeProjectId, f.x, f.y);
                                    }
                                    onPressed: mouse => apply(mouse.x, mouse.y)
                                    onPositionChanged: mouse => { if (pressed) apply(mouse.x, mouse.y); }
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: root.activeProject?.title ?? root.activeProjectId
                            font.pixelSize: Appearance.font.pixelSize.small
                        }

                        RippleButton {
                            Layout.fillWidth: true
                            implicitHeight: 32
                            buttonRadius: height / 2
                            onClicked: WallpaperEngine.stop()
                            contentItem: RowLayout {
                                anchors.fill: parent
                                spacing: Appearance.spacing.space75
                                Item { Layout.fillWidth: true }
                                MaterialSymbol {
                                    text: "stop_circle"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colOnLayer2
                                }
                                StyledText {
                                    text: Translation.tr("Clear selection")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer2
                                }
                                Item { Layout.fillWidth: true }
                            }
                        }
                    }
                }

                ConfigSwitch {
                    Layout.fillWidth: true
                    visible: root.activeProjectId !== ""
                    buttonIcon: "tune"
                    text: Translation.tr("Custom settings")
                    description: Translation.tr("Only this wallpaper")
                    checked: root.hasProjectOverride
                    onToggleRequested: {
                        if (root.hasProjectOverride) {
                            // Clears the ENGINE flags only: property edits
                            // below are per-wallpaper by nature and survive.
                            WallpaperEngineOverrides.clearEngineOverrides(root.activeProjectId);
                        } else {
                            // Seed the record from what runs right now, so
                            // flipping the switch changes nothing on screen
                            // until a control is moved.
                            WallpaperEngineOverrides.seedOverrides(root.activeProjectId, root.effective);
                        }
                    }
                }

                StyledText {
                    Layout.leftMargin: Appearance.spacing.space150
                    text: root.editingOverride
                        ? Translation.tr("This wallpaper")
                        : Translation.tr("All wallpapers")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.spacing.space100
                    StyledText {
                        Layout.leftMargin: Appearance.spacing.space150
                        Layout.fillWidth: true
                        text: Translation.tr("Frame rate")
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                    StyledComboBox {
                        id: fpsBox
                        implicitWidth: 92
                        readonly property var values: [24, 30, 60]
                        model: [
                            { value: 24, displayName: "24 FPS" },
                            { value: 30, displayName: "30 FPS" },
                            { value: 60, displayName: "60 FPS" }
                        ]
                        textRole: "displayName"
                        // Bound, not set at completion: the shown value swaps
                        // between the globals and a project's record when the
                        // override switch flips.
                        currentIndex: Math.max(0, fpsBox.values.indexOf(root.effective.fps))
                        onActivated: index => root.writeSetting("fps", fpsBox.values[index])
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.spacing.space100
                    StyledText {
                        Layout.leftMargin: Appearance.spacing.space150
                        Layout.fillWidth: true
                        text: Translation.tr("Scaling")
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                    StyledComboBox {
                        id: scalingBox
                        implicitWidth: 92
                        readonly property var values: ["fill", "fit", "stretch"]
                        model: [
                            { value: "fill", displayName: Translation.tr("Fill") },
                            { value: "fit", displayName: Translation.tr("Fit") },
                            { value: "stretch", displayName: Translation.tr("Stretch") }
                        ]
                        textRole: "displayName"
                        currentIndex: Math.max(0, scalingBox.values.indexOf(root.effective.scaling))
                        onActivated: index => root.writeSetting("scaling", scalingBox.values[index])
                    }
                }

                // Quality: renderScale, gated on a renderer that reads it.
                // Native draws at the surface's own resolution; the lower steps
                // render smaller and upscale. Honest about its reach - for a
                // heavy SCENE the frame rate above is the real lever, since a
                // scene renders at its authored resolution regardless and this
                // only trims the final composite; it is video wallpapers, drawn
                // at window size, where a lower quality cuts real work.
                RowLayout {
                    Layout.fillWidth: true
                    visible: WallpaperEngineFeatures.renderScale
                    spacing: Appearance.spacing.space100
                    StyledText {
                        Layout.leftMargin: Appearance.spacing.space150
                        Layout.fillWidth: true
                        text: Translation.tr("Quality")
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                    StyledComboBox {
                        id: qualityBox
                        implicitWidth: 116
                        readonly property var values: [1.0, 0.75, 0.5, 0.25]
                        model: [
                            { value: 1.0, displayName: Translation.tr("Native") },
                            { value: 0.75, displayName: Translation.tr("High (75%)") },
                            { value: 0.5, displayName: Translation.tr("Balanced (50%)") },
                            { value: 0.25, displayName: Translation.tr("Low (25%)") }
                        ]
                        textRole: "displayName"
                        currentIndex: Math.max(0, qualityBox.values.indexOf(root.effective.renderScale))
                        onActivated: index => root.writeSetting("renderScale", qualityBox.values[index])
                    }
                }

                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "volume_up"
                    text: Translation.tr("Wallpaper audio")
                    checked: !root.effective.silent
                    onToggleRequested: root.writeSetting("silent", !root.effective.silent)
                }

                // Volume, only while audio plays and only on a renderer that
                // reads it. Committed on RELEASE: every engine flag is a
                // load-time WE argument, so a per-tick write would reload the
                // wallpaper once per pixel of drag.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Appearance.spacing.space150
                    Layout.rightMargin: Appearance.spacing.space100
                    visible: !root.effective.silent && WallpaperEngineFeatures.engineFlags
                    spacing: Appearance.spacing.space100
                    StyledText {
                        text: Translation.tr("Volume")
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                    StyledSlider {
                        id: volumeSlider
                        Layout.fillWidth: true
                        from: 0
                        to: 100
                        stepSize: 1
                        onPressedChanged: {
                            if (!pressed)
                                root.writeSetting("volume", Math.round(value));
                        }
                        // A drag sets `value` imperatively, which would break a
                        // plain `value:` binding for good - after the first drag
                        // the handle would stop following a project switch or a
                        // Custom-settings toggle. A Binding element re-asserts
                        // whenever the resolved volume changes, so it keeps
                        // tracking without fighting the drag (effective.volume
                        // does not change mid-drag; it is written on release).
                        Binding {
                            target: volumeSlider
                            property: "value"
                            value: root.effective.volume
                        }
                    }
                }

                // The four feature toggles as a toggle bar, not four switch
                // rows - the Widget behaviour precedent (b89908fef): four
                // ConfigSwitches spend ~170px of a rail this narrow on four
                // bits, a FlowButtonGroup spends ~64. A glyph cannot label
                // itself, so the caption under the bar names the hovered
                // toggle - and, off-hover, which are on.
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: WallpaperEngineFeatures.engineFlags
                    spacing: Appearance.spacing.space50

                    property string hoveredLabel: ""
                    id: featureBar

                    readonly property var featureToggles: [
                        { key: "audioProcessing", icon: "graphic_eq",
                          label: Translation.tr("Audio reactive"),
                          on: root.effective.audioProcessing,
                          invert: false },
                        { key: "disableMouse", icon: "mouse",
                          label: Translation.tr("Mouse interaction"),
                          on: !root.effective.disableMouse,
                          invert: true },
                        { key: "disableParallax", icon: "layers",
                          label: Translation.tr("Parallax"),
                          on: !root.effective.disableParallax,
                          invert: true },
                        { key: "disableParticles", icon: "flare",
                          label: Translation.tr("Particles"),
                          on: !root.effective.disableParticles,
                          invert: true }
                    ]

                    FlowButtonGroup {
                        Layout.fillWidth: true
                        spacing: Appearance.spacing.space50

                        Repeater {
                            model: featureBar.featureToggles
                            delegate: IconToolbarButton {
                                id: featureToggle
                                required property var modelData
                                implicitHeight: 40
                                text: featureToggle.modelData.icon
                                toggled: featureToggle.modelData.on
                                onClicked: {
                                    const next = featureToggle.modelData.on;
                                    // `on` is the positive sense; the three
                                    // disable-keys store its inverse.
                                    root.writeSetting(featureToggle.modelData.key,
                                        featureToggle.modelData.invert ? next : !next);
                                }
                                onHoveredChanged: {
                                    if (featureToggle.hovered)
                                        featureBar.hoveredLabel = featureToggle.modelData.label;
                                    else if (featureBar.hoveredLabel === featureToggle.modelData.label)
                                        featureBar.hoveredLabel = "";
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: Appearance.spacing.space150
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: {
                            if (featureBar.hoveredLabel.length > 0)
                                return featureBar.hoveredLabel;
                            const on = featureBar.featureToggles
                                .filter(toggle => toggle.on)
                                .map(toggle => toggle.label);
                            return on.length > 0
                                ? Translation.tr("On: %1").arg(on.join("  ·  "))
                                : Translation.tr("Nothing on");
                        }
                    }
                }

                // ---- The wallpaper's own properties --------------------
                // project.json general.properties, per-wallpaper by nature
                // (there is no global side, so these are independent of the
                // Custom settings switch). Every edit reloads the wallpaper -
                // a load-time --set-property - hence commit-on-release for
                // the sliders and colors here too.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Appearance.spacing.space100
                    visible: root.activeProjectId !== ""
                        && WallpaperEngineFeatures.projectProperties
                        && root.activeProperties.length > 0
                    spacing: Appearance.spacing.space100
                    StyledText {
                        Layout.leftMargin: Appearance.spacing.space150
                        Layout.fillWidth: true
                        text: Translation.tr("Wallpaper properties")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    IconToolbarButton {
                        implicitWidth: height
                        visible: WallpaperEngineOverrides.hasProperties(root.activeProjectId)
                        text: "restart_alt"
                        onClicked: WallpaperEngineOverrides.clearProperties(root.activeProjectId)
                        StyledToolTip { text: Translation.tr("Reset to the wallpaper's defaults") }
                    }
                }

                Repeater {
                    model: (root.activeProjectId !== ""
                        && WallpaperEngineFeatures.projectProperties)
                        ? root.activeProperties : []
                    delegate: WallpaperPropertyControl {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: Appearance.spacing.space150
                        Layout.rightMargin: Appearance.spacing.space100
                        definition: modelData
                        // The edited value if there is one, else the
                        // wallpaper's own default.
                        currentValue: WallpaperEngineOverrides.active.properties[modelData.name]
                            ?? modelData.value
                        edited: modelData.name in WallpaperEngineOverrides.active.properties
                        onCommitted: value => WallpaperEngineOverrides.setProjectProperty(
                            root.activeProjectId, modelData.name, value)
                    }
                }

                // ---- Compatibility -------------------------------------
                // The reference's bulk scanner: test every wallpaper in a
                // spawned scanner process and mark the ones the renderer
                // cannot start, so a broken tile says so before it is
                // clicked instead of after the desktop goes black.
                StyledText {
                    Layout.leftMargin: Appearance.spacing.space150
                    Layout.topMargin: Appearance.spacing.space100
                    text: Translation.tr("Compatibility")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                // The active wallpaper's own verdict, when there is one.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Appearance.spacing.space150
                    visible: root.activeProject !== null
                        && WallpaperEngineCompat.statusFor(root.activeProject) !== "unknown"
                    spacing: Appearance.spacing.space75
                    MaterialSymbol {
                        readonly property string status: root.activeProject
                            ? WallpaperEngineCompat.statusFor(root.activeProject) : "unknown"
                        text: status === "ok" ? "check_circle" : "error"
                        iconSize: Appearance.font.pixelSize.larger
                        color: status === "ok"
                            ? Appearance.colors.colPrimary
                            : Appearance.m3colors.m3error
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        readonly property string status: root.activeProject
                            ? WallpaperEngineCompat.statusFor(root.activeProject) : "unknown"
                        text: status === "ok"
                            ? Translation.tr("Renders on this machine")
                            : Translation.tr("Could not be started")
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }

                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 36
                    buttonRadius: height / 2
                    enabled: WallpaperEngine.projects.length > 0
                    onClicked: {
                        if (WallpaperEngineCompat.scanning)
                            WallpaperEngineCompat.stopScan();
                        else
                            WallpaperEngineCompat.startScan(WallpaperEngine.projects, false);
                    }
                    altAction: () => WallpaperEngineCompat.startScan(WallpaperEngine.projects, true)
                    contentItem: RowLayout {
                        anchors.fill: parent
                        spacing: Appearance.spacing.space75
                        Item { Layout.fillWidth: true }
                        MaterialSymbol {
                            text: WallpaperEngineCompat.scanning ? "stop_circle" : "troubleshoot"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            text: WallpaperEngineCompat.scanning
                                ? Translation.tr("Scanning %1/%2")
                                    .arg(WallpaperEngineCompat.scanDone)
                                    .arg(WallpaperEngineCompat.scanTotal)
                                : Translation.tr("Check compatibility")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer2
                        }
                        Item { Layout.fillWidth: true }
                    }
                    StyledToolTip {
                        text: WallpaperEngineCompat.scanning
                            ? Translation.tr("Stop the scan")
                            : Translation.tr("Test untested wallpapers in the background. Long-press to retest all.")
                    }
                }

                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "visibility_off"
                    text: Translation.tr("Hide broken")
                    checked: root.weConfig.hideBroken ?? false
                    onToggleRequested: root.weConfig.hideBroken = !(root.weConfig.hideBroken ?? false)
                }

                Item { Layout.fillHeight: true }
            }
        }
    }
}
