pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services.ai

/**
 * One-sentence answers for the launcher (docs/proposals/ai-in-overview.md,
 * approach 3). The launcher hands a question over while the user types;
 * after a pause the question goes to the selected model with a
 * "one sentence, plain text" system prompt, and the first `maxChars` of the
 * reply stream into `answer`, which the Ask row shows as its subtitle.
 *
 * Separate from `Ai` on purpose: nothing here touches the chat, its
 * session, its requester or its strategy instances (a strategy carries
 * pending-tool-call state between lines), so an inline request can never
 * corrupt a conversation that is streaming at the same time. The dialect
 * strategies are instantiated here, in this context - they read
 * `root.apiKeyEnvVarName` unqualified.
 *
 * Gates, in order: `search.ai.inline` on; a usable model selected (the same
 * test the Ask row uses); the model local (loopback endpoint) OR
 * `search.ai.inlineWithCloud` on, because keystroke-driven cloud calls cost
 * money and send what you type. Nothing runs before the debounce elapses,
 * one request is in flight at a time, any keystroke cancels it, and closing
 * the overview cancels it (LauncherSearch owns both calls).
 */
Singleton {
    id: root

    readonly property string apiKeyEnvVarName: "API_KEY"
    readonly property int maxChars: 200
    readonly property string systemPrompt: "Answer in one short sentence of plain text: no markdown, no lists, no preamble, at most 200 characters. If it cannot be answered in one sentence, say so in one sentence."

    /** The question the current `answer` (or the request in flight) belongs to. */
    property string question: ""
    /** The answer so far, plain text, at most `maxChars` (+ an ellipsis when cut). */
    property string answer: ""
    /** A request process is running (not the debounce). */
    property bool busy: false
    /** The answer is complete (finished, or cut at `maxChars`). */
    property bool done: false

    readonly property var model: Ai.models[Ai.currentModelId] ?? null
    // Loopback only. A keyless remote endpoint is still someone else's
    // server receiving keystrokes.
    readonly property bool modelIsLocal: /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\]|0\.0\.0\.0)(:|\/|$)/i.test(String(root.model?.endpoint ?? ""))
    readonly property bool allowed: (Config.options.search.ai.inline ?? false)
        && !!root.model && Ai.currentModelHasApiKey
        && (root.modelIsLocal || (Config.options.search.ai.inlineWithCloud ?? false))

    // Each request has a generation; a process exit from a cancelled
    // generation touches nothing.
    property int generation: 0
    property var answerMessage: null

    /** The launcher's question as typed (prefix removed). Debounced; a
        repeat of the question already answered or in flight is a no-op. */
    function ask(text) {
        const q = String(text ?? "").trim();
        const minWords = Config.options.search.ai.inlineMinWords ?? 3;
        if (!root.allowed || q.length === 0 || q.split(/\s+/).length < minWords) {
            root.cancel();
            return;
        }
        if (q === root.question && (root.busy || root.done || debounce.running)) return;
        root.cancel();
        root.question = q;
        debounce.interval = Math.max(100, Config.options.search.ai.inlineDelayMs ?? 700);
        debounce.restart();
    }

    /** Stops the debounce and any request; clears the answer. */
    function cancel() {
        debounce.stop();
        root.generation++;
        if (proc.running) proc.running = false;
        root.busy = false;
        root.done = false;
        root.answer = "";
        root.question = "";
        root.answerMessage = null;
    }

    /** The answer for `text` if there is one (complete or partial), cleared
        on the way out so Enter carries it into the chat exactly once. */
    function take(text) {
        const q = String(text ?? "").trim();
        if (q !== root.question || root.answer.length === 0) return "";
        const a = root.answer;
        root.cancel();
        return a;
    }

    Timer {
        id: debounce
        repeat: false
        onTriggered: root.send()
    }

    Component { id: messageComponent; AiMessageData {} }
    OpenAiApiStrategy { id: openaiStrategy }
    GeminiApiStrategy { id: geminiStrategy }
    MistralApiStrategy { id: mistralStrategy }
    AnthropicApiStrategy { id: anthropicStrategy }
    function strategyFor(format) {
        switch (format) {
        case "gemini": return geminiStrategy;
        case "mistral": return mistralStrategy;
        case "anthropic": return anthropicStrategy;
        default: return openaiStrategy;
        }
    }

    function send() {
        const model = root.model;
        if (!root.allowed || !model || root.question.length === 0) { root.cancel(); return; }
        if (model.requires_key && !KeyringStorage.loaded) KeyringStorage.fetchKeyringData();
        const strategy = root.strategyFor(model.api_format);
        strategy.reset();
        const userMessage = messageComponent.createObject(root, {
            "role": "user", "content": root.question, "rawContent": root.question,
            "thinking": false, "done": true,
        });
        root.answerMessage = messageComponent.createObject(root, {
            "role": "assistant", "content": "", "rawContent": "", "thinking": false, "done": false,
        });
        const data = strategy.buildRequestData(model, [userMessage], root.systemPrompt, 0.2, [], []);
        const endpoint = strategy.buildEndpoint(model);
        const authHeader = strategy.buildAuthorizationHeader(root.apiKeyEnvVarName);
        // Same shape as Ai's request script, minus the file setup: the body
        // through a printf builtin into a file (no ARG_MAX), curl unbuffered,
        // a final newline so a one-blob answer is not dropped by SplitParser.
        const bodyFile = `/tmp/quickshell/ai/inline.${root.generation}.body.json`;
        let script = "#!/usr/bin/env bash\n";
        script += `mkdir -p /tmp/quickshell/ai\n`;
        script += `BODY_FILE='${bodyFile}'\n`;
        script += `printf '%s' '${StringUtils.shellSingleQuoteEscape(JSON.stringify(data))}' > "$BODY_FILE"\n`;
        script += `curl --no-buffer -sS "${endpoint}" -H 'Content-Type: application/json'`
            + (authHeader ? ` ${authHeader}` : "") + ` --data @"$BODY_FILE"\n`;
        script += `printf '\\n'\n`;
        script += `rm -f "$BODY_FILE"\n`;
        script = strategy.finalizeScriptContent(script);
        proc.strategy = strategy;
        proc.generation = root.generation;
        proc.environment[root.apiKeyEnvVarName] = model.requires_key ? (Ai.apiKeys?.[model.key_id] ?? "") : "";
        proc.command = ["bash", "-c", script];
        root.busy = true;
        root.done = false;
        proc.running = true;
    }

    function finish(cut) {
        root.busy = false;
        root.done = root.answer.length > 0;
        if (cut && root.answer.length > 0) root.answer = root.answer.slice(0, root.maxChars).replace(/\s+$/, "") + "…";
        if (proc.running) proc.running = false;
    }

    Process {
        id: proc
        property var strategy: null
        property int generation: -1
        stdout: SplitParser {
            onRead: data => {
                if (proc.generation !== root.generation || !root.answerMessage) return;
                if (data.length === 0) return;
                let result = {};
                try {
                    result = proc.strategy.parseResponseLine(data, root.answerMessage) ?? {};
                } catch (e) {
                    console.log("[AiInline] could not parse a response line:", e);
                    return;
                }
                const text = String(root.answerMessage.content ?? "");
                // An error body is not an answer to show under the row.
                if (text.startsWith("**Error**") || text.startsWith("**Request failed**")) {
                    console.log(`[AiInline] ${text.slice(0, 200)}`);
                    root.answer = "";
                    root.finish(false);
                    return;
                }
                root.answer = text.replace(/\s+/g, " ").trim();
                if (root.answer.length >= root.maxChars) { root.finish(true); return; }
                if (result.finished) root.finish(false);
            }
        }
        stderr: StdioCollector { id: procStderr }
        onExited: (exitCode, exitStatus) => {
            if (proc.generation !== root.generation) return;
            if (exitCode !== 0 && root.answer.length === 0)
                console.log(`[AiInline] request exited ${exitCode}: ${String(procStderr.text ?? "").trim().slice(0, 200)}`);
            root.busy = false;
            root.done = root.answer.length > 0;
        }
    }
}
