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
