pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import "PluginValidator.js" as PluginValidator
import "InstalledManifestState.js" as InstalledManifestState

Singleton {
    id: root

    property var availablePlugins: []
    property var manifestsMap: ({})
    property var installedManifests: ({})
    property list<string> installedManifestPaths: []
    readonly property string installedRoot: `${Directories.shellConfig}/plugins`
    property bool installing: false
    property string installMessage: ""
    property bool uninstalling: false
    // The plugin id awaiting a delete confirmation, or "" when no dialog is up.
    // A singleton property so the settings page can request a removal and the
    // window-level dialog host can show the prompt without them referencing
    // each other.
    property string pendingUninstallId: ""

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
        [clockManifestFile, dockerManifestFile, discordVoiceManifestFile,
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
        // Deliberately does not clear installedManifests here: the results are
        // reconciled against the scan in onStreamFinished instead. Clearing up
        // front and waiting for FileView.onLoaded to repopulate loses every
        // surviving plugin (an already-loaded FileView does not re-fire), and a
        // scan that finds nothing loads no FileView at all, so the list would
        // never rebuild and a just-removed plugin would linger.
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

    // Only packages that were installed into the plugins directory can be
    // removed; bundled plugins ship with the shell and are not on disk here.
    function isRemovable(id) {
        for (const plugin of root.availablePlugins)
            if (plugin.id === id && plugin._origin === "installed")
                return true;
        return false;
    }

    function requestUninstall(id) {
        if (!root.uninstalling && root.isRemovable(id))
            root.pendingUninstallId = id;
    }

    function cancelUninstall() {
        root.pendingUninstallId = "";
    }

    function confirmUninstall() {
        const id = root.pendingUninstallId;
        root.pendingUninstallId = "";
        if (root.uninstalling || !root.isRemovable(id))
            return;
        root.uninstalling = true;
        root.installMessage = "Removing plugin…";
        pluginUninstaller.command = ["python3", `${Directories.scriptPath}/plugins/uninstall_plugin.py`,
            root.installedRoot, id];
        pluginUninstaller.running = true;
    }

    Process {
        id: pluginUninstaller
        stdout: StdioCollector { id: uninstallerOutput }
        stderr: StdioCollector { id: uninstallerError }
        onExited: (exitCode, exitStatus) => {
            root.uninstalling = false;
            if (exitCode === 0) {
                const removed = uninstallerOutput.text.trim();
                // The delete affordance is only offered while disabled, but drop
                // the id from the enabled list regardless so a stale entry can
                // never re-enable a plugin that no longer exists.
                Config.setNestedValue("plugins.enabled",
                    Config.options.plugins.enabled.filter(id => id !== removed));
                root.installMessage = `Removed ${removed}`;
                root.scanInstalledPlugins();
            } else {
                const detail = uninstallerError.text.trim().split("\n").pop();
                root.installMessage = detail || "Plugin removal failed";
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
            onStreamFinished: {
                const paths = text.split("\n").filter(path => path.length > 0);
                // Drop manifests whose files the scan no longer found, keeping the
                // survivors already in memory. New paths are added when their
                // FileView loads below; either way a rebuild runs, so a removed
                // plugin leaves the list even when nothing remains to load.
                root.installedManifests = InstalledManifestState.reconcile(
                    paths, root.installedManifests);
                root.installedManifestPaths = paths;
                root.scheduleRebuild();
            }
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
