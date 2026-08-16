.pragma library

// Which file draws a bar widget, for both bars.
//
// The horizontal bar and the vertical bar each carried their own copy of this
// mapping, and only the horizontal one ever grew the `plugin:` branch that
// 2a3801a62 ("feat(plugins): support installable QML packages") added. The two
// bars share `Config.options.bar.layouts.*` and Settings > Bar offers plugin
// widgets whatever the orientation, so a layout holding `plugin:docker_plugin`
// hit the vertical bar's fallback, which capitalises a widget name into a file
// name: it resolved `Plugin:docker_plugin.qml`, the Loader went to
// Loader.Error, and the bar drew the empty BarGroup stub around it. The only
// evidence was one `No such file or directory` line per widget - not a
// `WARN scene:` and not an `ERROR:`, so the config still loaded.
//
// The mapping lives here, once, because two names for one thing let whichever
// one is not on screen rot silently.

const PLUGIN_PREFIX = "plugin:";

// Bundled plugins whose bar entry point is a native component in
// modules/imi/bar/ rather than the generic package host. Docker is off the
// generic path deliberately: PluginBarWidget's own Loader inside Docker's
// implicit-size chain caused multi-gigabyte relayout loops
// (7fb128afe ("fix(plugins): prevent Docker host memory runaway")).
const NATIVE_BAR_COMPONENTS = {
    "docker_plugin": "DockerPlugin.qml",
    "discord_voice": "DiscordVoicePlugin.qml"
};

const PACKAGE_BAR_COMPONENT = "PluginBarWidget.qml";

function pluginIdOf(name) {
    if (!name || !name.startsWith(PLUGIN_PREFIX))
        return "";
    return name.substring(PLUGIN_PREFIX.length);
}

// An installed plugin picks its own id, so the lookup goes through
// hasOwnProperty: a plugin calling itself `constructor` would otherwise resolve
// to something off Object's prototype and be loaded as a file name.
function nativeComponentFor(pluginId) {
    return Object.prototype.hasOwnProperty.call(NATIVE_BAR_COMPONENTS, pluginId)
        ? NATIVE_BAR_COMPONENTS[pluginId]
        : "";
}

// The file name alone. `Qt.resolvedUrl` needs an engine context a shared
// library has no business assuming, and the two bars reach modules/imi/bar/ by
// different relative paths, so the directory belongs to the caller and the
// mapping stays reachable from a test without one.
function fileNameFor(name) {
    if (!name)
        return "";
    const pluginId = pluginIdOf(name);
    if (pluginId)
        return nativeComponentFor(pluginId) || PACKAGE_BAR_COMPONENT;
    return name.charAt(0).toUpperCase() + name.slice(1) + ".qml";
}

// A plugin's bar widget tracks its enabled state: disabling (or uninstalling) a
// plugin drops its id from plugins.enabled, so its bar entry disappears with
// it. The layout token still holds the id, so re-enabling restores the widget
// in place.
//
// `plugins.enabled` is a `list<string>`, which reaches JS as a sequence
// wrapper rather than an Array - Config.qml's own migration walks it by index
// for the same reason - so this reads its length rather than calling a method
// only a real Array is obliged to have.
function isDisabledPlugin(name, enabledPluginIds) {
    const pluginId = pluginIdOf(name);
    if (!pluginId)
        return false;
    for (let i = 0; i < enabledPluginIds.length; i++) {
        if (enabledPluginIds[i] === pluginId)
            return false;
    }
    return true;
}
