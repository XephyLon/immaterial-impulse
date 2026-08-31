import QtQuick
import qs.modules.common.functions as CF

// Anthropic's Messages API (api_format "anthropic"): SSE with typed events.
// Text arrives as content_block_delta/text_delta, extended thinking as
// thinking_delta (routed into the same <think> blocks every dialect uses),
// tool calls as a content_block_start naming the tool followed by
// input_json_delta fragments - accumulated and flushed on message_stop or
// exit, the OpenAI dialect's hard-won grammar. Auth is x-api-key plus the
// pinned anthropic-version, and max_tokens is REQUIRED by the API, so a
// default rides along unless extraParams overrides it.
ApiStrategy {
    property bool isThinking: false
    property string pendingToolName: ""
    property string pendingToolArgs: ""
    property bool sawToolUse: false

    function reset() {
        isThinking = false;
        pendingToolName = "";
        pendingToolArgs = "";
        sawToolUse = false;
    }

    function takePendingToolCall() {
        if (pendingToolName.length === 0) return null;
        let parsed = {};
        try { parsed = JSON.parse(pendingToolArgs.length > 0 ? pendingToolArgs : "{}"); } catch (e) { /* shards */ }
        const call = { "name": pendingToolName, "args": parsed };
        pendingToolName = "";
        pendingToolArgs = "";
        return call;
    }

    // Indexed per attachment, the OpenAI dialect's placeholder trick: the
    // media type and base64 are only knowable in bash at send time.
    function fileMediaSubstitutionString(i) { return `__IMI_ANTHROPIC_FILE_MEDIA_${i}__`; }
    function fileB64SubstitutionString(i) { return `__IMI_ANTHROPIC_FILE_B64_${i}__`; }
    function fileMediaVarName(i) { return `IMI_ANTHROPIC_FILE_MEDIA_${i}`; }
    function fileB64VarName(i) { return `IMI_ANTHROPIC_FILE_B64_${i}`; }
    readonly property int maxAttachments: 16

    function buildEndpoint(model: AiModel): string {
        return model.endpoint;
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        return `-H "x-api-key: \$\{${apiKeyEnvVarName}\}" -H "anthropic-version: 2023-06-01"`;
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePaths) {
        const mapped = messages
            .filter(m => m.role === "user" || m.role === "assistant")
            .map(m => ({ "role": m.role, "content": m.rawContent }));
        const files = (filePaths ?? []).slice(0, maxAttachments);
        if (files.length > 0 && mapped.length > 0) {
            const last = mapped[mapped.length - 1];
            last.content = [
                { "type": "text", "text": last.content },
                ...files.map((_, i) => ({ "type": "image", "source": {
                    "type": "base64",
                    "media_type": fileMediaSubstitutionString(i),
                    "data": fileB64SubstitutionString(i)
                } }))
            ];
        }
        let baseData = {
            "model": model.model,
            "max_tokens": 4096, // required by the API
            "system": systemPrompt,
            "messages": mapped,
            "stream": true,
            "temperature": temperature,
        };
        if ((tools ?? []).length > 0) baseData["tools"] = tools;
        return model.extraParams ? Object.assign({}, baseData, model.extraParams) : baseData;
    }

    function buildScriptFileSetup(filePaths) {
        let content = "";
        (filePaths ?? []).slice(0, maxAttachments).forEach((filePath, i) => {
            const trimmed = CF.FileUtils.trimFileProtocol(filePath);
            content += `IMAGE_PATH_${i}='${CF.StringUtils.shellSingleQuoteEscape(trimmed)}'\n`;
            content += `${fileMediaVarName(i)}=$(file -b --mime-type "$IMAGE_PATH_${i}")\n`;
            content += `${fileB64VarName(i)}=$(base64 -w0 "$IMAGE_PATH_${i}")\n`;
        });
        return content;
    }

    function finalizeScriptContent(scriptContent: string): string {
        for (let i = 0; i < maxAttachments; i++) {
            if (scriptContent.indexOf(fileMediaSubstitutionString(i)) === -1) break;
            scriptContent = scriptContent.replace(fileMediaSubstitutionString(i), `'"\$${fileMediaVarName(i)}"'`)
                                         .replace(fileB64SubstitutionString(i), `'"\$${fileB64VarName(i)}"'`);
        }
        return scriptContent;
    }

    function parseResponseLine(line, message) {
        let cleanData = line.trim();
        if (cleanData.startsWith("event:")) return {};
        if (cleanData.startsWith("data:")) cleanData = cleanData.slice(5).trim();
        if (!cleanData || cleanData.startsWith(":")) return {};

        try {
            const dataJson = JSON.parse(cleanData);

            if (dataJson.type === "error" || dataJson.error) {
                const err = dataJson.error ?? {};
                const errorMsg = `**Error**: ${err.message || JSON.stringify(err)}`;
                message.rawContent += errorMsg;
                message.content += errorMsg;
                return { finished: true };
            }

            if (dataJson.type === "content_block_start") {
                const block = dataJson.content_block ?? {};
                if (block.type === "tool_use") {
                    sawToolUse = true;
                    pendingToolName = block.name ?? "";
                    pendingToolArgs = "";
                }
                return {};
            }

            if (dataJson.type === "content_block_delta") {
                const delta = dataJson.delta ?? {};
                if (delta.type === "input_json_delta") {
                    pendingToolArgs += delta.partial_json ?? "";
                    return {};
                }
                let newContent = "";
                if (delta.type === "thinking_delta" && (delta.thinking ?? "").length > 0) {
                    if (!isThinking) {
                        isThinking = true;
                        const startBlock = "\n\n<think>\n\n";
                        message.rawContent += startBlock;
                        message.content += startBlock;
                    }
                    newContent = delta.thinking;
                } else if ((delta.text ?? "").length > 0) {
                    if (isThinking) {
                        isThinking = false;
                        const endBlock = "\n\n</think>\n\n";
                        message.content += endBlock;
                        message.rawContent += endBlock;
                    }
                    newContent = delta.text;
                }
                message.content += newContent;
                message.rawContent += newContent;
                return {};
            }

            if (dataJson.type === "message_delta" && dataJson.usage) {
                return { tokenUsage: {
                    input: dataJson.usage.input_tokens ?? -1,
                    output: dataJson.usage.output_tokens ?? -1,
                    total: (dataJson.usage.input_tokens ?? 0) + (dataJson.usage.output_tokens ?? 0)
                } };
            }

            if (dataJson.type === "message_stop") {
                const call = takePendingToolCall();
                return call ? { functionCall: call, finished: true } : { finished: true };
            }
        } catch (e) {
            console.log("[AI] Anthropic: Could not parse line: ", e);
        }
        return {};
    }

    function onRequestFinished(message) {
        // A stream that ended without message_stop still owes its call.
        const call = takePendingToolCall();
        return call ? { functionCall: call, finished: true } : {};
    }
}
