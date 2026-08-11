.pragma library

const BUS_PREFIX = "org.mpris.MediaPlayer2.";

// playerctld is playerctl's daemon, not a player. It re-publishes whichever
// player it considers *current* - meaning last interacted with, not playing -
// while answering `Identity` with that player's name, so it can report
// `Playing` over a paused player's metadata under a borrowed identity. The bus
// name is the only thing about it that is its own.
const PROXY_PLAYER_IDS = ["playerctld"];

// The stable half of an MPRIS bus name. The spec lets a program that may run
// more than once append `.instance<pid>` (Firefox spells it `.instance_1_52`),
// so the full bus name changes on every launch and cannot be stored as a
// preference.
function playerIdFromBusName(busName) {
    let name = String(busName ?? "").trim().toLowerCase();
    // Case-insensitively, because normalizePreferredPlayer feeds this an
    // already-lowercased legacy value that may itself be a whole bus name.
    if (name.startsWith(BUS_PREFIX.toLowerCase()))
        name = name.slice(BUS_PREFIX.length);
    return name.replace(/\.instance[^.]*$/i, "");
}

function playerId(player) {
    return playerIdFromBusName(player?.dbusName);
}

function isProxyPlayer(player) {
    return PROXY_PLAYER_IDS.indexOf(playerId(player)) !== -1;
}

// Duplicate suppression, which is a preference (media.filterDuplicatePlayers)
// rather than a fact, unlike the proxy check above.
function isSuppressedDuplicate(player, hasPlasmaIntegration) {
    const busName = String(player?.dbusName ?? "");
    if (busName.endsWith(".mpd") && !busName.endsWith(BUS_PREFIX + "mpd"))
        return true;
    if (!hasPlasmaIntegration)
        return false;
    // plasma-browser-integration republishes one browser tab at a time, so
    // dropping every native browser bus while it is up hides whatever else is
    // playing. A bus that is playing is never the duplicate worth losing.
    if (player?.isPlaying)
        return false;
    const id = playerId(player);
    return id.startsWith("firefox") || id.startsWith("chromium");
}

function candidatePlayers(players, filterDuplicates) {
    const real = Array.from(players ?? []).filter(player => !isProxyPlayer(player));
    if (!filterDuplicates)
        return real;
    const hasPlasmaIntegration = real.some(player => playerId(player) === "plasma-browser-integration");
    return real.filter(player => !isSuppressedDuplicate(player, hasPlasmaIntegration));
}

function hasUsableMetadata(player) {
    return String(player?.trackTitle ?? "").trim().length > 0
        || String(player?.trackArtist ?? "").trim().length > 0;
}

function preferredPlayer(candidates) {
    const available = Array.from(candidates ?? []);
    return available.find(player => player?.isPlaying && hasUsableMetadata(player))
        ?? available.find(player => player?.isPlaying)
        ?? available.find(player => hasUsableMetadata(player))
        ?? available[0]
        ?? null;
}

// The setting used to be free text matched as a substring of `identity` or
// `desktopEntry`. It now stores a player id, but a config written before the
// picker existed still holds whatever the user typed, so the substring match
// stays as the fallback branch rather than as the rule.
function matchesPreference(player, preference) {
    const wanted = String(preference ?? "").trim().toLowerCase();
    if (wanted.length === 0)
        return false;
    const id = playerId(player);
    if (id === wanted)
        return true;
    return id.includes(wanted)
        || String(player?.identity ?? "").toLowerCase().includes(wanted)
        || String(player?.desktopEntry ?? "").toLowerCase().includes(wanted);
}

function preferenceMatches(candidates, preference) {
    return Array.from(candidates ?? []).filter(player => matchesPreference(player, preference));
}

// Idempotent, so it is safe to run on every load without a "already migrated"
// marker - a value the picker wrote is already its own normal form. A legacy
// value may be a list ("spotify, firefox"), which the old substring match
// could never have matched as a whole anyway; keep the first entry.
function normalizePreferredPlayer(value) {
    const raw = String(value ?? "").trim().toLowerCase();
    if (raw.length === 0)
        return "";
    const first = raw.split(/[,;]/)[0].trim().split(/\s+/)[0];
    return playerIdFromBusName(first);
}

// The preference is absolute while the player it names is present: a setting
// that stops applying the moment anything else starts playing is not a
// preference. When that player is absent the preference is simply not
// applicable this session and normal selection resumes - nothing is written
// back, so closing the player never forgets the choice.
function selectPlayer(candidates, preference) {
    const matches = preferenceMatches(candidates, preference);
    if (matches.length > 0)
        return preferredPlayer(matches);
    return preferredPlayer(candidates);
}

function collapseDuplicates(players) {
    const all = Array.from(players ?? []);
    const filtered = [];
    const used = new Set();

    for (let i = 0; i < all.length; ++i) {
        if (used.has(i))
            continue;

        const p1 = all[i];
        const group = [i];

        for (let j = i + 1; j < all.length; ++j) {
            const p2 = all[j];
            const titlesOverlap = p1.trackTitle && p2.trackTitle
                && (p1.trackTitle.includes(p2.trackTitle) || p2.trackTitle.includes(p1.trackTitle));
            const timingMatches = Math.abs(p1.position - p2.position) <= 2
                && Math.abs(p1.length - p2.length) <= 2;

            if (titlesOverlap || timingMatches)
                group.push(j);
        }

        let chosenIdx = group.find(idx => all[idx].trackArtUrl?.length > 0);
        if (chosenIdx === undefined)
            chosenIdx = group[0];

        filtered.push(all[chosenIdx]);
        group.forEach(idx => used.add(idx));
    }
    return filtered;
}

function meaningfulPlayers(candidates, preference) {
    const matches = preferenceMatches(candidates, preference);
    return collapseDuplicates(matches.length > 0 ? matches : Array.from(candidates ?? []));
}

// Rows for the settings picker, one per distinct player id. Labels are built
// at the call site because a translated string is not reachable from a
// `.pragma library`.
function playerOptions(candidates, preference) {
    const rows = [];
    const seen = {};

    for (const player of Array.from(candidates ?? [])) {
        const id = playerId(player);
        if (id.length === 0)
            continue;
        const existing = seen[id];
        if (existing !== undefined) {
            // Two instances of one program share an id, so let the one with
            // something to say describe the row.
            if (!existing.isPlaying && player?.isPlaying) {
                existing.isPlaying = true;
                existing.trackTitle = String(player?.trackTitle ?? "");
            } else if (existing.trackTitle.length === 0) {
                existing.trackTitle = String(player?.trackTitle ?? "");
            }
            continue;
        }
        const row = {
            value: id,
            name: String(player?.identity ?? "").trim() || id,
            trackTitle: String(player?.trackTitle ?? ""),
            isPlaying: !!player?.isPlaying,
            available: true
        };
        seen[id] = row;
        rows.push(row);
    }

    // A stored preference always gets a row, whether or not the player is
    // running and whether or not it matches by id. Without it the combo box
    // has nothing to show as current and falls back to displaying Automatic,
    // which reads as "closing the player reset my choice".
    const wanted = String(preference ?? "").trim().toLowerCase();
    if (wanted.length > 0 && !rows.some(row => row.value === wanted)) {
        const matches = preferenceMatches(candidates, wanted);
        rows.push({
            value: wanted,
            name: String(matches[0]?.identity ?? "").trim() || wanted,
            trackTitle: String(matches[0]?.trackTitle ?? ""),
            isPlaying: matches.some(player => !!player?.isPlaying),
            available: matches.length > 0
        });
    }

    return rows;
}
