pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

/**
 * Prism Launcher instances, for launching a modpack straight from the search
 * bar.
 *
 * Feature-detected end to end: a machine without Prism never spawns the
 * enumeration script, `available` stays false, and every consumer (the search
 * prefix, its settings row) hides itself. That is the whole reason detection
 * lives here rather than in Config - the shell ships to machines that have no
 * Minecraft on them at all, and an always-present prefix for a launcher you
 * do not own is clutter, not a feature.
 */
Singleton {
    id: root

    // Native install first, flatpak second - matching list_instances.py's own
    // data-dir preference, so the binary we launch and the instances we list
    // always come from the same install.
    readonly property string flatpakId: "org.prismlauncher.PrismLauncher"
    property string launcherCommand: ""
    readonly property bool available: root.launcherCommand !== ""

    property var instances: []

    // Instance names are what the user types, so that is what gets prepped.
    // Rebuilt only when the instance list actually changes - Fuzzy.prepare is
    // not free and a search bar calls fuzzyQuery on every keystroke.
    readonly property var preppedNames: root.instances.map(instance => ({
        name: Fuzzy.prepare(`${instance.name} `),
        entry: instance
    }))

    function fuzzyQuery(search: string): var {
        if (search.length === 0)
            return root.instances;
        return Fuzzy.go(search, root.preppedNames, {
            all: true,
            key: "name"
        }).map(result => result.obj.entry);
    }

    function launch(instance) {
        if (!instance?.launch?.length)
            return;
        Quickshell.execDetached(instance.launch);
    }

    // Also the instantiation hook, and that is the more important half. A QML
    // singleton is constructed on first use, and the only other thing that
    // reaches this one is the results binding inside LauncherSearch - so
    // without an early caller, detection would not even START until the user's
    // first keystroke, and their first query would silently have no modpacks
    // in it. Calling this from LauncherSearch's Component.onCompleted
    // constructs the singleton (which starts detection); the body no-ops on
    // that first call, because `available` is still false until detection
    // answers a moment later.
    function reload() {
        if (root.available)
            instanceLister.running = true;
    }

    // Detection runs once at startup. `command -v` covers the native binary;
    // the flatpak check is a directory test rather than `flatpak info` because
    // the latter costs hundreds of milliseconds on a cold flatpak store and
    // this runs on every shell start, on machines that will never need it.
    Process {
        id: detector
        running: true
        command: ["bash", "-c",
            `if command -v prismlauncher >/dev/null 2>&1; then echo prismlauncher; ` +
            `elif [ -d "$HOME/.var/app/${root.flatpakId}" ]; then echo "flatpak run ${root.flatpakId}"; fi`]
        stdout: SplitParser {
            onRead: data => {
                const found = data.trim();
                if (found.length === 0)
                    return;
                root.launcherCommand = found;
                instanceLister.running = true;
            }
        }
    }

    Process {
        id: instanceLister
        command: ["python3", Quickshell.shellPath("scripts/prism/list_instances.py"),
            "--launcher", root.launcherCommand]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.instances = JSON.parse(text);
                } catch (error) {
                    // A parse failure means no modpack results this session,
                    // not a broken search bar: every other result source is
                    // independent of this one.
                    console.warn("[PrismLauncher] could not parse instance list:", error);
                    root.instances = [];
                }
            }
        }
    }

    // Instances change when the user installs, renames or plays a pack - all
    // of which rewrite instance.cfg. Re-reading on every search keystroke
    // would spawn a process per character; re-reading when the launcher opens
    // is both cheap and exactly when a stale list would be visible.
    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (GlobalStates.overviewOpen)
                root.reload();
        }
    }
}
