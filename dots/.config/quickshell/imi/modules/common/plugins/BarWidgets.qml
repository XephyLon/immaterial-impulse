pragma Singleton

import QtQuick
import Quickshell
import qs.services

/**
 * The catalogue of everything that can sit on the bar, promoted out of
 * BarConfig.qml so the bar itself can read it (Edit Mode spec §4.2): the
 * settings page's add-widget dropdown and Edit Mode's drawer must offer the
 * same list, and a second copy is how the two drift apart.
 *
 * `available` is `{id, name, icon}` per widget - the built-ins, then every
 * installed plugin declaring a bar widget. Nothing may ADDRESS a widget by
 * `name`: a layout stores ids, and `nameFor(id)` is the one resolution back
 * to a display name (the settings-page-id lesson - a translated name changes
 * with the language, an id does not).
 *
 * The built-in names stay spelled as `Translation.tr("...")` literals on
 * purpose: translations/tools/translation-manager.py extracts keys by
 * scanning for exactly that call form, and its `clean` command deletes keys
 * nothing matches - a key held in a plain string and translated later would
 * be stripped from every language file on the next clean. The binding is
 * still live, so a language change re-evaluates the whole catalogue. Plugin
 * names deliberately do not go through tr(): a manifest's `name` is the
 * author's own string, not a translation key.
 */
Singleton {
    id: root

    readonly property var staticWidgets: [
        { id: "leftSidebarButton", name: Translation.tr("Left Sidebar Button"),  icon: "left_panel_open" },
        { id: "workspaces",        name: Translation.tr("Workspaces"),           icon: "steppers" },
        { id: "weatherBar",        name: Translation.tr("Weather"),              icon: "flare" },
        { id: "media",             name: Translation.tr("Media"),                icon: "music_note" },
        { id: "resources",         name: Translation.tr("Resources"),            icon: "empty_dashboard" },
        { id: "systemIcons",       name: Translation.tr("System Icons"),         icon: "info" },
        { id: "networkSpeed",      name: Translation.tr("Network Speed"),        icon: "network_check" },
        { id: "timerPill",         name: Translation.tr("Timer"),                icon: "timer" },
        { id: "privacyIndicator",  name: Translation.tr("Privacy"),              icon: "privacy_tip" },
        { id: "submapIndicator",   name: Translation.tr("Submap"),               icon: "keyboard" },
        { id: "clockWidget",       name: Translation.tr("Clock"),                icon: "schedule" },
        { id: "utilButtons",       name: Translation.tr("Util Buttons"),         icon: "toggle_on" },
        { id: "sysTray",           name: Translation.tr("Tray"),                 icon: "inbox" },
        { id: "batteryIndicator",  name: Translation.tr("Battery"),              icon: "battery_android_frame_full" },
        { id: "activeWindow",      name: Translation.tr("Active Window"),        icon: "subtitles" },
        { id: "powerButton",       name: Translation.tr("Power Button"),         icon: "power_settings_new" },
        { id: "updatesCount",      name: Translation.tr("Updates"),              icon: "deployed_code_update" },
        { id: "docktoPanel",       name: Translation.tr("Dock to Panel"),        icon: "apps" },
        { id: "visualizer",        name: Translation.tr("Visualizer"),           icon: "graphic_eq" },
        { id: "hyprlandXkbIndicator",   name: Translation.tr("Keyboard Layout"), icon: "keyboard" },
        { id: "divisor",            name: Translation.tr("Divider"),             icon: "horizontal_distribute" },
    ]

    // A binding on `availablePlugins` (a property), never a call into an
    // invokable: this is what keeps the catalogue following installs and
    // uninstalls for the life of the shell - AGENT.md's LiveDesktopEntry
    // entry is the shape that does not.
    readonly property var pluginWidgets: PluginManager.availablePlugins
        .filter(plugin => plugin.barWidget !== undefined)
        .map(plugin => ({
            id: "plugin:" + plugin.id,
            name: plugin.name,
            icon: plugin.icon || "extension"
        }))

    readonly property var available: staticWidgets.concat(pluginWidgets)

    function nameFor(id) {
        const found = root.available.find(entry => entry.id === id)
        // A layout can hold an id the catalogue no longer offers - an
        // uninstalled plugin's bar widget. Its chip keeps a readable label
        // rather than going blank.
        return found ? found.name : id
    }
}
