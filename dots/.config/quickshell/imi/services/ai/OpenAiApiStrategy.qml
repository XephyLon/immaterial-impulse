import QtQuick
import qs.modules.common.functions as CF

ApiStrategy {
    property bool isReasoning: false
    // Streamed tool calls arrive as fragments - a name in one delta,
    // argument shards across many - and this dialect used to drop them
    // all on the floor: no OpenAI-format model could ever call a
    // function. Accumulated here, emitted when the stream ends.
    property string pendingToolName: ""
    property string pendingToolArgs: ""

    function reset() {
        isReasoning = false;
        pendingToolName = "";
        pendingToolArgs = "";
    }

    function takePendingToolCall() {
        if (pendingToolName.length === 0) return null;
        let parsed = {};
        try { parsed = JSON.parse(pendingToolArgs.length > 0 ? pendingToolArgs : "{}"); } catch (e) { /* shards, not JSON */ }
        const call = { "name": pendingToolName, "args": parsed };
        pendingToolName = "";
        pendingToolArgs = "";
        return call;
    }
    
    function buildEndpoint(model: AiModel): string {
        // console.log("[AI] Endpoint: " + model.endpoint);
        return model.endpoint;
    }

    // Placeholders the request JSON carries until the script substitutes
    // them with shell variables - the Gemini strategy's trick, because the
    // file's mime and base64 are only knowable in bash at send time.
    // Indexed per attachment: file N's placeholders name shell variables
    // the script setup defines for exactly the files of this request.
    function fileMimeSubstitutionString(i) { return `__IMI_OPENAI_FILE_MIME_${i}__`; }
    function fileB64SubstitutionString(i) { return `__IMI_OPENAI_FILE_B64_${i}__`; }
    function fileMimeVarName(i) { return `IMI_OPENAI_FILE_MIME_${i}`; }
    function fileB64VarName(i) { return `IMI_OPENAI_FILE_B64_${i}`; }
    readonly property int maxAttachments: 16

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePaths) {
        const mapped = messages.map(message => {
            return {
                "role": message.role,
                "content": message.rawContent,
            }
        });
        // An attached image rides the LAST message (the one being sent) as
        // OpenAI vision content parts - a data URL whose mime and base64
        // the script substitutes in. Messages without a file stay plain
        // strings: some servers reject part-arrays they never needed.
        const files = (filePaths ?? []).slice(0, maxAttachments);
        if (files.length > 0 && mapped.length > 0) {
            const last = mapped[mapped.length - 1];
            last.content = [
                { "type": "text", "text": last.content },
                ...files.map((_, i) => ({ "type": "image_url", "image_url": {
                    "url": `data:${fileMimeSubstitutionString(i)};base64,${fileB64SubstitutionString(i)}` } }))
            ];
        }
        let baseData = {
            "model": model.model,
            "messages": [
                {role: "system", content: systemPrompt},
                ...mapped,
            ],
            "stream": true,
            "tools": tools,
            "temperature": temperature,
        };
        // Opt-in reasoning ask (OpenRouter grammar); gated on the model
        // DECLARING thinking, because a strict server 400s on unknown
        // fields. R1-style servers stream reasoning_content unasked and the
        // parser below routes it either way; extraParams still win.
        if (model.thinking)
            baseData["reasoning"] = { "effort": "medium" };
        return model.extraParams ? Object.assign({}, baseData, model.extraParams) : baseData;
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        return `-H "Authorization: Bearer \$\{${apiKeyEnvVarName}\}"`;
    }

    function buildScriptFileSetup(filePaths) {
        let content = "";
        (filePaths ?? []).slice(0, maxAttachments).forEach((filePath, i) => {
            const trimmed = CF.FileUtils.trimFileProtocol(filePath);
            content += `IMAGE_PATH_${i}='${CF.StringUtils.shellSingleQuoteEscape(trimmed)}'\n`;
            content += `${fileMimeVarName(i)}=$(file -b --mime-type "$IMAGE_PATH_${i}")\n`;
            content += `${fileB64VarName(i)}=$(base64 -w0 "$IMAGE_PATH_${i}")\n`;
        });
        return content;
    }

    function finalizeScriptContent(scriptContent: string): string {
        // The '"$VAR"' splice closes the --data single quote, drops in the
        // shell variable double-quoted, and reopens - Gemini's exact shape.
        // One pass per attachment index actually present.
        for (let i = 0; i < maxAttachments; i++) {
            if (scriptContent.indexOf(fileMimeSubstitutionString(i)) === -1) break;
            scriptContent = scriptContent.replace(fileMimeSubstitutionString(i), `'"\$${fileMimeVarName(i)}"'`)
                                         .replace(fileB64SubstitutionString(i), `'"\$${fileB64VarName(i)}"'`);
        }
        return scriptContent;
    }

    function parseResponseLine(line, message) {
        // Remove 'data: ' prefix if present and trim whitespace
        let cleanData = line.trim();
        if (cleanData.startsWith("data:")) {
            cleanData = cleanData.slice(5).trim();
        }

        // console.log("[AI] OpenAI: Data:", cleanData);
        
        // Handle special cases
        if (!cleanData || cleanData.startsWith(":")) return {};
        if (cleanData === "[DONE]") {
            const call = takePendingToolCall();
            return call ? { functionCall: call, finished: true } : { finished: true };
        }
        
        // Real stuff
        try {
            const dataJson = JSON.parse(cleanData);

            // Error response handling
            if (dataJson.error) {
                const errorMsg = `**Error**: ${dataJson.error.message || JSON.stringify(dataJson.error)}`;
                message.rawContent += errorMsg;
                message.content += errorMsg;
                return { finished: true };
            }

            // Streamed fragments (delta) or a whole call in one chunk
            // (message) - servers use either shape.
            const toolCalls = dataJson.choices?.[0]?.delta?.tool_calls
                ?? dataJson.choices?.[0]?.message?.tool_calls;
            if (toolCalls && toolCalls.length > 0) {
                for (const tc of toolCalls) {
                    const fn = tc.function ?? {};
                    if (fn.name) pendingToolName += fn.name;
                    if (fn.arguments) pendingToolArgs += fn.arguments;
                }
            }
            // Servers that skip [DONE] end the call with a finish_reason.
            if (dataJson.choices?.[0]?.finish_reason === "tool_calls") {
                const call = takePendingToolCall();
                if (call) return { functionCall: call, finished: true };
            }

            // Inline images: some servers answer a generation request from
            // the CHAT model itself, as delta.images data URLs (observed
            // live from gpt-5.6-sol) - one colossal base64 line the dialect
            // used to ignore entirely, leaving an empty message.
            const images = dataJson.choices?.[0]?.delta?.images
                ?? dataJson.choices?.[0]?.message?.images;
            if (images && images.length > 0) {
                const inline = [];
                for (const img of images) {
                    const url = img.image_url?.url ?? img.url ?? "";
                    if (url.length > 0) inline.push(url);
                }
                if (inline.length > 0) return { inlineImages: inline };
            }

            let newContent = "";

            const responseContent = dataJson.choices[0]?.delta?.content || dataJson.message?.content;
            const responseReasoning = dataJson.choices[0]?.delta?.reasoning || dataJson.choices[0]?.delta?.reasoning_content;

            if (responseContent && responseContent.length > 0) {
                if (isReasoning) {
                    isReasoning = false;
                    const endBlock = "\n\n</think>\n\n";
                    message.content += endBlock;
                    message.rawContent += endBlock;
                }
                newContent = responseContent;
            } else if (responseReasoning && responseReasoning.length > 0) {
                if (!isReasoning) {
                    isReasoning = true;
                    const startBlock = "\n\n<think>\n\n";
                    message.rawContent += startBlock;
                    message.content += startBlock;
                }
                newContent = responseReasoning;
            }

            message.content += newContent;
            message.rawContent += newContent;

            // Usage metadata
            if (dataJson.usage) {
                return {
                    tokenUsage: {
                        input: dataJson.usage.prompt_tokens ?? -1,
                        output: dataJson.usage.completion_tokens ?? -1,
                        total: dataJson.usage.total_tokens ?? -1
                    }
                };
            }

            if (dataJson.done) {
                return { finished: true };
            }
            
        } catch (e) {
            console.log("[AI] OpenAI: Could not parse line: ", e);
            message.rawContent += line;
            message.content += line;
        }
        
        return {};
    }
    
    function onRequestFinished(message) {
        // A stream that ended without [DONE] or a tool_calls finish_reason
        // still owes its accumulated call - this is the flush of last
        // resort, which is exactly where a proxy that just closes the
        // connection lands.
        const call = takePendingToolCall();
        return call ? { functionCall: call, finished: true } : {};
    }
    
}
