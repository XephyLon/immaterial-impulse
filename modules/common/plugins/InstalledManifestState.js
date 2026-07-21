.pragma library

// Reconcile the manifest cache with one completed filesystem scan. Existing
// entries are preserved because their FileViews may already be loaded and will
// not emit onLoaded again. Missing paths are dropped immediately; newly found
// paths remain absent until their new FileView loads and registers the parsed
// manifest.
function reconcile(paths, current) {
    const kept = {};
    for (const path of paths) {
        if (current[path] !== undefined)
            kept[path] = current[path];
    }
    return kept;
}
