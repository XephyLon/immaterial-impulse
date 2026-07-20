pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import "PluginValidator.js" as PluginValidator

Singleton {
    id: root

    property var availablePlugins: []
    property var manifestsMap: ({})
    property var installedManifests: ({})
    property list<string> installedManifestPaths: []
    readonly property string installedRoot: `${Directories.shellConfig}/plugins`
    property bool installing: false
    property string installMessage: ""

    function scheduleRebuild() {
        rebuildTimer.restart();
    }

    function parseManifest(text, basePath, origin) {
        const manifest = JSON.parse(text);
        const validation = PluginValidator.validateManifest(manifest);
        if (!validation.valid) throw new Error(validation.error);
        manifest._basePath = basePath;
        manifest._origin = origin;
        for (const entryPoint of ["barWidget", "desktopWidget", "controlCenterWidget",
                "launcherProvider", "panel", "settingsUi"]) {
            if (manifest[entryPoint]) manifest[entryPoint]._basePath = basePath;
        }
        return manifest;
    }

    function manifestDirectory(path) {
        const slash = path.lastIndexOf("/");
        return slash < 0 ? "" : path.substring(0, slash);
    }

    function registerInstalledManifest(path, text) {
        try {
            const manifest = root.parseManifest(text, root.manifestDirectory(path), "installed");
            const next = Object.assign({}, root.installedManifests);
            next[path] = manifest;
            root.installedManifests = next;
            root.scheduleRebuild();
        } catch (error) {
            console.warn(`[PluginManager] Rejecting installed manifest ${path}: ${error}`);
        }
    }

    function rebuildFromLoadedFiles() {
        let loaded = [];
        let map = {};
        [clockManifestFile, batteryManifestFile, dockerManifestFile, discordVoiceManifestFile,
                atAGlanceManifestFile,
                nandoroidClockManifestFile, nandoroidAtAGlanceManifestFile,
                nandoroidMediaManifestFile, nandoroidSystemMonitorManifestFile,
                nandoroidWeatherManifestFile, nandoroidCurrencyManifestFile].forEach(fileView => {
            if (!fileView.loaded) return;
            try {
                const text = fileView.text();
                if (!text) return;
                const manifest = root.parseManifest(text, fileView.pluginBase, "bundled");
                loaded.push(manifest);
                map[manifest.id] = manifest;
            } catch (e) {
                console.log("[PluginManager] Error parsing plugin manifest at " + fileView.path + ": " + e);
            }
        });
        for (const path in root.installedManifests) {
            const manifest = root.installedManifests[path];
            // Installed packages intentionally override bundled packages with
            // the same id, allowing development and user-managed updates.
            if (map[manifest.id]) loaded = loaded.filter(item => item.id !== manifest.id);
            loaded.push(manifest);
            map[manifest.id] = manifest;
        }
        root.availablePlugins = loaded.sort((a, b) => a.name.localeCompare(b.name));
        root.manifestsMap = map;
    }

    function scanInstalledPlugins() {
        installedManifests = {};
        installedManifestPaths = [];
        manifestScanner.command = ["find", installedRoot, "-mindepth", "2", "-maxdepth", "2",
            "-type", "f", "-name", "manifest.json", "-print"];
        manifestScanner.running = true;
    }

    function installFromManifest(url) {
        // Plain HTTP is rejected here and again in the installer: a package is
        // QML that runs inside this process, so it may not arrive over a
        // transport that can be rewritten in flight.
        if (installing || typeof url !== "string" || !/^https:\/\//.test(url)) {
            installMessage = "Enter a valid HTTPS manifest URL";
            return false;
        }
        installing = true;
        installMessage = "Downloading plugin…";
        pluginInstaller.command = ["python3", `${Directories.scriptPath}/plugins/install_plugin.py`,
            url, installedRoot];
        pluginInstaller.running = true;
        return true;
    }

    Process {
        id: pluginInstaller
        stdout: StdioCollector { id: installerOutput }
        stderr: StdioCollector { id: installerError }
        onExited: (exitCode, exitStatus) => {
            root.installing = false;
            if (exitCode === 0) {
                root.installMessage = `Installed ${installerOutput.text.trim()}`;
                root.scanInstalledPlugins();
            } else {
                const detail = installerError.text.trim().split("\n").pop();
                root.installMessage = detail || "Plugin installation failed";
            }
        }
    }

    // FileView completion arrives once per manifest. Publishing the model for every
    // individual completion repeatedly destroys and recreates every enabled desktop
    // widget during startup, which is especially expensive for canvas/effect widgets.
    Timer {
        id: rebuildTimer
        interval: 50
        repeat: false
        onTriggered: root.rebuildFromLoadedFiles()
    }

    Process {
        id: manifestScanner
        stdout: StdioCollector {
            onStreamFinished: root.installedManifestPaths = text.split("\n").filter(path => path.length > 0)
        }
    }

    Variants {
        model: root.installedManifestPaths
        Scope {
            required property string modelData
            FileView {
                path: modelData
                watchChanges: true
                onLoaded: root.registerInstalledManifest(modelData, text())
                onFileChanged: reload()
            }
        }
    }

    FileView {
        id: clockManifestFile
        property string pluginBase: Quickshell.shellPath("modules/common/plugins/bundled/clock")
        path: Quickshell.shellPath("modules/common/plugins/bundled/clock/manifest.json")
        onLoaded: root.scheduleRebuild()
    }
    FileView {
        id: batteryManifestFile
        property string pluginBase: Quickshell.shellPath("modules/common/plugins/bundled/battery")
        path: Quickshell.shellPath("modules/common/plugins/bundled/battery/manifest.json")
        onLoaded: root.scheduleRebuild()
    }
    FileView {
        id: dockerManifestFile
        property string pluginBase: Quickshell.shellPath("modules/common/plugins/bundled/docker")
        path: Quickshell.shellPath("modules/common/plugins/bundled/docker/manifest.json")
        onLoaded: root.scheduleRebuild()
    }
    FileView {
        id: discordVoiceManifestFile
        property string pluginBase: Quickshell.shellPath("modules/common/plugins/bundled/discordVoice")
        path: pluginBase + "/manifest.json"
        onLoaded: root.scheduleRebuild()
    }
    FileView {
        id: atAGlanceManifestFile
        property string pluginBase: Quickshell.shellPath("modules/common/plugins/bundled/atAGlance")
        path: Quickshell.shellPath("modules/common/plugins/bundled/atAGlance/manifest.json")
        onLoaded: root.scheduleRebuild()
    }
    FileView {
        id: nandoroidClockManifestFile
        property string pluginBase: Quickshell.shellPath("modules/common/plugins/bundled/nandoroid-clock")
        path: pluginBase + "/manifest.json"
        onLoaded: root.scheduleRebuild()
    }
    FileView {
        id: nandoroidAtAGlanceManifestFile
        property string pluginBase: Quickshell.shellPath("modules/common/plugins/bundled/nandoroid-at-a-glance")
        path: pluginBase + "/manifest.json"
        onLoaded: root.scheduleRebuild()
    }
    FileView {
        id: nandoroidMediaManifestFile
        property string pluginBase: Quickshell.shellPath("modules/common/plugins/bundled/nandoroid-media")
        path: pluginBase + "/manifest.json"
        onLoaded: root.scheduleRebuild()
    }
    FileView {
        id: nandoroidSystemMonitorManifestFile
        property string pluginBase: Quickshell.shellPath("modules/common/plugins/bundled/nandoroid-system-monitor")
        path: pluginBase + "/manifest.json"
        onLoaded: root.scheduleRebuild()
    }
    FileView {
        id: nandoroidWeatherManifestFile
        property string pluginBase: Quickshell.shellPath("modules/common/plugins/bundled/nandoroid-weather")
        path: pluginBase + "/manifest.json"
        onLoaded: root.scheduleRebuild()
    }
    FileView {
        id: nandoroidCurrencyManifestFile
        property string pluginBase: Quickshell.shellPath("modules/common/plugins/bundled/nandoroid-currency")
        path: pluginBase + "/manifest.json"
        onLoaded: root.scheduleRebuild()
    }

    Component.onCompleted: root.scanInstalledPlugins()
}
