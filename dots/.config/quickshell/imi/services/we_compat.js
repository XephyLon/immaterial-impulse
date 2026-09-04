.pragma library

// The Wallpaper Engine compatibility scan's decisions, kept pure so a test
// can drive them: which projects a scan spends time on, what a scanner
// process's NDJSON line means, and what the store records. The scan itself
// runs in a SPAWNED scanner process (scripts/wallpapers/we_compat_scan.qml)
// so one wallpaper that wedges or crashes the renderer kills the scanner and
// not the shell - the reference feature (jagrat7/linux-wallpaper-engine's
// bulk compatibility scanner) test-applies through its backend the same way.

// A verdict that is knowledge rather than measurement: the embedded renderer
// cannot run web projects (needs CEF, which breaks the shell's GL - the
// shell already falls back to the static wallpaper for them), and an
// application is not a wallpaper it can host. Nothing is stored for these;
// they are unsupported by construction, whatever a scan might say.
function staticVerdict(type) {
    var normalized = String(type ?? "").toLowerCase();
    if (normalized === "web" || normalized === "application")
        return "unsupported";
    return "";
}

// The projects a scan should test: testable types with a real path, minus -
// unless rescan is set - the ones that already carry a verdict.
function scanQueue(projects, results, rescan) {
    var queue = [];
    for (var i = 0; i < (projects?.length ?? 0); i++) {
        var project = projects[i];
        if (!project || !project.path || staticVerdict(project.type) !== "")
            continue;
        if (!rescan && results && results[project.id])
            continue;
        queue.push({ id: String(project.id), path: String(project.path) });
    }
    return queue;
}

// One line of the scanner's stdout: {"id", "status": "ok"|"broken",
// "error"}. Anything else - a stray print, a truncated line from a dying
// process - is null, never a throw: the reader drops it and the watchdog
// owns the silence.
function parseLine(line) {
    var parsed;
    try {
        parsed = JSON.parse(line);
    } catch (e) {
        return null;
    }
    if (!parsed || typeof parsed !== "object" || !parsed.id)
        return null;
    if (parsed.status !== "ok" && parsed.status !== "broken")
        return null;
    return {
        id: String(parsed.id),
        status: parsed.status,
        error: String(parsed.error ?? "")
    };
}

// A new map with the verdict recorded (a `property var` signals on
// reassignment only, so the store replaces the map whole).
function applyVerdict(results, verdict, testedAt) {
    var next = {};
    for (var id in (results ?? {}))
        next[id] = results[id];
    next[verdict.id] = {
        status: verdict.status,
        error: verdict.error ?? "",
        testedAt: testedAt
    };
    return next;
}

// What a tile or the sidebar says about a project: the static verdict wins
// (it is not overridable by a scan), then the stored one, then unknown.
function statusOf(project, results) {
    var fixed = staticVerdict(project?.type);
    if (fixed !== "")
        return fixed;
    var record = results ? results[project?.id] : null;
    if (record && (record.status === "ok" || record.status === "broken"))
        return record.status;
    return "unknown";
}

// What a loaded store file becomes: records with a recognisable status only.
function sanitize(loaded) {
    var result = {};
    if (!loaded || typeof loaded !== "object")
        return result;
    for (var id in loaded) {
        var record = loaded[id];
        if (!record || typeof record !== "object")
            continue;
        if (record.status !== "ok" && record.status !== "broken")
            continue;
        result[id] = {
            status: record.status,
            error: String(record.error ?? ""),
            testedAt: Number(record.testedAt) > 0 ? Number(record.testedAt) : 0
        };
    }
    return result;
}
