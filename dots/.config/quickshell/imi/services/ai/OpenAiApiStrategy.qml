import QtQuick
import qs.modules.common.functions as CF

ApiStrategy {
    property bool isReasoning: false
    
    function buildEndpoint(model: AiModel): string {
        // console.log("[AI] Endpoint: " + model.endpoint);
        return model.endpoint;
    }

    // Placeholders the request JSON carries until the script substitutes
    // them with shell variables - the Gemini strategy's trick, because the
    // file's mime and base64 are only knowable in bash at send time.
    readonly property string fileMimeSubstitutionString: "__IMI_OPENAI_FILE_MIME__"
    readonly property string fileB64SubstitutionString: "__IMI_OPENAI_FILE_B64__"
    readonly property string fileMimeVarName: "IMI_OPENAI_FILE_MIME"
    readonly property string fileB64VarName: "IMI_OPENAI_FILE_B64"

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string) {
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
        if (filePath && filePath.length > 0 && mapped.length > 0) {
            const last = mapped[mapped.length - 1];
            last.content = [
                { "type": "text", "text": last.content },
                { "type": "image_url", "image_url": {
                    "url": `data:${fileMimeSubstitutionString};base64,${fileB64SubstitutionString}` } }
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

    function buildScriptFileSetup(filePath) {
        const trimmed = CF.FileUtils.trimFileProtocol(filePath);
        let content = "";
        content += `IMAGE_PATH='${CF.StringUtils.shellSingleQuoteEscape(trimmed)}'\n`;
        content += `${fileMimeVarName}=$(file -b --mime-type "$IMAGE_PATH")\n`;
        content += `${fileB64VarName}=$(base64 -w0 "$IMAGE_PATH")\n`;
        return content;
    }

    function finalizeScriptContent(scriptContent: string): string {
        // The '"$VAR"' splice closes the --data single quote, drops in the
        // shell variable double-quoted, and reopens - Gemini's exact shape.
        return scriptContent.replace(fileMimeSubstitutionString, `'"\$${fileMimeVarName}"'`)
                            .replace(fileB64SubstitutionString, `'"\$${fileB64VarName}"'`);
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
            return { finished: true };
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
        // OpenAI format doesn't need special finish handling
        return {};
    }
    
    function reset() {
        isReasoning = false;
    }

}
