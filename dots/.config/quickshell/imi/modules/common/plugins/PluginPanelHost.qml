import QtQuick
import Quickshell
import qs.services
import qs.modules.common

/**
 * Instantiates every enabled plugin's `panel` entry point. Panels are
 * free-floating package-plugin surfaces (they own their PanelWindow/popup);
 * the host only loads them. Also anchors the ScreenshotEvents singleton so
 * its IPC handler exists even when no panel plugin is enabled.
 */
Scope {
    id: root

    readonly property var panelPlugins: PluginManager.availablePlugins.filter(manifest =>
        manifest.panel !== undefined
        && Config.options.plugins.enabled.includes(manifest.id))

    // Variants over a Scope is the repo's pattern for non-visual per-plugin
    // instantiation (see PluginManager's installed-manifest FileViews);
    // a Repeater would need a visual parent, which a Scope does not provide.
    Variants {
        model: root.panelPlugins

        Scope {
            id: pluginScope

            required property var modelData

            readonly property var entryPoint: modelData.panel
            readonly property string basePath: entryPoint?._basePath ?? modelData._basePath ?? ""
            // Same resolution as PluginBarWidget: absolute component paths pass
            // through, relative ones are joined onto the manifest's base path.
            readonly property string componentPath: entryPoint?.component && basePath
                ? (String(entryPoint.component).startsWith("/")
                    ? String(entryPoint.component)
                    : basePath + "/" + String(entryPoint.component).replace(/^\.\//, ""))
                : ""

            Loader {
                source: pluginScope.componentPath

                onStatusChanged: {
                    if (status === Loader.Error)
                        console.warn(`[PluginPanelHost] Failed to load panel for ${pluginScope.modelData.id} from ${pluginScope.componentPath}`);
                }
            }
        }
    }
}
