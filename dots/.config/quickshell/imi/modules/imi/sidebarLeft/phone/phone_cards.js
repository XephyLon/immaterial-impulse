.pragma library

// Everything the Phone tab's feature cards, its install guide and its Android
// Apps page DECIDE, kept here because nothing about the drawn cards is
// reachable from qmltestrunner - it can build neither a RippleButton nor a
// laid-out box (the reasoning tst_marquee.qml and tst_placeholder_fit.qml
// already record). tests/tst_phone_cards.qml drives all of it.
//
// Strings are not decided here. A key comes back and the call site maps it to
// a Translation.tr("...") literal: the translation extractor only sees that
// literal form, and a .pragma library has no engine context to reach
// Translation from anyway. tests/test_phone_tab_surface_contract.py fails if a
// key this module can return has no arm at the call site - an unmapped key is
// a card that draws an empty line.

// ---------------------------------------------------------------------------
// The card state machine
// ---------------------------------------------------------------------------

// The same ladder PhoneCamera.stateFor and PhoneMic.stateFor already run, kept
// here as well rather than read off one of them: the mirror card has no
// service that publishes a `state`, and two cards deriving it one way and the
// third another is how three cards come to disagree about what "offline"
// means.
function cardState(available, reachable, connecting, active) {
    if (!available) return "unavailable";
    if (active) return "active";
    if (connecting) return "connecting";
    if (!reachable) return "offline";
    return "ready";
}

// The mirror's own state. A launch error is drawn as `offline` (the sibling
// fork's choice): the card is not running, and the subtitle carries the
// error's first line, so a second state would say the same thing twice.
//
// The same is true of a phone that is reachable over KDE Connect but that
// `adb devices` does not list: scrcpy has nothing to attach to, so the card
// cannot start - and that is knowable BEFORE the click, the way missing
// tooling already is. It is `offline` for the same reason a launch error is,
// and the subtitle says which of the two links is the missing one.
//
// `adbDevice` is deliberately TRI-STATE. `undefined` means the probe has not
// answered yet, which must not read as a refusal - PhoneDeps' flags all start
// false, so a plain falsy test would put every card on "no device" for the
// first frames of every session, and would silently refuse for ever at any
// call site that forgot to pass the flag at all.
function mirrorState(flags) {
    const f = flags || {};
    if (!f.available) return "unavailable";
    if (f.running) return "active";
    if (f.launching) return "connecting";
    if (!f.reachable) return "offline";
    if (f.adbDevice === false) return "offline";
    if (errorHeadline(f.error).length > 0) return "offline";
    return "ready";
}

// The microphone's, which the service cannot answer for itself: PhoneMic's
// own `stateFor` knows whether a phone is reachable and not whether adb can
// see it, and its scrcpy backend - the preferred one wherever scrcpy is
// installed - drives the phone over ADB. The droidcam backend does not, so
// the refusal is asked for rather than assumed (`needsAdbDevice`); the webcam
// is the case that never asks, since droidcam-cli reaches the phone over
// Wi-Fi when adb has nothing.
function micState(flags) {
    const f = flags || {};
    const linked = f.reachable && !(f.needsAdbDevice && f.adbDevice === false);
    return cardState(f.available, linked, f.connecting, f.active);
}

// A service's lastError is whatever the process wrote; only its first line
// fits on a card's subtitle.
function errorHeadline(text) {
    return String(text || "").split("\n")[0].trim();
}

// ---------------------------------------------------------------------------
// Titles and subtitles, as keys
// ---------------------------------------------------------------------------

function mirrorTitleKey(flags) {
    const f = flags || {};
    if (!f.available) return "install";
    if (f.running) return "running";
    if (f.launching) return "connecting";
    return "open";
}

function mirrorSubtitleKey(flags) {
    const f = flags || {};
    if (!f.available) return "install";
    if (!f.reachable) return "offline";
    // Running and launching are asked BEFORE the error, and the order is the
    // load-bearing part: PhoneScrcpy.lastError is written by any session's
    // failure and cleared only by the next launchMirror(), so an app that
    // failed an hour ago is still sitting there while the mirror runs. Asking
    // the error first put a live mirror's card on a stale line.
    if (f.running) return "running";
    if (f.launching) return "launching";
    // Asked before the error, because "the phone is not on ADB" is what to do
    // about the error scrcpy's exit produced.
    if (f.adbDevice === false) return "noDevice";
    if (errorHeadline(f.error).length > 0) return "error";
    return "ready";
}

function webcamTitleKey(available) {
    return available ? "webcam" : "install";
}

function webcamSubtitleKey(flags) {
    const f = flags || {};
    if (!f.available) return "install";
    if (!f.reachable) return "offline";
    if (f.connecting) return "connecting";
    if (f.active) return String(f.device || "").length > 0 ? "device" : "running";
    // A launch that failed leaves the service back on `ready` with its
    // lastError set, and the card draws lastError only while it is ACTIVE -
    // so without this arm a webcam that could not start was a card that had
    // gone back to saying "Tap to start", which is what "clicking it does
    // nothing" looked like.
    if (errorHeadline(f.error).length > 0) return "error";
    return "ready";
}

function micTitleKey(available) {
    return available ? "mic" : "install";
}

function micSubtitleKey(flags) {
    const f = flags || {};
    if (!f.available) return "install";
    if (!f.reachable) return "offline";
    if (f.connecting) return "connecting";
    if (f.active) return f.muted ? "muted" : "active";
    if (f.needsAdbDevice && f.adbDevice === false) return "noDevice";
    // The webcam's reasoning, and the same silence: a microphone that failed
    // to start was a card back on "Tap to start" with the reason in a
    // property nothing drew.
    if (errorHeadline(f.error).length > 0) return "error";
    return "ready";
}

// ---------------------------------------------------------------------------
// The detail line's elapsed time
// ---------------------------------------------------------------------------

// PhoneCamera and PhoneMic publish `startedAt` in whole UNIX SECONDS (it comes
// out of the session script's state file), so the conversion happens once here
// rather than at three call sites. A session that has not started yet reports
// zero, which is not "started in 1970".
function elapsedMs(startedAtSeconds, nowMs) {
    const started = Number(startedAtSeconds) || 0;
    if (started <= 0) return 0;
    return Math.max(0, Number(nowMs) - started * 1000);
}

// "42s", "7m 05s", "1h 03m". Seconds are zero-padded past the first minute so
// the line does not change width every tick.
function formatElapsed(ms) {
    const total = Math.max(0, Math.floor(Number(ms) / 1000));
    if (total < 60) return total + "s";
    const minutes = Math.floor(total / 60);
    const seconds = total % 60;
    if (minutes < 60) return minutes + "m " + (seconds < 10 ? "0" : "") + seconds + "s";
    const hours = Math.floor(minutes / 60);
    const restMinutes = minutes % 60;
    return hours + "h " + (restMinutes < 10 ? "0" : "") + restMinutes + "m";
}

// ---------------------------------------------------------------------------
// The install guide
// ---------------------------------------------------------------------------

// The three distros PhoneDeps carries commands for. Labels are the projects'
// own names, so they are not translated - the same reason a codec name is not.
function distroPills() {
    return [
        { key: "arch", label: "Arch" },
        { key: "fedora", label: "Fedora" },
        { key: "debian", label: "Debian" }
    ];
}

function knownDistro(distro) {
    const key = String(distro || "");
    return distroPills().some(pill => pill.key === key);
}

// The pill the guide opens on. PhoneDeps answers "unknown" on a machine whose
// marker files it did not recognise, and a guide that opens on nothing shows
// no command at all - Arch is the fallback because it is the distro this shell
// is developed and installed on.
function initialDistro(detected) {
    return knownDistro(detected) ? String(detected) : "arch";
}

// One dependency row's command for the selected distro, or "" when the table
// has none - the row then draws its description and no command box, rather
// than an empty one.
function commandFor(dependency, distro) {
    const commands = dependency && dependency.commands;
    if (!commands) return "";
    const command = commands[String(distro || "")];
    return typeof command === "string" ? command : "";
}

// A dependency's command may be several lines with `#` comments between them
// (the DroidCam and v4l2loopback rows are). The whole block is what gets
// copied; this is what the box's single-line preview shows.
function firstCommand(text) {
    for (const line of String(text || "").split("\n")) {
        const trimmed = line.trim();
        if (trimmed.length === 0 || trimmed.charAt(0) === "#") continue;
        return trimmed;
    }
    return String(text || "").trim();
}

// wl-copy takes the text as an ARGUMENT, never through a shell. The fork
// spelled this `bash -c "wl-copy '" + quote(text) + "'"`, and its own quoting
// helper is the only thing between an install command and the shell - a
// dependency table is repo data today and a plausible thing to fetch
// tomorrow. An argv has no quoting to get wrong.
function copyArgv(text) {
    return ["wl-copy", "--", String(text === undefined || text === null ? "" : text)];
}

// ---------------------------------------------------------------------------
// The Android Apps page
// ---------------------------------------------------------------------------

// PhoneScrcpy publishes `apps` and nothing else - there is no search query on
// the service, and putting one there would make a page's text field a piece of
// global state. The page owns its query and this is the filter.
function filterApps(apps, query) {
    const needle = String(query || "").trim().toLowerCase();
    const source = apps || [];
    const kept = [];
    for (let i = 0; i < source.length; i++) {
        const app = source[i];
        if (!app) continue;
        if (needle.length === 0) {
            kept.push(app);
            continue;
        }
        const name = String(app.name || "").toLowerCase();
        const packageName = String(app.package || "").toLowerCase();
        if (name.includes(needle) || packageName.includes(needle)) kept.push(app);
    }
    return kept;
}

// scrcpy's --list-apps gives every app a name; the `pm list packages` fallback
// gives none, so the last segment of the package is the label there.
function appLabel(app) {
    const name = String((app && app.name) || "").trim();
    if (name.length > 0) return name;
    const packageName = String((app && app.package) || "");
    const segments = packageName.split(".");
    return segments[segments.length - 1] || packageName;
}
