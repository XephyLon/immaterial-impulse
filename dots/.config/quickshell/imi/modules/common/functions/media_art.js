.pragma library

// Cover art for a player that gives none. Browser MPRIS (Firefox, Plasma
// Browser Integration) leaves mpris:artUrl empty, so YouTube playback shows
// a blank tile - but xesam:url carries the watch link, and every video has a
// guaranteed i.ytimg thumbnail. hqdefault, not maxresdefault: maxres 404s on
// plenty of videos while hqdefault always exists.
function youtubeId(url) {
    const m = String(url || "").match(/(?:[?&]v=|youtu\.be\/|\/shorts\/|\/embed\/)([A-Za-z0-9_-]{11})/);
    return m ? m[1] : "";
}

// artUrl if the player supplied one, else a derived thumbnail, else "".
function resolve(artUrl, metadata) {
    if (artUrl && String(artUrl).length > 0)
        return artUrl;
    const url = metadata ? (metadata["xesam:url"] || "") : "";
    const id = youtubeId(url);
    return id ? ("https://i.ytimg.com/vi/" + id + "/hqdefault.jpg") : "";
}
