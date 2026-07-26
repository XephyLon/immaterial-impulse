pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    // property string cliphistBinary: FileUtils.trimFileProtocol(`${Directories.home}/.cargo/bin/stash`)
    property string cliphistBinary: "cliphist"
    property real pasteDelay: 0.05
    property string pressPasteCommand: "ydotool key -d 1 29:1 47:1 47:0 29:0"
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property real scoreThreshold: 0.2
    property list<string> entries: []
    // Pinned entries persist across wipe and cliphist rotation.
    // Each pin is { hash, entry, name, image }; identity is a content hash so it survives re-indexing.
    property var pins: []
    readonly property var pinnedHashes: root.pins.map(p => p.hash)
    // Pins resolved against the live store so decode uses a fresh cliphist id when the content is still present.
    readonly property var livePinnedEntries: root.pins.map(p => {
        const live = root.entries.find(e => root.contentHash(e) === p.hash);
        return {
            hash: p.hash,
            entry: live ?? p.entry,
            name: p.name,
            image: p.image,
            present: !!live
        };
    })
    readonly property var preparedEntries: entries.map(a => ({
        name: Fuzzy.prepare(`${a.replace(/^\s*\S+\s+/, "")}`),
        entry: a
    }))
    function fuzzyQuery(search: string): var {
        if (search.trim() === "") {
            return entries;
        }
        if (root.sloppySearch) {
            const results = entries.slice(0, 100).map(str => ({
                entry: str,
                score: Levendist.computeTextMatchScore(str.toLowerCase(), search.toLowerCase())
            })).filter(item => item.score > root.scoreThreshold)
                .sort((a, b) => b.score - a.score)
            return results
                .map(item => item.entry)
        }

        return Fuzzy.go(search, preparedEntries, {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        });
    }

    function entryIsImage(entry) {
        return !!(/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(entry))
    }

    // Strip the leading cliphist id so pins are keyed by content, surviving re-indexing/rotation.
    function contentHash(entry) {
        const content = `${entry}`.replace(/^\d+\t/, "");
        let hash = 5381;
        for (let i = 0; i < content.length; i++) {
            hash = ((hash << 5) + hash + content.charCodeAt(i)) >>> 0;
        }
        return hash.toString(36);
    }

    function isPinned(entry) {
        return root.pinnedHashes.includes(root.contentHash(entry));
    }

    function togglePin(entry) {
        const hash = root.contentHash(entry);
        const next = root.pins.filter(p => p.hash !== hash);
        if (next.length === root.pins.length) {
            next.push({
                hash: hash,
                entry: entry,
                name: StringUtils.cleanCliphistEntry(entry),
                image: root.entryIsImage(entry)
            });
        }
        root.pins = next;
        pinsFileView.setText(JSON.stringify(root.pins));
    }

    function refresh() {
        readProc.buffer = []
        readProc.running = true
    }

    function copy(entry) {
        if (root.cliphistBinary.includes("cliphist")) // Classic cliphist
            Quickshell.execDetached(["bash", "-c", `printf '${StringUtils.shellSingleQuoteEscape(entry)}' | ${root.cliphistBinary} decode | wl-copy`]);
        else { // Stash
            const entryNumber = entry.split("\t")[0];
            Quickshell.execDetached(["bash", "-c", `${root.cliphistBinary} decode ${entryNumber} | wl-copy`]);
        }
    }

    function paste(entry) {
        if (root.cliphistBinary.includes("cliphist")) // Classic cliphist
            Quickshell.execDetached(["bash", "-c", `printf '${StringUtils.shellSingleQuoteEscape(entry)}' | ${root.cliphistBinary} decode | wl-copy && wl-paste`]);
        else { // Stash
            const entryNumber = entry.split("\t")[0];
            Quickshell.execDetached(["bash", "-c", `${root.cliphistBinary} decode ${entryNumber} | wl-copy; ${root.pressPasteCommand}`]);
        }
    }

    function superpaste(count, isImage = false) {
        // Find entries
        const targetEntries = entries.filter(entry => {
            if (!isImage) return true;
            return entryIsImage(entry);
        }).slice(0, count)
        const pasteCommands = [...targetEntries].reverse().map(entry => `printf '${StringUtils.shellSingleQuoteEscape(entry)}' | ${root.cliphistBinary} decode | wl-copy && sleep ${root.pasteDelay} && ${root.pressPasteCommand}`)
        // Act
        Quickshell.execDetached(["bash", "-c", pasteCommands.join(` && sleep ${root.pasteDelay} && `)]);
    }

    Process {
        id: deleteProc
        property string entry: ""
        command: ["bash", "-c", `echo '${StringUtils.shellSingleQuoteEscape(deleteProc.entry)}' | ${root.cliphistBinary} delete`]
        function deleteEntry(entry) {
            deleteProc.entry = entry;
            deleteProc.running = true;
            deleteProc.entry = "";
        }
        onExited: (exitCode, exitStatus) => {
            root.refresh();
        }
    }

    function deleteEntry(entry) {
        deleteProc.deleteEntry(entry);
    }

    Process {
        id: wipeProc
        property list<string> targets: []
        command: ["bash", "-c", wipeProc.targets
            .map(entry => `echo '${StringUtils.shellSingleQuoteEscape(entry)}' | ${root.cliphistBinary} delete`)
            .join("; ")]
        onExited: (exitCode, exitStatus) => {
            root.refresh();
        }
    }

    // Wipe deletes only unpinned entries so pinned ones survive "wipe all".
    function wipe() {
        wipeProc.targets = root.entries.filter(entry => !root.pinnedHashes.includes(root.contentHash(entry)));
        if (wipeProc.targets.length === 0) {
            root.refresh();
            return;
        }
        wipeProc.running = true;
    }

    Connections {
        target: Quickshell
        function onClipboardTextChanged() {
            delayedUpdateTimer.restart()
        }
    }

    Timer {
        id: delayedUpdateTimer
        interval: Config.options.hacks.arbitraryRaceConditionDelay
        repeat: false
        onTriggered: {
            root.refresh()
        }
    }

    Process {
        id: readProc
        property list<string> buffer: []

        command: [root.cliphistBinary, "list"]

        stdout: SplitParser {
            onRead: (line) => {
                readProc.buffer.push(line)
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.entries = readProc.buffer
            } else {
                console.error("[Cliphist] Failed to refresh with code", exitCode, "and status", exitStatus)
            }
        }
    }

    FileView {
        id: pinsFileView
        path: Qt.resolvedUrl(Directories.clipboardPinsPath)
        onLoaded: {
            try {
                root.pins = JSON.parse(pinsFileView.text());
            } catch (e) {
                root.pins = [];
            }
        }
        onLoadFailed: (error) => {
            if (error == FileViewError.FileNotFound) {
                root.pins = [];
                pinsFileView.setText(JSON.stringify(root.pins));
            } else {
                console.error("[Cliphist] Failed to load pins:", error);
            }
        }
    }

    Component.onCompleted: pinsFileView.reload()

    IpcHandler {
        target: "cliphistService"

        function update(): void {
            root.refresh()
        }
    }
}
