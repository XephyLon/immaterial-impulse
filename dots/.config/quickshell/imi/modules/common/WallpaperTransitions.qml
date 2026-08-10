pragma Singleton

import qs.services
import Quickshell
import QtQml

/**
 * The wallpaper switch transitions this shell actually ships.
 *
 * There used to be three copies of this list - Background.qml's random pool,
 * the settings combo box, and the desktop menu's submenu - and they had already
 * drifted: the submenu offered four of the eight shaders, so Peel could be the
 * active transition while being absent from the menu that is supposed to change
 * it (#142). One list, three readers.
 */
Singleton {
    id: root

    // `value` is the shader's basename under modules/imi/background/shaders, so
    // an entry here resolves directly to `<value>.frag.qsb`.
    readonly property var shaders: [
        { value: "circleSelect", displayName: Translation.tr("Circle"), icon: "circle" },
        { value: "circlePit", displayName: Translation.tr("Circle Pit"), icon: "blur_circular" },
        { value: "magic", displayName: Translation.tr("Magic"), icon: "auto_awesome" },
        { value: "Doom", displayName: Translation.tr("Doom"), icon: "whatshot" },
        { value: "Peel", displayName: Translation.tr("Peel"), icon: "layers" },
        { value: "transition", displayName: Translation.tr("Fade"), icon: "gradient" },
        { value: "pixelate", displayName: Translation.tr("Pixelate"), icon: "grain" },
        { value: "stripes", displayName: Translation.tr("Stripes"), icon: "texture_minus" }
    ]

    // The pool "random" draws from. Shaders only - picking "" or "random" out of
    // it would mean "no transition" or an infinite regress.
    readonly property var shaderValues: root.shaders.map(entry => entry.value)

    readonly property var none: ({ value: "", displayName: Translation.tr("None"), icon: "block" })
    readonly property var random: ({ value: "random", displayName: Translation.tr("Random"), icon: "shuffle" })

    // Everything a picker should offer, in the order it should offer it.
    readonly property var options: [root.none].concat(root.shaders).concat([root.random])
}
