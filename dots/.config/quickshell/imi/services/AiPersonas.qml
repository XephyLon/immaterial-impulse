pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import "./ai/ai_personas.js" as Fold

/**
 * Personas: a way of answering, saved whole (the fork's grammar, on imi).
 *
 * A persona is the system prompt plus the temperature that goes with it;
 * picking one sets both at once. Built-ins ship here as starting points; a
 * user persona in config `ai.personas` with the same id shadows its
 * built-in. `ai.persona` holds the active id, "" meaning the free-text
 * System prompt card - and editing that card while a persona is active
 * switches back to "" so the card the user just typed into is what speaks.
 */
Singleton {
    id: root

    readonly property var builtIns: [
        {
            "id": "shell",
            "name": Translation.tr("Shell & Hyprland"),
            "icon": "terminal",
            "description": Translation.tr("Arch, Hyprland and the shell around them"),
            "systemPrompt": "You answer questions about an Arch Linux system running Hyprland and a Quickshell/QML desktop shell.\n\n- Give the command first, the explanation after, and only as much explanation as the command needs.\n- Prefer what is already installed. Say when something has to be installed, and with which package manager.\n- Warn plainly before anything that deletes, overwrites or needs root.\n- Context: {DISTRO}, {DE}, focused app {WINDOWCLASS}, {DATETIME}.",
            "temperature": 0.3
        },
        {
            "id": "qml",
            "name": Translation.tr("QML review"),
            "icon": "code",
            "description": Translation.tr("Reads QML like someone who has to maintain it"),
            "systemPrompt": "You review QML for a Quickshell desktop shell.\n\n- Point at the specific line and say what breaks, not what could be nicer.\n- Watch for: bindings that loop, properties shadowing FINAL ones on Control subclasses, work done at load that belongs in a Loader, and anchors set on a component instead of its Loader.\n- Match the file's own style: 4-space indent, no deep nesting, early returns.\n- Code first, prose second. No praise.",
            "temperature": 0.2
        },
        {
            "id": "plain",
            "name": Translation.tr("Plain answers"),
            "icon": "notes",
            "description": Translation.tr("Short, direct, no dressing"),
            "systemPrompt": "Answer briefly and directly.\n\n- Lead with the answer; add context only where the answer would mislead without it.\n- No headers, no emoji, no tables unless asked.\n- Context: {DISTRO}, {DE}, {DATETIME}.",
            "temperature": 0.4
        }
    ]

    readonly property var all: Fold.resolved(root.builtIns, Config.options?.ai?.personas ?? [])
    readonly property string activeId: Config.options?.ai?.persona ?? ""
    readonly property var active: Fold.personaById(root.all, root.activeId)

    /** Picking sets the id and applies the persona's temperature once. */
    function pick(id) {
        Config.options.ai.persona = id ?? "";
        const persona = Fold.personaById(root.all, id);
        if (persona && persona.temperature !== undefined)
            Config.options.ai.temperature = persona.temperature;
    }
}
