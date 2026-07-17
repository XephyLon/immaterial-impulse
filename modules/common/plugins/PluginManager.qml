pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var availablePlugins: []
    property var manifestsMap: ({})

    Component.onCompleted: {
        loadBundledPlugins();
    }

    function loadBundledPlugins() {
        let plugins = ["clock", "battery"];
        let loaded = [];
        let map = {};
        for (let i = 0; i < plugins.length; i++) {
            let path = Quickshell.shellPath("modules/common/plugins/bundled/" + plugins[i] + "/manifest.json");
            let req = new XMLHttpRequest();
            req.open("GET", "file://" + path, false);
            req.send(null);
            if (req.status === 200 || req.status === 0) {
                try {
                    let manifest = JSON.parse(req.responseText);
                    loaded.push(manifest);
                    map[manifest.id] = manifest;
                } catch (e) {
                    console.log("[PluginManager] Error parsing plugin " + plugins[i] + ": " + e);
                }
            } else {
                console.log("[PluginManager] Error reading " + path);
            }
        }
        root.availablePlugins = loaded;
        root.manifestsMap = map;
    }
}
