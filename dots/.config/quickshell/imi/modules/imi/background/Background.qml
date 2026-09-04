pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.imi.dropShelf
import qs.modules.common.widgets.widgetCanvas
import qs.modules.common.functions as CF
import "../../common/functions/parallax.js" as ParallaxMath
import "../../common/functions/clockDepth.js" as ClockDepthLogic
import "../../common/functions/edit_mode.js" as EditMode
import qs.modules.imi.editMode
import qs.modules.imi.lock
import qs.modules.common.panels.lock
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

import qs.modules.common.plugins

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

        property var shaderList: WallpaperTransitions.shaderValues
        property string currentShader: "pixelate"
        property string wallpaperAnimation: Config.options.background.wallpaperAnimation ?? "random"

        // True fullscreen only, not maximized - see
        // HyprlandData.fullscreenByMonitorName.
        // Whether this screen is the one that plays the wallpaper's sound.
        // The named monitor if it is still connected, else the first screen -
        // so unplugging the named one moves the audio somewhere audible
        // instead of silencing it.
        readonly property bool weAudioOutput: {
            const we = Config.options.wallpaperSelector.wallpaperEngine;
            // Through the per-project resolution: a project may override the
            // global audio switch either way (WallpaperEngineOverrides).
            if (WallpaperEngineOverrides.active.silent)
                return false;
            const name = bgRoot.monitor?.name ?? "";
            if (name === "")
                return false;
            const wanted = we.audioMonitor ?? "";
            const screens = Quickshell.screens ?? [];
            const named = wanted !== "" && screens.some(s => s.name === wanted);
            return named ? name === wanted : name === (screens[0]?.name ?? "");
        }

        readonly property bool monitorHasFullscreen:
            HyprlandData.fullscreenByMonitorName[bgRoot.monitor?.name ?? ""] ?? false

        // `hideWhenFullscreen` used to set `visible: false` on this window. Under
        // WlrLayershell that does not hide anything - it destroys the QQuickWindow
        // (deleteOnInvisible; window reuse is forbidden outright), so every
        // fullscreen transition tore down the surface and built a new scene-graph
        // GL context, which in turn forced the embedded Wallpaper Engine renderer
        // to rebuild against it. Flipping between workspaces with a fullscreen
        // window on one of them left the desktop strobing at 30Hz, alternating
        // between the wallpaper and a transition shader sampling a texture that
        // no longer existed. The exact path from the rebuild to the stuck shader
        // was never pinned down; destroying the surface on a routine user action
        // is reason enough not to.
        //
        // So the window stays mapped and the *contents* are suppressed instead -
        // nothing is drawn, and there is no surface to destroy. Debounced because
        // a workspace the user is flipping through should not cost a suppress and
        // an un-suppress; the un-suppress direction is deliberately immediate.
        property bool suppressedForFullscreen: false
        readonly property bool suppressContents: bgRoot.suppressedForFullscreen
            && !GlobalStates.screenLocked && (Config?.options.background.hideWhenFullscreen ?? true)
        onMonitorHasFullscreenChanged: {
            if (bgRoot.monitorHasFullscreen)
                fullscreenSuppressDelay.restart();
            else {
                fullscreenSuppressDelay.stop();
                bgRoot.suppressedForFullscreen = false;
            }
        }
        Timer {
            id: fullscreenSuppressDelay
            interval: 400
            onTriggered: bgRoot.suppressedForFullscreen = bgRoot.monitorHasFullscreen
        }
        // Deliberately does NOT touch the WE surface's `live`. All `live` gates
        // is the surface's own repaint timer - whether Qt asks it for another
        // frame - so clearing it on an item that is already not being drawn buys
        // nothing, and it costs: `updatePaintNode` is the only place the surface
        // re-shares against a recreated GL context and the only place a queued
        // project switch is applied, and a stopped timer never gets there.
        // Not drawing the contents is the whole of the suppression.
        //
        // `live` is also NOT why a video wallpaper could come back frozen. That
        // was measured to the wrong conclusion once, so: with suppression
        // disabled outright, a video wallpaper still stopped dead whenever ANY
        // window anywhere was fullscreen - including one parked on a workspace
        // that was never on screen. The WE render thread kept looping (0.7% CPU,
        // 59/60 samples parked in nanosleep) while its h264 decode threads sat
        // at 0.0%, against 3.0% and 71.7% when animating. linux-wallpaperengine
        // pauses itself: `WallpaperApplication::render()` early-returns while
        // its Wayland detector counts any fullscreen toplevel, and pauses mpv
        // with it. Nothing in QML can reach that.
        //
        // So idling a live wallpaper is not something `live` can do. Today the
        // embed passes --fullscreen-pause-only-active (qs-wallpaperengine
        // 7e58913, pinned in sdata/subcmd-install/4.wallpaperengine.sh), which
        // counts only *activated* fullscreen toplevels - a window holds
        // activation exactly while it is focused, which is exactly while it
        // covers the wallpaper. This file suppresses the drawing; WE pauses the
        // animation. The two agree on when, by different routes.
        //
        // That arrangement is on its way out, because WE's detector is
        // output-blind: its toplevel output-enter/leave handlers are empty
        // stubs, so its count is process-wide while this file runs one surface
        // per monitor. A game fullscreened on one monitor pauses the wallpaper
        // on all of them. The replacement is the `covered` binding on the loader
        // below, which hands the decision to the side that knows which output is
        // covered - this one. It is inert until the pin moves to a build with
        // `occluded`; both halves have to ship together, or there is a window
        // where neither side pauses anything.
        onSuppressContentsChanged: {
            // A switch requested while suppressed could not be applied - the
            // surface only builds a project from updatePaintNode, which does not
            // run for an item that is not being drawn. Apply it now.
            //
            // Re-read the request instead of replaying a stashed copy of one.
            // A stash has to be invalidated by everything that can supersede it:
            // a switch back to the project already loaded (which loadWeWallpaper
            // returns on before it could clear anything) and the WE layer being
            // destroyed and re-syncing on the way back. It was invalidated by
            // neither, so un-suppressing could load a project the user had
            // already moved off, silently, while the config said otherwise.
            // weProjectPath *is* the request and cannot go stale, and
            // loadWeWallpaper already no-ops when it matches what is loaded.
            if (!bgRoot.suppressContents)
                bgRoot.loadWeWallpaper(bgRoot.weProjectPath);
        }

        property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)

        // ---- Wallpaper parallax -------------------------------------------
        //
        // The wallpaper is drawn into a container larger than the screen and
        // that container is slid around underneath it. Doing it with ONE
        // container, rather than teaching each layer to offset itself, is what
        // makes this work for Wallpaper Engine as well as stills: the WE
        // surface, the frozen stills and the transition shaders all stay
        // `anchors.fill: parent` inside it, so they pan together and the
        // cross-fade keeps lining up mid-pan.
        //
        // The container is sized off the SCREEN rather than off the wallpaper's
        // own pixels. A live WE project has no intrinsic size to scale from, and
        // for stills `PreserveAspectCrop` already covers whatever it is given -
        // so one rule serves both, and the zoom means the same thing either way.
        readonly property bool parallaxEnabled: (Config.options.background.parallax.enable ?? true)
            && !GlobalStates.screenLocked
        // Locked: the lock screen has its own framing (and its own blur zoom),
        // and a wallpaper that slides while the session is locked reads as the
        // session still being live.
        readonly property real parallaxZoom: bgRoot.parallaxEnabled
            ? Math.max(1, Config.options.background.parallax.workspaceZoom ?? 1)
            : 1
        readonly property real parallaxWidth: bgRoot.width * bgRoot.parallaxZoom
        readonly property real parallaxHeight: bgRoot.height * bgRoot.parallaxZoom

        // The static wallpaper's decode bound: the most pixels this screen can
        // ever draw of it (screen x the configured zoom). Without one, the
        // wallpaper decodes at FILE resolution - an 8K picture is a ~130MB
        // decode plus a full-size texture, for a 1.1x-screen viewport. Three
        // properties of the bound are load-bearing:
        // - it reads the SCREEN's size, not bgRoot.width: geometry is 0 for
        //   the first frames, and a sourceSize that starts 0 (= unbounded) and
        //   then lands is one full-res decode plus one bounded re-decode per
        //   startup (the triple-decode trap the selector's own bound records);
        // - it reads the configured zoom, not parallaxZoom: that collapses to
        //   1 while the session is locked, and a bound that moves with it
        //   re-decodes the wallpaper on every lock and unlock;
        // - it is part of the pixmap cache key, so every sharer of this
        //   request (the widget frost, the depth cutout) must carry the SAME
        //   value - tests/tst_wallpaper_blur_sharing.qml holds the frost half.
        // Qt keeps the picture's aspect under PreserveAspectCrop (measured:
        // 7680x2160 bounded to 2112x1188 decodes 4224x1188), so everything
        // reading the item's implicit size for the picture's aspect - the
        // depth registration's coverRect - is unchanged by it.
        readonly property size wallpaperDecodeSize: Qt.size(
            Math.round(bgRoot.modelData.width
                * Math.max(1, Config.options.background.parallax.workspaceZoom ?? 1)),
            Math.round(bgRoot.modelData.height
                * Math.max(1, Config.options.background.parallax.workspaceZoom ?? 1)))

        // Portrait wallpapers have vertical room to spare and no horizontal
        // story to tell, so they pan down the picture instead of across it.
        // Only stills can be measured this way - a WE project reports nothing -
        // so a live wallpaper follows the explicit switch alone.
        readonly property bool parallaxVertical: {
            if (Config.options.background.parallax.vertical) return true;
            if (!(Config.options.background.parallax.autoVertical ?? false)) return false;
            if (bgRoot.weActive) return false;
            return bgRoot.wallpaperIsPortrait;
        }
        // Written by the wallpaper Image as it loads, rather than read off it by
        // id: the still's intrinsic size is only known once the source resolves,
        // and a binding reaching forward into a layer declared further down the
        // file resolves to nothing at all - it did, silently, and only a live
        // load surfaced the ReferenceError.
        property bool wallpaperIsPortrait: false

        readonly property int parallaxWorkspaceChunk: Config.options?.bar.workspaces.shown ?? 10
        readonly property var parallaxState: ({
            workspaceIndex: (bgRoot.monitor?.activeWorkspace?.id ?? 1) - 1,
            totalWorkspaces: bgRoot.parallaxWorkspaceChunk,
            vertical: bgRoot.parallaxVertical,
            enableWorkspace: Config.options.background.parallax.enableWorkspace ?? true,
            enableSidebar: Config.options.background.parallax.enableSidebar ?? true,
            sidebarLeftOpen: GlobalStates.sidebarLeftOpen,
            sidebarRightOpen: GlobalStates.sidebarRightOpen,
            // A sidebar is worth about half a workspace step, so opening one
            // reads as a nudge rather than as a workspace change.
            sidebarFraction: 0.5 / Math.max(1, bgRoot.parallaxWorkspaceChunk - 1),
            overflowX: Math.max(0, bgRoot.parallaxWidth - bgRoot.width),
            overflowY: Math.max(0, bgRoot.parallaxHeight - bgRoot.height)
        })
        readonly property var parallaxOffsets: bgRoot.parallaxEnabled
            ? ParallaxMath.offsets(bgRoot.parallaxState)
            : ({ x: 0, y: 0 })

        // Hands the depth layer's live box to the subject selector, which is a
        // layer surface of its own and therefore in another window. Keyed by
        // screen name and written per screen rather than as one rect, because
        // the same wallpaper is cropped differently on every output and a
        // cutout drawn into the wrong screen's box is a silhouette in the wrong
        // place. Removing the entry on disarm rather than leaving a stale one
        // behind keeps the map's contents equal to "the screens currently
        // publishing", which is what the surface tests to know it can draw.
        function publishDepthViewport(viewport): void {
            const published = Object.assign({}, GlobalStates.clockDepthViewports)
            if (viewport === null)
                delete published[bgRoot.screen.name]
            else
                published[bgRoot.screen.name] = viewport
            GlobalStates.clockDepthViewports = published
        }

        // The lock terms below read `GlobalStates.lockLookActive` - the one
        // spelling of "the lock's look is on screen", which is the session
        // lock OR Edit Mode's Lockscreen tab - because that tab is a FILTER on
        // this viewport (spec §1.4):
        // it switches these same layers to their locked inputs rather than
        // drawing a second copy of any of them, so the preview inside the
        // shrunk card is the picture the lock screen will actually show.
        property string effectiveWallpaperPath: {
            if (GlobalStates.lockLookActive
                    && Config.options.background.lockWall !== "")
                return Config.options.background.lockWall
            return Wallpapers.previewPath || Wallpapers.confirmedPath || Config.options.background.wallpaperPath
        }

        // Embedded Wallpaper Engine: when a WE project is active it is rendered
        // in-shell (WallpaperEngineLayer) as the wallpaper, replacing the static
        // image path. Suppressed while the work-safety screen is up.
        //
        // A WE lock wallpaper is served by switching this project on lock (and back
        // on unlock): the WE surface reloads the lock project and the existing
        // WE<->WE peel plays, so one renderer covers both - no second surface.
        property string weProjectPath: {
            if (GlobalStates.lockLookActive
                    && Config.options.background.lockWallEngine !== "")
                return Config.options.background.lockWallEngine
            return Config.options.wallpaperSelector.wallpaperEngine.activePath ?? ""
        }
        // "web" wallpapers can't render in the embed (need CEF, which is disabled
        // because it corrupts the shared GL context); fall back to the static
        // wallpaper for them. Case-insensitive: the scanner emits "Web".
        property bool weActive: bgRoot.weProjectPath !== "" && !bgRoot.wallpaperSafetyTriggered
            && (Config.options.wallpaperSelector.wallpaperEngine.activeType ?? "").toLowerCase() !== "web"
        // The renderer can also give up on a project it did load: it reports
        // `failed` when the WE thread could not start, or when its render targets
        // came back INCOMPLETE - a scene whose source texture plus per-element
        // composite buffers do not fit in VRAM at screen size. Nothing is ever
        // drawn into the surface in that state, so leaving it on screen is a
        // black desktop; degrade to the static image exactly as `web` does above.
        //
        // Read defensively: `failed` only exists on newer qs-wallpaperengine
        // builds, and on an older one the lookup is undefined, not an error.
        property bool weFailed: (weLoader.item?.failed ?? false)
        // Only hide the static-image layers once the WE surface has actually
        // loaded. If the module is missing (stock binary) the Loader errors and
        // weShown stays false, so the static wallpaper still shows.
        property bool weShown: weLoader.status === Loader.Ready && !bgRoot.weFailed

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
        property bool lockWallShown: GlobalStates.lockLookActive
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

        // Put the transition back to its resting state: no peel on screen, the
        // snapshot released, progress at "new surface". Reached from the
        // watchdog below, and from the two states that make the first frame the
        // peel is waiting for impossible to ever get.
        function settleWeTransition() {
            weTransitionAnim.stop()
            weTransitionDelay.stop()
            bgRoot.weTransitionProgress = 1.0
            bgRoot.weTransitioning = false
            weOldStill.source = ""
        }
        // `failed` latches on a project the renderer cannot draw, and that is
        // precisely a moment when a transition has just been armed: the switch
        // snapshots the outgoing frame and then waits on a frame that will never
        // arrive, since the failure is reported before a texture is ever
        // acquired. Nothing in the transition's own state can see that, so the
        // peel used to sit there for the watchdog's whole budget - about nine
        // seconds of the wallpaper the user just switched *away from*, painted
        // over the static fallback that weFailed had already revealed
        // underneath. That fallback exists to avoid exactly this.
        onWeFailedChanged: if (bgRoot.weFailed) bgRoot.settleWeTransition()
        // Same hole, different trigger: dropping weActive destroys the surface
        // the peel samples as its destination, so the frozen still is all that
        // is left to paint.
        onWeActiveChanged: if (!bgRoot.weActive) bgRoot.settleWeTransition()

        // The SDDM greeter cannot run Wallpaper Engine, so it needs a still of
        // the active project. That still used to be produced by launching a
        // SECOND linux-wallpaperengine - an entire extra copy of the renderer
        // and libcef, several seconds of GPU - to photograph what this surface
        // is already drawing. The surface is a QQuickItem, and the transition
        // below already grabs it, so the still is that same grab saved to a file.
        //
        // One output owns it: the greeter shows a single screen, and every
        // Background instance would otherwise race to write the same path.
        //
        // The path is never recorded in config. It is
        // <cache>/wallpaperengine-stills/<activeProject>.png, so any consumer
        // derives it from the project the config already names - see the note
        // where `activeStill` used to be declared in Config.qml for why storing
        // it is the bug (#103) rather than the convenience it looks like.
        readonly property bool ownsGreeterStill: bgRoot.modelData === Quickshell.screens[0]

        function captureGreeterStill() {
            if (!bgRoot.ownsGreeterStill || !(weLoader.item?.rendered ?? false)) return
            const id = Config.options.wallpaperSelector.wallpaperEngine.activeProject
            if (!id) return
            // PNG, not JPEG. saveToFile takes no quality argument, so a .jpg
            // here is written at Qt's default q75 - measured at 35.0 dB PSNR
            // against the lossless grab, where the old script produced q94.
            // That is a visible step down on a full-screen login background,
            // worst on the dark gradients these scenes are full of. Lossless
            // costs ~7-13 MiB per project against ~0.3-0.8 MiB, which the
            // greeter's own size cap is two orders of magnitude above.
            const target = `${Directories.wallpaperEngineStills}/${id}.png`
            // Failure is not worth surfacing: the greeter derives this same path,
            // finds nothing, and falls back to the preview - which is what it had
            // before any of this existed.
            //
            // On success, poke the greeter sync: the still is produced
            // asynchronously, AFTER the config changes that announced the new
            // wallpaper, so without this the theme apply can copy before the
            // still exists and the login screen keeps the preview until the
            // next unrelated color event. The grab's completion is the event
            // the sync has to observe - see GreeterSync.
            weLoader.item.grabToImage(result => {
                if (result.saveToFile(target)) {
                    GreeterSync.request();
                    // The depth picker's other consumer of this still. A
                    // project on screen for the first time had no still when
                    // it was asked about, and the grab's completion is the
                    // event that changes the answer - observed, not polled.
                    if (ClockDepth.watching)
                        ClockDepth.refresh();
                }
            });
        }

        // `rendered` flips on the FIRST frame, which can still be warmup or
        // black - the same reason the transition holds the outgoing still for a
        // beat. Grab once the surface has settled, not the instant it exists.
        Timer {
            id: greeterStillDelay
            interval: 600
            onTriggered: bgRoot.captureGreeterStill()
        }

        // Switch the WE surface to `path`, animating a shader transition from a
        // snapshot of the current frame into the newly-loaded surface. Called on
        // weProjectPath changes instead of a reactive binding so the old frame can
        // be captured before the surface reloads.
        function loadWeWallpaper(path) {
            if (!weLoader.item || path === bgRoot.weLoadedProject) return
            // Nothing draws this item while suppressed, so the surface would never
            // reach updatePaintNode to build the new project - it would sit on the
            // old one with QML believing otherwise, and the transition would hang
            // waiting for a first frame that cannot arrive. Drop it; un-suppressing
            // re-reads weProjectPath and applies whatever it says then.
            if (bgRoot.suppressContents) return
            const canTransition = bgRoot.weLoadedProject !== "" && weLoader.item.rendered
                && bgRoot.wallpaperAnimation !== ""
            if (!canTransition) {
                bgRoot.weLoadedProject = path
                weLoader.item.projectPath = path
                // A switch arriving mid-transition lands here (the outgoing surface
                // has no rendered frame to snapshot). `weTransitioning` stays true,
                // so give the watchdog a fresh budget for this new load rather than
                // letting it run out on the previous one's clock.
                if (bgRoot.weTransitioning)
                    weTransitionWatchdog.restart()
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
            onTriggered: {
                weTransitionWatchdog.restart() // the peel is starting for real now
                weTransitionAnim.restart()
            }
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

        // A transition is armed here and only disarmed by the animation finishing,
        // which the surface's first rendered frame is what starts. Anything that
        // stops that frame arriving leaves the peel shader on screen indefinitely,
        // blending a frozen still against a live texture - a wallpaper that never
        // settles. Nothing else clears that state, so give it a deadline.
        //
        // The budget has to cover a cold WE project start: a new thread, the scene
        // package parsed, textures and shaders uploaded, and mpv brought up for a
        // video wallpaper. Seconds, not milliseconds, on a large scene. So the
        // watchdog is restarted at each step that proves progress (first frame,
        // then the animation actually starting) rather than being one flat budget
        // from the beginning - otherwise a slow but perfectly healthy load gets
        // cut off mid-peel.
        Timer {
            id: weTransitionWatchdog
            interval: Appearance.wallpaperTransitionDuration + 8000
            running: bgRoot.weTransitioning
            onTriggered: {
                console.warn("[Background] Wallpaper Engine transition did not finish; settling")
                bgRoot.settleWeTransition()
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

        // Whichever layer is painting the wallpaper right now, as an item. Both
        // things that blur the wallpaper - the lock backdrop and Edit Mode's -
        // read this rather than each resolving the same four-way choice, since
        // two copies of it would disagree the first time a fifth layer arrived.
        readonly property Item liveWallpaperLayer: (bgRoot.weShown
                && (bgRoot.lockWallShown || lockPeelTimer.running))
            ? lockPeel
            : (bgRoot.weShown
                ? weLoader.item
                : (bgRoot.wallpaperAnimation === "" ? wallpaper : transitionEffect))

        // ---- Edit Mode's viewport ----------------------------------------
        //
        // The desktop stops being the whole screen and becomes an object on it:
        // the wallpaper viewport, the widget canvas and the clock-depth layer
        // all take one transform, so what the user is arranging keeps its
        // proportions and its coordinates. Derived, never chosen - see
        // edit_mode.js for why the drawer's width is the input.
        // The bar and the dock keep their edges at full size, so the desktop
        // shrinks inside what is LEFT of the screen rather than inside the raw
        // screen - see EditModeInsets for why the two surfaces share one object
        // for those four numbers and re-derive everything else.
        readonly property var editInsets: EditModeInsets.insetsFor(bgRoot.screen?.name ?? "")
        readonly property var editViewport: EditMode.viewportGeometry({
            screenWidth: bgRoot.width,
            screenHeight: bgRoot.height,
            drawerWidth: Appearance.sizes.editModeDrawerWidth,
            margin: Appearance.sizes.editModeMargin,
            edgeMargin: Appearance.sizes.editModeEdgeMargin,
            chromeThickness: Appearance.sizes.toolbarHeight,
            insetTop: bgRoot.editInsets.top,
            insetBottom: bgRoot.editInsets.bottom,
            insetLeft: bgRoot.editInsets.left,
            insetRight: bgRoot.editInsets.right
        })
        // One animated scalar for the whole entry, so the scale and the offset
        // cannot arrive on different frames - and it is GlobalStates' scalar
        // rather than this window's, because the chrome that frames this
        // desktop is a different layer surface deriving its geometry from the
        // same number. The animation, and why it is `elementMove` rather than
        // an entrance tier, are stated where the property lives.
        readonly property real editProgress: GlobalStates.editProgress
        // The ONLY term of the transform the drawer's open state reaches: the
        // desktop's sideways travel, spent out of the room the geometry above
        // reserved. The size takes the drawer's WIDTH whether or not it is
        // open, so opening it translates the desktop and can never resize it -
        // a viewport that changed size mid-edit would rescale every widget
        // under the cursor (spec §1.3, b710ef731's moving target).
        readonly property real editShift: EditMode.drawerTravel(bgRoot.editViewport)
            * GlobalStates.editDrawerProgress
        readonly property var editTransform: EditMode.atProgress(bgRoot.editViewport,
            bgRoot.editProgress, bgRoot.editShift)
        // A scale about the top-left followed by a translation, written as one
        // matrix rather than as a [Scale, Translate] pair: the order a transform
        // list composes in is exactly the kind of thing that is wrong by a
        // factor of the scale and still looks plausible. Row-major, so a point
        // maps to (s*x + tx, s*y + ty).
        //
        // What it DRAWS is a scale about the CENTRE, and that is the geometry's
        // doing rather than this matrix's: the offset edit_mode.js hands in is
        // the centring offset for the scale beside it, on every frame. A centred
        // scale is a different matrix, not a different structure.
        readonly property matrix4x4 editMatrix: Qt.matrix4x4(
            bgRoot.editTransform.scale, 0, 0, bgRoot.editTransform.x,
            0, bgRoot.editTransform.scale, 0, bgRoot.editTransform.y,
            0, 0, 1, 0,
            0, 0, 0, 1)
        // Where that transform puts the desktop, for the chrome drawn around
        // it. Out of the module rather than off the matrix's own terms: the
        // corner, the outline and the shadow have to sit on the desktop's edge
        // exactly, and a second derivation of a registration is the drift
        // ClockDepthCutout exists as one component to prevent.
        readonly property rect editCard: EditMode.cardRect(bgRoot.editViewport,
            bgRoot.editProgress, bgRoot.width, bgRoot.height, bgRoot.editShift)
        // The corner grows with the shrink, so a desktop at rest has no radius
        // applied to it at all rather than one that happens to be hidden. The
        // ladder's own name for the tier, per docs/M3_GUIDELINES.md - a whole
        // desktop is the "major distinct UI block" that tier is for, and the
        // `extraLarge` alias exists for the vendored design system's call sites
        // rather than for mainline ones.
        readonly property real editCardRadius: Appearance.rounding.verylarge * bgRoot.editProgress

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
        // Latched when the transition ShaderEffect fails to load its shader pack
        // (see the handler below for what that does and does not catch). While
        // set, the transition is skipped entirely and the switch snaps, rather
        // than holding a shader that draws nothing over the wallpaper. Reset at
        // the start of each switch so a one-off bad shader does not disable
        // transitions permanently.
        property bool transitionShaderBroken: false

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
            bgRoot.transitionShaderBroken = false
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

        // The wallpaper layers, and the parallax viewport they live in. It is
        // deliberately NOT anchored: it is drawn larger than the screen and its
        // x/y ARE the effect (see parallaxOffsets). At zoom 1 it is exactly
        // screen-sized at 0,0, so the feature collapses back to the old
        // geometry rather than to a special case.
        //
        // One viewport for every layer is what makes Wallpaper Engine parallax
        // for free: the WE surface, the frozen stills and the peel shaders all
        // stay `anchors.fill: parent` inside it, so they pan together and the
        // cross-fade keeps lining up mid-pan.
        Item {
            id: parallaxViewport
            width: bgRoot.parallaxWidth
            height: bgRoot.parallaxHeight
            x: bgRoot.parallaxOffsets.x
            y: bgRoot.parallaxOffsets.y
            // Everything the background draws hangs off here, so this is what
            // `hideWhenFullscreen` switches off - see suppressContents above.
            visible: !bgRoot.suppressContents

            // Edit Mode shrinks the wallpaper and the widgets on it by the same
            // transform, so the desktop reads as one object. A transform and
            // not x/y/width: those four are what the parallax animates, what
            // every widget's clamp measures against and what the frost samples
            // by, and folding a second meaning into them is the mistake
            // b710ef731 ("fix(plugins): stop the position Behavior swallowing
            // the parallax cancellation") cost a store full of walked positions.
            transform: Matrix4x4 { matrix: bgRoot.editMatrix }

            // Slower than a workspace switch on purpose: the wallpaper trails
            // the workspace animation rather than racing it, which is what reads
            // as distance instead of as a second window sliding. Not an
            // Appearance token - those are tuned for UI elements and made the
            // wallpaper snap.
            Behavior on x {
                enabled: bgRoot.parallaxEnabled
                NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
            }
            Behavior on y {
                enabled: bgRoot.parallaxEnabled
                NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
            }

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
                // Tell the renderer this output is covered, so it can idle the
                // producer instead of drawing frames nobody sees. Suppressing
                // the contents (above) only stops Qt asking for them; the WE
                // thread keeps rendering, blitting and publishing regardless.
                //
                // Same condition as the suppression on purpose: one policy, and
                // one the user controls. Turning hideWhenFullscreen off means
                // "leave my wallpaper alone when something is fullscreen", so it
                // should not silently idle the renderer either.
                //
                // Inert until the pin moves - the layer only forwards this to a
                // surface that has an `occluded` property. Until then WE's own
                // detector still does the pausing.
                // Sound belongs to ONE output. There is a renderer per screen,
                // so binding each one to `silent` alone played the wallpaper's
                // audio once per monitor, slightly out of phase - #338. Which
                // screen has the speakers is not something the shell can infer,
                // so it is named in config; empty means the first the
                // compositor reports.
                Binding {
                    target: weLoader.item
                    property: "audioWanted"
                    value: bgRoot.weAudioOutput
                }

                Binding {
                    target: weLoader.item
                    property: "covered"
                    value: bgRoot.suppressContents
                    when: weLoader.item !== null
                    restoreMode: Binding.RestoreNone
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
                                && bgRoot.weTransitioning && bgRoot.weTransitionProgress === 0.0) {
                            weTransitionWatchdog.restart() // the load finished; re-budget
                            weTransitionDelay.restart()
                        }
                        // Every load, transitioning or not - the first project of
                        // the session takes the no-transition path above, and it
                        // needs a still just as much as a switch does.
                        if (weLoader.item?.rendered)
                            greeterStillDelay.restart();
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
                // Above the static wallpaper, so its own visibility has to
                // account for the states that reveal it. `weTransitioning` alone
                // does not: a failed project and a destroyed WE layer both leave
                // the peel painting a frozen still of the *previous* project
                // full-screen over the fallback underneath. Settling on those
                // two clears this as well, but the guard is what makes it a
                // property of the shader rather than of getting the handler
                // ordering right.
                visible: bgRoot.weTransitioning && !bgRoot.weFailed && weLoader.item !== null
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
                sourceSize: bgRoot.wallpaperDecodeSize
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
                sourceSize: bgRoot.wallpaperDecodeSize
                layer.enabled: bgRoot.wallpaperAnimation !== ""
                    && bgRoot.transitionProgress < 1
                // The plain image is the wallpaper. It is always drawn (a
                // transition only paints *over* it for the length of the
                // animation - see transitionEffect), so nothing about the
                // desktop depends on a shader building successfully. Before,
                // an enabled animation made the ShaderEffect the sole painter
                // of the wallpaper forever, and any shader the machine's GL
                // profile could not build left the desktop empty until the
                // next switch (issue #70).
                visible: !bgRoot.weShown && !blurLoader.active && !bgRoot.centeredWallpaperEnabled && !bgRoot.videoRevealed
                onStatusChanged: {
                    if (status === Image.Ready && bgRoot.transitionProgress === 0.0) {
                        transitionAnim.restart()
                    }
                    // Feeds parallax.autoVertical. Both dimensions read 0 until
                    // the source resolves, so the guard keeps a not-yet-loaded
                    // image from looking square and flipping the pan axis.
                    if (status === Image.Ready && implicitWidth > 0 && implicitHeight > 0) {
                        bgRoot.wallpaperIsPortrait = implicitHeight > implicitWidth
                    }
                }
            }

            ShaderEffect {
                id: transitionEffect
                anchors.fill: parent
                // Only while a switch is in flight. Once it settles the plain
                // image below is already showing exactly what progress 1.0
                // would draw, so keeping the shader up buys nothing and costs a
                // full-screen pass every frame - and, because layer.enabled
                // drops with the same binding, it would sample the images at
                // their natural size and stretch them to the screen rather than
                // PreserveAspectCrop.
                visible: !bgRoot.weShown && !blurLoader.active && bgRoot.wallpaperAnimation !== "" && !bgRoot.centeredWallpaperEnabled && !bgRoot.videoRevealed && !bgRoot.transitionShaderBroken && bgRoot.transitionProgress < 1
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
                onStatusChanged: {
                    // Covers a .qsb that is missing or will not parse. It does
                    // NOT cover a shader the driver refuses to compile: Qt bakes
                    // the GLSL ahead of time, so `status` only reports loading
                    // the pack, while the real compile happens later inside the
                    // RHI and surfaces as nothing more than a repeating
                    // "Failed to build graphics pipeline state" warning - status
                    // stays Compiled and this handler never runs (verified
                    // against Qt 6.11 by baking a deliberately invalid variant).
                    // That case is handled structurally instead, by the plain
                    // image above always being drawn.
                    if (status === ShaderEffect.Error) {
                        console.warn("[Background] wallpaper transition shader '" + bgRoot.currentShader + "' failed to compile, falling back to plain image:", log)
                        bgRoot.transitionShaderBroken = true
                        transitionAnim.stop()
                        bgRoot.transitionProgress = 1.0
                        previousWallpaper.source = ""
                        bgRoot.previousWallpaperSource = ""
                    }
                }
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
                // An offscreen render target the size of the output, held for
                // the whole session. With no lock wallpaper configured there is
                // nothing to sample and the layer is pure cost, so skip it.
                //
                // Deliberately NOT gated on "is the lock peel showing": the
                // shader samples this the frame the lock appears, and a layer
                // built one frame late would sample the raw texture instead of
                // the PreserveAspectCrop'd render - the exact bug the comment
                // above describes. Narrowing it further needs the lock path
                // exercised, which is a test rather than a guess.
                layer.enabled: lockWallImage.source.toString() !== ""
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
                // `lockLook` rather than screenLocked alone: Edit Mode's
                // Lockscreen tab shows the lock's own blur inside the shrunk
                // card, through this same loader - a child of the viewport, so
                // it takes the edit transform with everything else in here.
                readonly property bool lockLook: GlobalStates.lockLookActive
                active: Config.options.lock.blur.enable && (blurLoader.lockLook || scaleAnim.running)
                anchors.fill: parent
                scale: blurLoader.lockLook ? Config.options.lock.blur.extraZoom : 1
                Behavior on scale {
                    NumberAnimation {
                        id: scaleAnim
                        duration: 400
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                    }
                }
                sourceComponent: WallpaperBlurBackdrop {
                    // The lock peel (WE<->lock-image) when a lock wallpaper is
                    // in play; the live WE surface when it is the wallpaper;
                    // otherwise the static image / transition.
                    source: bgRoot.liveWallpaperLayer
                    radius: blurLoader.lockLook ? Config.options.lock.blur.radius : 0
                    samples: Config.options.lock.blur.size
                    tintOpacity: blurLoader.lockLook ? 1 : 0
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

                // Live Wallpaper Engine content, centre-cropped into the shape.
                // Samples the same surface the blur/lock shaders use, so no
                // second WE renderer is spawned; only instantiated while the
                // centred wallpaper is on AND a WE surface is actually drawing.
                Loader {
                    anchors.fill: parent
                    active: bgRoot.centeredWallpaperEnabled && bgRoot.weShown && weLoader.item
                    sourceComponent: ShaderEffectSource {
                        sourceItem: weLoader.item
                        live: true
                        hideSource: false
                        // Centre-crop a square out of the full-screen WE surface
                        // so the aspect matches the (square) shape - the
                        // ShaderEffectSource equivalent of PreserveAspectCrop.
                        readonly property real srcW: weLoader.item?.width ?? 0
                        readonly property real srcH: weLoader.item?.height ?? 0
                        readonly property real side: Math.min(srcW, srcH)
                        sourceRect: side > 0
                            ? Qt.rect((srcW - side) / 2, (srcH - side) / 2, side, side)
                            : Qt.rect(0, 0, 0, 0)
                    }
                }

                // Static / video-thumbnail fallback: shown whenever the live WE
                // surface isn't (stock build, image wallpaper, WE still loading).
                StyledImage {
                    anchors.fill: parent
                    visible: !(bgRoot.weShown && weLoader.item)
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
                        const validExt = /\.(png|jpe?g|webp|bmp|gif)$/i.test(path)
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
                        && /\.(png|jpe?g|webp|bmp|gif)$/i.test(
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

        } // parallaxViewport

        WidgetCanvas {
            id: widgetCanvas
            width: bgRoot.width
            height: bgRoot.height
            // Moved out of the viewport, so it needs its own copy of the
            // fullscreen gate the viewport carries - without this the
            // desktop widgets would stay on screen under a fullscreen
            // window while the wallpaper behind them vanished.
            visible: !bgRoot.suppressContents
            // Widget parallax. The canvas is a SIBLING of the wallpaper
            // viewport, not a child, so it cannot inherit the pan - and it
            // must not: matching the wallpaper exactly would glue the
            // widgets to the picture and there would be no effect to see.
            // Travelling further than the wallpaper (factor > 1) is what
            // reads as the widgets sitting in front of it.
            //
            // Screen-sized regardless of the zoom, so a widget dragged to a
            // corner stays where the user put it rather than being placed
            // against an overscanned canvas they cannot see the edges of.
            // Centre-relative, not edge-relative: this canvas is screen-sized,
            // so the wallpaper's own offsets would shift it off the screen by
            // half the zoom overflow and make that strip of desktop
            // unreachable - permanently on whichever axis is not travelling.
            // See ParallaxMath.widgetOffsets.
            readonly property var widgetParallax: (Config.options.background.parallax.enableWidgets ?? true)
                ? ParallaxMath.widgetOffsets(bgRoot.parallaxState, Config.options.background.parallax.widgetsFactor ?? 0)
                : ({ x: 0, y: 0 })
            x: widgetParallax.x
            y: widgetParallax.y
            Behavior on x {
                enabled: bgRoot.parallaxEnabled
                NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
            }
            Behavior on y {
                enabled: bgRoot.parallaxEnabled
                NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
            }
            // Above the WE wallpaper-switch transition (weTransition, z 1) so the
            // desktop widgets/plugins stay visible while wallpapers cross-fade.
            z: 2
            // The desktop is the canvas the marquee exists for: rubber-band
            // several widgets, then drag any of them to move the cluster.
            selectionEnabled: true
            // The one desktop canvas is the one that edits. The overlay reuses
            // this component and must never enter the mode, so the flag is
            // handed in here rather than read from GlobalStates inside it.
            editMode: GlobalStates.editMode
            // The same transform the wallpaper takes. `scale` is a render-time
            // transform and touches none of x, y, width or height, so every
            // stored position still means the same point, every clamp range is
            // unchanged, and the hand-computed drag stays exact - it maps the
            // pointer through the moving item into this frame, and the current
            // transform cancels itself out (AbstractWidget).
            transform: Matrix4x4 { matrix: bgRoot.editMatrix }

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
            Repeater {
                model: PluginManager.availablePlugins

                FadeLoader {
                    id: pluginLoader

                    required property var modelData
                    // The union of the two surfaces' choices: the desktop's
                    // enabled list, plus whatever the lock screen's own choice
                    // holds once it has forked from it (layout_surfaces.js).
                    // The host builds a widget or it does not - there is no
                    // per-surface instantiation - so the widget's own
                    // visibleOnDesktop/visibleWhenLocked pair is what keeps a
                    // lock-only pick off the desktop. While the two are linked
                    // this term answers exactly what the list alone did.
                    shown: modelData.desktopWidget !== undefined
                        && modelData.startupSafe !== false
                        && (Config.options.plugins.enabled.includes(modelData.id)
                            || (Config.options.lock.showWidgets
                                && PluginState.lockWidgetEnabled(modelData.id)))
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
                        wallpaperSafetyTriggered: bgRoot.wallpaperSafetyTriggered
                        // Live surface for in-shell "blur" frost. During lock
                        // and the lock<->WE peel, frost against the peel itself
                        // so it tracks the exact lock background (avoids the WE
                        // flashing through the frost before the unlock peel
                        // catches up). Otherwise the live WE, or null (=> static
                        // image path) when no WE is active.
                        weSurfaceItem: (bgRoot.lockWallShown || lockPeelTimer.running)
                            ? lockPeel
                            : (bgRoot.weShown ? weLoader.item : null)
                        // The frost samples the wallpaper item, so it needs
                        // both containers' real positions rather than this
                        // widget's canvas coordinates. Every wallpaper layer -
                        // the WE surface, the peel, the still - is declared
                        // inside parallaxViewport and is therefore viewport-
                        // sized and viewport-positioned; the canvas is a
                        // sibling that travels further. Read off the items and
                        // not off parallaxOffsets/widgetParallax so the two
                        // 600ms pans are followed frame by frame.
                        //
                        // A video wallpaper is the exception, and it is one of
                        // ownership rather than of maths: mpvpaper paints it on
                        // its own layer surface, which this viewport does not
                        // move, so on screen it neither pans nor zooms. While
                        // it owns the screen the wallpaper IS the screen, and
                        // handing the frost the viewport would give it a pan
                        // the wallpaper never had. videoRevealed is exactly
                        // "mpvpaper is showing" - the shell's own layers are
                        // hidden then, and during a switch cross-fade or on the
                        // lock screen it is false and the viewport is right
                        // again, so the branch follows whoever is painting.
                        canvasOffsetX: widgetCanvas.x
                        canvasOffsetY: widgetCanvas.y
                        wallpaperRect: bgRoot.videoRevealed
                            ? Qt.rect(0, 0, bgRoot.width, bgRoot.height)
                            : Qt.rect(parallaxViewport.x, parallaxViewport.y,
                                parallaxViewport.width, parallaxViewport.height)
                        wallpaperDecodeSize: bgRoot.wallpaperDecodeSize
                    }
                }
            }
        }

        // Clock depth: the wallpaper's subject, painted back over the desktop
        // widgets, so the clock sits behind the person in the photo.
        //
        // A FOURTH sibling, not a child of the viewport. A child's z only
        // reorders it against its viewport siblings and can never lift it above
        // widgetCanvas (weTransition at z 1 is exactly that case), so a cutout
        // declared inside the viewport would be drawn UNDER the clock - which
        // is the effect the shell already has. Being a sibling means it
        // inherits nothing, and each of the three things it reconstructs below
        // is a bug this file has already been through once.
        Item {
            id: clockDepthLayer
            // The viewport's LIVE geometry, not bgRoot.parallaxOffsets. Those
            // are the 600ms Behavior's destination: bound to them, the subject
            // would jump to the new position while the wallpaper under it took
            // 600ms to arrive - detached from its own image for the whole of
            // every workspace switch. Same mistake as #157, and the frost's
            // wallpaperRect one screen up reads these four for the same reason.
            x: parallaxViewport.x
            y: parallaxViewport.y
            width: parallaxViewport.width
            height: parallaxViewport.height
            // Above widgetCanvas (z 2), which is the whole point.
            z: 3
            // A fourth thing that reconstructs the viewport, so a fourth copy
            // of the edit transform: this layer paints the wallpaper's own
            // pixels back over the widgets, and a subject drawn at full size
            // over a shrunk desktop is a picture of a different wallpaper.
            transform: Matrix4x4 { matrix: bgRoot.editMatrix }
            // Its own copy of the fullscreen gate. The viewport carries one for
            // its children and widgetCanvas carries a second because it moved
            // out; a fourth sibling needs a fourth, or the subject floats over
            // fullscreen video with the wallpaper gone.
            visible: !bgRoot.suppressContents && clockDepthLayer.opacity > 0
            // Takes no input, ever. desktopRightClickArea sits at z -2, below
            // everything, and works only because every layer above it lets
            // clicks fall through; a MouseArea or a HoverHandler anywhere in
            // here would silently kill the desktop menu, every widget drag and
            // the drop shelf. This root is a plain Item, so the gate cascades.
            enabled: false
            opacity: ClockDepthLogic.eligible({
                enable: ClockDepth.enabled,
                maskPath: ClockDepth.maskPath,
                optedOut: ClockDepth.optedOut,
                // The selection surface draws the candidate over these same
                // widgets while it is up; two cutouts arguing is not a thing
                // anyone can give a verdict on.
                selecting: GlobalStates.clockDepthSelectOpen,
                editing: GlobalStates.editMode,
                weActive: bgRoot.weActive,
                // Whether the mask on offer was cut from the project's still
                // rather than the static wallpaper. Compared against
                // weActive INSIDE the predicate: this instance can fall back
                // to the static image on its own (weFailed, the safety
                // screen) while the service is still asking about the
                // project, and that mismatch is the wrong silhouette either
                // way round.
                maskIsWe: ClockDepth.askingWe,
                wallpaperIsVideo: bgRoot.wallpaperIsVideo,
                centeredWallpaper: bgRoot.centeredWallpaperEnabled,
                screenLocked: GlobalStates.screenLocked,
                transitionInFlight: bgRoot.transitionProgress < 1
            }) ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }

            // What the selection surface has to be handed to draw the same
            // cutout on the same pixels. It is a separate layer surface in a
            // separate window, so it can read neither this item nor the
            // wallpaper item - and reconstructing the pan from parallax.js on
            // the other side would be a second derivation of the one number
            // this whole component exists to have only one of.
            //
            // Null while the mode is disarmed, so the binding is a comparison
            // rather than a fresh object on every frame of every pan for the
            // rest of the session.
            readonly property var publishedViewport: GlobalStates.clockDepthSelectOpen
                ? ({
                    x: clockDepthLayer.x,
                    y: clockDepthLayer.y,
                    width: clockDepthLayer.width,
                    height: clockDepthLayer.height,
                    // A live project's picture is its still (spec §8): the
                    // selector is another window and cannot sample this
                    // scene's surface, so it draws the candidate cut from the
                    // still over the live scene - frozen inside the
                    // silhouette, live everywhere else - which is exactly the
                    // honesty question §8.4 asks the user to judge.
                    source: bgRoot.weActive && ClockDepth.askingWe
                        ? `file://${ClockDepth.weStillPath}` : String(wallpaper.source)
                })
                : null
            onPublishedViewportChanged: bgRoot.publishDepthViewport(clockDepthLayer.publishedViewport)

            // The registration lives in the component, not here, because the
            // wallpaper selector's picker draws the same cutout to ask whether
            // it is any good - and a picker that computed its own crop could
            // certify a mask against a geometry the desktop never uses.
            ClockDepthCutout {
                id: clockDepthCutout
                anchors.fill: parent
                // The wallpaper ITEM, not bgRoot.wallpaperPath: a switch
                // assigns that source imperatively so it can snapshot the
                // outgoing frame, and reading the path would put the incoming
                // image under the outgoing image's mask for the length of it.
                wallpaperSource: wallpaper.source
                // The same decode bound the wallpaper item carries - it is
                // part of the request, and the one-decode sharing this file
                // documents on the cutout's own Image holds only while every
                // parameter matches.
                decodeSize: bgRoot.wallpaperDecodeSize
                // The live surface, never its still (spec §8.3): a masked
                // still would freeze every animated pixel inside the
                // silhouette. weLiveSource is the texture the WE transition
                // already samples, so this adds no second render pass.
                liveSource: bgRoot.weActive ? weLiveSource : null
                maskPath: ClockDepth.maskPath
                maskRevision: ClockDepth.maskRevision
            }
        }

        // Edit Mode's Lockscreen tab: the real lock islands, rendered by the
        // preview context that cannot authenticate (spec §4.3, and the whole
        // of tests/test_lock_preview_contract.py). A FIFTH sibling carrying
        // the one edit transform, at z 4 - above the widget canvas (z 2)
        // because the real session lock surface draws over the desktop
        // widgets, and above the clock depth layer (z 3), which stands down
        // for the mode anyway.
        //
        // The surface is the real LockSurface, `interactive: false`: its root
        // area stands down through its own enabled, every handler in it
        // returns first thing, and the context handed in here is the plain
        // object whose unlock paths are empty by contract - never the real
        // LockContext, which runs a fingerprint enumeration and declares two
        // pam contexts the moment it is built. Declared inside the Loader so
        // the preview context exists only while the tab is showing.
        //
        // Its own copy of the fullscreen gate, like every sibling that left
        // the viewport: without it the islands would float over fullscreen
        // video with the wallpaper gone.
        Loader {
            id: lockPreviewIslands
            active: GlobalStates.editLockPreview && !bgRoot.suppressContents
            width: bgRoot.width
            height: bgRoot.height
            z: 4
            transform: Matrix4x4 { matrix: bgRoot.editMatrix }
            sourceComponent: LockSurface {
                interactive: false
                context: LockPreviewContext {}
            }
        }

        // Edit Mode's chrome: the wallpaper blurred around the shrunk desktop,
        // the desktop's corner, its outline and its shadow. That blur plus the
        // shrink IS the mode signal - there is no scrim - so it is not optional
        // and is not gated on the lock's own blur preference; only its radius is
        // borrowed from there, since it is the same picture and a second setting
        // for it would be a second thing to disagree.
        //
        // A SIBLING of the viewport rather than a second gate on the lock's
        // blurLoader, which is what the spec asked for and which cannot work:
        // that loader is a CHILD of parallaxViewport, so it takes the edit
        // transform with everything else in there and shrinks along with the
        // desktop it is supposed to sit behind. Sourcing the wallpaper item is
        // unaffected - a ShaderEffectSource renders its source item in that
        // item's own coordinates, not the scene's.
        //
        // ABOVE the wallpaper rather than behind it, which is what rounds the
        // corner: see EditModeCard for why covering the corner with the picture
        // behind it is the only cheap way to round a transformed sibling. And
        // BELOW the widget canvas at z 2, which is the whole of what stops it
        // rounding the widgets too.
        //
        // It sat at z 4, over everything, and a cover over everything cuts
        // everything: the desktop scales about its own centre, so the canvas's
        // edge lands exactly on the card's edge and a widget parked against a
        // screen edge has its own edge flush with it. At a CORNER the rounding
        // comes in on both axes at once and takes a bite out of whatever is
        // there - measured at 5120x1440, a widget at the desktop's corner lost
        // 20px along each edge and 10px on the diagonal. `visualizer` sits at
        // 0,1200 in this machine's own store, so the desktop editor was cutting
        // a corner off a widget while the user was arranging it.
        //
        // What that costs, and it is the deliberate trade: a widget in the
        // corner now OVERHANGS the rounding, drawn whole over the blurred
        // backdrop. It says "this widget is at the edge of your desktop", which
        // is true and is information; the alternative was hiding part of a
        // widget in the mode that exists to place it.
        //
        // Non-interactive either way, because desktopRightClickArea at z -2
        // works only while everything over it lets clicks through.
        Loader {
            id: editChrome
            active: bgRoot.editProgress > 0 && !bgRoot.suppressContents
            anchors.fill: parent
            z: 1
            enabled: false
            opacity: bgRoot.editProgress
            sourceComponent: EditModeCard {
                wallpaperLayer: bgRoot.liveWallpaperLayer
                blurRadius: Config.options.lock.blur.radius
                blurSamples: Config.options.lock.blur.size
                card: bgRoot.editCard
                cardRadius: bgRoot.editCardRadius
            }
        }

        MouseArea {
            id: desktopRightClickArea
            // Kept off while the contents are suppressed, which the removed
            // wrapper used to do for it: a right-click desktop menu opening
            // behind a fullscreen window is not a desktop the user can see.
            visible: !bgRoot.suppressContents
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
