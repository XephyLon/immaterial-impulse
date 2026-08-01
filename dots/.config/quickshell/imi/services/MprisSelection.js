.pragma library

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
