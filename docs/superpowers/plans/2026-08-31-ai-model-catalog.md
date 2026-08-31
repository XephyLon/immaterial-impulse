# AI Model Catalog & OpenRouter Browse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Models carry capability metadata, and an OpenRouter browse view imports models into `extraModels` with one click.

**Architecture:** Pure mapping in `openrouter_models.js` under a read-only fetch singleton; a third canvas view on AiChat's switcher renders the index and writes only `extraModels`; `AiModel` gains `thinking`/`vision`/`contextWindow`. Spec: `docs/superpowers/specs/2026-08-31-ai-model-catalog-design.md`.

**Tech Stack:** QML, qmltestrunner, python pins. Paths relative to `dots/.config/quickshell/imi/`.

**Conventions:** `git commit --only -F - -- <paths>`; no attribution; named tests only; VERIFY green before each commit (gate on "0 failed"/"N/N").

**Facts verified at plan time:** live `/models` entry: `{ id, name, context_length, pricing: { prompt: "0.000000065", completion: ... }, architecture: { input_modalities: [...] }, supported_parameters: [... "reasoning", "include_reasoning" ...] }`, 396 rows; `Ai.safeModelName` replaces `:`/` `/`/`; `addUserModels()` re-runs safely (idempotent adds); the canvas switcher is `activeView` with two Components in `overlayViewLoader`; the picker is `modelPicker` in the composer's commands row with a `Connections` resync.

---

### Task 1: the mapping arithmetic (TDD)

**Files:** Create `services/ai/openrouter_models.js`; Test `tests/tst_openrouter_models.qml`.

Test (write first, run expecting compile FAIL, then implement, expect `0 failed`):

```qml
import QtTest
import "../services/ai/openrouter_models.js" as OR

TestCase {
    name: "OpenRouterModelsTest"

    readonly property var raw: ({
        id: "deepseek/deepseek-v4-flash",
        name: "DeepSeek: V4 Flash",
        context_length: 1310720,
        pricing: { prompt: "0.000000065", completion: "0.00000018" },
        architecture: { input_modalities: ["text", "image"] },
        supported_parameters: ["temperature", "reasoning", "tools"]
    })

    function test_row_mapping() {
        const row = OR.rowFor(raw);
        compare(row.id, "deepseek/deepseek-v4-flash");
        compare(row.provider, "deepseek");
        compare(row.contextWindow, 1310720);
        verify(row.vision);
        verify(row.reasoning);
        verify(Math.abs(row.promptPrice - 0.000000065) < 1e-12);
    }

    function test_row_mapping_defaults() {
        const row = OR.rowFor({ id: "x", name: "X" });
        compare(row.provider, "x");
        compare(row.contextWindow, 0);
        verify(!row.vision);
        verify(!row.reasoning);
        compare(row.promptPrice, 0);
    }

    function test_filter() {
        const rows = [OR.rowFor(raw), OR.rowFor({ id: "openai/gpt-5", name: "GPT-5" })];
        compare(OR.filterRows(rows, "deep").length, 1);
        compare(OR.filterRows(rows, "OPENAI").length, 1);
        compare(OR.filterRows(rows, "").length, 2);
    }

    function test_import_entry_and_dedupe() {
        const entry = OR.importEntry(OR.rowFor(raw));
        compare(entry.model, "deepseek/deepseek-v4-flash");
        compare(entry.key_id, "openrouter");
        compare(entry.api_format, "openai");
        verify(entry.thinking);
        verify(entry.vision);
        compare(entry.endpoint, "https://openrouter.ai/api/v1/chat/completions");
        const one = OR.withImported([], entry);
        const two = OR.withImported(one, entry);
        compare(two.length, 1, "deduped by model id");
    }

    function test_price_label() {
        compare(OR.priceLabel(0, 0), "free");
        verify(OR.priceLabel(0.000000065, 0.00000018).indexOf("/M") !== -1);
    }
}
```

Implementation:

```js
.pragma library

// OpenRouter's /models entries as the shell's rows and imports - pure, so
// the mapping decisions live under a test instead of inside a view.

function rowFor(raw) {
    var id = String(raw?.id ?? "");
    var params = raw?.supported_parameters ?? [];
    var modalities = raw?.architecture?.input_modalities ?? [];
    return {
        id: id,
        name: String(raw?.name ?? id),
        provider: id.indexOf("/") > 0 ? id.slice(0, id.indexOf("/")) : id,
        contextWindow: Number(raw?.context_length ?? 0) || 0,
        promptPrice: Number(raw?.pricing?.prompt ?? 0) || 0,
        completionPrice: Number(raw?.pricing?.completion ?? 0) || 0,
        vision: modalities.indexOf("image") !== -1,
        reasoning: params.indexOf("reasoning") !== -1 || params.indexOf("include_reasoning") !== -1
    };
}

function filterRows(rows, query) {
    var needle = String(query ?? "").toLowerCase().trim();
    if (needle.length === 0) return rows || [];
    return (rows || []).filter(function (row) {
        return row.name.toLowerCase().indexOf(needle) !== -1
            || row.id.toLowerCase().indexOf(needle) !== -1
            || row.provider.toLowerCase().indexOf(needle) !== -1;
    });
}

function importEntry(row) {
    return {
        name: row.name,
        icon: "",
        description: "OpenRouter | " + row.id,
        endpoint: "https://openrouter.ai/api/v1/chat/completions",
        model: row.id,
        requires_key: true,
        key_id: "openrouter",
        key_get_link: "https://openrouter.ai/settings/keys",
        api_format: "openai",
        thinking: !!row.reasoning,
        vision: !!row.vision,
        contextWindow: row.contextWindow
    };
}

function withImported(extraModels, entry) {
    var next = (extraModels || []).slice();
    if (next.some(function (m) { return m.model === entry.model; })) return next;
    next.push(entry);
    return next;
}

// Per-token to per-million, the unit people quote.
function priceLabel(prompt, completion) {
    if (!prompt && !completion) return "free";
    function m(v) { return "$" + (v * 1e6).toFixed(2); }
    return m(prompt) + "/" + m(completion) + " /M";
}
```

Commit: `feat(ai): the OpenRouter mapping arithmetic`.

---

### Task 2: capability fields + fetch singleton

**Files:** Modify `services/ai/AiModel.qml` (three properties); Create `services/ai/OpenRouterModels.qml`... placed at `services/OpenRouterModels.qml` (same registration lesson as AiSessions: `services/ai/` is a different implicit module and this singleton reads `Ai`-adjacent globals - it only needs Quickshell+its js though, so `services/ai/` would work; keep `services/` for consistency with AiSessions/AiDrafts).

AiModel additions after `property var extraParams: ({})`:

```qml
    // Capability metadata (spec 2026-08-31): `thinking` is what the
    // reasoning ask reads; `vision` and `contextWindow` are stored and
    // shown (browse rows) but not enforced yet - provider-fetched models
    // cannot declare them, and a false "can't see images" is worse than no
    // gate. `tools` above is the request schema list, not a capability.
    property bool thinking: false
    property bool vision: false
    property int contextWindow: 0
```

`services/OpenRouterModels.qml`:

```qml
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "./ai/openrouter_models.js" as OR

/**
 * Read-only OpenRouter model index for the browse view (spec 2026-08-31):
 * fetched on demand, cached five minutes, never writes anything anywhere.
 * The import decision belongs to the view; the mapping to the js.
 */
Singleton {
    id: root

    readonly property string endpoint: "https://openrouter.ai/api/v1/models?output_modalities=text&sort=most-popular"
    readonly property int cacheTtlMs: 300000

    property var models: []
    property bool loading: false
    property string error: ""
    property double fetchedAt: 0

    function refresh(force = false) {
        if (root.loading) return;
        if (!force && root.models.length > 0
                && (Date.now() - root.fetchedAt) < root.cacheTtlMs) return;
        root.loading = true;
        root.error = "";
        fetchProc.running = true;
    }

    Process {
        id: fetchProc
        command: ["curl", "-sL", "--max-time", "15", root.endpoint]
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                try {
                    const parsed = JSON.parse(text);
                    const list = parsed?.data ?? [];
                    root.models = list.map(raw => OR.rowFor(raw));
                    root.fetchedAt = Date.now();
                    if (root.models.length === 0)
                        root.error = "OpenRouter answered with no models.";
                } catch (e) {
                    root.error = "Could not read OpenRouter's answer - offline, or the index moved.";
                }
            }
        }
    }
}
```

Verify: `tst_openrouter_models` still green; qmllint both files. Commit: `feat(ai): capability fields and the read-only OpenRouter index`.

---

### Task 3: the browse view and its doors

**Files:** Create `modules/imi/sidebarLeft/aiChat/BrowseModelsView.qml`; Modify `modules/imi/sidebarLeft/AiChat.qml` (third Component + picker sentinel), keys view door.

`BrowseModelsView.qml` (sessions-view grammar):

```qml
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../../../services/ai/openrouter_models.js" as OR
import QtQuick
import QtQuick.Layouts

/**
 * OpenRouter browse-and-import (spec 2026-08-31): a read-only remote
 * index; a click imports ONE model into extraModels and selects it -
 * nothing auto-imports. Hosted by AiChat's view switcher.
 */
Rectangle {
    id: root
    color: Appearance.colors.colLayer1
    radius: Appearance.rounding.large

    signal closed()

    transform: Translate { id: slideIn }
    Component.onCompleted: {
        slideIn.x = 24;
        slideAnim.start();
        OpenRouterModels.refresh();
        if (!KeyringStorage.loaded) KeyringStorage.fetchKeyringData();
    }
    NumberAnimation {
        id: slideAnim
        target: slideIn
        property: "x"
        to: 0
        duration: Appearance.animation.elementMoveEnter.duration
        easing.type: Easing.OutExpo
    }

    property string query: ""
    readonly property var filtered: OR.filterRows(OpenRouterModels.models, root.query)
    readonly property int shownCap: 60

    function importRow(row) {
        Config.options.ai.extraModels = OR.withImported(
            Config.options.ai.extraModels ?? [], OR.importEntry(row));
        Ai.addUserModels();
        Ai.setModel(Ai.safeModelName(row.id));
        root.closed();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Appearance.spacing.space150
        spacing: Appearance.spacing.space100

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.space100
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                onClicked: root.closed()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                }
            }
            StyledText {
                text: Translation.tr("Browse models")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
            Item { Layout.fillWidth: true }
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                onClicked: OpenRouterModels.refresh(true)
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "refresh"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                }
                StyledToolTip { text: Translation.tr("Refresh the index") }
            }
        }

        ConfigTextArea {
            Layout.fillWidth: true
            buttonIcon: "key"
            text: Translation.tr("OpenRouter key")
            placeholderText: Translation.tr("Enter API key")
            password: true
            value: KeyringStorage.loaded ? (KeyringStorage.keyringData.apiKeys?.openrouter || "") : ""
            onValueChanged: {
                if (!textArea.activeFocus) return;
                const currentText = value;
                Qt.callLater(() => {
                    if (KeyringStorage.loaded)
                        KeyringStorage.setNestedField(["apiKeys", "openrouter"], currentText);
                });
            }
        }

        ConfigTextArea {
            Layout.fillWidth: true
            buttonIcon: "search"
            text: Translation.tr("Search")
            placeholderText: Translation.tr("Model, provider…")
            value: root.query
            onValueChanged: root.query = value
        }

        StyledText {
            visible: OpenRouterModels.loading
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("Fetching the index…")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }
        StyledText {
            visible: OpenRouterModels.error.length > 0 && !OpenRouterModels.loading
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: OpenRouterModels.error
            color: Appearance.m3colors.m3error
            font.pixelSize: Appearance.font.pixelSize.small
        }

        StyledFlickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: rowsColumn.implicitHeight

            ColumnLayout {
                id: rowsColumn
                width: parent.width
                spacing: Appearance.spacing.space25

                Repeater {
                    model: root.filtered.slice(0, root.shownCap)
                    delegate: RippleButton {
                        id: modelRow
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 52
                        buttonRadius: Appearance.rounding.normal
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: root.importRow(modelRow.modelData)
                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Appearance.spacing.space150
                            anchors.rightMargin: Appearance.spacing.space150
                            spacing: Appearance.spacing.space100
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: modelRow.modelData.name
                                    color: Appearance.colors.colOnLayer1
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: `${modelRow.modelData.provider} · ${Math.round(modelRow.modelData.contextWindow / 1000)}k · ${OR.priceLabel(modelRow.modelData.promptPrice, modelRow.modelData.completionPrice)}`
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                }
                            }
                            MaterialSymbol {
                                visible: modelRow.modelData.reasoning
                                text: "star_shine"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colPrimary
                                StyledToolTip { text: Translation.tr("Reasoning") }
                            }
                            MaterialSymbol {
                                visible: modelRow.modelData.vision
                                text: "visibility"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colSubtext
                                StyledToolTip { text: Translation.tr("Vision") }
                            }
                        }
                    }
                }

                StyledText {
                    visible: root.filtered.length > root.shownCap
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("%1 more - type to narrow").arg(root.filtered.length - root.shownCap)
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
        }
    }
}
```

AiChat wiring: third Component beside sessions/keys:

```qml
                Component {
                    id: browseViewComponent
                    BrowseModelsView {
                        onClosed: root.activeView = ""
                    }
                }
```

switcher chooser gains `: root.activeView === "browse" ? browseViewComponent`; picker model gains the sentinel appended: `.concat([{ name: Translation.tr("Browse models…"), value: "__browse__" }])` and onActivated:

```qml
                    onActivated: index => {
                        const chosen = modelPicker.model[index];
                        if (!chosen) return;
                        if (chosen.value === "__browse__") {
                            root.activeView = "browse";
                            modelPicker.currentIndex = Ai.pickerModelList.indexOf(Ai.currentModelId);
                            return;
                        }
                        Ai.setModel(chosen.value);
                    }
```

Keys view door: an EmptyStateKey-style row is overkill inside the keys column - a plain actionable row (RippleButton, "travel_explore" glyph, "Browse OpenRouter models") appended under the providers editor, `onClicked: root.activeView = "browse"` (the keys component can reach `root`).

Verify: qmllint all touched; pins grown in Task 4. Commit: `feat(ai): browse OpenRouter, import with one click`.

---

### Task 4: pins + receipts + deploy

Pins appended to `tests/test_ai_skeleton_contract.py` (before the guard):

```python
def test_the_browse_view_rides_the_switcher_and_writes_only_extra_models():
    chat = CHAT.read_text(encoding="utf-8")
    assert '"browse"' in chat and "BrowseModelsView" in chat
    view = (ROOT / "modules/imi/sidebarLeft/aiChat/BrowseModelsView.qml").read_text(encoding="utf-8")
    assert "Config.options.ai.extraModels" in view
    assert "customProviders" not in view, "the browse import must not touch providers"
    model = (ROOT / "services/ai/AiModel.qml").read_text(encoding="utf-8")
    for field in ("property bool thinking", "property bool vision", "property int contextWindow"):
        assert field in model, f"AiModel lost {field}"
```

CHANGELOG (top of Added):

```markdown
- **Browse OpenRouter, import with one click.** The picker's "Browse
  models…" row (and a door in Providers & keys) opens a searchable index
  of OpenRouter's catalogue - context, pricing, reasoning and vision at
  a glance. A click imports the model, keys it to your OpenRouter key,
  and selects it. Models now carry capability metadata; reasoning is
  requested wherever a model declares it.
```

tests-README:

```markdown
* **OpenRouter mapping tests (`tst_openrouter_models.qml`)**: the /models entry mapping (provider from the id, vision from input modalities, reasoning from supported parameters, per-token prices), the filter, the import entry shape and its dedupe, and the per-million price label. The skeleton contract pins the browse view to the one switcher and its import to extraModels alone.
```

Deploy + full restart (new singleton + view files); log check. Commit: `docs: receipts for the OpenRouter browse`.

## Self-review

Coverage: mapping+tests (T1), capability fields + singleton (T2), view + sentinel + keys door + import path incl. addUserModels/setModel/safeModelName (T3), pins/receipts/deploy (T4). Type consistency: `OR.rowFor/filterRows/importEntry/withImported/priceLabel` uniform; `activeView === "browse"` matches the pin. Deviation (no attach gate) carried from the spec.
