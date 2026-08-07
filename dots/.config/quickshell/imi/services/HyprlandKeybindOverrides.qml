pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import "../modules/common/functions/keybindOverrides.js" as KeybindOverridesLogic
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Owner of the keyboard-shortcuts editor's state: the declarative sidecar
 * (~/.config/immaterial-impulse/keybind-overrides.json) and the generated Lua
 * shim rendered from it by scripts/hyprland/keybind_overrides.py.
 *
 * The sidecar is dynamic data keyed by binding identity, so it lives in its
 * own raw-JSON FileView (the PluginState.qml pattern), never in Config's
 * JsonAdapter. The shim is regenerated through the Python script, which owns
 * all safety: hand-edit detection, literal-only emission, atomic writes, no
 * rewrite when unchanged. Regeneration passes the sidecar content inline so it
 * never races the debounced sidecar write.
 *
 * Also maintains the full chord-occupancy scan (get_keybinds.py --flat over
 * both keybind files, hidden binds included) that conflict detection reads.
 */
Singleton {
    id: root

    readonly property int schemaVersion: 1
    readonly property string sidecarPath: `${Directories.shellConfig}/keybind-overrides.json`
    readonly property string shimPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland/shellOverrides/keybinds.lua`)
    readonly property string generatorPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/hyprland/keybind_overrides.py`)
    readonly property string keybindParserPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/hyprland/get_keybinds.py`)

    property var state: root.emptyState()
    property bool ready: false
    // "unknown" | "ok" | "foreign" | "invalid" | "error"
    // "foreign" means the shim on disk was hand-edited: the generator refuses
    // to touch it and the UI must say so instead of pretending edits apply.
    property string shimStatus: "unknown"
    property string lastError: ""

    property var flatDefaultBinds: []
    property var flatUserBinds: []

    readonly property int overrideCount: Object.keys(root.state.overrides).length

    function emptyState() {
        return { version: root.schemaVersion, overrides: {} };
    }

    function identityFor(mods, key) {
        return KeybindOverridesLogic.identityFor(mods, key);
    }

    function splitIdentity(identity) {
        return KeybindOverridesLogic.splitIdentity(identity);
    }

    function overrideFor(identity) {
        return root.state.overrides[identity] ?? null;
    }

    function canRebind(kb) {
        return KeybindOverridesLogic.canRebind(kb);
    }

    function conflictsFor(mods, key, ignoreIdentity) {
        return KeybindOverridesLogic.chordConflicts(
            mods, key, ignoreIdentity,
            root.flatDefaultBinds, root.flatUserBinds, root.state.overrides);
    }

    // sourceBind is the parsed default this override replaces; its dispatcher,
    // params and flags are stored in full so the entry stays a complete
    // replacement even if the shipped file changes underneath it.
    function setRebind(identity, mods, key, sourceBind) {
        root.setEntry(identity, {
            action: "rebind",
            mods: mods.slice(),
            key: key,
            dispatcher: sourceBind.dispatcher ?? "",
            params: sourceBind.params ?? "",
            flags: sourceBind.flags ?? {},
            description: sourceBind.comment ?? "",
        });
    }

    function removeBinding(identity) {
        root.setEntry(identity, { action: "remove" });
    }

    function addBinding(mods, key, command, description) {
        root.setEntry(root.identityFor(mods, key), {
            action: "add",
            mods: mods.slice(),
            key: key,
            command: command,
            description: description ?? "",
        });
    }

    function reset(identity) {
        if (!(identity in root.state.overrides))
            return;
        const nextOverrides = Object.assign({}, root.state.overrides);
        delete nextOverrides[identity];
        root.replaceOverrides(nextOverrides);
    }

    function resetAll() {
        root.replaceOverrides({});
    }

    function setEntry(identity, entry) {
        if (!identity || identity.endsWith("|"))
            return;
        const nextOverrides = Object.assign({}, root.state.overrides);
        nextOverrides[identity] = entry;
        root.replaceOverrides(nextOverrides);
    }

    function replaceOverrides(nextOverrides) {
        root.state = { version: root.schemaVersion, overrides: nextOverrides };
        writeTimer.restart();
    }

    function loadText(text) {
        try {
            const parsed = JSON.parse(text);
            if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
                throw new Error("root value must be an object");
            root.state = {
                version: root.schemaVersion,
                overrides: parsed.overrides
                    && typeof parsed.overrides === "object"
                    && !Array.isArray(parsed.overrides)
                    ? parsed.overrides
                    : {},
            };
        } catch (error) {
            console.warn("[HyprlandKeybindOverrides] Ignoring invalid sidecar: " + error);
            root.state = root.emptyState();
        }
        root.ready = true;
        // Reconcile on startup: a dots update may have removed the shim while
        // the sidecar still holds overrides (or vice versa). The generator is
        // a no-op when nothing changed, so this is safe to run every launch.
        root.requestRegenerate();
    }

    function requestRegenerate() {
        if (!root.ready)
            return;
        if (regenProcess.running) {
            root.regenQueued = true;
            return;
        }
        regenProcess.command = [
            "python3", root.generatorPath,
            "--sidecar-json", JSON.stringify(root.state),
            "--out", root.shimPath,
        ];
        regenProcess.running = true;
    }

    property bool regenQueued: false

    Timer {
        id: writeTimer
        interval: 100
        onTriggered: {
            sidecarFile.setText(JSON.stringify(root.state, null, 2));
            root.requestRegenerate();
        }
    }

    Timer {
        id: reloadTimer
        interval: 100
        onTriggered: sidecarFile.reload()
    }

    FileView {
        id: sidecarFile
        path: root.sidecarPath
        watchChanges: true
        onFileChanged: reloadTimer.restart()
        onLoaded: root.loadText(sidecarFile.text())
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                root.state = root.emptyState();
                root.ready = true;
                root.requestRegenerate();
            } else {
                console.warn("[HyprlandKeybindOverrides] Failed to load sidecar: " + error);
            }
        }
    }

    Process {
        id: regenProcess

        property string resultLine: ""
        property string errorLine: ""

        stdout: SplitParser {
            onRead: data => regenProcess.resultLine = data.trim()
        }
        stderr: SplitParser {
            onRead: data => regenProcess.errorLine = data.trim()
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.shimStatus = "ok";
                root.lastError = "";
                // An updated file is picked up by Hyprland's own config watch.
                // A created file was not sourced at the last load (so nothing
                // watches it), and deletion is not reliably watched either -
                // both need an explicit reload for hyprland.lua's
                // is_file_exists gate to re-evaluate.
                const result = regenProcess.resultLine;
                if (result === "created" || result === "deleted") {
                    Quickshell.execDetached(["hyprctl", "reload"]);
                }
            } else if (exitCode === 4) {
                root.shimStatus = "foreign";
                root.lastError = regenProcess.errorLine;
            } else if (exitCode === 3) {
                root.shimStatus = "invalid";
                root.lastError = regenProcess.errorLine;
            } else {
                root.shimStatus = "error";
                root.lastError = regenProcess.errorLine
                    || `keybind_overrides.py exited with ${exitCode}`;
            }
            regenProcess.resultLine = "";
            regenProcess.errorLine = "";
            if (root.regenQueued) {
                root.regenQueued = false;
                root.requestRegenerate();
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name == "configreloaded") {
                getFlatDefault.running = true;
                getFlatUser.running = true;
            }
        }
    }

    Process {
        id: getFlatDefault
        running: true
        command: [root.keybindParserPath, "--flat", "--path", HyprlandKeybinds.defaultKeybindConfigPath]
        stdout: SplitParser {
            onRead: data => {
                try {
                    root.flatDefaultBinds = JSON.parse(data).binds ?? [];
                } catch (e) {
                    console.error("[HyprlandKeybindOverrides] Error parsing flat default binds:", e);
                }
            }
        }
    }

    Process {
        id: getFlatUser
        running: true
        command: [root.keybindParserPath, "--flat", "--path", HyprlandKeybinds.userKeybindConfigPath]
        stdout: SplitParser {
            onRead: data => {
                try {
                    root.flatUserBinds = JSON.parse(data).binds ?? [];
                } catch (e) {
                    console.error("[HyprlandKeybindOverrides] Error parsing flat user binds:", e);
                }
            }
        }
    }
}
