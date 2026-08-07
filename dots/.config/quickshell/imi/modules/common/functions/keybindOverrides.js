.pragma library

// Pure logic for the keyboard-shortcuts editor: binding identity, override
// application to the parsed keybind tree, rebindability, and chord-conflict
// detection. services/HyprlandKeybinds.qml and
// services/HyprlandKeybindOverrides.qml drive it; tests/tst_keybind_overrides_logic.qml
// exercises every branch without a disk or a compositor.
//
// An override is a full replacement entry keyed on the DEFAULT binding's
// identity (sorted mods + key), so the shipped keybinds.lua can change across
// updates without discarding overrides, and a rebound default cannot be
// resurrected by an update reshuffling its definition.

// Mirrors scripts/hyprland/keybind_overrides.py's KNOWN_GLOBALS - identifiers
// the generated shim can safely reference because variables.lua defines them
// as globals and the shim is sourced after it. The Python side is the
// enforcer; this copy only decides whether the UI offers a rebind at all.
var KNOWN_GLOBALS = [
    "terminal", "fileManager", "browser", "codeEditor", "officeSoftware",
    "textEditor", "volumeMixer", "settingsApp", "taskManager",
];

function sortedMods(mods) {
    return (mods ?? []).slice().sort();
}

function identityFor(mods, key) {
    return sortedMods(mods).join("+") + "|" + (key ?? "");
}

function bindIdentity(kb) {
    return identityFor(kb.mods ?? [], kb.key ?? "");
}

function splitIdentity(identity) {
    const sep = identity.lastIndexOf("|");
    const modsPart = sep >= 0 ? identity.slice(0, sep) : "";
    return {
        mods: modsPart.length ? modsPart.split("+") : [],
        key: sep >= 0 ? identity.slice(sep + 1) : identity,
    };
}

// Whether a parsed bind's action can be re-emitted by the shim generator: an
// hl.dsp.* dispatcher whose params are literals (or known variables.lua
// globals). Conservative mirror of the generator's grammar - the generator
// still validates for real at write time; this only gates the edit UI.
function canRebind(kb) {
    if (!kb || typeof kb.dispatcher !== "string")
        return false;
    if (!kb.dispatcher.startsWith("hl.dsp."))
        return false;
    const params = kb.params ?? "";
    const stripped = params.replace(/"(?:\\.|[^"\\])*"/g, "");
    if (/[()\[\];]/.test(stripped))
        return false;
    const idents = stripped.match(/[A-Za-z_][A-Za-z0-9_]*/g) ?? [];
    for (const ident of idents) {
        if (ident === "true" || ident === "false")
            continue;
        if (KNOWN_GLOBALS.indexOf(ident) !== -1)
            continue;
        // Table keys (`ident =`) are field names, not variable reads.
        if (new RegExp(ident + "\\s*=").test(stripped))
            continue;
        return false;
    }
    return true;
}

// Rewrites the merged section tree through the override map: rebound binds
// show their replacement chord, removed binds disappear, and every real bind
// is annotated with its identity and what the editor may do to it. "add"
// entries are collected into one extra section appended to the last column so
// the cheatsheet renders them.
function applyOverrides(sections, overrides, customSectionName) {
    overrides = overrides ?? {};

    function mapSection(section) {
        const keybinds = [];
        for (const kb of section.keybinds ?? []) {
            const identity = bindIdentity(kb);
            const entry = overrides[identity];
            if (entry && entry.action === "remove")
                continue;
            const isReal = kb.dispatcher !== "comment";
            const annotated = Object.assign({}, kb, {
                identity: identity,
                editable: isReal && canRebind(kb),
                removable: isReal,
                overridden: false,
                added: false,
            });
            if (entry && entry.action === "rebind") {
                annotated.mods = (entry.mods ?? []).slice();
                annotated.key = entry.key ?? "";
                annotated.overridden = true;
            }
            keybinds.push(annotated);
        }
        return {
            name: section.name,
            keybinds: keybinds,
            children: (section.children ?? []).map(mapSection),
        };
    }

    const result = (sections ?? []).map(mapSection);

    const additions = [];
    for (const identity of Object.keys(overrides).sort()) {
        const entry = overrides[identity];
        if (entry.action !== "add")
            continue;
        additions.push({
            mods: (entry.mods ?? []).slice(),
            key: entry.key ?? "",
            dispatcher: "hl.dsp.exec_cmd",
            params: "",
            comment: entry.description || entry.command || "",
            flags: entry.flags ?? {},
            submap: "",
            identity: identity,
            editable: false,
            removable: true,
            overridden: true,
            added: true,
        });
    }
    if (additions.length > 0) {
        const section = { name: customSectionName ?? "Custom", keybinds: additions, children: [] };
        if (result.length > 0) {
            const last = result[result.length - 1];
            result[result.length - 1] = {
                name: last.name,
                keybinds: last.keybinds,
                children: last.children.concat([section]),
            };
        } else {
            result.push({ name: "", keybinds: [], children: [section] });
        }
    }
    return result;
}

// Everything already sitting on a chord the user wants to bind. flatDefault /
// flatUser come from get_keybinds.py --flat (hidden binds included, submap
// tagged); overrides contribute the chords they claim and release. The result
// can prove a conflict but never the absence of one - loop-generated binds are
// invisible to the static scan.
function chordConflicts(mods, key, ignoreIdentity, flatDefault, flatUser, overrides) {
    overrides = overrides ?? {};
    const target = identityFor(mods, key);

    // Chords the override set frees up (their defaults are unbound by the shim).
    const freed = {};
    for (const id in overrides) {
        const entry = overrides[id];
        if (entry.action === "remove" || entry.action === "rebind") {
            const s = splitIdentity(id);
            freed[identityFor(s.mods, s.key)] = true;
        }
    }

    let ignoreChord = null;
    if (ignoreIdentity) {
        const s = splitIdentity(ignoreIdentity);
        ignoreChord = identityFor(s.mods, s.key);
    }

    const conflicts = [];

    function describe(bind) {
        if (bind.comment)
            return bind.comment;
        if (bind.dispatcher === "function")
            return "(script binding)";
        return bind.dispatcher + "(" + (bind.params ?? "") + ")";
    }

    function scan(binds, source) {
        for (const bind of binds ?? []) {
            const chord = identityFor(bind.mods ?? [], bind.key);
            if (chord !== target)
                continue;
            if (chord === ignoreChord)
                continue;
            if (freed[chord] === true)
                continue;
            conflicts.push({
                description: describe(bind),
                source: source,
                submap: bind.submap ?? "",
            });
        }
    }
    scan(flatDefault, "default");
    scan(flatUser, "user");

    for (const id in overrides) {
        if (id === ignoreIdentity)
            continue;
        const entry = overrides[id];
        if (entry.action !== "rebind" && entry.action !== "add")
            continue;
        const chord = identityFor(entry.mods ?? [], entry.key ?? "");
        if (chord !== target)
            continue;
        conflicts.push({
            description: entry.description || entry.command || "",
            source: "override",
            submap: "",
        });
    }

    return conflicts;
}
