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
    readonly property string interfaceRole: "interface"
    readonly property string apiKeyEnvVarName: "API_KEY"

    signal responseFinished()

    property string systemPrompt: {
        let prompt = Config.options?.ai?.systemPrompt ?? "";
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
    property var tools: {
        "gemini": {
            "functions": [{"functionDeclarations": [
                {
                    "name": "switch_to_search_mode",
                    "description": "Search the web",
                },
                {
                    "name": "get_shell_config",
                    "description": "Get the desktop shell config file contents",
                },
                {
                    "name": "set_shell_config",
                    "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "key": {
                                "type": "string",
                                "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting.",
                            },
                            "value": {
                                "type": "string",
                                "description": "The value to set, e.g. `true`"
                            }
                        },
                        "required": ["key", "value"]
                    }
                },
                {
                    "name": "run_shell_command",
                    "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "command": {
                                "type": "string",
                                "description": "The bash command to run",
                            },
                        },
                        "required": ["command"]
                    }
                },
            ]}],
            "search": [{
                "google_search": {}
            }],
            "none": []
        },
        "openai": {
            "functions": [
                {
                    "type": "function",
                    "function": {
                        "name": "get_shell_config",
                        "description": "Get the desktop shell config file contents",
                        "parameters": {}
                    },
                },
                {
                    "type": "function",
                    "function": {
                        "name": "set_shell_config",
                        "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "key": {
                                    "type": "string",
                                    "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting.",
                                },
                                "value": {
                                    "type": "string",
                                    "description": "The value to set, e.g. `true`"
                                }
                            },
                            "required": ["key", "value"]
                        }
                    }
                },
                {
                    "type": "function",
                    "function": {
                        "name": "run_shell_command",
                        "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "command": {
                                    "type": "string",
                                    "description": "The bash command to run",
                                },
                            },
                            "required": ["command"]
                        }
                    },
                },
            ],
            "search": [],
            "none": [],
        },
        "mistral": {
            "functions": [
                {
                    "type": "function",
                    "function": {
                        "name": "get_shell_config",
                        "description": "Get the desktop shell config file contents",
                        "parameters": {}
                    },
                },
                {
                    "type": "function",
                    "function": {
                        "name": "set_shell_config",
                        "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "key": {
                                    "type": "string",
                                    "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting.",
                                },
                                "value": {
                                    "type": "string",
                                    "description": "The value to set, e.g. `true`"
                                }
                            },
                            "required": ["key", "value"]
                        }
                    }
                },
                {
                    "type": "function",
                    "function": {
                        "name": "run_shell_command",
                        "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "command": {
                                    "type": "string",
                                    "description": "The bash command to run",
                                },
                            },
                            "required": ["command"]
                        }
                    },
                },
            ],
            "search": [],
            "none": [],
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
    readonly property bool isGenerating: requester.running

    // TEMPORARY TRACER (remove when the provider-wipe is caught): the
    // maintainer's custom provider has twice been found blanked -
    // {enabled:true, name:"", baseUrl:""} - by an in-memory change some
    // later config flush persisted. This logs every change of the list
    // with a timestamp, so the wiping write self-identifies in the
    // instance log instead of being reconstructed from guesses.
    property Connections providerWipeTracer: Connections {
        target: Config.options.ai
        function onCustomProvidersChanged() {
            console.log("[Ai][trace] customProviders ->",
                JSON.stringify(Config.options.ai.customProviders));
        }
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
    property string pendingFilePath: ""

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
            
            // Positional args ($1/$2), never spliced into the script body: apiKey
            // is a secret and baseUrl comes from custom-provider config (which flows
            // through shareable presets), so interpolating them into a double-quoted
            // bash string - where $()/backticks expand - was a command-injection hole.
            // The status code rides on the last line, so a failure can say
            // what it was: the old "Failed to fetch" covered a 404 from a
            // base URL that already ended in /models, a 401 from a missing
            // key and a server that was not there, and a reader could act on
            // none of them.
            command: ["bash", "-c", 'curl -sL --max-time 10 -H "Authorization: Bearer $1" -w "\n%{http_code}" "$2/models" 2>/dev/null', "bash", apiKey, baseUrl]
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
                    const parsedModels = AiModelsParser.parseCustomProviderModels(body, fetcherProcess.baseUrl, fetcherProcess.providerName, `custom_provider_${fetcherProcess.providerIndex}`);
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
                providerIndex: i
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

            /* Build endpoint, request data */
            const endpoint = root.currentApiStrategy.buildEndpoint(model);
            const messageArray = root.messageIDs.map(id => root.messageByID[id]);
            const filteredMessageArray = messageArray.filter(message => message.role !== Ai.interfaceRole);
            const data = root.currentApiStrategy.buildRequestData(model, filteredMessageArray, root.systemPrompt, root.temperature, root.tools[model.api_format][root.currentTool], root.pendingFilePath);
            // console.log("[Ai] Request data: ", JSON.stringify(data, null, 2));

            let requestHeaders = {
                "Content-Type": "application/json",
            }
            
            /* Create local message object */
            requester.message = root.aiMessageComponent.createObject(root, {
                "role": "assistant",
                "model": currentModelId,
                "content": "",
                "rawContent": "",
                "thinking": true,
                "done": false,
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
            if (root.pendingFilePath && root.pendingFilePath.length > 0) {
                requester.message.localFilePath = root.pendingFilePath;
                scriptFileSetupContent = requester.currentStrategy.buildScriptFileSetup(root.pendingFilePath);
                root.pendingFilePath = ""
            }

            /* Create command string */
            let scriptRequestContent = ""
            scriptRequestContent += `curl --no-buffer "${endpoint}"`
                + ` ${headerString}`
                + (authHeader ? ` ${authHeader}` : "")
                + ` --data '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(data))}'`
                + "\n"
            
            /* Send the request */
            const scriptContent = requester.currentStrategy.finalizeScriptContent(scriptShebang + scriptFileSetupContent + scriptRequestContent)
            const shellScriptPath = CF.FileUtils.trimFileProtocol(root.requestScriptFilePath)
            requesterScriptFile.path = Qt.resolvedUrl(shellScriptPath)
            requesterScriptFile.setText(scriptContent)
            requester.command = baseCommand.concat([shellScriptPath]);
            requester.running = true
        }

        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0) return;
                if (requester.message.thinking) requester.message.thinking = false;
                // console.log("[Ai] Raw response line: ", data);

                // Handle response line
                try {
                    const result = requester.currentStrategy.parseResponseLine(data, requester.message);
                    // console.log("[Ai] Parsed response result: ", JSON.stringify(result, null, 2));

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
            const result = requester.currentStrategy.onRequestFinished(requester.message);
            
            if (result.finished) {
                requester.markDone();
            } else if (!requester.message.done) {
                requester.markDone();
            }

            // Handle error responses
            if (requester.message.content.includes("API key not valid")) {
                root.addApiKeyAdvice(models[requester.message.model]);
            }
        }
    }

    function sendUserMessage(message) {
        if (message.length === 0) return;
        // The first user message of an unsaved chat mints its session -
        // lazily, so an empty chat never touches disk (spec 2026-08-31).
        AiSessions.mint(message);
        root.addMessage(message, "user");
        requester.makeRequest();
    }

    function attachFile(filePath: string) {
        root.pendingFilePath = CF.FileUtils.trimFileProtocol(filePath);
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
