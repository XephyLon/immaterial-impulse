pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common

/**
 * The active phone's contacts (docs/superpowers/specs/2026-08-27-phone-tab-design.md, W4).
 *
 * KDE Connect writes one vCard per contact into
 * ~/.local/share/kpeoplevcard/kdeconnect-<deviceId>/ and answers no "list
 * the contacts" call over D-Bus, so the source is that directory, read by
 * scripts/phone/contacts_monitor.py: one long-lived Python process per
 * shell session that parses the cards, watches the directory (gio, else a
 * poll) and streams NDJSON - `ready`, `snapshot` only when the parsed set
 * changed, `error {code: "no_contact_source"}`. The device it follows is
 * PhoneConnect.activeDevice; with no active device the script reads the
 * most recently synced device's directory, so the count is on screen while
 * the phone is off the network.
 *
 * The monitor is a streaming Process, so it is started imperatively and
 * never by a `running` binding (CONTRIBUTING.md): restarts go through
 * PhoneConnect.monitorExitPlan - the one spelling of the backoff ladder,
 * a ceiling of five per device, a healthy-run reset - after which the
 * service holds whatever it last read. A device change restarts it from
 * the top of the ladder: a new device is a new opportunity, not the next
 * rung.
 *
 * Config keys under phone.contacts (favoriteIds, hideUnnamed, sortBy,
 * enabled) are read with optional chaining and defaults because the block
 * is declared by the scrcpy workstream (W3); until it lands the defaults
 * run and toggleFavorite() refuses rather than writing into a key the
 * JsonAdapter would drop on the next launch (AGENT.md, "A key with no
 * declared property is destroyed by the first write").
 *
 * The dialer and SMS intents go to the phone over adb - `adb devices`
 * first, then `adb -s <serial> shell am start` - both argv arrays; a
 * missing adb or no device in the `device` state is refused with
 * lastError rather than spawned into.
 *
 * The functions between the sync markers are kept byte-for-byte in sync
 * with the logic-only double (tests/imports/testservices/PhoneContacts.qml);
 * tests/test_phone_contacts_contract.py enforces it.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options.phone?.contacts?.enabled ?? true
    readonly property bool hideUnnamed: Config.options.phone?.contacts?.hideUnnamed ?? true
    readonly property string sortBy: Config.options.phone?.contacts?.sortBy ?? "first"
    readonly property var favorites: Config.options.phone?.contacts?.favoriteIds ?? []
    readonly property string deviceId: PhoneConnect.activeDevice?.id ?? ""

    property bool ready: false
    property string sourcePath: ""
    // [{ id, displayName, givenName, familyName, organization,
    //    phones: [{ value, normalized, type, primary }],
    //    emails: [{ value, type, primary }], photo (data URI or ""),
    //    nameless, source }] - what contacts_monitor.py emits, sorted by it.
    property var contacts: []
    readonly property int count: root.contacts.length
    property string query: ""
    readonly property var filtered: root.filterContacts(root.contacts, root.query, root.hideUnnamed, root.favorites, root.sortBy)
    // Why the last dialer/SMS request was refused; "" once one goes through.
    // Written empty-then-message so a repeat of the same refusal still
    // raises lastErrorChanged for whoever toasts it.
    property string lastError: ""

    property bool gioAvailable: false // gio found on PATH; without it the monitor polls
    property bool adbAvailable: false // adb found on PATH; without it no intent is attempted

    readonly property string monitorScript: `${Directories.scriptPath}/phone/contacts_monitor.py`

    // BEGIN phone-contacts logic (synced with tests/imports/testservices/PhoneContacts.qml)
    // A query in its two spellings: lower-cased text for names, organizations
    // and addresses, and digits-only for numbers - "555 010" is typed the way
    // a number is drawn, and the stored number is "+1 (555) 010-0001".
    function normalizeQuery(query: var): var {
        const text = String(query ?? "").trim().toLowerCase();
        return { text: text, digits: text.replace(/[\s\-().]/g, "") };
    }

    function contactMatches(contact: var, needle: var): bool {
        if (!contact) return false;
        if (needle.text.length === 0) return true;
        const texts = [contact.displayName, contact.organization];
        for (const text of texts)
            if (typeof text === "string" && text.toLowerCase().includes(needle.text)) return true;
        const phones = contact.phones ?? [];
        for (let i = 0; i < phones.length; i++) {
            const phone = phones[i];
            if (typeof phone?.value === "string" && phone.value.toLowerCase().includes(needle.text)) return true;
            if (needle.digits.length > 0 && typeof phone?.normalized === "string"
                    && phone.normalized.includes(needle.digits)) return true;
        }
        const emails = contact.emails ?? [];
        for (let i = 0; i < emails.length; i++)
            if (typeof emails[i]?.value === "string" && emails[i].value.toLowerCase().includes(needle.text)) return true;
        return false;
    }

    // By index rather than includes(): a list<var> that crossed a Config
    // boundary keeps its length and its indices and nothing else (109e6d897).
    function isFavorite(uid: var, favorites: var): bool {
        const list = favorites ?? [];
        for (let i = 0; i < list.length; i++)
            if (list[i] === uid) return true;
        return false;
    }

    // Hidden only when the card had no human-readable name AND nobody starred
    // it: starring is an explicit statement that the number matters.
    function isHidden(contact: var, hideUnnamed: bool, favorites: var): bool {
        return hideUnnamed && contact?.nameless === true && !root.isFavorite(contact.id, favorites);
    }

    function sortKey(contact: var, sortBy: string): string {
        const name = sortBy === "last" ? contact?.familyName : contact?.givenName;
        return String(name || contact?.displayName || "").toLowerCase();
    }

    // The tie-break is CASE-FOLDED and compared by code point, not by
    // localeCompare: collation is the runner's locale, and "adam" vs "Adam B"
    // orders one way under en_US.UTF-8 and the other under C - green here and
    // red in CI. The primary key keeps localeCompare (it is already folded, so
    // case cannot reach it, and accents order the way a reader expects); the
    // tie-break is what has to be the same on every machine.
    function compareFolded(a: var, b: var): int {
        const x = String(a ?? "").toLowerCase();
        const y = String(b ?? "").toLowerCase();
        if (x === y) return 0;
        return x < y ? -1 : 1;
    }

    function sortContacts(list: var, sortBy: string): var {
        return [...(list ?? [])].sort((a, b) => root.sortKey(a, sortBy).localeCompare(root.sortKey(b, sortBy))
            || root.compareFolded(a?.displayName, b?.displayName)
            || root.compareFolded(a?.id, b?.id));
    }

    function filterContacts(list: var, query: var, hideUnnamed: bool, favorites: var, sortBy: string): var {
        const needle = root.normalizeQuery(query);
        const source = list ?? [];
        const kept = [];
        for (let i = 0; i < source.length; i++) {
            const contact = source[i];
            if (root.isHidden(contact, hideUnnamed, favorites)) continue;
            if (root.contactMatches(contact, needle)) kept.push(contact);
        }
        return root.sortContacts(kept, sortBy);
    }

    // A new list every time: the stored one is a Config property, and a
    // splice in place would neither notify nor survive the JsonAdapter.
    function toggledFavorites(favorites: var, uid: string): var {
        const source = favorites ?? [];
        const list = [];
        let found = false;
        for (let i = 0; i < source.length; i++) {
            if (source[i] === uid) { found = true; continue; }
            list.push(source[i]);
        }
        if (!found) list.push(uid);
        return list;
    }

    // `adb devices` -> the serial an intent is aimed at. Only the `device`
    // state counts (unauthorized and offline cannot take an `am start`), and
    // a USB serial - no ':' in it - wins over a wireless ip:port.
    function adbSerialFromDevices(text: var): string {
        const serials = [];
        for (const line of String(text ?? "").split("\n")) {
            const cells = line.trim().split(/\s+/);
            if (cells.length >= 2 && cells[1] === "device" && cells[0] !== "List") serials.push(cells[0]);
        }
        return serials.find(serial => !serial.includes(":")) ?? serials[0] ?? "";
    }

    // RFC 3966 lets a tel: URI carry digits, '+' and the visual separators
    // unencoded; whitespace is dropped and anything else (a USSD code's '#',
    // which a URI reads as a fragment marker) is percent-encoded.
    function intentUri(scheme: string, number: var): string {
        const dial = String(number ?? "").replace(/\s+/g, "");
        let out = "";
        for (const ch of dial)
            out += /[0-9+\-().*]/.test(ch) ? ch : encodeURIComponent(ch);
        return scheme + ":" + out;
    }

    function intentArgv(serial: string, action: string, uri: string): var {
        const target = serial ? ["-s", serial] : [];
        return ["adb", ...target, "shell", "am", "start", "-a", action, "-d", uri];
    }

    function monitorArgv(script: string, deviceId: string): var {
        const device = deviceId ? ["--device", deviceId] : [];
        return ["python3", script, ...device];
    }

    // One NDJSON line from the monitor as its event object, or null.
    function parseMonitorEvent(line: var): var {
        const trimmed = String(line ?? "").trim();
        if (trimmed.length === 0) return null;
        let doc;
        try {
            doc = JSON.parse(trimmed);
        } catch (e) {
            return null;
        }
        if (!doc || typeof doc !== "object" || Array.isArray(doc) || typeof doc.event !== "string") return null;
        return doc;
    }
    // END phone-contacts logic

    // ---- favorites ----

    function toggleFavorite(uid: string): void {
        if (!uid) return;
        const store = Config.options.phone?.contacts;
        if (!store || store.favoriteIds === undefined) {
            console.warn("[PhoneContacts] phone.contacts.favoriteIds is not declared in Config.qml; a favorite cannot be stored");
            return;
        }
        store.favoriteIds = root.toggledFavorites(store.favoriteIds, uid);
    }

    // ---- dialer and SMS over adb ----

    function openDialer(number: var): void {
        root.startIntent("android.intent.action.DIAL", "tel", number);
    }

    function composeSms(number: var): void {
        root.startIntent("android.intent.action.SENDTO", "sms", number);
    }

    function refuse(message: string): void {
        root.lastError = "";
        root.lastError = message;
    }

    property var pendingIntent: null

    function startIntent(action: string, scheme: string, number: var): void {
        const uri = root.intentUri(scheme, number);
        if (uri === scheme + ":") {
            root.refuse(Translation.tr("This contact has no number"));
            return;
        }
        if (!root.adbAvailable) {
            root.refuse(Translation.tr("adb was not found - install android-tools to reach the phone"));
            return;
        }
        // The wireless-debugging port changes on every toggle and reboot, so
        // the target is re-resolved for every intent rather than remembered.
        root.pendingIntent = { action: action, uri: uri };
        if (!adbDevicesProc.running) adbDevicesProc.exec(["adb", "devices"]);
    }

    Process {
        id: adbDevicesProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            id: adbDevicesOut
        }
        stderr: StdioCollector {}
        onExited: (exitCode, exitStatus) => {
            const intent = root.pendingIntent;
            root.pendingIntent = null;
            if (!intent) return;
            const serial = root.adbSerialFromDevices(adbDevicesOut.text);
            if (serial === "") {
                root.refuse(Translation.tr("ADB cannot reach the phone - enable USB debugging or Wireless debugging"));
                return;
            }
            intentProc.exec(root.intentArgv(serial, intent.action, intent.uri));
        }
    }

    Process {
        id: intentProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stderr: StdioCollector {
            id: intentErr
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.refuse(intentErr.text.trim() || Translation.tr("adb could not start the intent on the phone"));
                return;
            }
            root.lastError = "";
        }
    }

    // ---- the monitor ----

    property string monitorState: "idle" // idle | running | backoff | failed
    property int monitorAttempts: 0
    property real monitorStartedAt: 0
    // Set by restartMonitor() while the running monitor is being stopped so
    // the exit handler starts the next one at once, outside the ladder.
    property bool monitorRestartWanted: false

    readonly property int monitorAttemptCeiling: 5
    readonly property int monitorHealthyMs: 30000
    readonly property bool monitorLive: root.monitorState === "running"

    function monitorWanted(): bool {
        return root.enabled && root.monitorState !== "failed";
    }

    function startMonitor(): void {
        if (monitorProc.running || !root.monitorWanted()) return;
        monitorRestart.stop();
        root.monitorStartedAt = Date.now();
        root.monitorState = "running";
        monitorProc.exec(root.monitorArgv(root.monitorScript, root.deviceId));
    }

    function stopMonitor(): void {
        monitorRestart.stop();
        root.monitorRestartWanted = false;
        root.monitorAttempts = 0;
        root.monitorState = "idle";
        monitorProc.running = false;
    }

    // The inputs changed under the monitor (a different device, the feature
    // switched back on): the next start is from the top of the ladder, and
    // the list is "syncing" again until the new source answers.
    function restartMonitor(): void {
        monitorRestart.stop();
        root.monitorAttempts = 0;
        root.ready = false;
        if (root.monitorState === "failed") root.monitorState = "idle";
        if (monitorProc.running) {
            root.monitorRestartWanted = true;
            monitorProc.running = false;
            return;
        }
        root.startMonitor();
    }

    function handleMonitorLine(line: string): void {
        const message = root.parseMonitorEvent(line);
        if (!message) return;
        switch (message.event) {
        case "ready":
            root.sourcePath = typeof message.sourcePath === "string" ? message.sourcePath : "";
            root.ready = true;
            break;
        case "snapshot":
            root.contacts = Array.isArray(message.contacts) ? message.contacts : [];
            break;
        case "error":
            if (message.code === "no_contact_source") root.ready = false;
            console.warn("[PhoneContacts]", message.code ?? "error", message.message ?? "");
            break;
        }
    }

    Timer {
        id: monitorRestart
        onTriggered: root.startMonitor()
    }

    Process {
        id: monitorProc
        // process-lifecycle: restart-safe -- capped exponential backoff; no running binding.
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: SplitParser {
            onRead: data => root.handleMonitorLine(data)
        }
        stderr: SplitParser {
            onRead: data => console.warn("[PhoneContacts]", data)
        }
        onExited: (exitCode, exitStatus) => {
            if (root.monitorRestartWanted) {
                root.monitorRestartWanted = false;
                root.monitorState = "idle";
                root.startMonitor();
                return;
            }
            const plan = PhoneConnect.monitorExitPlan(root.monitorAttempts, Date.now() - root.monitorStartedAt,
                root.monitorWanted(), root.monitorHealthyMs, root.monitorAttemptCeiling);
            root.monitorAttempts = plan.attempts;
            if (!plan.retry) {
                if (root.monitorWanted()) {
                    root.monitorState = "failed";
                    console.warn(`[PhoneContacts] contacts monitor gave up after ${root.monitorAttemptCeiling} restarts`);
                } else {
                    root.monitorState = "idle";
                }
                return;
            }
            root.monitorState = "backoff";
            monitorRestart.interval = plan.delay;
            monitorRestart.restart();
        }
    }

    onEnabledChanged: {
        if (root.enabled) {
            root.restartMonitor();
        } else {
            root.stopMonitor();
            root.ready = false;
        }
    }

    onDeviceIdChanged: {
        if (root.enabled) root.restartMonitor();
    }

    Component.onCompleted: {
        if (root.enabled) root.startMonitor();
    }

    // One-shot presence checks, started here rather than from the feature
    // that needs them (tests/lint_capability_probe_gating.py).
    Process {
        id: gioProbe
        running: true
        command: ["sh", "-c", "command -v gio"]
        onExited: (exitCode, exitStatus) => {
            root.gioAvailable = (exitCode === 0);
        }
    }

    Process {
        id: adbProbe
        running: true
        command: ["sh", "-c", "command -v adb"]
        onExited: (exitCode, exitStatus) => {
            root.adbAvailable = (exitCode === 0);
        }
    }
}
