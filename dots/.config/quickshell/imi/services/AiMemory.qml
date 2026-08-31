pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import "./ai/ai_memory.js" as Fold

/**
 * What the assistant is allowed to remember between conversations (the
 * fork's grammar): plain fact lines the user can list, add and delete
 * (/memory, /remember, /forget), folded into the system prompt. The model
 * may add one through the remember_fact tool - every addition is announced
 * in the chat, never silent. A JSON list beside the chats, hand-editable.
 */
Singleton {
    id: root

    readonly property string path: `${Directories.aiChats}/memory.json`
    property bool loaded: false
    property var facts: []

    readonly property bool enabled: Config.options?.ai?.memory?.enabled ?? true
    readonly property int limit: Config.options?.ai?.memory?.limit ?? 40
    readonly property string promptBlock: Fold.promptBlock(root.facts, root.enabled)

    function newId() {
        return `m${Date.now().toString(36)}${Math.floor(Math.random() * 1296).toString(36)}`;
    }

    /** Returns true when the fact is new (and now saved). */
    function remember(text, source) {
        const next = Fold.withFact(root.facts, text, root.newId(), Date.now(), source, root.limit);
        if (next === root.facts || next.length === root.facts.length
                && JSON.stringify(next) === JSON.stringify(root.facts))
            return false;
        root.facts = next;
        root.save();
        return true;
    }

    function forget(id) {
        const next = Fold.withoutFact(root.facts, id);
        if (next.length === root.facts.length) return false;
        root.facts = next;
        root.save();
        return true;
    }

    function save() {
        memoryFile.setText(JSON.stringify(root.facts, null, 2));
    }

    Component.onCompleted: memoryFile.reload()

    FileView {
        id: memoryFile
        path: Qt.resolvedUrl(root.path)
        onLoaded: {
            try { root.facts = JSON.parse(memoryFile.text()); }
            catch (e) { root.facts = []; }
            root.loaded = true;
        }
        onLoadFailed: { root.facts = []; root.loaded = true; }
    }
}
