"""The AI catalog and Ai.qml cannot drift while the wiring waits.

services/ai_catalog.js declares every built-in provider and model in one
place; services/Ai.qml still carries its own literals until stage 2 of
docs/proposals/ai-assistant-upgrade.md wires it to the catalog. Two copies of
one truth is exactly the shape this repo keeps paying for (BarWidgets,
MprisController), so until the second copy is deleted this module pins them
equal, field by field:

- every built-in model Ai.qml declares exists in the catalog under the same
  legacy id, with the same resolved endpoint, model value, dialect
  (api_format), key id, key link and requires_key;
- every non-discovered catalog model is declared in Ai.qml - a model added to
  only one side fails in either direction;
- the catalog's dialect vocabulary matches Ai.qml's apiStrategies keys and
  the strategy files under services/ai/;
- the Ollama discovery endpoint Ai.qml hands discovered models matches the
  catalog's ollama provider record;
- ai_catalog.js stays pure: `.pragma library`, no imports, no Qt.

The parsers are proven against in-memory fixtures first (asserted counts),
so a reformat that makes them match nothing is loud rather than green.

When stage 2 lands, most of this module inverts: Ai.qml stops declaring
model literals and the pin becomes "Ai.qml declares none".
"""

import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
AI_QML = ROOT / "services" / "Ai.qml"
CATALOG_JS = ROOT / "services" / "ai_catalog.js"
STRATEGY_DIR = ROOT / "services" / "ai"

# dialect id -> the strategy file that implements it
DIALECT_STRATEGY_FILES = {
    "gemini": "GeminiApiStrategy.qml",
    "openai": "OpenAiApiStrategy.qml",
    "mistral": "MistralApiStrategy.qml",
    "anthropic": "AnthropicApiStrategy.qml",
}


def _matching_brace(text, start, open_ch, close_ch):
    """Index just past the brace matching text[start], skipping strings."""
    assert text[start] == open_ch, f"expected {open_ch!r} at {start}"
    depth = 0
    i = start
    in_string = None
    while i < len(text):
        ch = text[i]
        if in_string:
            if ch == "\\":
                i += 2
                continue
            if ch == in_string:
                in_string = None
        elif ch in "\"'`":
            in_string = ch
        elif ch == open_ch:
            depth += 1
        elif ch == close_ch:
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise AssertionError(f"unbalanced {open_ch} starting at {start}")


def _string_field(block, name):
    m = re.search(r'"%s"\s*:\s*"((?:[^"\\]|\\.)*)"' % re.escape(name), block)
    return m.group(1) if m else None


def _bool_field(block, name):
    m = re.search(r'"%s"\s*:\s*(true|false)' % re.escape(name), block)
    return m.group(1) == "true" if m else None


def parse_ai_qml_builtins(text):
    """Ai.qml's built-in models: {legacy_id: {field: value}}."""
    result = {}
    for m in re.finditer(
            r'"([\w.\-]+)"\s*:\s*aiModelComponent\.createObject\(this,\s*\{',
            text):
        key = m.group(1)
        start = m.end() - 1
        end = _matching_brace(text, start, "{", "}")
        block = text[start:end]
        result[key] = {
            "endpoint": _string_field(block, "endpoint"),
            "model": _string_field(block, "model"),
            "api_format": _string_field(block, "api_format") or "openai",
            "key_id": _string_field(block, "key_id"),
            "key_get_link": _string_field(block, "key_get_link"),
            "requires_key": _bool_field(block, "requires_key"),
        }
    return result


def parse_catalog_providers(text):
    """ai_catalog.js's PROVIDERS: [{...provider fields, models: [...]}]."""
    m = re.search(r"var PROVIDERS\s*=\s*\[", text)
    assert m, "PROVIDERS declaration not found in ai_catalog.js"
    list_start = m.end() - 1
    list_end = _matching_brace(text, list_start, "[", "]")
    body = text[list_start + 1:list_end - 1]

    providers = []
    i = 0
    while True:
        brace = body.find("{", i)
        if brace < 0:
            break
        end = _matching_brace(body, brace, "{", "}")
        block = body[brace:end]
        i = end

        models_match = re.search(r'"models"\s*:\s*\[', block)
        assert models_match, "provider block without a models list"
        models_start = models_match.end() - 1
        models_end = _matching_brace(block, models_start, "[", "]")
        models_body = block[models_start + 1:models_end - 1]
        head = block[:models_start]

        models = []
        j = 0
        while True:
            mb = models_body.find("{", j)
            if mb < 0:
                break
            me = _matching_brace(models_body, mb, "{", "}")
            entry = models_body[mb:me]
            j = me
            models.append({
                "value": _string_field(entry, "value"),
                "legacyId": _string_field(entry, "legacyId"),
                "endpoint": _string_field(entry, "endpoint"),
            })

        providers.append({
            "id": _string_field(head, "id"),
            "dialect": _string_field(head, "dialect"),
            "endpoint": _string_field(head, "endpoint"),
            "keyId": _string_field(head, "keyId"),
            "keyGetLink": _string_field(head, "keyGetLink"),
            "requiresKey": _bool_field(head, "requiresKey"),
            "discovered": _bool_field(head, "discovered") or False,
            "models": models,
        })
    return providers


def parse_catalog_dialects(text):
    m = re.search(r"var DIALECTS\s*=\s*\{", text)
    assert m, "DIALECTS declaration not found in ai_catalog.js"
    start = m.end() - 1
    end = _matching_brace(text, start, "{", "}")
    body = text[start:end]
    return sorted(set(re.findall(r'"id"\s*:\s*"(\w+)"', body)))


def parse_ai_qml_strategy_keys(text):
    m = re.search(r"property var apiStrategies\s*:\s*\{", text)
    assert m, "apiStrategies declaration not found in Ai.qml"
    start = m.end() - 1
    end = _matching_brace(text, start, "{", "}")
    body = text[start:end]
    return sorted(set(re.findall(r'"(\w+)"\s*:\s*\w+ApiStrategy\.createObject', body)))


# ── Parser self-checks against in-memory fixtures ────────────────────────────

_QML_FIXTURE = """
    property var models: cond ? {} : {
        "fixture-model": aiModelComponent.createObject(this, {
            "name": "Fixture {braces} in string",
            "endpoint": "https://example.test/v1beta/models/fixture-1:streamGenerateContent",
            "model": "fixture-1",
            "requires_key": true,
            "key_id": "fixture",
            "key_get_link": "https://example.test/keys",
            "api_format": "gemini",
        }),
        "fixture-openai": aiModelComponent.createObject(this, {
            "endpoint": "https://example.test/v1/chat/completions",
            "model": "fixture-2",
            "requires_key": false,
        }),
    }
    property var apiStrategies: {
        "openai": openaiApiStrategy.createObject(this),
        "gemini": geminiApiStrategy.createObject(this),
    }
"""

_JS_FIXTURE = """
var DIALECTS = {
    "gemini": { "id": "gemini", "endpointShape": "model-in-path", "auth": "query-key", "streaming": "json-array" },
    "openai": { "id": "openai", "endpointShape": "chat-completions", "auth": "bearer-header", "streaming": "sse" }
};
var PROVIDERS = [
    {
        "id": "fixture",
        "dialect": "gemini",
        "endpoint": "https://example.test/v1beta/models/{model}:streamGenerateContent",
        "requiresKey": true,
        "keyId": "fixture",
        "keyGetLink": "https://example.test/keys",
        "models": [
            { "value": "fixture-1", "name": "Fixture", "legacyId": "fixture-model" }
        ]
    },
    {
        "id": "disc",
        "dialect": "openai",
        "endpoint": "https://example.test/v1/chat/completions",
        "requiresKey": false,
        "discovered": true,
        "models": []
    }
];
"""


def test_the_parsers_find_what_the_fixtures_hold():
    qml = parse_ai_qml_builtins(_QML_FIXTURE)
    assert len(qml) == 2, f"fixture parse found {sorted(qml)}"
    assert qml["fixture-model"]["endpoint"] == \
        "https://example.test/v1beta/models/fixture-1:streamGenerateContent"
    assert qml["fixture-model"]["requires_key"] is True
    assert qml["fixture-openai"]["api_format"] == "openai"  # the default
    assert qml["fixture-openai"]["requires_key"] is False

    provs = parse_catalog_providers(_JS_FIXTURE)
    assert len(provs) == 2, f"fixture parse found {len(provs)} providers"
    assert provs[0]["id"] == "fixture"
    assert provs[0]["models"][0]["legacyId"] == "fixture-model"
    assert provs[1]["discovered"] is True

    assert parse_catalog_dialects(_JS_FIXTURE) == ["gemini", "openai"]
    assert parse_ai_qml_strategy_keys(_QML_FIXTURE) == ["gemini", "openai"]


# ── The contract ─────────────────────────────────────────────────────────────

def _catalog_models_by_legacy_id():
    providers = parse_catalog_providers(CATALOG_JS.read_text())
    result = {}
    for provider in providers:
        if provider["discovered"]:
            continue
        for model in provider["models"]:
            legacy = model["legacyId"]
            assert legacy, (
                f"catalog model {provider['id']}:{model['value']} carries no "
                f"legacyId; every non-discovered built-in needs the Ai.qml key "
                f"it mirrors until stage 2 removes the second copy")
            template = model["endpoint"] or provider["endpoint"]
            result[legacy] = {
                "endpoint": template.replace("{model}", model["value"]),
                "model": model["value"],
                "api_format": provider["dialect"],
                "key_id": provider["keyId"],
                "key_get_link": provider["keyGetLink"],
                "requires_key": provider["requiresKey"],
            }
    return result


def test_ai_qml_declares_no_builtin_models():
    """The inversion the module docstring promised: built-ins are gone
    (maintainer's call, 2026-08-31) - the user brings providers, and the
    catalog's builtin records remain only as data for the parsers and any
    future first-run material. A model literal reappearing in Ai.qml is
    the two-copies drift coming back."""
    body = AI_QML.read_text(encoding="utf-8")
    assert "property var models: ({})" in body, (
        "Ai.qml's models map must start empty - providers fill it")
    assert "key_get_link\":" not in body and "\"key_get_link\"" not in body, (
        "a built-in model literal (a quoted key_get_link field) is back in Ai.qml")


def test_the_dialect_vocabulary_matches_the_strategies():
    dialects = parse_catalog_dialects(CATALOG_JS.read_text())
    strategy_keys = parse_ai_qml_strategy_keys(AI_QML.read_text())
    assert dialects == strategy_keys, (
        f"catalog dialects {dialects} != Ai.qml apiStrategies {strategy_keys}")
    assert dialects == sorted(DIALECT_STRATEGY_FILES), (
        f"catalog dialects {dialects} do not match this module's "
        f"dialect-to-strategy-file map; update DIALECT_STRATEGY_FILES with "
        f"the new strategy")
    for dialect, filename in DIALECT_STRATEGY_FILES.items():
        assert (STRATEGY_DIR / filename).is_file(), (
            f"dialect {dialect!r} names {filename}, which does not exist "
            f"under services/ai/")


def test_the_ollama_discovery_endpoint_matches_the_catalog():
    catalog_providers = parse_catalog_providers(CATALOG_JS.read_text())
    ollama = next((p for p in catalog_providers if p["id"] == "ollama"), None)
    assert ollama is not None, "the catalog lost its ollama provider record"
    assert ollama["discovered"], "ollama must stay a discovered provider"
    assert ollama["endpoint"] in AI_QML.read_text(), (
        f"Ai.qml's Ollama discovery no longer hands out the endpoint the "
        f"catalog records ({ollama['endpoint']})")


def test_the_catalog_stays_pure():
    text = CATALOG_JS.read_text()
    assert text.startswith(".pragma library"), (
        "ai_catalog.js must stay a .pragma library")
    assert not re.search(r"^\s*\.import\b", text, re.M), (
        "ai_catalog.js must not import anything - inputs arrive as arguments")
    assert not re.search(r"\bQt\.\w+", text), (
        "ai_catalog.js must not reach Qt; it has no engine context to assume")
    # Describing HOW a key travels (auth: "bearer-header") is catalog data;
    # holding or fetching one is not, so the names the key plumbing uses may
    # not appear in the CODE at all. Comments are free to state the rule.
    code = re.sub(r"//[^\n]*", "", text)
    for secret_shape in ("apiKey", "api_key", "KeyringStorage", "keyringData"):
        assert secret_shape not in code, (
            f"ai_catalog.js code mentions {secret_shape!r}: the catalog "
            f"carries key metadata, never key material or key plumbing")


if __name__ == "__main__":
    import sys
    from contract_runner import run
    sys.exit(run(globals()))
