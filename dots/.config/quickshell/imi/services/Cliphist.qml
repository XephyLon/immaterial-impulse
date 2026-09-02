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
    // Decoded previews are shared files (one per entry) with many short-lived
    // readers: the launcher rebuilds its rows on every keystroke and a hot
    // reload rebuilds every one of them, and a row that deleted "its" file on
    // destruction took it from the row built a frame later - the Image logged
    // `Cannot open` and drew its placeholder. A file lives while anything
    // holds it and for a beat after the last holder let go, so a rebuilt row
    // reclaims it instead of racing a detached rm.
    property var decodeHolders: ({})
    property list<string> decodeReleased: []
    function acquireDecode(path: string): void {
        const holders = root.decodeHolders;
        holders[path] = (holders[path] ?? 0) + 1;
        root.decodeHolders = holders;
    }
    function releaseDecode(path: string): void {
        const holders = root.decodeHolders;
        const left = (holders[path] ?? 0) - 1;
        if (left > 0) {
            holders[path] = left;
            root.decodeHolders = holders;
            return;
        }
        delete holders[path];
        root.decodeHolders = holders;
        if (!root.decodeReleased.includes(path))
            root.decodeReleased = [...root.decodeReleased, path];
    }
    Timer {
        id: decodeSweep
        interval: 3000
        repeat: true
        running: root.decodeReleased.length > 0
        onTriggered: {
            const stale = root.decodeReleased.filter(path => !(path in root.decodeHolders));
            root.decodeReleased = [];
            if (stale.length > 0)
                Quickshell.execDetached(["rm", "-f", ...stale]);
        }
    }

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
            return results.map(item => item.entry)
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
        property list<string> targets: []
        command: [root.cliphistBinary, "delete"]
        onRunningChanged: {
            if (deleteProc.running) {
                // `cliphist delete` reads newline-separated entries from stdin.
                // Feeding stdin directly avoids splicing entry text into a shell string.
                deleteProc.write(deleteProc.targets.join("\n") + "\n");
                deleteProc.stdinEnabled = false; // End input stream
            }
        }
        onExited: (exitCode, exitStatus) => {
            deleteProc.targets = [];
            root.refresh();
        }
    }

    // Batch-delete entries via a single `cliphist delete` invocation, entries passed over stdin.
    function deleteEntries(entries) {
        if (!entries || entries.length === 0) {
            return;
        }
        deleteProc.targets = entries;
        deleteProc.stdinEnabled = true;
        deleteProc.running = true;
    }

    function deleteEntry(entry) {
        root.deleteEntries([entry]);
    }

    // Deletes only the unpinned entries matching the given search string,
    // so pinned ones survive "clear results" like they survive a wipe.
    function deleteSearchResults(searchString) {
        const matches = root.fuzzyQuery(searchString)
            .filter(entry => !root.pinnedHashes.includes(root.contentHash(entry)));
        root.deleteEntries(matches);
    }

    // Wipe deletes only unpinned entries so pinned ones survive "wipe all".
    function wipe() {
        const targets = root.entries.filter(entry => !root.pinnedHashes.includes(root.contentHash(entry)));
        if (targets.length === 0) {
            root.refresh();
            return;
        }
        root.deleteEntries(targets);
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
                root.entries = []
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