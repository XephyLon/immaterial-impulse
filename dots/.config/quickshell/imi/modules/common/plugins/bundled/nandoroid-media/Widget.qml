import QtQuick
import qs.modules.common
import qs.modules.common.functions as Functions
import qs.modules.common.plugins
import qs.services
import "../../designsystem/widgets" as Expressive
import "media_layouts.js" as MediaLayouts
import "media_geometry.js" as Geometry

// The media widget as ONE tree.
//
// This file used to be a shell around one layout file per span: a Loader
// whose source followed the span, so changing size destroyed LayoutLarge and
// constructed LayoutCookie - the play button at 3x2 and the play button at
// 2x2 were different objects that had never coexisted, and the best a resize
// could do was cross-fade them (spec 2026-08-11, §1).
//
// Now the SHARED elements - one card, three transport buttons, the progress
// slider - are declared once and never destroyed. media_geometry.js decides
// where each one sits per span; this file binds those rects. Step 4 lands
// this statically: positions snap on a span change, and the Behaviors that
// make them travel are step 5, deliberately separate so the structural change
// is reviewable on its own.
//
// Unshared content - the 3x2's text/lyrics page, the 2x2's visualizer cookie
// - has nothing to morph into, so it enters and exits behind span-gated
// Loaders. That is the design's own rule (§6): in a reflowing tree, unloaded
// beats invisible-but-alive, because a VisualizerCookie at 2x1 would hold a
// cava claim for a size that shows no visualiser.
Item {
    id: root

    // The span the host resolved, handed down by PluginNode: the stored choice,
    // then the manifest default. Empty until the host answers, and for a bare
    // `qs -p` probe of this file.
    property string hostGridSize: ""
    property point hostResizeBow: Qt.point(0, 0)

    // The host's span-change cross-fade exists to hide a destroy. This tree
    // has no destroy: the shared elements re-derive their rects from the
    // animating box on every frame, so they travel while the box does, and a
    // dissolve on top of that would be exactly the vanish-and-reappear this
    // architecture replaces.
    readonly property bool handlesSpanTransition: true

    readonly property var span: MediaLayouts.spanFor(root.hostGridSize)
    readonly property string spanName: root.span.cols + "x" + root.span.rows

    // Not derived from content: the manifest declares a grid, so the host
    // sizes this item to the span and fills it.
    implicitWidth: Appearance.sizes.widgetGridSpanX(root.span.cols)
    implicitHeight: Appearance.sizes.widgetGridSpanY(root.span.rows)

    readonly property bool useBlurBackground: PluginState.option("nandoroid_media", "blurEnabled", false)
    readonly property real backgroundOpacity: PluginState.effectiveBackgroundOpacity("nandoroid_media")
    readonly property bool managesBlurTint: true
    readonly property var blurRegions: [bgCard.blurRegion]

    readonly property real playbackProgress:
        (MprisController.length > 0 ? (MprisController.position / MprisController.length) : 0) || 0
    readonly property string artUrl: MprisController.activePlayer?.trackArtUrl ?? ""

    // The geometry, evaluated at the span's SETTLED box, not the animating
    // one. Measured before this was fixed: rects derived from the live width
    // made position drift but size and y snap at t0 - the new-span branch
    // evaluated at the old-span box - and the change read as a teleport.
    // Worse, live-box rects are targets that move every frame, which is the
    // shape that freezes a Behavior outright (AGent.md, the parallax opt-out).
    // Settled-span rects change exactly once per commit, so the Behaviors
    // below get a discrete jump to carry - old rect to new rect, on the same
    // clock family as the box.
    readonly property real spanW: Appearance.sizes.widgetGridSpanX(root.span.cols)
    readonly property real spanH: Appearance.sizes.widgetGridSpanY(root.span.rows)
    readonly property var transport: Geometry.transportRects(
        root.spanName, root.spanW, root.spanH, Appearance.effectiveScale)
    readonly property var progressSlot: Geometry.progressRect(
        root.spanName, root.spanW, root.spanH, Appearance.effectiveScale)
    readonly property var timeSlot: Geometry.timeLabelRect(
        root.spanName, root.spanW, root.spanH, Appearance.effectiveScale)

    // The 3x2's lyrics page replaces its controls; while it is up the shared
    // elements yield the stage. Text pages exist at one span only, so reading
    // it off the extras loader is not a shared-element reaching into a fade.
    readonly property bool lyricsUp: root.spanName === "3x2"
        && largeExtras.item !== null && largeExtras.item.viewLyrics === true

    // ---- the card (shared, never destroyed) ------------------------------
    Expressive.WidgetCard {
        id: bgCard
        anchors.fill: parent
        useBlurBackground: root.useBlurBackground
        backgroundOpacity: root.backgroundOpacity
        tensionX: root.hostResizeBow.x
        tensionY: root.hostResizeBow.y
    }

    // ---- unshared content, entering and exiting per span -----------------

    // 3x2: title, artist, lyrics page and its toggles. DesktopMediaWidget
    // stays whole for the component registry; hosted here it runs chromeless
    // - no card, no transport, no slider, no time - because this tree owns
    // those.
    Loader {
        id: largeExtras
        active: root.spanName === "3x2"
        anchors.fill: parent
        sourceComponent: Expressive.DesktopMediaWidget {
            chromeless: true
            showLyrics: PluginState.option("nandoroid_media", "showLyrics", false)
            useRomaji: PluginState.option("nandoroid_media", "useRomaji", false)
        }
    }

    // 2x2: the visualizer cookie the artwork sits in. The cookie is the
    // progress slot's occupant-in-waiting (step 7 strokes the inner ring on
    // this frame); today it is the celebratory container it was in
    // LayoutCookie, unchanged.
    Loader {
        id: cookieExtras
        active: root.spanName === "2x2"
        x: root.progressSlot ? root.progressSlot.x : 0
        y: root.progressSlot ? root.progressSlot.y : 0
        width: root.progressSlot ? root.progressSlot.width : 0
        height: root.progressSlot ? root.progressSlot.height : 0

        Behavior on x { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
        Behavior on y { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
        Behavior on width { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
        Behavior on height { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
        sourceComponent: Expressive.VisualizerCookie {
            lobes: 12
            // Claimed only while something is playing: the claim starts cava,
            // and a paused desktop has no spectrum to draw.
            audioReactive: MprisController.isPlaying
            color: Appearance.colors.colPrimary
        }
    }

    // ---- the shared elements ---------------------------------------------

    MediaTransportButton {
        id: prevButton
        objectName: "prevButton"
        role: "prev"
        span: root.spanName
        visible: !root.lyricsUp && root.transport !== null
        x: root.transport ? root.transport.prev.x : 0
        y: root.transport ? root.transport.prev.y : 0
        width: root.transport ? root.transport.prev.width : 0
        height: root.transport ? root.transport.prev.height : 0
        Behavior on x { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
        Behavior on y { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
        Behavior on width { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
        Behavior on height { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
    }

    MediaTransportButton {
        id: playButton
        objectName: "playButton"
        role: "play"
        span: root.spanName
        visible: !root.lyricsUp && root.transport !== null
        progress: root.playbackProgress
        artUrl: root.artUrl
        x: root.transport ? root.transport.play.x : 0
        y: root.transport ? root.transport.play.y : 0
        width: root.transport ? root.transport.play.width : 0
        height: root.transport ? root.transport.play.height : 0
        Behavior on x { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
        Behavior on y { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
        Behavior on width { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
        Behavior on height { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
    }

    MediaTransportButton {
        id: nextButton
        objectName: "nextButton"
        role: "next"
        span: root.spanName
        visible: !root.lyricsUp && root.transport !== null
        x: root.transport ? root.transport.next.x : 0
        y: root.transport ? root.transport.next.y : 0
        width: root.transport ? root.transport.next.width : 0
        height: root.transport ? root.transport.next.height : 0
        Behavior on x { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
        Behavior on y { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
        Behavior on width { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
        Behavior on height { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
    }

    // Progress's 3x2 renderer, in its geometry slot. At 2x1 the ring is drawn
    // by the play button itself - the same rect, two concentric draws of one
    // outline - and at 2x2 the slot is reserved for step 7's inner ring, so
    // this slider exists only where the wavy bar does.
    Expressive.StyledSlider {
        id: progressSlider
        visible: root.spanName === "3x2" && !root.lyricsUp && root.progressSlot !== null
        x: root.progressSlot ? root.progressSlot.x : 0
        y: root.progressSlot ? root.progressSlot.y : 0
        width: root.progressSlot ? root.progressSlot.width : 0
        height: root.progressSlot ? root.progressSlot.height : 0

        Behavior on x { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
        Behavior on y { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
        Behavior on width { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
        Behavior on height { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
        handleMargins: 0
        configuration: Expressive.StyledSlider.Configuration.Wavy
        stopIndicatorValues: []
        animateValue: false
        value: root.playbackProgress
        wavy: MprisController.isPlaying
        highlightColor: Appearance.colors.colPrimary
        trackColor: Functions.ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.25)
        handle: Rectangle {
            x: progressSlider.leftPadding + (progressSlider.visualPosition * (progressSlider.availableWidth - width))
            y: (progressSlider.height - height) / 2
            width: 14 * Appearance.effectiveScale
            height: 14 * Appearance.effectiveScale
            radius: width / 2
            color: Appearance.colors.colPrimary
        }
        onMoved: {
            if (MprisController.activePlayer && MprisController.activePlayer.canSeek) {
                MprisController.activePlayer.position = value * MprisController.activePlayer.length;
            }
        }
    }

    // The time label, in the fixed slot the geometry gives it (the one
    // deliberate deviation from the flowed original - see media_geometry.js).
    Expressive.StyledText {
        visible: root.spanName === "3x2" && !root.lyricsUp && root.timeSlot !== null
        x: root.timeSlot ? root.timeSlot.x : 0
        y: root.timeSlot ? root.timeSlot.y : 0
        width: root.timeSlot ? root.timeSlot.width : 0
        height: root.timeSlot ? root.timeSlot.height : 0

        Behavior on x { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
        Behavior on y { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
        Behavior on width { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
        Behavior on height { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: Functions.StringUtils.friendlyTimeForSeconds(MprisController.position)
            + " / " + Functions.StringUtils.friendlyTimeForSeconds(MprisController.length)
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.family: Appearance.font.family.numbers
        font.features: { "tnum": 1 }
        font.weight: Font.DemiBold
        color: Appearance.colors.colPrimary
        renderType: Text.QtRendering
    }
}
