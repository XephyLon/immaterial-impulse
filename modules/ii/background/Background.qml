pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.common.functions as CF
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

import qs.modules.ii.background.widgets
import qs.modules.ii.background.widgets.clock
import qs.modules.ii.background.widgets.weather
import qs.modules.ii.background.widgets.media
import qs.modules.common.plugins
import qs.modules.ii.background.widgets.images
import qs.modules.ii.background.widgets.resources
import qs.modules.ii.background.widgets.visualizer
import qs.modules.ii.background.widgets.calendar
import qs.modules.ii.background.widgets.worldclock
import qs.modules.ii.background.widgets.usercard

Variants {
    id: root
    model: Quickshell.screens

    function getShapeFromName(name) {
        switch (name) {
            case "Circle":        return MaterialShape.Shape.Circle
            case "Square":        return MaterialShape.Shape.Square
            case "Slanted":       return MaterialShape.Shape.Slanted
            case "Arch":          return MaterialShape.Shape.Arch
            case "Fan":           return MaterialShape.Shape.Fan
            case "Arrow":         return MaterialShape.Shape.Arrow
            case "SemiCircle":    return MaterialShape.Shape.SemiCircle
            case "Oval":          return MaterialShape.Shape.Oval
            case "Pill":          return MaterialShape.Shape.Pill
            case "Triangle":      return MaterialShape.Shape.Triangle
            case "Diamond":       return MaterialShape.Shape.Diamond
            case "ClamShell":     return MaterialShape.Shape.ClamShell
            case "Pentagon":      return MaterialShape.Shape.Pentagon
            case "Gem":           return MaterialShape.Shape.Gem
            case "Sunny":         return MaterialShape.Shape.Sunny
            case "VerySunny":     return MaterialShape.Shape.VerySunny
            case "Cookie4Sided":  return MaterialShape.Shape.Cookie4Sided
            case "Cookie6Sided":  return MaterialShape.Shape.Cookie6Sided
            case "Cookie7Sided":  return MaterialShape.Shape.Cookie7Sided
            case "Cookie9Sided":  return MaterialShape.Shape.Cookie9Sided
            case "Cookie12Sided": return MaterialShape.Shape.Cookie12Sided
            case "Ghostish":      return MaterialShape.Shape.Ghostish
            case "Clover4Leaf":   return MaterialShape.Shape.Clover4Leaf
            case "Clover8Leaf":   return MaterialShape.Shape.Clover8Leaf
            case "Burst":         return MaterialShape.Shape.Burst
            case "SoftBurst":     return MaterialShape.Shape.SoftBurst
            case "Boom":          return MaterialShape.Shape.Boom
            case "SoftBoom":      return MaterialShape.Shape.SoftBoom
            case "Flower":        return MaterialShape.Shape.Flower
            case "Puffy":         return MaterialShape.Shape.Puffy
            case "PuffyDiamond":  return MaterialShape.Shape.PuffyDiamond
            case "PixelCircle":   return MaterialShape.Shape.PixelCircle
            case "PixelTriangle": return MaterialShape.Shape.PixelTriangle
            case "Bun":           return MaterialShape.Shape.Bun
            case "Heart":         return MaterialShape.Shape.Heart
            default:              return MaterialShape.Shape.Cookie7Sided
        }
    }

    function getColorFromName(name) {
        switch (name) {
            case "primary":            return Appearance.colors.colPrimary
            case "secondary":          return Appearance.colors.colSecondary
            case "tertiary":           return Appearance.colors.colTertiary
            case "primaryContainer":   return Appearance.colors.colPrimaryContainer
            case "secondaryContainer": return Appearance.colors.colSecondaryContainer
            case "tertiaryContainer":  return Appearance.colors.colTertiaryContainer
            case "layer0":             return Appearance.colors.colLayer0
            case "layer1":             return Appearance.colors.colLayer1
            default:                  return Appearance.colors.colPrimaryContainer
        }
    }

    PanelWindow {
        id: bgRoot

        required property var modelData
        property string currentWallpaperSource: Config.options.background.wallpaperPath
        property string previousWallpaperSource: Config.options.background.wallpaperPath

        //centered Wallpaper
        property bool centeredWallpaperEnabled: Config.options.background.centeredWallpaper && (!Config.options.background.centeredWallpaperOnlyWhenLocked || GlobalStates.screenLocked)
        readonly property bool wallpaperEngineConfigured: WallpaperEngine.stableConfigured
        readonly property bool wallpaperEngineActive: wallpaperEngineConfigured && !GlobalStates.screenLocked
        readonly property string widgetWallpaperPath: wallpaperEngineActive
            && Config.options.wallpaperSelector.wallpaperEngine.activePreview !== ""
            ? Config.options.wallpaperSelector.wallpaperEngine.activePreview
            : bgRoot.wallpaperPath
        // The still is already rendered at monitor resolution with the live
        // wallpaper's scaling baked in, so it fills 1:1 on the matching monitor;
        // crop covers the small residual on differently-shaped monitors.
        readonly property int wallpaperEngineStillFillMode: Image.PreserveAspectCrop
        property int centeredWallpaperShape: getShapeFromName(Config.options.background.centeredWallpaperShape)
        property int centeredWallpaperSize: Config.options.background.centeredWallpaperSize
        property color centeredWallpaperColor: root.getColorFromName(Config.options.background.centeredWallpaperColor)

        property var shaderList: ["circlePit", "circleSelect", "magic", "Doom", "Peel", "transition", "pixelate", "stripes"]
        property string currentShader: "pixelate"
        property string wallpaperAnimation: Config.options.background.wallpaperAnimation ?? "random"

        property list<HyprlandWorkspace> workspacesForMonitor: Hyprland.workspaces.values.filter(workspace => workspace.monitor && workspace.monitor.name == monitor.name)
        property var activeWorkspaceWithFullscreen: workspacesForMonitor.filter(workspace => ((workspace.toplevels.values.filter(window => window.wayland?.fullscreen)[0] != undefined) && workspace.active))[0]
        visible: GlobalStates.screenLocked || (!(activeWorkspaceWithFullscreen != undefined)) || !Config?.options.background.hideWhenFullscreen

        property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)

        property string effectiveWallpaperPath: {
            if (GlobalStates.screenLocked && Config.options.background.lockWall !== "")
                return Config.options.background.lockWall
            if (bgRoot.wallpaperEngineConfigured && Config.options.wallpaperSelector.wallpaperEngine.activePreview !== "")
                return Config.options.wallpaperSelector.wallpaperEngine.activePreview
            return Config.options.background.wallpaperPath
        }

        property bool wallpaperIsVideo: bgRoot.effectiveWallpaperPath.endsWith(".mp4") || bgRoot.effectiveWallpaperPath.endsWith(".webm") || bgRoot.effectiveWallpaperPath.endsWith(".mkv") || bgRoot.effectiveWallpaperPath.endsWith(".avi") || bgRoot.effectiveWallpaperPath.endsWith(".mov")
        property string wallpaperPath: wallpaperIsVideo ? Config.options.background.thumbnailPath : bgRoot.effectiveWallpaperPath
        property bool wallpaperSafetyTriggered: {
            const enabled = Config.options.workSafety.enable.wallpaper;
            const sensitiveWallpaper = (CF.StringUtils.stringListContainsSubstring(wallpaperPath.toLowerCase(), Config.options.workSafety.triggerCondition.fileKeywords));
            const sensitiveNetwork = (CF.StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
            return enabled && sensitiveWallpaper && sensitiveNetwork;
        }

        property bool shouldBlur: (GlobalStates.screenLocked && Config.options.lock.blur.enable)
        property color dominantColor: Appearance.colors.colPrimary
        property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
        property color colText: {
            if (wallpaperSafetyTriggered)
                return CF.ColorUtils.mix(Appearance.colors.colOnLayer0, Appearance.colors.colPrimary, 0.75);
            return (GlobalStates.screenLocked && shouldBlur) ? Appearance.colors.colOnLayer0 : CF.ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12));
        }
        Behavior on colText {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        property real transitionProgress: 1.0
        property int wallpaperTransitionGeneration: 0
        property real engineTransitionProgress: 1.0
        property bool engineTransitionActive: false
        property bool engineTransitionReady: false
        property real wallpaperEngineLockProgress: 0

        Behavior on wallpaperEngineLockProgress {
            NumberAnimation {
                duration: Appearance.wallpaperTransitionDuration
                easing.type: Easing.InOutCubic
            }
        }

        // Animate lightweight project previews. Full-monitor cached stills are
        // retained only as fallback: feeding two 5120px stills through layered
        // ShaderEffect inputs makes Qt/NVIDIA allocate gigabytes of private
        // render memory for an image visible only during this short hand-off.
        // The live Wallpaper Engine surface supplies full resolution as soon as
        // the transition completes.
        function startEngineTransition(fromStill, fromPreview, toStill, toPreview) {
            engineTransitionAnim.stop()
            const fromSrc = fromPreview || fromStill
            const toSrc = toPreview || toStill
            if (bgRoot.wallpaperAnimation === "" || !fromSrc || !toSrc)
                return
            enginePreviousPreview.usedFallback = false
            engineNextPreview.usedFallback = false
            enginePreviousPreview.fallbackSource = fromStill
            engineNextPreview.fallbackSource = toStill
            enginePreviousPreview.source = fromSrc
            engineNextPreview.source = toSrc
            bgRoot.currentShader = bgRoot.wallpaperAnimation === "random"
                ? bgRoot.shaderList[Math.floor(Math.random() * bgRoot.shaderList.length)]
                : bgRoot.wallpaperAnimation
            bgRoot.engineTransitionProgress = 0.0
            bgRoot.engineTransitionReady = false
            bgRoot.engineTransitionActive = true
            bgRoot.currentWallpaperSource = toSrc
            if (engineNextPreview.status === Image.Ready)
                engineTransitionAnim.restart()
        }

        screen: modelData
        exclusionMode: ExclusionMode.Ignore
        // Under WlSessionLock the compositor hides every normal surface beneath
        // the lock surface, so the background must sit on the Overlay layer to be
        // seen while locked. Promote the instant locking begins and hold it there
        // until the reverse transition has fully played out (progress back to 0),
        // otherwise the peel animates while hidden and only its end state pops in.
        WlrLayershell.layer: wallpaperEngineConfigured
            ? ((GlobalStates.screenLocked || bgRoot.wallpaperEngineLockProgress > 0) ? WlrLayer.Overlay : WlrLayer.Bottom)
            : ((GlobalStates.screenLocked && !scaleAnim.running) ? WlrLayer.Overlay : WlrLayer.Bottom)
        WlrLayershell.namespace: "quickshell:background"
        WlrLayershell.keyboardFocus: GlobalStates.desktopWidgetKeyboardFocus
            ? WlrKeyboardFocus.OnDemand
            : WlrKeyboardFocus.None
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: {
            // Stay transparent whenever Wallpaper Engine is configured, including
            // while locked: the peel overlay leaves its unrevealed region clear so
            // the live wallpaper surface beneath keeps showing through and gets
            // peeled, instead of being covered by an opaque fill.
            if (bgRoot.wallpaperEngineConfigured)
                return "transparent";
            if (!bgRoot.wallpaperSafetyTriggered || bgRoot.wallpaperIsVideo)
                return "transparent";
            return CF.ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colPrimary, 0.75);
        }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        Component.onCompleted: {
            bgRoot.wallpaperEngineLockProgress = GlobalStates.screenLocked ? 1 : 0
            previousWallpaper.source = ""
            wallpaper.source = bgRoot.wallpaperSafetyTriggered ? "" : bgRoot.wallpaperPath
            bgRoot.currentWallpaperSource = bgRoot.wallpaperPath
            bgRoot.previousWallpaperSource = ""
            bgRoot.transitionProgress = 1.0
            if (bgRoot.wallpaperAnimation !== "") {
                bgRoot.currentShader = bgRoot.wallpaperAnimation === "random"
                    ? bgRoot.shaderList[Math.floor(Math.random() * bgRoot.shaderList.length)]
                    : bgRoot.wallpaperAnimation
            }
        }

        onWallpaperPathChanged: {
            // Wallpaper Engine owns live-wallpaper changes through
            // startEngineTransition(). Its preview also feeds wallpaperPath,
            // but the ordinary transition layer is hidden in this mode. Do not
            // decode and render a second full-screen from/to pair behind it.
            if (bgRoot.wallpaperEngineConfigured) {
                transitionAnim.stop()
                previousWallpaper.source = ""
                wallpaper.source = ""
                bgRoot.transitionProgress = 1.0
                return
            }
            // Lock/unlock can request a wallpaper that is still in QML's image
            // cache. In that case status may remain Ready and emit no change,
            // so explicitly start the transition on the next event-loop turn.
            // Stop the previous animation first so its completion handler cannot
            // clear the sources belonging to this newer request.
            transitionAnim.stop()
            const generation = ++bgRoot.wallpaperTransitionGeneration
            if (wallpaperSafetyTriggered) {
                previousWallpaper.source = ""
                wallpaper.source = ""
                bgRoot.transitionProgress = 1.0
                return
            }
            if (bgRoot.wallpaperAnimation === "") {
                wallpaper.source = wallpaperPath
                bgRoot.currentWallpaperSource = wallpaperPath
                return
            }

            previousWallpaper.source = bgRoot.currentWallpaperSource
            wallpaper.source = wallpaperPath
            bgRoot.currentWallpaperSource = wallpaperPath
            if (bgRoot.wallpaperAnimation === "random") {
                bgRoot.currentShader = bgRoot.shaderList[Math.floor(Math.random() * bgRoot.shaderList.length)]
            } else {
                bgRoot.currentShader = bgRoot.wallpaperAnimation
            }
            bgRoot.transitionProgress = 0.0
            Qt.callLater(function() {
                if (generation !== bgRoot.wallpaperTransitionGeneration) return
                if (wallpaper.status === Image.Ready && bgRoot.transitionProgress === 0.0)
                    transitionAnim.restart()
            })
        }

        onWallpaperEngineConfiguredChanged: {
            if (bgRoot.wallpaperEngineConfigured) {
                transitionAnim.stop()
                previousWallpaper.source = ""
                wallpaper.source = ""
                bgRoot.transitionProgress = 1.0
            } else {
                wallpaper.source = bgRoot.wallpaperPath
                bgRoot.currentWallpaperSource = bgRoot.wallpaperPath
            }
        }

        NumberAnimation {
            id: transitionAnim
            target: bgRoot
            property: "transitionProgress"
            from: 0.0
            to: 1.0
            duration: Appearance.wallpaperTransitionDuration
            easing.type: Easing.InOutCubic
            onFinished: {
                previousWallpaper.source = ""
                bgRoot.previousWallpaperSource = ""
                bgRoot.transitionProgress = 1.0
            }
        }

        Connections {
            target: WallpaperEngine
            function onTransitionRequested(fromStill, fromPreview, toStill, toPreview) {
                bgRoot.startEngineTransition(fromStill, fromPreview, toStill, toPreview)
            }
        }

        Connections {
            target: GlobalStates
            function onScreenLockedChanged() {
                if (!bgRoot.wallpaperEngineConfigured)
                    return
                // Pick the shader before kicking off its progress animation. The
                // Overlay-layer promotion is bound to screenLocked/progress, so the
                // peel is visible above the lock surface from its first frame.
                bgRoot.currentShader = bgRoot.wallpaperAnimation === "random"
                    ? bgRoot.shaderList[Math.floor(Math.random() * bgRoot.shaderList.length)]
                    : bgRoot.wallpaperAnimation
                bgRoot.wallpaperEngineLockProgress = GlobalStates.screenLocked ? 1 : 0
            }
        }

        NumberAnimation {
            id: engineTransitionAnim
            target: bgRoot
            property: "engineTransitionProgress"
            from: 0.0
            to: 1.0
            duration: Appearance.wallpaperTransitionDuration
            easing.type: Easing.InOutCubic
            onStarted: bgRoot.engineTransitionReady = true
            onFinished: {
                bgRoot.engineTransitionActive = false
                bgRoot.engineTransitionReady = false
                enginePreviousPreview.source = ""
                engineNextPreview.source = ""
            }
        }

        Timer {
            id: wallpaperChangeTimer
            interval: Config.options.wallpaperSelector.changeInterval
            running: Config.options.wallpaperSelector.changeInterval > 0 && !bgRoot.wallpaperEngineActive
            repeat: true
            onTriggered: {
                if (Wallpapers.folderModel.count > 0) {
                    Wallpapers.randomFromCurrentFolder()
                }
            }
        }

        Item {
            anchors.fill: parent

            Item {
                id: engineTransitionLayer
                anchors.fill: parent
                visible: bgRoot.engineTransitionActive

                Image {
                    id: enginePreviousPreview
                    property string fallbackSource: ""
                    property bool usedFallback: false
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    layer.enabled: bgRoot.engineTransitionActive
                    visible: !bgRoot.engineTransitionReady
                    onStatusChanged: {
                        if (status === Image.Error && fallbackSource && !usedFallback) {
                            usedFallback = true
                            source = fallbackSource
                        }
                    }
                }

                Image {
                    id: engineNextPreview
                    property string fallbackSource: ""
                    property bool usedFallback: false
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    layer.enabled: bgRoot.engineTransitionActive
                    visible: false
                    onStatusChanged: {
                        if (status === Image.Error && fallbackSource && !usedFallback) {
                            usedFallback = true
                            source = fallbackSource
                            return
                        }
                        if (status === Image.Ready && bgRoot.engineTransitionActive && !engineTransitionAnim.running)
                            engineTransitionAnim.restart()
                    }
                }

                ShaderEffect {
                    anchors.fill: parent
                    visible: bgRoot.engineTransitionReady
                    property var fromImage: enginePreviousPreview
                    property var toImage: engineNextPreview
                    property real progress: bgRoot.engineTransitionProgress
                    property real aspectX: width / height
                    property real aspectY: 1.0
                    property vector2d aspectRatio: Qt.vector2d(aspectX, aspectY)
                    property vector2d origin: Qt.vector2d(0.5, 0.5)
                    fragmentShader: Qt.resolvedUrl(`shaders/${bgRoot.currentShader}.frag.qsb`)
                }
            }

            Image {
                id: previousWallpaper
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                cache: true
                smooth: true
                asynchronous: true
                layer.enabled: !bgRoot.wallpaperEngineConfigured
                    && bgRoot.wallpaperAnimation !== ""
                    && bgRoot.transitionProgress < 1
                visible: false
            }

            StyledImage {
                id: wallpaper
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                cache: true
                smooth: true
                asynchronous: true
                layer.enabled: !bgRoot.wallpaperEngineConfigured
                    && bgRoot.wallpaperAnimation !== ""
                    && bgRoot.transitionProgress < 1
                visible: !bgRoot.wallpaperEngineConfigured
                    && bgRoot.wallpaperAnimation === "" && !blurLoader.active && !bgRoot.centeredWallpaperEnabled
                onStatusChanged: {
                    if (status === Image.Ready && bgRoot.transitionProgress === 0.0) {
                        transitionAnim.restart()
                    }
                }
            }

            ShaderEffect {
                id: transitionEffect
                anchors.fill: parent
                visible: !bgRoot.wallpaperEngineConfigured
                    && !blurLoader.active && bgRoot.wallpaperAnimation !== "" && !bgRoot.centeredWallpaperEnabled
                property var fromImage: previousWallpaper
                property var toImage: wallpaper
                property real progress: bgRoot.transitionProgress
                property real aspectX: width / height
                property real aspectY: 1.0
                property vector2d aspectRatio: Qt.vector2d(aspectX, aspectY)
                property vector2d origin: Qt.vector2d(0.5, 0.5)
                fragmentShader: bgRoot.wallpaperAnimation !== ""
                    ? Qt.resolvedUrl(`shaders/${bgRoot.currentShader}.frag.qsb`)
                    : ""
            }

            Loader {
                id: blurLoader
                active: !bgRoot.wallpaperEngineConfigured
                    && Config.options.lock.blur.enable && (GlobalStates.screenLocked || scaleAnim.running)
                anchors.fill: parent
                scale: GlobalStates.screenLocked ? Config.options.lock.blur.extraZoom : 1
                Behavior on scale {
                    NumberAnimation {
                        id: scaleAnim
                        duration: 400
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                    }
                }
                sourceComponent: GaussianBlur {
                    source: bgRoot.wallpaperAnimation === "" ? wallpaper : transitionEffect
                    radius: GlobalStates.screenLocked ? Config.options.lock.blur.radius : 0
                    samples: Config.options.lock.blur.size 
                    Rectangle {
                        opacity: GlobalStates.screenLocked ? 1 : 0
                        anchors.fill: parent
                        color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 0.7)
                    }
                }
            }

            Item {
                id: wallpaperEngineLockOverlay
                anchors.fill: parent
                visible: bgRoot.wallpaperEngineConfigured && bgRoot.wallpaperEngineLockProgress > 0
                layer.enabled: visible && Config.options.lock.blur.enable
                // Ramp the frost with lock progress so the peel itself stays sharp
                // and the blur only settles in as the lock finishes (and lifts as
                // it unlocks), instead of blurring the wallpaper mid-transition.
                layer.effect: FastBlur { radius: Config.options.lock.blur.radius * bgRoot.wallpaperEngineLockProgress }

                // "From" texture: a full-scene still rendered from the live
                // wallpaper. Opaque, so it fully covers (and thus hides the
                // compositor-blurred live surface) and can be parallaxed by the
                // shader. When no still exists yet it loads blank/transparent,
                // gracefully falling back to showing the live surface.
                Image {
                    id: wallpaperEngineLockFrom
                    anchors.fill: parent
                    source: wallpaperEngineLockOverlay.visible
                        ? Config.options.wallpaperSelector.wallpaperEngine.activeStill
                        : ""
                    fillMode: bgRoot.wallpaperEngineStillFillMode
                    asynchronous: true
                    // Never cache the still: a re-render writes the same path, and
                    // Qt's pixmap cache would otherwise keep serving the old frame.
                    cache: false
                    layer.enabled: wallpaperEngineLockOverlay.visible
                        && bgRoot.wallpaperAnimation !== ""
                    visible: false
                }

                Image {
                    id: wallpaperEngineLockImage
                    anchors.fill: parent
                    source: wallpaperEngineLockOverlay.visible
                        ? (Config.options.background.lockWall !== ""
                            ? Config.options.background.lockWall
                            : Config.options.wallpaperSelector.wallpaperEngine.activePreview)
                        : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    layer.enabled: wallpaperEngineLockOverlay.visible
                        && bgRoot.wallpaperAnimation !== ""
                    visible: bgRoot.wallpaperAnimation === ""
                    // With a shader the reveal drives visibility, so keep the lock
                    // wallpaper fully opaque; only the no-animation fallback fades in.
                    opacity: bgRoot.wallpaperAnimation === "" ? bgRoot.wallpaperEngineLockProgress : 1
                }

                ShaderEffect {
                    anchors.fill: parent
                    visible: bgRoot.wallpaperAnimation !== ""
                    property var fromImage: wallpaperEngineLockFrom
                    property var toImage: wallpaperEngineLockImage
                    property real progress: bgRoot.wallpaperEngineLockProgress
                    property real aspectX: width / height
                    property real aspectY: 1.0
                    property vector2d aspectRatio: Qt.vector2d(aspectX, aspectY)
                    property vector2d origin: Qt.vector2d(0.5, 0.5)
                    fragmentShader: Qt.resolvedUrl(`shaders/${bgRoot.currentShader}.frag.qsb`)

                    // Dim only ramps in with the lock so the live wallpaper stays at
                    // full brightness until the peel actually covers it.
                    Rectangle {
                        anchors.fill: parent
                        color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 0.7)
                        opacity: bgRoot.wallpaperEngineLockProgress
                    }
                }
            }

            Rectangle {
                id: centeredWallpaperBg
                anchors.fill: parent
                color: bgRoot.centeredWallpaperColor
                opacity: bgRoot.centeredWallpaperEnabled && !bgRoot.wallpaperEngineConfigured ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
            }

            MaterialShape {
                id: centeredWallpaperShapeItem
                anchors.centerIn: parent
                width: bgRoot.centeredWallpaperSize
                height: bgRoot.centeredWallpaperSize
                color: bgRoot.centeredWallpaperColor
                shape: bgRoot.centeredWallpaperShape
                transformOrigin: Item.Center
                visible: opacity > 0

                state: bgRoot.centeredWallpaperEnabled && !bgRoot.wallpaperEngineConfigured ? "shown" : "hidden"

                states: [
                    State {
                        name: "shown"
                        PropertyChanges { target: centeredWallpaperShapeItem; scale: 1; opacity: 1 }
                    },
                    State {
                        name: "hidden"
                        PropertyChanges { target: centeredWallpaperShapeItem; scale: 1.4; opacity: 0 }
                    }
                ]

                transitions: [
                    Transition {
                        to: "shown"
                        ParallelAnimation {
                            NumberAnimation { target: centeredWallpaperShapeItem; property: "scale"; from: 0; duration: Appearance.animation.elementMove.duration; easing.type: Easing.InOutCubic }
                            NumberAnimation { target: centeredWallpaperShapeItem; property: "opacity"; duration: Appearance.animation.elementMove.duration; easing.type: Easing.InOutCubic }
                        }
                    },
                    Transition {
                        to: "hidden"
                        ParallelAnimation {
                            NumberAnimation { target: centeredWallpaperShapeItem; property: "scale"; duration: Appearance.animation.elementMove.duration; easing.type: Easing.InOutCubic }
                            NumberAnimation { target: centeredWallpaperShapeItem; property: "opacity"; duration: Appearance.animation.elementMove.duration; easing.type: Easing.InOutCubic }
                        }
                    }
                ]

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: MaterialShape {
                        width: centeredWallpaperShapeItem.width
                        height: centeredWallpaperShapeItem.height
                        shape: bgRoot.centeredWallpaperShape
                    }
                }

                StyledImage {
                    anchors.fill: parent
                    source: bgRoot.wallpaperPath
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                    antialiasing: true
                    sourceSize.width: parent.width
                    sourceSize.height: parent.height
                }
            }

            WidgetCanvas {
                id: widgetCanvas
                anchors.fill: parent

                transitions: Transition {
                    PropertyAnimation {
                        properties: "width,height"
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                    AnchorAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.visualizer.enable
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: VisualizerWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.customImage.enable
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: CustomImage {
                        screenWidth:        bgRoot.screen.width
                        screenHeight:       bgRoot.screen.height
                        scaledScreenWidth:  bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale:     1
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.calendar.enable
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: CalendarWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.weather.enable
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: WeatherWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.clock.enable
                        && (GlobalStates.screenLocked
                            || Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: ClockWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                        wallpaperSafetyTriggered: bgRoot.wallpaperSafetyTriggered
                    }
                }
                FadeLoader {
                    id: mediaLoader
                    property bool enableLoading: true
                    shown: Config.options.background.widgets.media.enable && enableLoading
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: MediaWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                    onLoaded: {
                        if (item && item.requestReset) {
                            item.requestReset.connect(() => {
                                mediaLoader.enableLoading = false
                                mediaTimer.running = true
                            })
                        }
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.images.enable
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: ImageConverterWidget {
                        screenWidth:        bgRoot.screen.width
                        screenHeight:       bgRoot.screen.height
                        scaledScreenWidth:  bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale:     1
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.resources.enable
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: ResourcesWidget {
                        screenWidth:        bgRoot.screen.width
                        screenHeight:       bgRoot.screen.height
                        scaledScreenWidth:  bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale:     1
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.worldClock.enable
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: WorldClockWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }
                FadeLoader {
                    shown: Config.options.background.widgets.userCard.enable
                        && (Config.options.background.screenList.length === 0
                            || Config.options.background.screenList.includes(bgRoot.screen.name))
                    sourceComponent: UserCardWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                        wallpaperPath: bgRoot.widgetWallpaperPath
                    }
                }

                Repeater {
                    model: PluginManager.availablePlugins

                    FadeLoader {
                        id: pluginLoader

                        required property var modelData
                        shown: modelData.desktopWidget !== undefined
                            && modelData.startupSafe !== false
                            && Config.options.plugins.enabled.includes(modelData.id)
                        // Keep the loader untransformed. Hyprland derives live
                        // background blur from this surface's alpha map; wrapping
                        // plugin widgets in a Scale transform offsets that map
                        // from the live Wallpaper Engine layer beneath it.
                        enterDuration: Appearance.animation.elementMoveEnter.duration
                        enterEasingCurve: Appearance.animation.elementMoveEnter.bezierCurve
                        exitDuration: Appearance.animation.elementMoveExit.duration
                        exitEasingCurve: Appearance.animation.elementMoveExit.bezierCurve

                        sourceComponent: PluginWidget {
                            manifest: pluginLoader.modelData
                            screenName: bgRoot.screen.name
                            screenWidth: bgRoot.screen.width
                            screenHeight: bgRoot.screen.height
                            scaledScreenWidth: bgRoot.screen.width
                            scaledScreenHeight: bgRoot.screen.height
                            wallpaperScale: 1
                            // Use the exact source resolved by this background,
                            // including lock wallpaper and video thumbnails.
                            wallpaperPath: bgRoot.widgetWallpaperPath
                        }
                    }
                }
            }
            MouseArea {
                id: desktopRightClickArea
                anchors.fill: parent
                z: -2
                acceptedButtons: Qt.RightButton
                onClicked: (mouse) => {
                    GlobalStates.desktopMenuScreen = bgRoot.screen
                    GlobalStates.desktopMenuX = mouse.x
                    GlobalStates.desktopMenuY = mouse.y
                    GlobalStates.desktopMenuOpen = true
                }
            }
        }
    }
}
