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
    /** `answer` belongs to the previous question and is shown dimmed while
        the new one is pending, so the row does not collapse and regrow on
        every keystroke. */
    property bool stale: false
    /** A one-line note when a request failed (a bad key, an unreachable
        endpoint, an unparseable body) - shown where the answer would be, so
        "Thinking…" never just vanishes. Cleared by the next question. */
    property string errorNote: ""
    /** The model that produced (or is producing) `answer`, recorded when the
        request starts - the selected model can change before Enter. */
    property string answerModel: ""

    readonly property var model: Ai.models[Ai.currentModelId] ?? null
    // Loopback only (StringUtils.isLoopbackUrl). A keyless remote endpoint
    // is still someone else's server receiving keystrokes.
    readonly property bool modelIsLocal: StringUtils.isLoopbackUrl(root.model?.endpoint ?? "")
    readonly property bool allowed: (Config.options.search.ai.inline ?? false)
        && !!root.model && Ai.currentModelHasApiKey
        && (root.modelIsLocal || (Config.options.search.ai.inlineWithCloud ?? false))
    // Switching the feature (or the model) off while an answer is on the row
    // clears it; nothing else would, since the launcher stops calling in.
    onAllowedChanged: if (!root.allowed) root.cancel()

    // Each request has a generation; a process exit from a cancelled
    // generation touches nothing.
    property int generation: 0
    property var answerMessage: null
    // What Enter can still claim after a cancel. The row's activated()
    // closes the overview (which cancels) BEFORE its execute() runs, so the
    // answer on the row would be gone by the time askAssistant asks for it
    // (found in the sandbox: Enter re-asked instead of carrying). A cancel
    // parks the current question and answer here; take() claims them once;
    // a different question replaces them.
    property string lastQuestion: ""
    property string lastAnswer: ""
    property string lastModel: ""
    property var userMessage: null

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
        const previous = root.answer;
        const previousQuestion = root.question;
        root.cancel();
        if (q !== root.lastQuestion) { root.lastQuestion = ""; root.lastAnswer = ""; root.lastModel = ""; }
        // The previous answer stays on the row, dimmed, until the new one
        // has a first token: a row that collapses to nothing for the whole
        // debounce walks the rows below it up and down while typing. Only
        // while the question is being extended or trimmed, though - an
        // unrelated question gets no stale answer under its title.
        const related = previousQuestion.length > 0 && (q.startsWith(previousQuestion) || previousQuestion.startsWith(q));
        if (previous.length > 0 && related) { root.answer = previous; root.stale = true; }
        root.question = q;
        debounce.interval = Math.max(100, Config.options.search.ai.inlineDelayMs ?? 700);
        debounce.restart();
    }

    /** Stops the debounce and any request; clears the answer (parking a
        non-empty one for take()). */
    function cancel() {
        // Nothing armed, nothing to do: this is called on every keystroke of
        // every query, and the writes below re-evaluate every row's binding.
        if (!root.busy && !debounce.running && root.question.length === 0 && root.answer.length === 0 && root.errorNote.length === 0)
            return;
        debounce.stop();
        if (root.answer.length > 0 && !root.stale) { root.lastQuestion = root.question; root.lastAnswer = root.answer; root.lastModel = root.answerModel; }
        root.generation++;
        if (proc.running) proc.running = false;
        root.busy = false;
        root.done = false;
        root.stale = false;
        root.answer = "";
        root.errorNote = "";
        root.question = "";
        root.releaseMessages();
    }

    // The two AiMessageData a request mints are QObjects parented to this
    // singleton; without this they outlive every question for the life of
    // the shell.
    function releaseMessages() {
        if (root.answerMessage) { root.answerMessage.destroy(); root.answerMessage = null; }
        if (root.userMessage) { root.userMessage.destroy(); root.userMessage = null; }
    }

    /** The answer for `text` if there is one (complete or partial) and the
        model that gave it, as { answer, model }; cleared on the way out so
        Enter carries it into the chat exactly once. An empty answer means
        there was none. */
    function take(text) {
        const q = String(text ?? "").trim();
        let a = "", m = "";
        if (q === root.question && root.answer.length > 0 && !root.stale) { a = root.answer; m = root.answerModel; }
        else if (q === root.lastQuestion && root.lastAnswer.length > 0) { a = root.lastAnswer; m = root.lastModel; }
        root.cancel();
        root.lastQuestion = "";
        root.lastAnswer = "";
        root.lastModel = "";
        return { "answer": a, "model": m };
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
        root.releaseMessages();
        root.userMessage = messageComponent.createObject(root, {
            "role": "user", "content": root.question, "rawContent": root.question,
            "thinking": false, "done": true,
        });
        root.answerMessage = messageComponent.createObject(root, {
            "role": "assistant", "content": "", "rawContent": "", "thinking": false, "done": false,
        });
        root.answerModel = Ai.currentModelId;
        root.errorNote = "";
        const data = strategy.buildRequestData(model, [root.userMessage], root.systemPrompt, 0.2, [], []);
        const endpoint = strategy.buildEndpoint(model);
        const authHeader = strategy.buildAuthorizationHeader(root.apiKeyEnvVarName);
        // Same shape as Ai's request script, minus the file setup: the body
        // through a printf builtin into a file (no ARG_MAX), curl unbuffered,
        // a final newline so a one-blob answer is not dropped by SplitParser.
        // A cancel SIGTERMs the bash wrapper: the trap removes the body file
        // (it holds the typed question) and curl runs backgrounded under
        // `wait` so the trap fires at once and kills curl too - otherwise
        // curl only died at its next write, after the model had the question.
        const bodyFile = `/tmp/quickshell/ai/inline.${root.generation}.body.json`;
        let script = "#!/usr/bin/env bash\n";
        script += `mkdir -p /tmp/quickshell/ai\n`;
        script += `BODY_FILE='${bodyFile}'\n`;
        script += `CURL_PID=\n`;
        script += `trap 'rm -f "$BODY_FILE"; [ -n "$CURL_PID" ] && kill "$CURL_PID" 2>/dev/null' EXIT TERM INT\n`;
        script += `printf '%s' '${StringUtils.shellSingleQuoteEscape(JSON.stringify(data))}' > "$BODY_FILE"\n`;
        script += `curl --no-buffer -sS "${endpoint}" -H 'Content-Type: application/json'`
            + (authHeader ? ` ${authHeader}` : "") + ` --data @"$BODY_FILE" &\n`;
        script += `CURL_PID=$!\n`;
        script += `wait "$CURL_PID"\n`;
        script += `printf '\\n'\n`;
        script = strategy.finalizeScriptContent(script);
        proc.strategy = strategy;
        proc.generation = root.generation;
        proc.environment[root.apiKeyEnvVarName] = model.requires_key ? (Ai.apiKeys?.[model.key_id] ?? "") : "";
        proc.command = ["bash", "-c", script];
        root.busy = true;
        root.done = false;
        proc.running = true;
    }

    // The first clause of a server or curl message, cut on a word boundary
    // so the row never ends mid-word; "" when there is nothing short enough
    // to show (the caller keeps its generic sentence then).
    function clause(text) {
        const first = String(text ?? "").split(/[.\n]/)[0].trim();
        if (first.length === 0) return "";
        if (first.length <= 80) return first;
        const cut = first.slice(0, 80).replace(/\s\S*$/, "");
        return cut.length >= 20 ? cut + "…" : "";
    }

    function finish(cut) {
        root.busy = false;
        root.done = root.answer.length > 0;
        // The cut strips trailing whitespace and punctuation first, so a
        // sentence end never renders as ".…".
        if (cut && root.answer.length > 0) root.answer = root.answer.slice(0, root.maxChars).replace(/[\s.,;:!?…]+$/, "") + "…";
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
                // An error body is not an answer to show under the row; the
                // row says so instead of going blank.
                if (text.startsWith("**Error**") || text.startsWith("**Request failed**")) {
                    console.log(`[AiInline] ${text.slice(0, 200)}`);
                    root.answer = "";
                    root.stale = false;
                    // The server's own first clause rides along: it is what
                    // tells a bad key from a wrong endpoint.
                    const detail = root.clause(text.replace(/^\*\*[^*]*\*\*:?\s*/, ""));
                    root.errorNote = Translation.tr("No answer: %1").arg(detail.length > 0 ? detail : Translation.tr("the model returned an error"));
                    root.finish(false);
                    return;
                }
                const cleaned = text.replace(/\s+/g, " ").trim();
                if (cleaned.length > 0) root.stale = false;
                if (!root.stale) root.answer = cleaned;
                if (root.answer.length >= root.maxChars) { root.finish(true); return; }
                if (result.finished) root.finish(false);
            }
        }
        stderr: StdioCollector { id: procStderr }
        onExited: (exitCode, exitStatus) => {
            if (proc.generation !== root.generation) return;
            if (root.stale) { root.answer = ""; root.stale = false; }
            if (root.answer.length === 0 && root.errorNote.length === 0) {
                console.log(`[AiInline] request exited ${exitCode}: ${String(procStderr.text ?? "").trim().slice(0, 200)}`);
                const stderrLine = root.clause(String(procStderr.text ?? "").trim().split("\n").pop().replace(/^curl:\s*\(\d+\)\s*/, ""));
                root.errorNote = exitCode === 0
                    ? Translation.tr("No answer: the model sent nothing back.")
                    : Translation.tr("No answer: %1").arg(stderrLine.length > 0 ? stderrLine : Translation.tr("the model could not be reached"));
            }
            root.busy = false;
            root.done = root.answer.length > 0;
        }
    }
}
