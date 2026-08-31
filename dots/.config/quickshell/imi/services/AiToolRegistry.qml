pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "./ai/ai_tool_registry.js" as Fold

/**
 * Everything that is true about a tool before anyone runs it (the fork's
 * words). One row per tool - name, description, JSON-schema parameters,
 * which dialects carry it - rendered into each dialect's wire shape by the
 * tested fold. The dispatcher (Ai.handleFunctionCall) stays where the
 * behavior lives; the skeleton contract holds its case list to exactly
 * these names, so a tool added here without a handler (or vice versa)
 * reddens a test instead of failing silently at 2am.
 */
Singleton {
    id: root

    readonly property var defs: [
        {
            "name": "switch_to_search_mode",
            "description": "Search the web",
            "dialects": ["gemini"]
        },
        {
            "name": "get_shell_config",
            "description": "Get the desktop shell config file contents",
            "dialects": ["gemini", "openai", "mistral"]
        },
        {
            "name": "set_shell_config",
            "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
            "dialects": ["gemini", "openai", "mistral"],
            "parameters": {
                "type": "object",
                "properties": {
                    "key": { "type": "string", "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting." },
                    "value": { "type": "string", "description": "The value to set, e.g. `true`" }
                },
                "required": ["key", "value"]
            }
        },
        {
            "name": "run_shell_command",
            "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
            "dialects": ["gemini", "openai", "mistral"],
            "parameters": {
                "type": "object",
                "properties": {
                    "command": { "type": "string", "description": "The bash command to run" }
                },
                "required": ["command"]
            }
        },
        {
            "name": "remember_fact",
            "description": "Save one short durable fact about the user for future conversations (preferences, environment, standing context). Only for things worth knowing next week; every save is announced to the user.",
            "dialects": ["gemini", "openai", "mistral"],
            "parameters": {
                "type": "object",
                "properties": {
                    "fact": { "type": "string", "description": "The fact, one short sentence" }
                },
                "required": ["fact"]
            }
        },
        {
            "name": "generate_image",
            "description": "Generate an image from a text prompt using the user's image-generation model. Use when the user asks to draw, render, paint or generate a picture.",
            // The pipeline behind this call is OpenAI-dialect (the
            // generator endpoints), but the CALLER can be any dialect -
            // gemini gets it now, which the hand-written block never did.
            "dialects": ["gemini", "openai", "mistral"],
            "parameters": {
                "type": "object",
                "properties": {
                    "prompt": { "type": "string", "description": "The image prompt - detailed and self-contained, since the generator sees nothing else" }
                },
                "required": ["prompt"]
            }
        }
    ]

    readonly property var geminiDeclarations: Fold.toGeminiDeclarations(root.defs)
    function openAiTools(dialect) { return Fold.toOpenAiTools(root.defs, dialect); }
    function knows(name) { return Fold.allNames(root.defs).indexOf(name) !== -1; }
}
