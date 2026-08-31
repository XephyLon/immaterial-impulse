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

    // The selective-apply popup's request, mirroring PluginStore's
    // pendingInstallEntry: the Profile page only requests, the window-level
    // host in SettingsContent shows the dialog, and the dialog itself calls
    // apply() with the chosen sections.
    property string pendingApplyName: ""
    property var pendingApplyData: null

    function requestApply(name, presetData) {
        root.pendingApplyData = presetData ?? null
        root.pendingApplyName = name
    }

    function cancelApply() {
        root.pendingApplyName = ""
        root.pendingApplyData = null
    }

    // `sections` comes from PresetGroups.sectionsFor - config keys and
    // appearance:<sub> spellings, sanitized by construction, but still
    // passed as ONE argv element after --only, never shell-spliced.
    function apply(name, sections) {
        GlobalStates.settingsOpen = false
        // Clearing the wallpaper preview belongs to the wallpaper group:
        // an apply that keeps the current wallpaper must not blank it.
        const wallpaperIncluded = !sections
            || sections.some(s => s === "background" || s === "wallpaperSelector")
        if (wallpaperIncluded) {
            Wallpapers.confirmedPath = ""
            Wallpapers.previewPath = ""
        }
        const argv = ["bash", Directories.presetsScriptPath, "--apply", name]
        if (sections && sections.length > 0)
            argv.push("--only", sections.join(","))
        Quickshell.execDetached(argv)
    }

    function remove(name) {
        deleteProc.command = ["bash", Directories.presetsScriptPath, "--remove", name]
        deleteProc.running = true
    }
}