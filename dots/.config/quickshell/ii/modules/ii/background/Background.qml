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
        property bool videoRevealed: false

        //centered Wallpaper
        property bool centeredWallpaperEnabled: Config.options.background.centeredWallpaper && (!Config.options.background.centeredWallpaperOnlyWhenLocked || GlobalStates.screenLocked)
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
            return Config.options.background.wallpaperPath
        }

        // Embedded Wallpaper Engine: when a WE project is active it is rendered
        // in-shell (WallpaperEngineLayer) as the wallpaper, replacing the static
        // image path. Suppressed while the work-safety screen is up.
        //
        // A WE lock wallpaper is served by switching this project on lock (and back
        // on unlock): the WE surface reloads the lock project and the existing
        // WE<->WE peel plays, so one renderer covers both - no second surface.
        property string weProjectPath: {
            if (GlobalStates.screenLocked && Config.options.background.lockWallEngine !== "")
                return Config.options.background.lockWallEngine
            return Config.options.wallpaperSelector.wallpaperEngine.activePath ?? ""
        }
        // "web" wallpapers can't render in the embed (need CEF, which is disabled
        // because it corrupts the shared GL context); fall back to the static
        // wallpaper for them. Case-insensitive: the scanner emits "Web".
        property bool weActive: bgRoot.weProjectPath !== "" && !bgRoot.wallpaperSafetyTriggered
            && (Config.options.wallpaperSelector.wallpaperEngine.activeType ?? "").toLowerCase() !== "web"
        // Only hide the static-image layers once the WE surface has actually
        // loaded. If the module is missing (stock binary) the Loader errors and
        // weShown stays false, so the static wallpaper still shows.
        property bool weShown: weLoader.status === Loader.Ready

        // Lock wallpaper peel (WE desktop + a distinct lock image). Rendered here
        // on the background - below the desktop widgets, which must stay visible on
        // the lock screen - rather than on the lock surface (which would cover
        // them). Peels the live WE into the lock image on lock, and back on unlock.
        //
        // progress is advanced by lockPeelTimer against the wall clock rather than a
        // QML animation: on the freshly-shown lock state the animation clock can
        // jump and complete the tween in one step, whereas the timer is immune.
        // Image lock wallpaper only. A WE lock wallpaper (lockWallEngine set) is
        // served by switching weProjectPath instead, so exclude it here even though
        // its preview lives in lockWall for palette generation.
        property bool lockWallShown: GlobalStates.screenLocked
            && Config.options.background.lockWall !== ""
            && Config.options.background.lockWallEngine === "" && bgRoot.weActive
        property bool lockRevealWe: false // true = peeling back to WE (unlock)

        onLockWallShownChanged: {
            if (!bgRoot.weActive || Config.options.background.lockWall === "") return
            bgRoot.lockRevealWe = !bgRoot.lockWallShown
            if (bgRoot.wallpaperAnimation === "") { lockPeel.progress = 1.0; return }
            bgRoot.currentShader = bgRoot.wallpaperAnimation === "random"
                ? bgRoot.shaderList[Math.floor(Math.random() * bgRoot.shaderList.length)]
                : bgRoot.wallpaperAnimation
            lockPeel.progress = 0.0
            lockPeelTimer.startTime = Date.now()
            lockPeelTimer.running = true
        }
        Timer {
            id: lockPeelTimer
            interval: 16
            repeat: true
            running: false
            property double startTime: 0
            onTriggered: {
                const t = Math.min((Date.now() - lockPeelTimer.startTime) / Appearance.wallpaperTransitionDuration, 1.0)
                // InOutCubic, matching the wallpaper-switch transition.
                lockPeel.progress = t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2
                if (t >= 1.0) lockPeelTimer.running = false
            }
        }

        // WE wallpaper switch transition state.
        property string weLoadedProject: ""     // project currently in the surface
        property real weTransitionProgress: 1.0  // 0 = old still, 1 = new surface
        property bool weTransitioning: false

        // Switch the WE surface to `path`, animating a shader transition from a
        // snapshot of the current frame into the newly-loaded surface. Called on
        // weProjectPath changes instead of a reactive binding so the old frame can
        // be captured before the surface reloads.
        function loadWeWallpaper(path) {
            if (!weLoader.item || path === bgRoot.weLoadedProject) return
            const canTransition = bgRoot.weLoadedProject !== "" && weLoader.item.rendered
                && bgRoot.wallpaperAnimation !== ""
            if (!canTransition) {
                bgRoot.weLoadedProject = path
                weLoader.item.projectPath = path
                return
            }
            // Snapshot the outgoing frame, then swap + run the transition.
            weLoader.item.grabToImage(function(result) {
                weOldStill.source = result.url
                bgRoot.weLoadedProject = path
                bgRoot.currentShader = bgRoot.wallpaperAnimation === "random"
                    ? bgRoot.shaderList[Math.floor(Math.random() * bgRoot.shaderList.length)]
                    : bgRoot.wallpaperAnimation
                bgRoot.weTransitionProgress = 0.0
                bgRoot.weTransitioning = true
                weLoader.item.projectPath = path // reload; onRenderedChanged starts the anim
            })
        }
        onWeProjectPathChanged: loadWeWallpaper(bgRoot.weProjectPath)

        // Hold the old still briefly after the new surface's first frame so the
        // transition reveals settled content, not a warmup/black frame.
        Timer {
            id: weTransitionDelay
            interval: 300
            onTriggered: weTransitionAnim.restart()
        }

        NumberAnimation {
            id: weTransitionAnim
            target: bgRoot
            property: "weTransitionProgress"
            from: 0.0
            to: 1.0
            duration: Appearance.wallpaperTransitionDuration
            easing.type: Easing.InOutCubic
            onFinished: {
                bgRoot.weTransitioning = false
                weOldStill.source = ""
            }
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

        screen: modelData
        exclusionMode: ExclusionMode.Ignore
        // Under WlSessionLock the compositor hides every normal surface beneath
        // the lock surface, so the background must sit on the Overlay layer to be
        // seen while locked. Promote the instant locking begins and hold it there
        // until the reverse transition has fully played out (progress back to 0),
        // otherwise the peel animates while hidden and only its end state pops in.
        WlrLayershell.layer: (GlobalStates.screenLocked && !scaleAnim.running) ? WlrLayer.Overlay : WlrLayer.Bottom
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
            if (!bgRoot.wallpaperSafetyTriggered || bgRoot.wallpaperIsVideo)
                return "transparent";
            return CF.ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colPrimary, 0.75);
        }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        Component.onCompleted: {
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
            bgRoot.videoRevealed = bgRoot.wallpaperIsVideo
        }

        onWallpaperPathChanged: {
            // Lock/unlock can request a wallpaper that is still in QML's image
            // cache. In that case status may remain Ready and emit no change,
            // so explicitly start the transition on the next event-loop turn.
            // Stop the previous animation first so its completion handler cannot
            // clear the sources belonging to this newer request.
            transitionAnim.stop()
            const generation = ++bgRoot.wallpaperTransitionGeneration
            bgRoot.videoRevealed = false
            if (wallpaperSafetyTriggered) {
                previousWallpaper.source = ""
                wallpaper.source = ""
                bgRoot.transitionProgress = 1.0
                return
            }
            if (bgRoot.wallpaperAnimation === "") {
                wallpaper.source = wallpaperPath
                bgRoot.currentWallpaperSource = wallpaperPath
                if (!bgRoot.wallpaperIsVideo) return
                bgRoot.videoRevealed = true
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
                bgRoot.videoRevealed = bgRoot.wallpaperIsVideo
            }
        }

        Timer {
            id: wallpaperChangeTimer
            interval: Config.options.wallpaperSelector.changeInterval
            running: Config.options.wallpaperSelector.changeInterval > 0
            repeat: true
            onTriggered: {
                if (Wallpapers.folderModel.count > 0) {
                    Wallpapers.randomFromCurrentFolder()
                }
            }
        }

        Connections {
            target: GlobalStates
            function onScreenLockedChanged() {
                if (!GlobalStates.screenLocked) {
                    bgRoot.videoRevealed = bgRoot.wallpaperIsVideo
                }
            }
        }

        Item {
            anchors.fill: parent

            // Live Wallpaper Engine layer - bottom of the stack. When active it
            // is the wallpaper; the static-image layers below are hidden. Loaded
            // by URL so a stock binary (no WE module) degrades to static images
            // instead of erroring the whole background.
            Loader {
                id: weLoader
                anchors.fill: parent
                active: bgRoot.weActive
                source: Qt.resolvedUrl("WallpaperEngineLayer.qml")
                // projectPath is set imperatively (see loadWeWallpaper) rather than
                // bound, so a switch can snapshot the old frame before reloading.
                onLoaded: if (item) {
                    bgRoot.weLoadedProject = bgRoot.weProjectPath
                    item.projectPath = bgRoot.weProjectPath
                }
                // First rendered frame of a newly-loaded project: kick off the
                // shader transition against the captured old frame.
                Connections {
                    target: weLoader.item
                    enabled: weLoader.item !== null
                    function onRenderedChanged() {
                        // `rendered` flips on the first frame, which can still be a
                        // warmup/black frame. Hold the old still a touch longer so
                        // the peel reveals real content, not black.
                        if (weLoader.item && weLoader.item.rendered
                                && bgRoot.weTransitioning && bgRoot.weTransitionProgress === 0.0)
                            weTransitionDelay.restart()
                    }
                }
            }

            // Frozen snapshot of the outgoing WE frame (fromImage of the transition).
            Image {
                id: weOldStill
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                cache: false
                visible: false
            }
            // The live incoming WE surface as a sampled texture (toImage).
            ShaderEffectSource {
                id: weLiveSource
                anchors.fill: parent
                sourceItem: weLoader.item
                live: true
                hideSource: false
                visible: false
            }
            // Reuses the same peel/pixelate/etc. shaders as the static-image
            // transition, blending the old WE still into the live new WE surface.
            ShaderEffect {
                id: weTransition
                anchors.fill: parent
                z: 1
                visible: bgRoot.weTransitioning
                property var fromImage: weOldStill
                property var toImage: weLiveSource
                property real progress: bgRoot.weTransitionProgress
                property real aspectX: width / height
                property real aspectY: 1.0
                property vector2d aspectRatio: Qt.vector2d(aspectX, aspectY)
                property vector2d origin: Qt.vector2d(0.5, 0.5)
                fragmentShader: Qt.resolvedUrl(`shaders/${bgRoot.currentShader}.frag.qsb`)
            }

            Image {
                id: previousWallpaper
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                cache: true
                smooth: true
                asynchronous: true
                layer.enabled: bgRoot.wallpaperAnimation !== ""
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
                layer.enabled: bgRoot.wallpaperAnimation !== ""
                    && bgRoot.transitionProgress < 1
                visible: !bgRoot.weShown && bgRoot.wallpaperAnimation === "" && !blurLoader.active && !bgRoot.centeredWallpaperEnabled && !bgRoot.videoRevealed
                onStatusChanged: {
                    if (status === Image.Ready && bgRoot.transitionProgress === 0.0) {
                        transitionAnim.restart()
                    }
                }
            }

            ShaderEffect {
                id: transitionEffect
                anchors.fill: parent
                visible: !bgRoot.weShown && !blurLoader.active && bgRoot.wallpaperAnimation !== "" && !bgRoot.centeredWallpaperEnabled && !bgRoot.videoRevealed
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

            // Lock wallpaper (static image), sampled by the lock peel shader.
            // layer.enabled so the shader samples the PreserveAspectCrop'd render,
            // not the raw image texture (which it would stretch to the screen -
            // badly wrong for a square WE preview).
            Image {
                id: lockWallImage
                anchors.fill: parent
                source: Config.options.background.lockWall
                fillMode: Image.PreserveAspectCrop
                cache: false
                smooth: true
                asynchronous: true
                layer.enabled: true
                visible: false
            }
            // Lock peel: live WE <-> lock image, using the configured shader. Above
            // the WE/static layers, below the blur and the desktop widgets. Held
            // visible while locked so the settled state (progress 1 -> toImage) shows
            // the lock image; hidden once unlocked so the live WE draws directly.
            ShaderEffect {
                id: lockPeel
                anchors.fill: parent
                blending: true
                visible: bgRoot.weShown && (bgRoot.lockWallShown || lockPeelTimer.running)
                property var fromImage: bgRoot.lockRevealWe ? lockWallImage : weLiveSource
                property var toImage: bgRoot.lockRevealWe ? weLiveSource : lockWallImage
                property real progress: 1.0
                property real aspectX: width / height
                property real aspectY: 1.0
                property vector2d aspectRatio: Qt.vector2d(aspectX, aspectY)
                property vector2d origin: Qt.vector2d(0.5, 0.5)
                fragmentShader: Qt.resolvedUrl(`shaders/${bgRoot.currentShader}.frag.qsb`)
            }

            Loader {
                id: blurLoader
                active: Config.options.lock.blur.enable && (GlobalStates.screenLocked || scaleAnim.running)
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
                    // Blur the lock peel (WE<->lock-image) when a lock wallpaper is
                    // in play; the live WE surface when it is the wallpaper;
                    // otherwise the static image / transition.
                    source: (bgRoot.weShown && (bgRoot.lockWallShown || lockPeelTimer.running))
                        ? lockPeel
                        : (bgRoot.weShown
                            ? weLoader.item
                            : (bgRoot.wallpaperAnimation === "" ? wallpaper : transitionEffect))
                    radius: GlobalStates.screenLocked ? Config.options.lock.blur.radius : 0
                    samples: Config.options.lock.blur.size 
                    Rectangle {
                        opacity: GlobalStates.screenLocked ? 1 : 0
                        anchors.fill: parent
                        color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 0.7)
                    }
                }
            }

            Rectangle {
                id: centeredWallpaperBg
                anchors.fill: parent
                color: bgRoot.centeredWallpaperColor
                opacity: bgRoot.centeredWallpaperEnabled ? 1 : 0
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

                state: bgRoot.centeredWallpaperEnabled ? "shown" : "hidden"

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

            DropArea {
                id: wallpaperDropArea
                anchors.fill: parent
                keys: ["text/uri-list"]

                property var currentUrls: []

                onEntered: (drag) => {
                    drag.accepted = drag.hasUrls
                    wallpaperDropArea.currentUrls = drag.hasUrls ? drag.urls : []
                }

                onExited: {
                    wallpaperDropArea.currentUrls = []
                }

                onDropped: (drop) => {
                    if (!drop.hasUrls) {
                        drop.accepted = false
                        wallpaperDropArea.currentUrls = []
                        return
                    }

                    if (drop.urls.length === 1) {
                        const path = CF.FileUtils.trimFileProtocol(decodeURIComponent(drop.urls[0].toString()))
                        const validExt = /\.(png|jpe?g|webp|bmp|gif|mp4|webm|mkv|avi|mov)$/i.test(path)
                        if (validExt) {
                            Wallpapers.select(path, Appearance.m3colors.darkmode)
                        } else {
                            const globalPos = wallpaperDropArea.mapToGlobal(drop.x, drop.y)
                            DropShelf.show(drop.urls, globalPos.x, globalPos.y)
                        }
                    } else {
                        const globalPos = wallpaperDropArea.mapToGlobal(drop.x, drop.y)
                        DropShelf.show(drop.urls, globalPos.x, globalPos.y)
                    }
                    drop.accept()
                    wallpaperDropArea.currentUrls = []
                }

                Rectangle {
                    id: dropOverlay
                    anchors.fill: parent
                    visible: wallpaperDropArea.containsDrag
                    color: CF.ColorUtils.transparentize(Appearance.colors.colPrimary, 0.6)

                    property bool isSingleImage: wallpaperDropArea.currentUrls.length === 1
                        && /\.(png|jpe?g|webp|bmp|gif|mp4|webm|mkv|avi|mov)$/i.test(
                            CF.FileUtils.trimFileProtocol(wallpaperDropArea.currentUrls[0].toString())
                        )

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Appearance.spacing.space100
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: dropOverlay.isSingleImage ? "wallpaper" : "stacks"
                            iconSize: 64
                            color: Appearance.colors.colOnPrimary
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: dropOverlay.isSingleImage
                                ? Translation.tr("Drop to set as wallpaper")
                                : Translation.tr("Drop to add to shelf")
                            font.pixelSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
            }

            WidgetCanvas {
                id: widgetCanvas
                anchors.fill: parent
                // Above the WE wallpaper-switch transition (weTransition, z 1) so the
                // desktop widgets/plugins stay visible while wallpapers cross-fade.
                z: 2

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
                        wallpaperPath: bgRoot.wallpaperPath
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
                            wallpaperPath: bgRoot.wallpaperPath
                            // Live surface for in-shell "blur" frost. During lock
                            // and the lock<->WE peel, frost against the peel itself
                            // so it tracks the exact lock background (avoids the WE
                            // flashing through the frost before the unlock peel
                            // catches up). Otherwise the live WE, or null (=> static
                            // image path) when no WE is active.
                            weSurfaceItem: (bgRoot.lockWallShown || lockPeelTimer.running)
                                ? lockPeel
                                : (bgRoot.weShown ? weLoader.item : null)
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