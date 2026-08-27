pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick

// Logic-only double of services/PhoneContacts.qml. The functions between the
// sync markers are kept byte-for-byte in sync with the real service
// (tests/test_phone_contacts_contract.py enforces it), and so is the
// `filtered` binding that composes them; the monitor Process, the adb
// Processes and the Config reads are omitted so tests stay deterministic
// and offline.
Singleton {
    id: root

    property var contacts: []
    property string query: ""
    property bool hideUnnamed: true
    property string sortBy: "first"
    property var favorites: []

    readonly property int count: root.contacts.length
    readonly property var filtered: root.filterContacts(root.contacts, root.query, root.hideUnnamed, root.favorites, root.sortBy)

    // BEGIN phone-contacts logic (synced with services/PhoneContacts.qml)
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

    function sortContacts(list: var, sortBy: string): var {
        return [...(list ?? [])].sort((a, b) => root.sortKey(a, sortBy).localeCompare(root.sortKey(b, sortBy))
            || String(a?.displayName ?? "").localeCompare(String(b?.displayName ?? "")));
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
}
