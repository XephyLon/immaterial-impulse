pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell

/**
 * Picking the wallpaper's subject on the desktop, at full size, over the real
 * widgets.
 *
 * The gesture used to live on a ~300px thumbnail inside the wallpaper
 * selector's depth picker, and the reason that was wrong is structural rather
 * than aesthetic: the mask is JUDGED at screen size against the widgets it has
 * to occlude, and it was AUTHORED against a postage stamp. A click landing on a
 * character's shoulder in the preview is several hundred pixels off at
 * 5120x1440, and nothing about the result says so - a mis-aimed click comes
 * back as a perfectly good mask of the wrong thing.
 *
 * So the surface is the desktop. Nothing here redraws the wallpaper: it is
 * already on screen at exactly the size and crop the click has to be measured
 * against, and the selection surface is transparent over it, so the pixels the
 * user clicks are by construction the pixels the depth layer will mask. The
 * widgets stay live underneath for the same reason - they are what the cutout
 * has to occlude, and a composited copy of them would be a second thing that
 * can drift from the first.
 *
 * The picker keeps the two salient detectors, this wallpaper's verdict, and the
 * way in. It is where you SEE the state; this is where you author it.
 */
Scope {
    id: root

    // The wallpaper this session is cutting, captured when the mode arms. The
    // clicks are stored against that picture's cache key, so if the picture
    // changes underneath the surface every one of them belongs to a different
    // file and the cutout on screen is registered against something that is no
    // longer there.
    property string armedWallpaper: ""

    function cancel(): void {
        GlobalStates.clockDepthSelectOpen = false
    }

    function accept(): void {
        if (ClockDepth.promptedModel === "")
            return
        ClockDepth.acceptModel(ClockDepth.promptedModel)
        // Accepting a cutout while the feature is switched off would put the
        // artifact on disk and change nothing on screen, which reads as the
        // button not working. The acceptance IS the intent - same reasoning as
        // the picker's own accept, which the two detector columns still use.
        Config.options.background.clockDepth.enable = true
        root.cancel()
    }

    function decline(): void {
        ClockDepth.declineWallpaper()
        root.cancel()
    }

    Connections {
        target: GlobalStates
        function onClockDepthSelectOpenChanged() {
            root.armedWallpaper = GlobalStates.clockDepthSelectOpen
                ? ClockDepth.wallpaperPath : ""
        }
    }

    Connections {
        target: ClockDepth
        // Two ways the ground moves under an armed selection, and both leave
        // the surface drawing a cutout of a picture the desktop is not showing:
        // the wallpaper is switched, or the desktop stops being a still image
        // at all (a Wallpaper Engine project starts, the screen locks, centred
        // mode goes on). Disarming is the whole response - the candidate stays
        // on disk under its own key, so re-entering on that wallpaper picks the
        // gesture back up rather than starting over.
        function onWallpaperPathChanged() {
            if (GlobalStates.clockDepthSelectOpen
                && ClockDepth.wallpaperPath !== root.armedWallpaper)
                root.cancel()
        }
        function onSelectableChanged() {
            if (GlobalStates.clockDepthSelectOpen && !ClockDepth.selectable)
                root.cancel()
        }
    }

    Variants {
        model: Quickshell.screens
        delegate: Loader {
            id: surfaceLoader
            required property var modelData
            active: GlobalStates.clockDepthSelectOpen

            sourceComponent: ClockDepthSelectSurface {
                screen: surfaceLoader.modelData
                onCancelled: root.cancel()
                onAccepted: root.accept()
                onDeclined: root.decline()
            }
        }
    }
}
