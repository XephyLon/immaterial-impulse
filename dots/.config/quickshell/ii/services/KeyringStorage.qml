pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import Quickshell;
import Quickshell.Io;
import QtQuick;

/**
 * For storing sensitive data in the keyring.
 * Use this for small data only, since it stores a JSON of the contents directly and doesn't use a database.
 */
Singleton {
    id: root

    signal dataChanged()

    property bool loaded: false
    property var keyringData: ({})
    
    property var properties: {
        "application": "immaterial-impulse",
        "explanation": Translation.tr("For storing API keys and other sensitive information"),
    }
    property var propertiesAsArgs: Object.keys(root.properties).reduce(
        function(arr, key) {
            return arr.concat([key, root.properties[key]]);
        }, []
    )
    property string keyringLabel: Translation.tr("%1 Safe Storage").arg("Immaterial Impulse")

    // Pre-rebrand secrets were stored under this attribute. Kept only as a
    // fallback lookup id so existing users aren't forced to re-enter API keys:
    // see legacyLookup below, which re-keys a hit under the new application
    // attribute so the fallback is only ever needed once per machine.
    readonly property string legacyApplication: "illogical-impulse"

    function setNestedField(path, value) {
        if (!root.keyringData) root.keyringData = {};
        let keys = path;
        let obj = root.keyringData;
        let parents = [obj];

        // Traverse and collect parent objects
        for (let i = 0; i < keys.length - 1; ++i) {
            if (!obj[keys[i]] || typeof obj[keys[i]] !== "object") {
                obj[keys[i]] = {};
            }
            obj = obj[keys[i]];
            parents.push(obj);
        }

        // Set the value at the innermost key
        obj[keys[keys.length - 1]] = value;

        // Reassign each parent object from the bottom up to trigger change notifications
        for (let i = keys.length - 2; i >= 0; --i) {
            let parent = parents[i];
            let key = keys[i];
            // Shallow clone to change object identity (spread replaced with Object.assign)
            parent[key] = Object.assign({}, parent[key]);
        }

        // Finally, reassign root.keyringData to trigger top-level change
        root.keyringData = Object.assign({}, root.keyringData);

        saveKeyringData();
    }

    function fetchKeyringData() {
        // console.log("[KeyringStorage] Fetching keyring data...");
        // console.log("[KeyringStorage] getData command:'" + getData.command.join("' '") + "'");
        getData.running = true;
    }

    function saveKeyringData() {
        saveData.stdinEnabled = true;
        saveData.running = true;
    }

    Process {
        id: saveData
        command: [
            "secret-tool", "store", "--label=" + keyringLabel,
            ...propertiesAsArgs,
        ]
        onRunningChanged: {
            if (saveData.running) {
                // console.log("[KeyringStorage] Saving with command: '" + saveData.command.join("' '") + "'");
                saveData.write(JSON.stringify(root.keyringData));
                root.dataChanged()
                stdinEnabled = false // End input stream
            }
        }
    }

    Process {
        id: getData
        command: [ // We need to use echo for a newline so splitparser does parse
            "bash", "-c", `${Directories.scriptPath}/keyring/try_lookup.sh 2> /dev/null`,
        ]
        stdout: StdioCollector {
            id: keyringDataOutputCollector
            onStreamFinished: {
                const data = keyringDataOutputCollector.text;
                if (data.length === 0 || !data.startsWith("{")) return;
                try {
                    root.keyringData = JSON.parse(data);
                    // console.log("[KeyringStorage] Keyring data fetched:", JSON.stringify(root.keyringData));
                } catch (e) {
                    console.error("[KeyringStorage] Failed to get keyring data, reinitializing.");
                    root.keyringData = {};
                    saveKeyringData()
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            // console.log("[KeyringStorage] Keyring data fetch process exited with code:", exitCode);
            if (exitCode === 1) {
                // Not found under the current application attribute. Before
                // giving up, check whether this is a pre-rebrand secret sitting
                // under the legacy attribute rather than truly missing.
                console.error("[KeyringStorage] Entry not found under '" + root.properties.application + "', trying legacy attribute.");
                legacyLookup.running = true;
                return;
            }
            if (exitCode !== 2) {
                root.loaded = true;
            }
        }
    }

    // Fallback for secrets stored before the rebrand: looks up the old
    // "illogical-impulse" application attribute directly via secret-tool. A
    // hit is lazily re-keyed under the new attribute (via saveKeyringData) so
    // no user ever has to re-enter their API keys, and this fallback is only
    // exercised once per machine.
    //
    // Only a CONFIRMED miss (secret-tool's own "no matching item" exit code)
    // is license to fresh-init. Every other outcome - a lookup error, a
    // locked collection, or output that doesn't parse - is ambiguous, not
    // proof the secret doesn't exist, so it's left untouched: keyringData and
    // root.loaded stay as they are and the next launch retries the whole
    // fallback. This mirrors how getData already treats a locked keyring
    // (exitCode === 2): don't touch state, don't mark loaded, just try again
    // later. Blindly fresh-initing here would permanently orphan a real
    // legacy secret after one transient failure.
    Process {
        id: legacyLookup
        command: ["secret-tool", "lookup", "application", root.legacyApplication]
        stdout: StdioCollector {
            id: legacyLookupCollector
        }
        onExited: (exitCode, exitStatus) => {
            const data = legacyLookupCollector.text;
            if (exitCode === 0 && data.length > 0 && data.startsWith("{")) {
                try {
                    root.keyringData = JSON.parse(data);
                    console.error("[KeyringStorage] Found legacy data under '" + root.legacyApplication + "', re-keying to '" + root.properties.application + "'.");
                    saveKeyringData(); // Re-key under the new application attribute.
                    root.loaded = true;
                } catch (e) {
                    // A real secret exists but failed to parse - not a
                    // confirmed absence. Leave it for the next launch rather
                    // than overwriting it with {}.
                    console.error("[KeyringStorage] Legacy keyring data failed to parse; leaving untouched for retry.");
                }
            } else if (exitCode === 1) {
                // secret-tool confirms no matching item under the legacy
                // attribute either. We only reach legacyLookup after
                // try_lookup.sh's own is_unlocked.sh check passed, so the
                // collection is known unlocked and this exit code is a real
                // "not found", not a locked-keyring false negative.
                console.error("[KeyringStorage] No legacy entry either, initializing.");
                root.keyringData = {};
                saveKeyringData();
                root.loaded = true;
            } else {
                // Inconclusive (lookup error, unexpected exit code, or an
                // empty/malformed result that didn't come with a confirmed
                // miss). Leave state untouched so the next launch re-attempts
                // the fallback instead of orphaning a real legacy secret.
                console.error("[KeyringStorage] Legacy lookup inconclusive (exit " + exitCode + "); leaving untouched for retry.");
            }
        }
    }

}
