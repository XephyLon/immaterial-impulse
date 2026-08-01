pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * A service that provides access to Hyprland keybinds.
 * Uses the `get_keybinds.py` script to parse comments in config files in a certain format and convert to JSON.
 */
Singleton {
    id: root
    property string keybindParserPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/hyprland/get_keybinds.py`)
    property string defaultKeybindConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland/keybinds.lua`)
    property string userKeybindConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/keybinds.lua`)
    property var defaultKeybinds: {"children": []}
    property var userKeybinds: {"children": []}
    // Merge default + custom keybinds instead of blindly concatenating: sections
    // are merged by name and binds deduped by mods+key, with the custom file
    // winning. Without this, a bind copied into custom/keybinds.lua to override a
    // default one was listed twice in the cheatsheet. See issue #34.
    property var keybinds: ({
        children: root.mergeKeybindSections(defaultKeybinds.children ?? [],
                                            userKeybinds.children ?? [])
    })

    function bindIdentity(kb) {
        return `${(kb.mods ?? []).join("+")}|${kb.key ?? ""}`;
    }

    // Concatenate two bind lists, dropping earlier duplicates so the later
    // (custom) definition of a given mods+key wins.
    function dedupKeybinds(binds) {
        const byId = new Map();
        for (const kb of binds)
            byId.set(root.bindIdentity(kb), kb);
        return Array.from(byId.values());
    }

    // Merge two lists of sections by name; matching sections have their binds and
    // sub-sections merged recursively, custom overriding default on collisions.
    function mergeKeybindSections(defaultSections, userSections) {
        const merged = [];
        const indexByName = {};
        const absorb = (section) => {
            const existingIndex = indexByName[section.name];
            if (existingIndex === undefined) {
                indexByName[section.name] = merged.length;
                merged.push({
                    name: section.name,
                    keybinds: [...(section.keybinds ?? [])],
                    children: [...(section.children ?? [])],
                });
            } else {
                const existing = merged[existingIndex];
                existing.keybinds = root.dedupKeybinds([
                    ...(existing.keybinds ?? []),
                    ...(section.keybinds ?? []),
                ]);
                existing.children = root.mergeKeybindSections(
                    existing.children ?? [], section.children ?? []);
            }
        };
        for (const section of defaultSections) absorb(section);
        for (const section of userSections) absorb(section);
        return merged;
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name == "configreloaded") {
                getDefaultKeybinds.running = true
                getUserKeybinds.running = true
            }
        }
    }

    Process {
        id: getDefaultKeybinds
        running: true
        command: [root.keybindParserPath, "--path", root.defaultKeybindConfigPath]
        
        stdout: SplitParser {
            onRead: data => {
                try {
                    root.defaultKeybinds = JSON.parse(data)
                } catch (e) {
                    console.error("[CheatsheetKeybinds] Error parsing keybinds:", e)
                }
            }
        }
    }

    Process {
        id: getUserKeybinds
        running: true
        command: [root.keybindParserPath, "--path", root.userKeybindConfigPath]
        
        stdout: SplitParser {
            onRead: data => {
                try {
                    root.userKeybinds = JSON.parse(data)
                } catch (e) {
                    console.error("[CheatsheetKeybinds] Error parsing keybinds:", e)
                }
            }
        }
    }
}

