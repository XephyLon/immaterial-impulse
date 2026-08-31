pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common.functions as CF
import qs.modules.common
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.services.ai
import "./ai/model_curation.js" as Curation
import "./ai/ai_personas.js" as PersonasFold
import "./ai/ai_sessions.js" as SessionsFold
import "AiModelsParser.js" as AiModelsParser

/**
 * Basic service to handle LLM chats. Supports Google's and OpenAI's API formats.
 * Supports Gemini and OpenAI models.
 * Limitations:
 * - For now functions only work with Gemini API format
 */
Singleton {
    id: root

    property Component aiMessageComponent: AiMessageData {}
    property Component aiModelComponent: AiModel {}
    property Component geminiApiStrategy: GeminiApiStrategy {}
    property Component openaiApiStrategy: OpenAiApiStrategy {}
    property Component mistralApiStrategy: MistralApiStrategy {}
    property Component anthropicApiStrategy: AnthropicApiStrategy {}
    readonly property string interfaceRole: "interface"
    readonly property string apiKeyEnvVarName: "API_KEY"

    signal responseFinished()

    property string systemPrompt: {
        // The active persona's prompt wins over the free-text card; the
        // memory block rides along either way.
        let prompt = PersonasFold.effectivePrompt(AiPersonas.active,
            Config.options?.ai?.systemPrompt ?? "");
        if (AiMemory.promptBlock.length > 0)
            prompt += "\n\n" + AiMemory.promptBlock;
        for (let key in root.promptSubstitutions) {
            // prompt = prompt.replaceAll(key, root.promptSubstitutions[key]);
            // QML/JS doesn't support replaceAll, so use split/join
            prompt = prompt.split(key).join(root.promptSubstitutions[key]);
        }
        return prompt;
    }
    // property var messages: []
    property var messageIDs: []
    property var messageByID: ({})
    readonly property var apiKeys: KeyringStorage.keyringData?.apiKeys ?? {}
    readonly property var apiKeysLoaded: KeyringStorage.loaded
    readonly property bool currentModelHasApiKey: {
        const model = models[currentModelId];
        if (!model || !model.requires_key) return true;
        if (!apiKeysLoaded) return false;
        const key = apiKeys[model.key_id];
        return (key?.length > 0);
    }
    property var postResponseHook
    property real temperature: Persistent.states?.ai?.temperature ?? 0.5
    property QtObject tokenCount: QtObject {
        property int input: -1
        property int output: -1
        property int total: -1
    }

    function idForMessage(message) {
        // Generate a unique ID using timestamp and random value
        return Date.now().toString(36) + Math.random().toString(36).substr(2, 8);
    }

    function safeModelName(modelName) {
        return modelName.replace(/:/g, "_").replace(/ /g, "-").replace(/\//g, "-")
    }

    property list<var> defaultPrompts: []
    property list<var> userPrompts: []
    property list<var> promptFiles: [...defaultPrompts, ...userPrompts]
    property list<var> savedChats: []

    property var promptSubstitutions: {
        "{DISTRO}": SystemInfo.distroName,
        "{DATETIME}": `${DateTime.time}, ${DateTime.collapsedCalendarFormat}`,
        "{WINDOWCLASS}": ToplevelManager.activeToplevel?.appId ?? "Unknown",
        "{DE}": `${SystemInfo.desktopEnvironment} (${SystemInfo.windowingSystem})` 
    }

    // Gemini: https://ai.google.dev/gemini-api/docs/function-calling
    // OpenAI: https://platform.openai.com/docs/guides/function-calling
    property string currentTool: Config?.options.ai.tool ?? "search"
    // Rendered from ONE declaration per tool (AiToolRegistry) instead of
    // three hand-kept copies that had already drifted - gemini never
    // learned generate_image until this landed.
    property var tools: {
        "gemini": {
            "functions": [{ "functionDeclarations": AiToolRegistry.geminiDeclarations }],
            "search": [{ "google_search": {} }],
            "none": []
        },
        "openai": {
            "functions": AiToolRegistry.openAiTools("openai"),
            "search": [],
            "none": []
        },
        "mistral": {
            "functions": AiToolRegistry.openAiTools("mistral"),
            "search": [],
            "none": []
        },
        "anthropic": {
            "functions": AiToolRegistry.anthropicTools,
            "search": [],
            "none": []
        }
    }
    // models is empty until the model list finishes loading, so the tool table
    // lookup has to tolerate an unresolved api_format.
    property list<var> availableTools: Object.keys(root.tools[models[currentModelId]?.api_format] ?? {})
    property var toolDescriptions: {
        "functions": Translation.tr("Commands, edit configs, search.\nTakes an extra turn to switch to search mode if that's needed"),
        "search": Translation.tr("Gives the model search capabilities (immediately)"),
        "none": Translation.tr("Disable tools")
    }

    // Model properties:
    // - name: Name of the model
    // - icon: Icon name of the model
    // - description: Description of the model
    // - endpoint: Endpoint of the model
    // - model: Model name of the model
    // - requires_key: Whether the model requires an API key
    // - key_id: The identifier of the API key. Use the same identifier for models that can be accessed with the same key.
    // - key_get_link: Link to get an API key
    // - key_get_description: Description of pricing and how to get an API key
    // - api_format: The API format of the model. Can be "openai" or "gemini". Default is "openai".
    // - extraParams: Extra parameters to be passed to the model. This is a JSON object.
    // No built-in models (maintainer's call, 2026-08-31): the user brings
    // OpenAI-compatible providers (or a local ollama), and the chat says so
    // when none exist. The dialect strategies stay - a provider is free to
    // speak any of them.
    property var models: ({})
    property var modelList: Object.keys(root.models)
    // The picker's list: hand-rolled and imported models always surface;
    // a provider-fetched model surfaces by its provider's curation - an
    // empty selectedModels surfaces the lot (spec 2026-08-31).
    readonly property var pickerModelList: root.modelList.filter(id => {
        const m = root.models[id];
        const idx = Curation.providerIndexOf(m?.key_id);
        if (idx < 0) return true;
        return Curation.isSurfaced(
            Config.options.ai.customProviders?.[idx]?.selectedModels, m.model);
    })

    // What the composer's Up key recalls: the prompts someone actually
    // typed into THIS chat - user role, visible, non-empty - in order.
    // Hidden carriers (tool outputs, silent instructions) are not prompts.
    // The busy signal two guards already read (the transcript reveal and
    // editAndResend) - which turned out to be reading an UNDEFINED name
    // since the reveal landed: undefined is falsy, so the guard was
    // silently inert. The requester process's lifetime is the answer.
    readonly property bool isGenerating: requester.running || simTimer.running

    /** A generation the tool path queued while the chat stream was still
        running; launched by onExited once the requester is free. */
    property var pendingImageGeneration: null
    /** A follow-up request queued the same way (a tool answered and the
        model should continue). */
    property bool pendingContinuation: false

    /** Ends the current generation - network or simulated - marking the
        message done so every done-gated surface settles normally. */
    function stopGeneration() {
        root.pendingImageGeneration = null;
        root.pendingContinuation = false;
        if (simTimer.running) {
            simTimer.stop();
            root.simRemaining = "";
            if (root.simMessage) root.simMessage.done = true;
            AiSessions.scheduleSave();
        }
        if (requester.running) requester.running = false; // onExited marks done
    }

    readonly property var ownPromptHistory: {
        const list = [];
        for (let i = 0; i < root.messageIDs.length; i++) {
            const message = root.messageByID[root.messageIDs[i]];
            if (message?.role !== "user" || message.visibleToUser === false)
                continue;
            const text = String(message.rawContent ?? message.content ?? "").trim();
            if (text.length > 0)
                list.push(text);
        }
        return list;
    }
    property var currentModelId: Persistent.states?.ai?.model || modelList[0]

    property var apiStrategies: {
        "openai": openaiApiStrategy.createObject(this),
        "gemini": geminiApiStrategy.createObject(this),
        "mistral": mistralApiStrategy.createObject(this),
        "anthropic": anthropicApiStrategy.createObject(this),
    }
    property ApiStrategy currentApiStrategy: apiStrategies[models[currentModelId]?.api_format || "openai"]

    function addUserModels() {
        (Config?.options.ai?.extraModels ?? []).forEach(model => {
            const safeModelName = root.safeModelName(model["model"]);
            root.addModel(safeModelName, model)
        });
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (!Config.ready) return;
            root.addUserModels()
        }
    }

    property string requestScriptFilePath: "/tmp/quickshell/ai/request.sh"
    property list<string> pendingFilePaths: []

    Component.onCompleted: {
        setModel(currentModelId, false, false); // Do necessary setup for model
        root.addUserModels() // Config onReadyChanged above might not fire if config is loaded before this service
        // Same creation-order gap as the line above: wantsCustomModels can
        // be TRUE from birth (Config already ready), and a binding that is
        // born true never fires its change handler - so the auto-fetch
        // needs this kick as well as the handler.
        if (root.wantsCustomModels) root.fetchCustomModels()
    }

    function guessModelLogo(model) {
        if (model.includes("llama")) return "ollama-symbolic";
        if (model.includes("gemma")) return "google-gemini-symbolic";
        if (model.includes("deepseek")) return "deepseek-symbolic";
        if (/^phi\d*:/i.test(model)) return "microsoft-symbolic";
        return "ollama-symbolic";
    }

    function guessModelName(model) {
        const replaced = model.replace(/-/g, ' ').replace(/:/g, ' ');
        let words = replaced.split(' ');
        words[words.length - 1] = words[words.length - 1].replace(/(\d+)b$/, (_, num) => `${num}B`)
        words = words.map((word) => {
            return (word.charAt(0).toUpperCase() + word.slice(1))
        });
        if (words[words.length - 1] === "Latest") words.pop();
        else words[words.length - 1] = `(${words[words.length - 1]})`; // Surround the last word with square brackets
        const result = words.join(' ');
        return result;
    }

    property string customProviderFeedbackText: ""

    Component {
        id: customModelFetcherComponent
        Process {
            id: fetcherProcess
            property string baseUrl
            property string apiKey
            property string providerName
            property int providerIndex
            // "openai" (Bearer, /models, chat/completions entries) or
            // "anthropic" (x-api-key + version header, /models, /messages
            // entries) - the provider card's own type.
            property string providerType: "openai"
            
            // Positional args ($1/$2), never spliced into the script body: apiKey
            // is a secret and baseUrl comes from custom-provider config (which flows
            // through shareable presets), so interpolating them into a double-quoted
            // bash string - where $()/backticks expand - was a command-injection hole.
            // The status code rides on the last line, so a failure can say
            // what it was: the old "Failed to fetch" covered a 404 from a
            // base URL that already ended in /models, a 401 from a missing
            // key and a server that was not there, and a reader could act on
            // none of them.
            command: providerType === "anthropic"
                ? ["bash", "-c", 'curl -sL --max-time 10 -H "x-api-key: $1" -H "anthropic-version: 2023-06-01" -w "\n%{http_code}" "$2/models" 2>/dev/null', "bash", apiKey, baseUrl]
                : ["bash", "-c", 'curl -sL --max-time 10 -H "Authorization: Bearer $1" -w "\n%{http_code}" "$2/models" 2>/dev/null', "bash", apiKey, baseUrl]
            stdout: StdioCollector {
                onStreamFinished: {
                    const cut = text.lastIndexOf("\n");
                    const status = cut >= 0 ? parseInt(text.slice(cut + 1), 10) : 0;
                    const body = cut >= 0 ? text.slice(0, cut) : "";
                    const where = `${fetcherProcess.baseUrl}/models`;
                    if (!status) {
                        root.customProviderFeedbackText = Translation.tr("No response from %1 at %2 - unreachable, or it took more than 10s.").arg(fetcherProcess.providerName).arg(where);
                        return;
                    }
                    if (status === 401 || status === 403) {
                        root.customProviderFeedbackText = Translation.tr("%1 refused the request (HTTP %2) - check its API key.").arg(fetcherProcess.providerName).arg(status);
                        return;
                    }
                    if (status === 404) {
                        root.customProviderFeedbackText = Translation.tr("%1 has nothing at %2 (HTTP 404) - the base URL should end where /models is appended, usually at /v1.").arg(fetcherProcess.providerName).arg(where);
                        return;
                    }
                    if (status < 200 || status >= 300) {
                        root.customProviderFeedbackText = Translation.tr("HTTP %2 from %1 at %3.").arg(fetcherProcess.providerName).arg(status).arg(where);
                        return;
                    }
                    const parsedModels = fetcherProcess.providerType === "anthropic"
                        ? AiModelsParser.parseAnthropicProviderModels(body, fetcherProcess.baseUrl, fetcherProcess.providerName, `custom_provider_${fetcherProcess.providerIndex}`)
                        : AiModelsParser.parseCustomProviderModels(body, fetcherProcess.baseUrl, fetcherProcess.providerName, `custom_provider_${fetcherProcess.providerIndex}`);
                    if (parsedModels.length > 0) {
                        parsedModels.forEach(model => {
                            const safeModelName = root.safeModelName(model.model);
                            root.addModel(safeModelName, model);
                        });
                        root.modelList = Object.keys(root.models);
                        root.customProviderFeedbackText = Translation.tr("Successfully fetched from %1.").arg(fetcherProcess.providerName);
                    } else {
                        root.customProviderFeedbackText = Translation.tr("No models found from %1.").arg(fetcherProcess.providerName);
                    }
                }
            }
            onExited: {
                Qt.callLater(() => fetcherProcess.destroy());
            }
        }
    }

    // The keyring is loaded on demand, and until this asked for it nothing on
    // this path did: with a local model selected nothing else loads it, so a
    // custom provider's key read as "" and every fetch went out with an empty
    // bearer - a 401 the page called "Failed to fetch", whatever key the user
    // had typed. Ask, and run once it is here.
    property bool customFetchWaitingForKeyring: false
    readonly property Connections keyringArrival: Connections {
        target: KeyringStorage
        function onLoadedChanged() {
            if (KeyringStorage.loaded && root.customFetchWaitingForKeyring) {
                root.customFetchWaitingForKeyring = false;
                root.fetchCustomModels();
            }
        }
    }
    // Custom providers auto-fetch (maintainer's ask): their models arrive
    // at startup and whenever a provider is enabled, instead of waiting
    // behind the editor's Fetch button. Gated on an ENABLED provider
    // existing, so nobody gets a keyring prompt for a feature they never
    // configured; the keyringArrival arm above finishes the job once the
    // keyring answers.
    readonly property bool wantsCustomModels: Config.ready
        && (Config.options.ai.customProviders || []).some(p => p.enabled)
    onWantsCustomModelsChanged: if (root.wantsCustomModels) root.fetchCustomModels()

    function fetchCustomModels() {
        if (!KeyringStorage.loaded) {
            customProviderFeedbackText = Translation.tr("Unlocking the keyring...");
            root.customFetchWaitingForKeyring = true;
            KeyringStorage.fetchKeyringData();
            return;
        }
        customProviderFeedbackText = Translation.tr("Fetching models...");
        let providers = Config.options.ai.customProviders || [];
        let anyEnabled = false;
        
        for (let i = 0; i < providers.length; i++) {
            let provider = providers[i];
            if (!provider.enabled) continue;
            anyEnabled = true;
            let fetcher = customModelFetcherComponent.createObject(root, {
                baseUrl: AiModelsParser.normalizeBaseUrl(provider.baseUrl || ""),
                apiKey: KeyringStorage.loaded ? (KeyringStorage.keyringData.apiKeys?.[`custom_provider_${i}`] || "") : "",
                providerName: provider.name || "Custom",
                providerIndex: i,
                providerType: provider.type || "openai"
            });
            fetcher.running = true;
        }
        
        if (!anyEnabled) {
            customProviderFeedbackText = Translation.tr("No custom providers enabled.");
        }
    }

    function addModel(modelName, data) {
        root.models = Object.assign({}, root.models, {
            [modelName]: aiModelComponent.createObject(this, data)
        });
    }

    Process {
        id: getOllamaModels
        running: true
        command: ["bash", "-c", `${Directories.scriptPath}/ai/show-installed-ollama-models.sh`.replace(/file:\/\//, "")]
        stdout: SplitParser {
            onRead: data => {
                try {
                    if (data.length === 0) return;
                    const dataJson = JSON.parse(data);
                    root.modelList = [...root.modelList, ...dataJson];
                    dataJson.forEach(model => {
                        const safeModelName = root.safeModelName(model);
                        root.addModel(safeModelName, {
                            "name": guessModelName(model),
                            "icon": guessModelLogo(model),
                            "description": Translation.tr("Local Ollama model | %1").arg(model),
                            "homepage": `https://ollama.com/library/${model}`,
                            "endpoint": "http://localhost:11434/v1/chat/completions",
                            "model": model,
                            "requires_key": false,
                        })
                    });

                    root.modelList = Object.keys(root.models);

                } catch (e) {
                    console.log("Could not fetch Ollama models:", e);
                }
            }
        }
    }

    Process {
        id: getDefaultPrompts
        running: true
        command: ["ls", "-1", Directories.defaultAiPrompts]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.defaultPrompts = text.split("\n")
                    .filter(fileName => fileName.endsWith(".md") || fileName.endsWith(".txt"))
                    .map(fileName => `${Directories.defaultAiPrompts}/${fileName}`)
            }
        }
    }

    Process {
        id: getUserPrompts
        running: true
        command: ["ls", "-1", Directories.userAiPrompts]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.userPrompts = text.split("\n")
                    .filter(fileName => fileName.endsWith(".md") || fileName.endsWith(".txt"))
                    .map(fileName => `${Directories.userAiPrompts}/${fileName}`)
            }
        }
    }

    Process {
        id: getSavedChats
        running: true
        command: ["ls", "-1", Directories.aiChats]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.savedChats = text.split("\n")
                    .filter(fileName => fileName.endsWith(".json"))
                    .map(fileName => `${Directories.aiChats}/${fileName}`)
            }
        }
    }

    FileView {
        id: promptLoader
        watchChanges: false;
        onLoadedChanged: {
            if (!promptLoader.loaded) return;
            Config.options.ai.systemPrompt = promptLoader.text();
            root.addMessage(Translation.tr("Loaded the following system prompt\n\n---\n\n%1").arg(Config.options.ai.systemPrompt), root.interfaceRole);
        }
    }

    function printPrompt() {
        root.addMessage(Translation.tr("The current system prompt is\n\n---\n\n%1").arg(Config.options.ai.systemPrompt), root.interfaceRole);
    }

    function loadPrompt(filePath) {
        promptLoader.path = "" // Unload
        promptLoader.path = filePath; // Load
        promptLoader.reload();
    }

    // /test's sample: long enough that streaming spans many viewports -
    // short samples finished before scroll, coalescer and shimmer ever
    // interacted, which is where the stutter lived.
    readonly property string testStreamText: `
<think>
A longer think block to test revealing animation
OwO wem ipsum dowo sit amet, consekituwet awipiscing ewit, sed do eiuwsmod tempow inwididunt ut wabowe et dowo mawa. Ut enim ad minim weniam, quis nostwud exeucitation uwuwamcow bowowis nisi ut awiquip ex ea commowo consequat. Duuis aute iwuwe dowo in wepwependewit in wowuptate velit esse ciwwum dowo eu fugiat nuwa pawiatuw. Excepteuw sint occaecat cupidatat non pwowoident, sunt in cuwpa qui officia desewunt mowit anim id est wabowum. Meouw! >w<
Mowe uwu wem ipsum!
</think>
## ✏️ Markdown test
### Formatting

- *Italic*, \`Monospace\`, **Bold**, [Link](https://example.com)

### Prose

Streaming text is judged on its worst paragraph, not its best. A renderer that looks composed while short bullets tick in can still fall apart when a long unbroken paragraph grows word by word, because every appended chunk re-wraps the whole block and every re-wrap is a chance to shift lines the reader is in the middle of. This paragraph exists to be that stress: long, plain, unbroken, and steadily growing.

The second stress is the follow scroll. While content grows past the viewport the view must advance at the speed the content demands - too eager and the text the reader is on slides out from under them, too lazy and the growth pools invisibly below the fold until it arrives as a lurch. The right behavior is a chase that keeps its velocity across retargets instead of restarting its easing curve on every chunk.

The third stress is mixed content. A stream rarely stays one shape for long: prose gives way to a table, the table to code, the code back to prose, and each transition changes the block structure the renderer has to keep stable. The stable-prefix split means settled blocks never re-render - only the tail is live - and this section exercises exactly that boundary, block after block.

A fourth paragraph, because three is a pattern and four is a test. By the time this text arrives, the transcript is several viewports tall, the earliest blocks are far above the fold, and any accidental whole-transcript work would show up as a frame spike right about here. If the motion still reads as one continuous glide, the coalescer and the chase are doing their jobs.

### Table

Quickshell vs AGS/Astal

|                          | Quickshell       | AGS/Astal         |
|--------------------------|------------------|-------------------|
| UI Toolkit               | Qt               | Gtk3/Gtk4         |
| Language                 | QML              | Js/Ts/Lua         |
| Reactivity               | Implied          | Needs declaration |
| Widget placement         | Mildly difficult | More intuitive    |
| Bluetooth & Wifi support | ❌               | ✅                |
| No-delay keybinds        | ✅               | ❌                |
| Development              | New APIs         | New syntax        |

### Code block

Just a hello world...

\`\`\`cpp
#include <bits/stdc++.h>
// This is intentionally very long to test scrolling
const std::string GREETING = "UwU";
int main(int argc, char* argv[]) {
    std::cout << GREETING;
}
\`\`\`

### A second, longer code block

\`\`\`python
def follow_to_end(view, velocity=1200):
    """The chase, not the snap - retarget mid-flight, keep the speed."""
    end = view.origin_y + view.content_height + view.bottom_margin - view.height
    if end - view.content_y < 1:
        return
    view.anim.to = end
    if not view.anim.running:
        view.anim.start()

def coalesce(chunks, interval_ms=50):
    buffer = []
    for chunk in chunks:
        buffer.append(chunk)
        if elapsed() >= interval_ms:
            yield "".join(buffer)
            buffer.clear()
    if buffer:
        yield "".join(buffer)
\`\`\`

### List, long enough to wrap

- The first item is short.
- The second item is deliberately much longer than the first, long enough to wrap onto a second line at any sane sidebar width, because wrapped list items re-measure differently from unwrapped ones.
- Third: *italic across a wrapping boundary is its own small renderer test*, so this item keeps going until it certainly wraps too.
- Fourth, with \`inline code\` and **bold** mixed in the middle of a sentence that also wraps.

### LaTeX


Inline w/ dollar signs: $\\frac{1}{2} = \\frac{2}{4}$

Inline w/ double dollar signs: $$\\int_0^\\infty e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}$$

Inline w/ backslash and square brackets \\[\\int_0^\\infty \\frac{1}{x^2} dx = \\infty\\]

Inline w/ backslash and round brackets \\(e^{i\\pi} + 1 = 0\\)

### Closing prose

And a final paragraph after the math, so the stream does not end on a block boundary but mid-prose, the way real answers usually do. When this sentence finishes, done flips, the coalescer syncs its last copy immediately, and the shimmer on the model name stops.
`

    property IpcHandler testIpc: IpcHandler {
        target: "ai"
        function testStream(): void {
            root.simulateStream(root.testStreamText);
        }
    }

    // /test's streamer: feeds a canned response through the same
    // message-object append path a network stream uses, so streaming
    // rendering is testable without a model on the other end.
    property AiMessageData simMessage
    property string simRemaining: ""
    property int simTick: 0
    function simulateStream(content) {
        simTimer.stop();
        const msg = aiMessageComponent.createObject(root, {
            "role": "assistant",
            "model": currentModelId,
            "content": "",
            "rawContent": "",
            "thinking": false,
            "done": false,
        });
        const id = idForMessage(msg);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = msg;
        root.simMessage = msg;
        root.simRemaining = String(content);
        root.simTick = 0;
        simTimer.start();
    }
    property Timer simTimer: Timer {
        interval: 45
        repeat: true
        onTriggered: {
            if (root.simRemaining.length === 0) {
                stop();
                root.simMessage.done = true;
                AiSessions.scheduleSave();
                return;
            }
            // Chunk sizes cycle 4..22 chars - lumpy like a real stream.
            const n = 4 + (root.simTick++ % 7) * 3;
            const chunk = root.simRemaining.slice(0, n);
            root.simRemaining = root.simRemaining.slice(n);
            root.simMessage.rawContent += chunk;
            root.simMessage.content += chunk;
        }
    }

    function addMessage(message, role) {
        if (message.length === 0) return;
        const aiMessage = aiMessageComponent.createObject(root, {
            "role": role,
            "content": message,
            "rawContent": message,
            "thinking": false,
            "done": true,
        });
        const id = idForMessage(aiMessage);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = aiMessage;
        AiSessions.scheduleSave();
    }

    function removeMessage(index) {
        if (index < 0 || index >= messageIDs.length) return;
        const id = root.messageIDs[index];
        root.messageIDs.splice(index, 1);
        root.messageIDs = [...root.messageIDs];
        delete root.messageByID[id];
    }

    function addApiKeyAdvice(model) {
        // Provider-brought models carry no key_get_link; the advice stays
        // useful without printing "undefined" where a URL was expected.
        const linkLine = model.key_get_link ? Translation.tr("\n\n**Link**: %1").arg(model.key_get_link) : "";
        root.addMessage(
            Translation.tr('To set an API key, pass it with the %3 command\n\nTo view the key, pass "get" with the command<br/>\n\n### For %1:%2')
                .arg(model.name).arg(linkLine).arg("/key"),
            Ai.interfaceRole
        );
    }

    function getModel() {
        return models[currentModelId];
    }

    function setModel(modelId, feedback = true, setPersistentState = true) {
        if (!modelId) modelId = ""
        modelId = modelId.toLowerCase()
        if (modelList.indexOf(modelId) !== -1) {
            const model = models[modelId]
            // See if policy prevents online models
            if (Config.options.policies.ai === 2 && !model.endpoint.includes("localhost")) {
                root.addMessage(
                    Translation.tr("Online models disallowed\n\nControlled by `policies.ai` config option"),
                    root.interfaceRole
                );
                return;
            }
            if (setPersistentState) Persistent.states.ai.model = modelId;
            if (feedback) root.addMessage(Translation.tr("Model set to %1").arg(model.name), root.interfaceRole);
            if (model.requires_key) {
                // If key not there show advice
                if (root.apiKeysLoaded && (!root.apiKeys[model.key_id] || root.apiKeys[model.key_id].length === 0)) {
                    root.addApiKeyAdvice(model)
                }
            }
        } else {
            if (feedback) root.addMessage(Translation.tr("Invalid model. Supported: \n```\n") + modelList.join("\n```\n```\n"), Ai.interfaceRole) + "\n```"
        }
    }

    function setTool(tool) {
        if (!root.tools[models[currentModelId]?.api_format] || !(tool in root.tools[models[currentModelId]?.api_format])) {
            root.addMessage(Translation.tr("Invalid tool. Supported tools:\n- %1").arg(root.availableTools.join("\n- ")), root.interfaceRole);
            return false;
        }
        Config.options.ai.tool = tool;
        return true;
    }
    
    function getTemperature() {
        return root.temperature;
    }

    function setTemperature(value) {
        if (value == NaN || value < 0 || value > 2) {
            root.addMessage(Translation.tr("Temperature must be between 0 and 2"), Ai.interfaceRole);
            return;
        }
        Persistent.states.ai.temperature = value;
        root.temperature = value;
        root.addMessage(Translation.tr("Temperature set to %1").arg(value), Ai.interfaceRole);
    }

    function setApiKey(key) {
        const model = models[currentModelId];
        if (!model.requires_key) {
            root.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), Ai.interfaceRole);
            return;
        }
        if (!key || key.length === 0) {
            const model = models[currentModelId];
            root.addApiKeyAdvice(model)
            return;
        }
        KeyringStorage.setNestedField(["apiKeys", model.key_id], key.trim());
        root.addMessage(Translation.tr("API key set for %1").arg(model.name), Ai.interfaceRole);
    }

    function printApiKey() {
        const model = models[currentModelId];
        if (model.requires_key) {
            const key = root.apiKeys[model.key_id];
            if (key) {
                root.addMessage(Translation.tr("API key:\n\n```txt\n%1\n```").arg(key), Ai.interfaceRole);
            } else {
                root.addMessage(Translation.tr("No API key set for %1").arg(model.name), Ai.interfaceRole);
            }
        } else {
            root.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), Ai.interfaceRole);
        }
    }

    function printTemperature() {
        root.addMessage(Translation.tr("Temperature: %1").arg(root.temperature), Ai.interfaceRole);
    }

    function clearMessages() {
        root.messageIDs = [];
        root.messageByID = ({});
        root.tokenCount.input = -1;
        root.tokenCount.output = -1;
        root.tokenCount.total = -1;
    }

    FileView {
        id: requesterScriptFile
    }

    FileView {
        id: titlerScriptFile
    }

    FileView {
        id: inlineImageFile
    }

    /** An image the CHAT stream carried inline. A data URL's base64 rides
        to disk through a FileView (multi-megabyte strings never touch an
        argv), decodes into the durable store, and lands in the message as
        markdown; a plain http url embeds directly. */
    property var inlineImageQueue: []
    function saveInlineImage(url, message) {
        if (!url.startsWith("data:")) {
            const md = `\n![generated image](${url})\n`;
            message.content += md;
            message.rawContent += md;
            return;
        }
        const comma = url.indexOf(",");
        if (comma === -1) return;
        message.generatingImage = true; // skeleton through the decode
        root.inlineImageQueue = [...root.inlineImageQueue, { "b64": url.slice(comma + 1), "message": message }];
        Qt.callLater(root.drainInlineImages);
    }
    function drainInlineImages() {
        if (inlineImageSaver.running || root.inlineImageQueue.length === 0) return;
        const job = root.inlineImageQueue[0];
        root.inlineImageQueue = root.inlineImageQueue.slice(1);
        const b64Path = `${Directories.aiAttachments}/inline.b64.tmp`;
        const outPath = `${Directories.aiAttachments}/inline-${Date.now()}.png`;
        inlineImageFile.path = Qt.resolvedUrl(b64Path);
        inlineImageFile.setText(job.b64);
        inlineImageSaver.message = job.message;
        inlineImageSaver.outPath = outPath;
        inlineImageSaver.command = ["bash", "-c",
            `base64 -d '${b64Path}' > '${outPath}' && rm -f '${b64Path}' && echo ok`];
        inlineImageSaver.running = true;
    }
    Process {
        id: inlineImageSaver
        property var message
        property string outPath: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "ok" && inlineImageSaver.message) {
                    const md = `\n![generated image](${inlineImageSaver.outPath})\n`;
                    inlineImageSaver.message.content += md;
                    inlineImageSaver.message.rawContent += md;
                    AiSessions.scheduleSave();
                }
                // The skeleton comes down once no queued job still feeds
                // this message.
                if (inlineImageSaver.message
                        && !root.inlineImageQueue.some(j => j.message === inlineImageSaver.message)) {
                    inlineImageSaver.message.generatingImage = false;
                }
                Qt.callLater(root.drainInlineImages);
            }
        }
    }

    // The session's title, asked of the model itself: one tiny
    // non-streaming completion after the first finished answer. Only the
    // OpenAI dialect (every provider-fetched and imported model) is asked;
    // elsewhere the trimmed first prompt stays. A manual rename is safe -
    // this fires once, on the first answer, and never again.
    property string pendingTitleSessionId: ""
    function requestSessionTitle() {
        if (titler.running) return;
        if (!AiSessions.currentId || AiSessions.currentId.length === 0) return;
        const visible = root.messageIDs
            .map(id => root.messageByID[id])
            .filter(m => m && (m.role === "user" || m.role === "assistant"));
        if (visible.length !== 2) return; // exactly first question + first answer
        const model = models[currentModelId];
        if (!model || model.api_format !== "openai") return;
        const question = String(visible[0].rawContent ?? visible[0].content ?? "").slice(0, 1200);
        const answer = String(visible[1].rawContent ?? visible[1].content ?? "").slice(0, 1200);
        if (question.length === 0 || answer.length === 0) return;

        const data = {
            "model": model.model,
            "messages": [
                { "role": "system", "content": "You title conversations. Reply with ONLY a concise 3-6 word title for the exchange. No quotes, no punctuation, no explanations." },
                { "role": "user", "content": `Question:\n${question}\n\nAnswer:\n${answer}` }
            ],
            "stream": false,
            "temperature": 0.3
        };
        if (model.requires_key) titler.environment[`${root.apiKeyEnvVarName}`] = root.apiKeys ? (root.apiKeys[model.key_id] ?? "") : "";
        const authHeader = root.currentApiStrategy.buildAuthorizationHeader(root.apiKeyEnvVarName);
        const script = "#!/usr/bin/env bash\n"
            + `curl -s --max-time 20 "${model.endpoint}"`
            + ` -H "Content-Type: application/json"`
            + (authHeader ? ` ${authHeader}` : "")
            + ` --data '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(data))}'`
            + "\n";
        const path = CF.FileUtils.trimFileProtocol(root.requestScriptFilePath) + ".title.sh";
        titlerScriptFile.path = Qt.resolvedUrl(path);
        titlerScriptFile.setText(script);
        root.pendingTitleSessionId = AiSessions.currentId;
        titler.command = ["bash", path];
        titler.running = true;
    }

    // /diagnose's answers: the last request's exit, and an on-demand
    // reachability probe of the current model's endpoint (no key attached -
    // a 401 is still "reachable", which is the question being asked).
    property int lastRequestExitCode: -1
    property real lastRequestAt: 0
    function probeEndpoint() {
        const model = models[currentModelId];
        if (!model || !model.endpoint) {
            root.addMessage(Translation.tr("No model selected - nothing to probe."), root.interfaceRole);
            return;
        }
        if (prober.running) return;
        prober.endpoint = model.endpoint;
        prober.command = ["bash", "-c",
            `code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 6 '${CF.StringUtils.shellSingleQuoteEscape(model.endpoint)}' -X POST -H 'Content-Type: application/json' --data '{}'); echo "$code"`];
        prober.running = true;
    }
    Process {
        id: prober
        property string endpoint: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const code = text.trim();
                const reachable = code.length === 3 && code !== "000";
                root.addMessage(reachable
                    ? Translation.tr("Endpoint reachable: %1 answered HTTP %2.").arg(prober.endpoint).arg(code)
                    : Translation.tr("Endpoint UNREACHABLE: %1 (no HTTP answer - server down, wrong URL, or no network).").arg(prober.endpoint),
                    root.interfaceRole);
            }
        }
    }

    Process {
        id: titler
        stdout: StdioCollector {
            onStreamFinished: {
                const sessionId = root.pendingTitleSessionId;
                root.pendingTitleSessionId = "";
                if (!sessionId || sessionId.length === 0) return;
                try {
                    const reply = JSON.parse(text);
                    const raw = reply.choices?.[0]?.message?.content ?? "";
                    const current = AiSessions.index.find(r => r.id === sessionId);
                    const title = SessionsFold.titleFromModelReply(raw, current?.title ?? "");
                    if (title.length > 0 && current && title !== current.title)
                        AiSessions.rename(sessionId, title);
                } catch (e) {
                    // A failed titling is silence, never an error in the chat.
                }
            }
        }
    }

    Process {
        id: requester
        property list<string> baseCommand: ["bash"]
        property AiMessageData message
        property ApiStrategy currentStrategy

        function markDone() {
            requester.message.done = true;
            if (root.postResponseHook) {
                root.postResponseHook();
                root.postResponseHook = null; // Reset hook after use
            }
            // The finished answer is the autosave's strongest trigger; the
            // old write-only lastSession snapshot had no restore path and
            // retires here.
            AiSessions.scheduleSave();
            // The ledger: whatever the provider's last usage frame said
            // (or -1s - the request still counts), ok unless the message
            // carries a failure note.
            AiUsage.record({
                "input": root.tokenCount.input,
                "output": root.tokenCount.output,
                "total": root.tokenCount.total,
            }, !requester.message.content.includes("**Request failed**")
                && !requester.message.content.includes("**Error**"));
            root.requestSessionTitle();
            root.responseFinished()
        }

        function makeRequest() {
            const model = models[currentModelId];

            // Fetch API keys if needed
            if (model?.requires_key && !KeyringStorage.loaded) KeyringStorage.fetchKeyringData();
            
            requester.currentStrategy = root.currentApiStrategy;
            requester.currentStrategy.reset(); // Reset strategy state

            /* Put API key in environment variable */
            if (model.requires_key) requester.environment[`${root.apiKeyEnvVarName}`] = root.apiKeys ? (root.apiKeys[model.key_id] ?? "") : ""

            /* Image generators speak a different endpoint and shape */
            if (model.imageGeneration) {
                requester.makeImageRequest(model);
                return;
            }

            /* Build endpoint, request data */
            const endpoint = root.currentApiStrategy.buildEndpoint(model);
            const messageArray = root.messageIDs.map(id => root.messageByID[id]);
            const filteredMessageArray = messageArray.filter(message => message.role !== Ai.interfaceRole);
            const data = root.currentApiStrategy.buildRequestData(model, filteredMessageArray, root.systemPrompt, root.temperature, root.tools[model.api_format][root.currentTool], root.pendingFilePaths);
            // console.log("[Ai] Request data: ", JSON.stringify(data, null, 2));

            let requestHeaders = {
                "Content-Type": "application/json",
            }
            
            /* Create local message object. Whether the server will answer
               with an inline image is unknowable up front, so a prompt that
               reads like an image ask pre-arms the image skeleton; the
               first TEXT that arrives clears it instantly (onRead), while
               an inline image keeps it up to the moment the file lands. */
            const lastUser = [...root.messageIDs].reverse()
                .map(id => root.messageByID[id]).find(m => m?.role === "user");
            // Arm on an image-sounding prompt OR in any chat where this
            // model has already painted inline - follow-ups ("make it
            // blue") never repeat the word "image". A wrong guess costs
            // one blink: the first text stands the skeleton down.
            const chatPaintsInline = root.messageIDs.some(id => {
                const m = root.messageByID[id];
                return m?.role === "assistant"
                    && String(m.rawContent ?? "").includes("/attachments/inline-");
            });
            const looksLikeImageAsk = chatPaintsInline
                || /\b(generate|draw|paint|render|create|make)\b[\s\S]{0,80}\b(image|picture|photo|logo|icon|drawing|art)\b|\bimage of\b/i
                    .test(String(lastUser?.rawContent ?? ""));
            requester.message = root.aiMessageComponent.createObject(root, {
                "role": "assistant",
                "model": currentModelId,
                "content": "",
                "rawContent": "",
                "thinking": !looksLikeImageAsk,
                "done": false,
                "generatingImage": looksLikeImageAsk,
            });
            const id = idForMessage(requester.message);
            root.messageIDs = [...root.messageIDs, id];
            root.messageByID[id] = requester.message;

            /* Build header string for curl */ 
            let headerString = Object.entries(requestHeaders)
                .filter(([k, v]) => v && v.length > 0)
                .map(([k, v]) => `-H '${k}: ${v}'`)
                .join(' ');

            // console.log("Request headers: ", JSON.stringify(requestHeaders));
            // console.log("Header string: ", headerString);

            /* Get authorization header from strategy */
            const authHeader = requester.currentStrategy.buildAuthorizationHeader(root.apiKeyEnvVarName);
            
            /* Script shebang */
            const scriptShebang = "#!/usr/bin/env bash\n";

            /* Create extra setup when there's an attached file */
            let scriptFileSetupContent = ""
            if (root.pendingFilePaths.length > 0) {
                scriptFileSetupContent = requester.currentStrategy.buildScriptFileSetup(root.pendingFilePaths);
                root.pendingFilePaths = [];
            }

            /* Create command string. The body goes through a FILE, written
               by bash's builtin printf: a base64-encoded image inlined as a
               curl argument blew ARG_MAX ("Argument list too long", exit
               126) - builtins never exec, so they have no such limit. */
            let scriptRequestContent = ""
            scriptRequestContent += `BODY_FILE='${CF.FileUtils.trimFileProtocol(root.requestScriptFilePath)}.body.json'\n`
            scriptRequestContent += `printf '%s' '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(data))}' > "$BODY_FILE"\n`
            scriptRequestContent += `curl --no-buffer "${endpoint}"`
                + ` ${headerString}`
                + (authHeader ? ` ${authHeader}` : "")
                + ` --data @"$BODY_FILE"`
                + "\n"
            // A server that answers in ONE json blob (a proxy handling a
            // tool call, an error body) ends without a newline, and
            // SplitParser drops an unterminated final line on the floor -
            // the reply parsed as nothing at all. Terminate it ourselves.
            scriptRequestContent += `printf '\\n'\n`
            scriptRequestContent += `rm -f "$BODY_FILE"\n`
            
            /* Send the request */
            const scriptContent = requester.currentStrategy.finalizeScriptContent(scriptShebang + scriptFileSetupContent + scriptRequestContent)
            const shellScriptPath = CF.FileUtils.trimFileProtocol(root.requestScriptFilePath)
            requesterScriptFile.path = Qt.resolvedUrl(shellScriptPath)
            requesterScriptFile.setText(scriptContent)
            requester.command = baseCommand.concat([shellScriptPath]);
            requester.running = true
        }

        /** /images/generations (or /edits with an attachment): one
            non-streaming request whose b64 payload lands as a file in the
            durable attachment store and renders as a markdown image. */
        function makeImageRequest(model, promptOverride) {
            // Called with a foreign generator by the tool path, so the key
            // env is set HERE, for THIS model - not inherited from the
            // chat model that asked.
            if (model.requires_key) requester.environment[`${root.apiKeyEnvVarName}`] = root.apiKeys ? (root.apiKeys[model.key_id] ?? "") : "";
            requester.message = root.aiMessageComponent.createObject(root, {
                "role": "assistant",
                "model": currentModelId,
                "content": "",
                "rawContent": "",
                "thinking": false,
                "done": false,
                "generatingImage": true,
            });
            const mid = idForMessage(requester.message);
            root.messageIDs = [...root.messageIDs, mid];
            root.messageByID[mid] = requester.message;

            let prompt = String(promptOverride ?? "").trim();
            if (prompt.length === 0) {
                for (let i = root.messageIDs.length - 1; i >= 0; i--) {
                    const m = root.messageByID[root.messageIDs[i]];
                    if (m?.role === "user") { prompt = String(m.rawContent ?? m.content ?? ""); break; }
                }
            }
            const attachment = root.pendingFilePaths[0] ?? "";
            root.pendingFilePaths = [];
            const base = model.endpoint.replace(/\/chat\/completions\/?$/, "");
            const endpoint = base + (attachment ? "/images/edits" : "/images/generations");
            const authHeader = requester.currentStrategy.buildAuthorizationHeader(root.apiKeyEnvVarName);
            const outPath = `${Directories.aiAttachments}/gen-$(date +%s).png`;
            const respPath = CF.FileUtils.trimFileProtocol(root.requestScriptFilePath) + ".image.json";

            let script = "#!/usr/bin/env bash\n";
            if (attachment) {
                script += `curl -s "${endpoint}"`
                    + (authHeader ? ` ${authHeader}` : "")
                    + ` -F model='${CF.StringUtils.shellSingleQuoteEscape(model.model)}'`
                    + ` -F prompt='${CF.StringUtils.shellSingleQuoteEscape(prompt)}'`
                    + ` -F image=@'${CF.StringUtils.shellSingleQuoteEscape(attachment)}'`
                    + ` -o '${respPath}'\n`;
            } else {
                const body = Object.assign({
                    "model": model.model,
                    "prompt": prompt,
                    "response_format": "b64_json",
                }, model.extraParams ?? {});
                script += `BODY_FILE='${respPath}.body'\n`;
                script += `printf '%s' '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(body))}' > "$BODY_FILE"\n`;
                script += `curl -s "${endpoint}" -H "Content-Type: application/json"`
                    + (authHeader ? ` ${authHeader}` : "")
                    + ` --data @"$BODY_FILE" -o '${respPath}'\n`;
                script += `rm -f "$BODY_FILE"\n`;
            }
            script += `OUT="${outPath}"\n`;
            script += `b64=$(jq -r '.data[0].b64_json // empty' '${respPath}')\n`;
            script += `if [ -n "$b64" ]; then printf '%s' "$b64" | base64 -d > "$OUT"; echo "IMI_IMAGE_SAVED:$OUT";\n`;
            script += `elif [ -n "$(jq -r '.data[0].url // empty' '${respPath}')" ]; then echo "IMI_IMAGE_URL:$(jq -r '.data[0].url' '${respPath}')";\n`;
            script += `else echo "IMI_IMAGE_ERROR:$(jq -c '.error.message // .error // .' '${respPath}' | head -c 300)"; fi\n`;
            script += `rm -f '${respPath}'\n`;

            const shellScriptPath = CF.FileUtils.trimFileProtocol(root.requestScriptFilePath);
            requesterScriptFile.path = Qt.resolvedUrl(shellScriptPath);
            requesterScriptFile.setText(script);
            requester.command = requester.baseCommand.concat([shellScriptPath]);
            requester.running = true;
        }

        stderr: StdioCollector { id: requesterStderr }
        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0) return;
                if (requester.message.thinking) requester.message.thinking = false;

                // Image-run sentinels ride ahead of the streaming parser.
                if (data.startsWith("IMI_IMAGE_SAVED:") || data.startsWith("IMI_IMAGE_URL:")) {
                    const ref = data.slice(data.indexOf(":") + 1).trim();
                    const md = `![generated image](${ref})`;
                    requester.message.content += md;
                    requester.message.rawContent += md;
                    requester.message.generatingImage = false;
                    requester.markDone();
                    return;
                }
                if (data.startsWith("IMI_IMAGE_ERROR:")) {
                    const err = `**Error**: ${data.slice(16).trim()}`;
                    requester.message.content += err;
                    requester.message.rawContent += err;
                    requester.message.generatingImage = false;
                    requester.markDone();
                    return;
                }
                // console.log("[Ai] Raw response line: ", data);

                // Handle response line
                try {
                    const result = requester.currentStrategy.parseResponseLine(data, requester.message);
                    // console.log("[Ai] Parsed response result: ", JSON.stringify(result, null, 2));

                    // A pre-armed skeleton stands down as soon as the
                    // answer turns out to be text.
                    if (requester.message.generatingImage
                            && requester.message.content.trim().length > 0) {
                        requester.message.generatingImage = false;
                    }
                    if (result.inlineImages) {
                        for (const url of result.inlineImages)
                            root.saveInlineImage(url, requester.message);
                    }
                    if (result.functionCall) {
                        requester.message.functionCall = result.functionCall;
                        root.handleFunctionCall(result.functionCall.name, result.functionCall.args, requester.message);
                    }
                    if (result.tokenUsage) {
                        root.tokenCount.input = result.tokenUsage.input;
                        root.tokenCount.output = result.tokenUsage.output;
                        root.tokenCount.total = result.tokenUsage.total;
                    }
                    if (result.finished) {
                        requester.markDone();
                    }
                    
                } catch (e) {
                    console.log("[AI] Could not parse response: ", e);
                    requester.message.rawContent += data;
                    requester.message.content += data;
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.lastRequestExitCode = exitCode;
            root.lastRequestAt = Date.now();
            const result = requester.currentStrategy.onRequestFinished(requester.message);

            // The exit-time flush can still carry a tool call (a stream
            // that ended without its closing frame) - route it exactly as
            // the streaming path does.
            if (result.functionCall) {
                requester.message.functionCall = result.functionCall;
                root.handleFunctionCall(result.functionCall.name, result.functionCall.args, requester.message);
            }

            if (result.finished) {
                requester.markDone();
            } else if (!requester.message.done) {
                requester.markDone();
            }

            // Handle error responses
            if (requester.message.content.includes("API key not valid")) {
                root.addApiKeyAdvice(models[requester.message.model]);
            }
            // A dead endpoint fails with an empty transcript and no
            // explanation; say what happened - stderr included, which is
            // where bash and curl actually put the reason - and name the
            // retry.
            if (exitCode !== 0 && requester.message.content.trim().length === 0) {
                let note = Translation.tr("**Request failed** (curl exit %1). Check the provider's Base URL and key, then hit Regenerate.").arg(exitCode);
                const err = String(requesterStderr.text ?? "").trim();
                if (err.length > 0)
                    note += `\n\n\`\`\`\n${err.slice(-400)}\n\`\`\``;
                requester.message.content += note;
                requester.message.rawContent += note;
            }

            // The requester is free now: launch the generation the tool
            // path queued mid-stream, if any.
            if (root.pendingImageGeneration) {
                const job = root.pendingImageGeneration;
                root.pendingImageGeneration = null;
                requester.makeImageRequest(job.model, job.prompt);
            } else if (root.pendingContinuation) {
                root.pendingContinuation = false;
                requester.makeRequest();
            }
        }
    }

    /** The visible transcript, as a markdown file in Downloads. */
    function exportChat() {
        if (root.messageIDs.length === 0) return;
        let md = "";
        for (const id of root.messageIDs) {
            const m = root.messageByID[id];
            if (!m || !(m.visibleToUser ?? true)) continue;
            const who = m.role === "user" ? Translation.tr("User")
                : m.role === "assistant" ? (root.models[m.model]?.name ?? m.model ?? "Assistant")
                : Translation.tr("Interface");
            md += `## ${who}\n\n${(m.rawContent && m.rawContent.length > 0) ? m.rawContent : m.content}\n\n`;
        }
        const dir = CF.FileUtils.trimFileProtocol(Directories.downloads);
        const path = `${dir}/ai-chat-${Math.floor(Date.now() / 1000)}.md`;
        Quickshell.execDetached(["bash", "-c",
            `echo '${CF.StringUtils.shellSingleQuoteEscape(md)}' > '${path}'`]);
        root.addMessage(Translation.tr("Chat exported to %1").arg(path), root.interfaceRole);
    }

    function sendUserMessage(message) {
        if (message.length === 0) return;
        // The first user message of an unsaved chat mints its session -
        // lazily, so an empty chat never touches disk (spec 2026-08-31).
        AiSessions.mint(message);
        root.addMessage(message, "user");
        // The attachment belongs to the message that SENDS it - it used to
        // be stamped on the assistant's reply, which also lost it on every
        // regenerate. pendingFilePath itself survives until makeRequest
        // consumes it for the script.
        if (root.pendingFilePaths.length > 0) {
            const uid = root.messageIDs[root.messageIDs.length - 1];
            root.messageByID[uid].localFilePaths = [...root.pendingFilePaths];
            root.messageByID[uid].localFilePath = root.pendingFilePaths[0];
        }
        requester.makeRequest();
    }

    function attachFile(filePath: string) {
        // "" clears the tray (the historical calling convention); a path
        // appends, once.
        if (!filePath || filePath.length === 0) {
            root.pendingFilePaths = [];
            return;
        }
        const trimmed = CF.FileUtils.trimFileProtocol(filePath);
        // Copy into the durable store: clipboard decodes live in a /tmp
        // cache that can vanish before the request - or the regenerate -
        // runs (a request went out pointing at nothing). Paths already in
        // the store (a session re-arm) are kept as they are.
        let kept = trimmed;
        if (trimmed.indexOf(Directories.aiAttachments) !== 0) {
            const base = trimmed.split("/").pop() || "file";
            kept = `${Directories.aiAttachments}/${Date.now()}-${base}`;
            Quickshell.execDetached(["cp", "-f", trimmed, kept]);
        }
        if (root.pendingFilePaths.indexOf(kept) !== -1) return;
        root.pendingFilePaths = [...root.pendingFilePaths, kept];
    }

    function removeAttachment(filePath: string) {
        root.pendingFilePaths = root.pendingFilePaths.filter(p => p !== filePath);
    }

    function regenerate(messageIndex) {
        if (messageIndex < 0 || messageIndex >= messageIDs.length) return;
        const id = root.messageIDs[messageIndex];
        const message = root.messageByID[id];
        if (message.role !== "assistant") return;
        // Remove all messages after this one
        for (let i = root.messageIDs.length - 1; i >= messageIndex; i--) {
            root.removeMessage(i);
        }
        // The question being re-asked keeps its image: re-arm the script's
        // file from the last user message so vision answers regenerate as
        // vision answers.
        for (let i = root.messageIDs.length - 1; i >= 0; i--) {
            const m = root.messageByID[root.messageIDs[i]];
            if (m?.role === "user") {
                if (m.localFilePaths && m.localFilePaths.length > 0)
                    root.pendingFilePaths = [...m.localFilePaths];
                else if (m.localFilePath && m.localFilePath.length > 0)
                    root.pendingFilePaths = [m.localFilePath];
                break;
            }
        }
        requester.makeRequest();
    }

    /**
     * Sends a rewritten question as a FORK (spec 2026-08-31): everything
     * after the old wording answered the old wording, so the current
     * session is flushed and left behind - still openable in Chats - and
     * the edit continues in a fresh transcript truncated at the edited
     * question. Never a removeMessage loop: nothing is destroyed.
     */
    function editAndResend(messageIndex, newText) {
        const text = String(newText ?? "").trim();
        if (text.length === 0) return;
        if (messageIndex < 0 || messageIndex >= root.messageIDs.length) return;
        if (root.messageByID[root.messageIDs[messageIndex]]?.role !== "user") return;
        if (root.isGenerating) {
            root.addMessage(Translation.tr("Wait for the current answer to finish before editing."), root.interfaceRole);
            return;
        }
        AiSessions.saveNow();
        AiSessions.currentId = "";
        const kept = root.chatToJson(root.messageIDs.slice(0, messageIndex));
        root.loadMessagesFromJson(kept);
        root.sendUserMessage(text);
    }

    function createFunctionOutputMessage(name, output, includeOutputInChat = true) {
        return aiMessageComponent.createObject(root, {
            "role": "user",
            "content": `[[ Output of ${name} ]]${includeOutputInChat ? ("\n\n<think>\n" + output + "\n</think>") : ""}`,
            "rawContent": `[[ Output of ${name} ]]${includeOutputInChat ? ("\n\n<think>\n" + output + "\n</think>") : ""}`,
            "functionName": name,
            "functionResponse": output,
            "thinking": false,
            "done": true,
            // "visibleToUser": false,
        });
    }

    function addFunctionOutputMessage(name, output) {
        const aiMessage = createFunctionOutputMessage(name, output);
        const id = idForMessage(aiMessage);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = aiMessage;
    }

    function rejectCommand(message: AiMessageData) {
        if (!message.functionPending) return;
        message.functionPending = false; // User decided, no more "thinking"
        addFunctionOutputMessage(message.functionName, Translation.tr("Command rejected by user"))
    }

    function approveCommand(message: AiMessageData) {
        if (!message.functionPending) return;
        message.functionPending = false; // User decided, no more "thinking"

        const responseMessage = createFunctionOutputMessage(message.functionName, "", false);
        const id = idForMessage(responseMessage);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = responseMessage;

        commandExecutionProc.message = responseMessage;
        commandExecutionProc.baseMessageContent = responseMessage.content;
        commandExecutionProc.shellCommand = message.functionCall.args.command;
        commandExecutionProc.running = true; // Start the command execution
    }

    Process {
        id: commandExecutionProc
        property string shellCommand: ""
        property AiMessageData message
        property string baseMessageContent: ""
        command: ["bash", "-c", shellCommand]
        stdout: SplitParser {
            onRead: (output) => {
                commandExecutionProc.message.functionResponse += output + "\n\n";
                const updatedContent = commandExecutionProc.baseMessageContent + `\n\n<think>\n<tt>${commandExecutionProc.message.functionResponse}</tt>\n</think>`;
                commandExecutionProc.message.rawContent = updatedContent;
                commandExecutionProc.message.content = updatedContent;
            }
        }
        onExited: (exitCode, exitStatus) => {
            commandExecutionProc.message.functionResponse += `[[ Command exited with code ${exitCode} (${exitStatus}) ]]\n`;
            requester.makeRequest(); // Continue
        }
    }

    function handleFunctionCall(name, args: var, message: AiMessageData) {
        if (name === "switch_to_search_mode") {
            const modelId = root.currentModelId;
            root.currentTool = "search"
            root.postResponseHook = () => { root.currentTool = "functions" }
            addFunctionOutputMessage(name, Translation.tr("Switched to search mode. Continue with the user's request."))
            requester.makeRequest();
        } else if (name === "get_shell_config") {
            const configJson = CF.ObjectUtils.toPlainObject(Config.options)
            addFunctionOutputMessage(name, JSON.stringify(configJson));
            requester.makeRequest();
        } else if (name === "set_shell_config") {
            if (!args.key || !args.value) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `key` and `value`."));
                return;
            }
            const key = args.key;
            const value = args.value;
            Config.setNestedValue(key, value);
        } else if (name === "run_shell_command") {
            if (!args.command || args.command.length === 0) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `command`."));
                return;
            }
            const contentToAppend = `\n\n**Command execution request**\n\n\`\`\`command\n${args.command}\n\`\`\``;
            message.rawContent += contentToAppend;
            message.content += contentToAppend;
            message.functionPending = true; // Use thinking to indicate the command is waiting for approval
        }
        else if (name === "remember_fact") {
            const fact = String(args?.fact ?? "").trim();
            if (fact.length === 0) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `fact`."));
            } else if (AiMemory.remember(fact, "model")) {
                // Announced, never silent - and undoable by id via /memory.
                root.addMessage(Translation.tr("Remembered: %1").arg(fact), root.interfaceRole);
                addFunctionOutputMessage(name, "Saved.");
            } else {
                addFunctionOutputMessage(name, Translation.tr("Already known (or memory is disabled)."));
            }
            // NEVER makeRequest here: the call lands mid-stream and a
            // running Process ignores running=true (the generate_image
            // lesson). The exit handler continues the conversation.
            root.pendingContinuation = true;
        }
        else if (name === "generate_image") {
            const prompt = String(args?.prompt ?? "").trim();
            if (prompt.length === 0) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `prompt`."));
                requester.makeRequest();
                return;
            }
            // Prefer a generator from the same provider as the caller;
            // any surfaced generator otherwise.
            const currentKey = models[currentModelId]?.key_id;
            const generators = root.modelList
                .map(id => root.models[id])
                .filter(m => m?.imageGeneration && m.api_format === "openai");
            const generator = generators.find(m => m.key_id === currentKey) ?? generators[0];
            if (!generator) {
                addFunctionOutputMessage(name, Translation.tr("No image-generation model is available from the configured providers."));
                requester.makeRequest();
                return;
            }
            const note = `\n\n*${Translation.tr("Generating image with %1…").arg(generator.name)}*\n`;
            message.content += note;
            message.rawContent += note;
            // NEVER launch here: the tool call lands mid-stream, and
            // setting running=true on an already-running Process is a
            // silent no-op - the generation (and its skeleton) vanished.
            // The exit handler launches it once the chat request is done.
            root.pendingImageGeneration = { "model": generator, "prompt": prompt };
        }
        else root.addMessage(Translation.tr("Unknown function call: %1").arg(name), "assistant");
    }

    function chatToJson(ids = root.messageIDs) {
        return ids.map(id => {
            const message = root.messageByID[id]
            return ({
                "role": message.role,
                "rawContent": message.rawContent,
                "fileMimeType": message.fileMimeType,
                "fileUri": message.fileUri,
                "localFilePath": message.localFilePath,
                "localFilePaths": message.localFilePaths ?? [],
                "model": message.model,
                "thinking": false,
                "done": true,
                "annotations": message.annotations,
                "annotationSources": message.annotationSources,
                "functionName": message.functionName,
                "functionCall": message.functionCall,
                "functionResponse": message.functionResponse,
                "visibleToUser": message.visibleToUser,
            })
        })
    }

    FileView {
        id: chatSaveFile
        property string chatName: ""
        path: chatName.length > 0 ? `${Directories.aiChats}/${chatName}.json` : ""
        blockLoading: true // Prevent race conditions
    }

    /**
     * Saves chat to a JSON list of message objects.
     * @param chatName name of the chat
     */
    function saveChat(chatName) {
        chatSaveFile.chatName = chatName.trim()
        const saveContent = JSON.stringify(root.chatToJson())
        chatSaveFile.setText(saveContent)
        getSavedChats.running = true;
        // Commands are sugar over sessions: /save NAME also names the
        // current auto-saved session.
        if (AiSessions.currentId.length > 0)
            AiSessions.rename(AiSessions.currentId, chatName.trim())
    }

    /**
     * Loads chat from a JSON list of message objects.
     * @param chatName name of the chat
     */
    /** Rebuilds the live chat from a saved message array - shared by the
        legacy /load path and AiSessions.openSession. */
    function loadMessagesFromJson(saveData) {
        root.clearMessages()
        root.messageIDs = saveData.map((_, i) => {
            return i
        })
        for (let i = 0; i < saveData.length; i++) {
            const message = saveData[i];
            root.messageByID[i] = root.aiMessageComponent.createObject(root, {
                "role": message.role,
                "rawContent": message.rawContent,
                "content": message.rawContent,
                "fileMimeType": message.fileMimeType,
                "fileUri": message.fileUri,
                "localFilePath": message.localFilePath,
                "localFilePaths": message.localFilePaths ?? [],
                "model": message.model,
                "thinking": message.thinking,
                "done": message.done,
                "annotations": message.annotations,
                "annotationSources": message.annotationSources,
                "functionName": message.functionName,
                "functionCall": message.functionCall,
                "functionResponse": message.functionResponse,
                "visibleToUser": message.visibleToUser,
            });
        }
    }

    function loadChat(chatName) {
        // Sugar over sessions now: a legacy flat file imports as a session
        // and opens (the original stays); see the sessions view's Legacy
        // section for the same door.
        AiSessions.importLegacy(`${Directories.aiChats}/${chatName.trim()}.json`)
    }
}
