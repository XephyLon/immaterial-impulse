import QtQuick;

/**
 * An AI model representation.
 * - name: Friendly name of the model
 * - icon: Icon name of the model
 * - description: Description of the model
 * - endpoint: Endpoint of the model
 * - model: Model code (like gpt-4.1 or gemini-2.5-flash)
 * - requires_key: Whether the model requires an API key
 * - key_id: The identifier of the API key. Use the same identifier for models that can be accessed with the same key.
 * - key_get_link: Link to get an API key
 * - key_get_description: Description of pricing and how to get an API key
 * - api_format: The API format of the model. Can be "openai" or "gemini". Default is "openai".
 * - extraParams: Extra parameters to be passed to the model. This is a JSON object.
 */

QtObject {
    property string name
    // Which custom provider fetched this model - the parser stamps it so
    // browse rows and headers can say "CLIP: ..." without re-deriving.
    property string providerName: ""
    property string icon
    property string description
    property string homepage
    property string endpoint
    property string model
    property bool requires_key: true
    property string key_id
    property string key_get_link
    property string key_get_description
    property string api_format: "openai"
    property var tools
    property var extraParams: ({})
    // Capability metadata (spec 2026-08-31): `thinking` is what the
    // reasoning ask reads; `vision` and `contextWindow` are stored and
    // shown (browse rows) but not enforced yet - provider-fetched models
    // cannot declare them, and a false "can't see images" is worse than
    // no gate. `tools` above is the request schema list, not a capability.
    property bool thinking: false
    property bool vision: false
    property int contextWindow: 0
}
