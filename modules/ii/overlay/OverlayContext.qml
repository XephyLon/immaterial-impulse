pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.common
import "../../common/plugins/bundled/discordVoice" as DiscordPackage

Singleton {
    id: root
    
    signal requestCenter(string identifier)

    readonly property list<var> builtInWidgets: [
        { identifier: "crosshair", materialSymbol: "point_scan" },
        { identifier: "fpsLimiter", materialSymbol: "animation" },
        { identifier: "floatingImage", materialSymbol: "imagesmode" },
        { identifier: "recorder", materialSymbol: "screen_record" },
        { identifier: "resources", materialSymbol: "browse_activity" },
        { identifier: "notes", materialSymbol: "note_stack" },
        { identifier: "volumeMixer", materialSymbol: "volume_up" },
    ]
    // Optional per-entry override for widgets whose identity a Material Symbol
    // cannot carry. The overlay taskbar renders `iconComponent` instead of
    // `materialSymbol` when one is present and binds `toggled` on the result,
    // so branded widgets need no special case in the shared taskbar.
    readonly property Component discordVoiceIcon: Component { DiscordPackage.TaskbarGlyph {} }

    readonly property list<var> availableWidgets: root.builtInWidgets.concat(
        Config.options.plugins.enabled.includes("discord_voice")
            ? [{
                identifier: "discordVoice",
                materialSymbol: "voice_chat",
                iconComponent: root.discordVoiceIcon
            }]
            : [])
    
    // Read from persisted state rather than from a registry the widgets fill
    // in. Overlay.qml gates its Loader on this, and the widgets that would
    // register live inside that Loader - so a registry-backed answer is empty
    // on startup and a pinned widget stays invisible until the overlay is
    // opened once, which is exactly what it is meant to avoid.
    readonly property bool hasPinnedWidgets: Persistent.states.overlay.open.some(identifier =>
        Persistent.states.overlay[identifier]?.pinned === true
            && root.availableWidgets.some(widget => widget.identifier === identifier))

    property list<var> clickableWidgets: []

    function registerClickableWidget(widget: var, clickable = true) {
        if (clickable) {
            if (!root.clickableWidgets.includes(widget)) {
                root.clickableWidgets.push(widget)
            }
        } else {
            root.clickableWidgets = root.clickableWidgets.filter(w => w !== widget)
        }
    }
}
