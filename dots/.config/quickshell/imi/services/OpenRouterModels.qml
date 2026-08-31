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
