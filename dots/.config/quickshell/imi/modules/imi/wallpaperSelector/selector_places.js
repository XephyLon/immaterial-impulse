.pragma library

// The places the selector's sidebar offers while browsing local files, and
// which of them is lit for the directory on screen. Pure: the visibility
// rules and the current-place match are the decisions, and nothing about the
// drawn sidebar is reachable from qmltestrunner.

function _basename(path) {
    var parts = String(path).split("/").filter(function (s) { return s.length > 0; });
    return parts.length > 0 ? parts[parts.length - 1] : path;
}

// Ordered rows: {key, icon, name, path, translate}. `name` for the custom row
// is the folder's own basename, so `translate` says whether a caller should
// run the label through Translation.tr - a directory name is not a phrase
// this repo owns.
function places(dirs, options) {
    var rows = [
        { key: "wallpapers", icon: "wallpaper", name: "Wallpapers", path: dirs.pictures + "/Wallpapers", translate: true }
    ];
    if (options.showHomePath)
        rows.push({ key: "home", icon: "home", name: "Home", path: dirs.home, translate: true });
    rows.push({ key: "documents", icon: "description", name: "Documents", path: dirs.documents, translate: true });
    rows.push({ key: "downloads", icon: "download", name: "Downloads", path: dirs.downloads, translate: true });
    rows.push({ key: "pictures", icon: "imagesmode", name: "Pictures", path: dirs.pictures, translate: true });
    rows.push({ key: "videos", icon: "movie", name: "Videos", path: dirs.videos, translate: true });
    if (options.weeb)
        rows.push({ key: "homework", icon: "school", name: "Homework", path: dirs.pictures + "/homework", translate: true });
    rows.push({ key: "random", icon: "casino", name: "Random", path: dirs.pictures + "/Random", translate: true });
    var userPath = String(options.userPath ?? "").trim();
    if (userPath.length > 0)
        rows.push({ key: "custom", icon: "folder_special", name: _basename(userPath), path: options.userPath, translate: false });
    return rows;
}

// Whether a place's stored path is the directory on screen.
// `currentDirectory` arrives as Wallpapers.directory - a resolved file:// URL
// - while a place stores a plain path, and either side may carry a trailing
// slash; normalising both is what lets any row light up at all.
function _normalize(path) {
    var p = String(path);
    if (p.indexOf("file://") === 0)
        p = p.substring(7);
    while (p.length > 1 && p.charAt(p.length - 1) === "/")
        p = p.substring(0, p.length - 1);
    return p;
}

function isCurrent(placePath, currentDirectory) {
    return _normalize(placePath) === _normalize(currentDirectory);
}
