pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.plugins

Singleton {
    id: root

    property alias folderModel: presetsFolderModel

    FolderListModel {
        id: presetsFolderModel
        folder: Qt.resolvedUrl(Directories.userPresetsPath)
        showDirs: false
        nameFilters: ["*.json"]
    }

    function refresh() {
        const current = presetsFolderModel.folder
        presetsFolderModel.folder = ""
        presetsFolderModel.folder = current
    }

    Process {
        id: saveProc
        onExited: root.refresh()
    }

    Process {
        id: deleteProc
        onExited: root.refresh()
    }

    function save(rawInput) {
        const raw = rawInput.trim()
        if (raw.length === 0) return

        const commaIndex = raw.indexOf(",")
        let name = raw
        let description = ""

        if (commaIndex !== -1) {
            name = raw.substring(0, commaIndex).trim()
            description = raw.substring(commaIndex + 1).trim()
        }

        name = name.replace(/\s/g, "_")
        if (name.length === 0) return

        // PluginState writes are debounced. Pass the authoritative in-memory
        // snapshot so a preset saved immediately after changing an option does
        // not capture the previous contents of plugin-state.json.
        saveProc.command = ["bash", Directories.presetsScriptPath, "--save", name,
            description, PluginState.snapshot()]
        saveProc.running = true
    }

    // Save the current state over an existing preset. `name` is an existing
    // preset's exact (already-sanitized) name; --save writes ${name}.json,
    // replacing it. Keeps the preset's description.
    function overwrite(name, description) {
        if (!name || name.length === 0) return
        saveProc.command = ["bash", Directories.presetsScriptPath, "--save", name,
            description ?? "", PluginState.snapshot()]
        saveProc.running = true
    }

    function apply(name) {
        GlobalStates.settingsOpen = false
        Quickshell.execDetached(["bash", Directories.presetsScriptPath, "--apply", name])
    }

    function remove(name) {
        deleteProc.command = ["bash", Directories.presetsScriptPath, "--remove", name]
        deleteProc.running = true
    }
}