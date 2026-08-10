pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * Publishes the alpha threshold Hyprland should use when blurring the shell's
 * popups, as a Lua file rules.lua reads.
 *
 * Popups cannot scope their blur the way panels do. A panel turns the
 * whole-surface blur off and publishes an ext-background-effect region over its
 * painted body, so the compositor never touches the shadow in its elevation
 * margin. That mechanism is for layer surfaces, and a PopupWindow is an
 * xdg-popup: a region published from one is accepted and does nothing. The only
 * knob aimed at popups is `blur_popups` on the parent surface's namespace, and
 * turning it off costs the body its blur along with the shadow.
 *
 * What is left is `ignore_alpha`, which skips blur for pixels below a
 * threshold. The shadow and the body sit at different alphas, so a value
 * between them blurs one and not the other - but where "between" is depends on
 * the user's transparency setting, and a layerrule is static Lua that cannot
 * read it. Hence this: the shell computes the threshold and writes it out, and
 * rules.lua reads the file with a fallback for the first run.
 */
Singleton {
    id: root

    // colShadow is m3shadow transparentized 0.7, and StyledRectangularShadow
    // fades outward from there, so this is the shadow's ceiling rather than its
    // typical value.
    readonly property real shadowPeakAlpha: 0.3

    // The faintest body the threshold has to stay below.
    //
    // Not just the popups'. `ignore_alpha` is a single value per namespace,
    // shared between a popup's blur and its parent panel's, because the panel
    // is blurred through a region and a region is subject to ignore_alpha too.
    // So this has to clear the *panels* as well, and the bar is the faintest of
    // them: it thins colLayer0 further by its own background opacity. Set this
    // above the bar's body and the bar loses its blur.
    readonly property real bodyAlpha: (1 - Appearance.backgroundTransparency)
        * Math.min(1, Config.options.bar.backgroundOpacity ?? 1)

    /**
     * Midway between the two, which is the most forgiving spot: it tolerates
     * the most drift in either direction before one of them lands on the wrong
     * side.
     *
     * The `bodyAlpha - 0.05` clamp is for the case where the user has turned
     * transparency up so far that the body is fainter than the shadow's ceiling
     * and no threshold separates them. Then the choice is which one to get
     * wrong, and this keeps the body blurred: losing the blur is the change
     * people notice, and a frosted shadow on a nearly-invisible body is not.
     */
    readonly property real threshold: Math.max(
        0.02,
        Math.min(root.bodyAlpha - 0.05,
                 (root.shadowPeakAlpha + root.bodyAlpha) / 2))

    readonly property string path: FileUtils.trimFileProtocol(
        `${Directories.config}/hypr/hyprland/shellOverrides/popupBlur.lua`)

    // Rounded before it is written and before it is compared, so a float that
    // wobbles in the last decimal place cannot cause a write, and every write
    // costs a Hyprland config reload.
    readonly property string rendered: `-- Written by the shell (services/PopupBlurThreshold.qml). Do not edit.
-- The alpha below which Hyprland leaves the shell's popups unblurred, so a
-- popup's drop shadow stays crisp while its body still gets a backdrop.
return ${root.threshold.toFixed(3)}
`

    property string lastWritten: ""

    /**
     * Nothing reads this singleton's properties, and a QML singleton is built
     * on first use, so without a call from shell.qml it would never start and
     * the file would never be written. Doubles as the seed of the file.
     */
    function load(): void {
        reader.reload();
    }

    function publish(): void {
        if (root.rendered === root.lastWritten)
            return;
        root.lastWritten = root.rendered;
        writer.setText(root.rendered);
    }

    FileView {
        id: writer
        path: root.path
        printErrors: true
        onSaved: Quickshell.execDetached(["hyprctl", "reload"])
    }

    onRenderedChanged: republishDebounce.restart()

    // Dragging the transparency slider walks through every value on the way,
    // and each one would otherwise be a file write plus a compositor reload.
    Timer {
        id: republishDebounce
        interval: 400
        onTriggered: root.publish()
    }

    FileView {
        id: reader
        path: root.path
        printErrors: false
        onLoaded: {
            root.lastWritten = reader.text();
            root.publish();
        }
        onLoadFailed: root.publish()
    }
}
