import QtQuick
import QtTest
import "../services/we_compat.js" as WeCompat

// The compatibility scan's decisions: which projects need testing at all,
// what a scanner line means, and what the store records. The scan itself
// runs in a spawned scanner process (one bad wallpaper kills the scanner,
// not the shell), so everything decidable lives here where a test can reach
// it.
TestCase {
    name: "WeCompatTest"

    function test_web_and_application_types_are_unsupported_without_a_scan() {
        // The embedded renderer cannot run CEF, and an application is not a
        // wallpaper it can host - both are knowledge, not measurements, so
        // no scan is spent on them and nothing is stored.
        compare(WeCompat.staticVerdict("web"), "unsupported")
        compare(WeCompat.staticVerdict("application"), "unsupported")
        compare(WeCompat.staticVerdict("scene"), "")
        compare(WeCompat.staticVerdict("video"), "")
        // Steam capitalizes inconsistently ("Video" is in this library).
        compare(WeCompat.staticVerdict("Video"), "")
        compare(WeCompat.staticVerdict("Web"), "unsupported")
    }

    function test_scan_queue_holds_testable_projects_only() {
        var projects = [
            { id: "1", path: "/a", type: "scene" },
            { id: "2", path: "/b", type: "web" },
            { id: "3", path: "/c", type: "video" },
            { id: "4", path: "", type: "scene" }
        ]
        var queue = WeCompat.scanQueue(projects, {})
        compare(queue.map(entry => entry.id), ["1", "3"])
    }

    function test_rescan_false_skips_projects_with_a_verdict() {
        var projects = [
            { id: "1", path: "/a", type: "scene" },
            { id: "2", path: "/b", type: "scene" }
        ]
        var results = { "1": { status: "ok", testedAt: 5 } }
        compare(WeCompat.scanQueue(projects, results).map(e => e.id), ["2"])
        // A full rescan retests everything.
        compare(WeCompat.scanQueue(projects, results, true).map(e => e.id), ["1", "2"])
    }

    function test_scanner_lines_parse_and_garbage_is_null() {
        var v = WeCompat.parseLine('{"id":"42","status":"broken","error":"WE start failed"}')
        compare(v.id, "42")
        compare(v.status, "broken")
        compare(v.error, "WE start failed")
        verify(WeCompat.parseLine("not json") === null)
        verify(WeCompat.parseLine('{"noId":true}') === null)
        verify(WeCompat.parseLine('{"id":"1","status":"weird"}') === null)
    }

    function test_apply_verdict_returns_a_new_map_with_the_record() {
        var results = WeCompat.applyVerdict({}, { id: "1", status: "ok", error: "" }, 1234)
        compare(results["1"].status, "ok")
        compare(results["1"].testedAt, 1234)
        // ...and does not mutate the old map (a `property var` signals on
        // reassignment only).
        var next = WeCompat.applyVerdict(results, { id: "2", status: "broken", error: "x" }, 5678)
        verify(!("2" in results))
        compare(next["2"].error, "x")
    }

    function test_status_of_resolves_static_then_stored_then_unknown() {
        var results = { "1": { status: "broken", error: "boom" } }
        compare(WeCompat.statusOf({ id: "9", type: "web" }, results), "unsupported")
        compare(WeCompat.statusOf({ id: "1", type: "scene" }, results), "broken")
        compare(WeCompat.statusOf({ id: "2", type: "scene" }, results), "unknown")
    }

    function test_sanitize_keeps_known_shapes_only() {
        var m = WeCompat.sanitize({
            "1": { status: "ok", testedAt: 3, error: "" },
            "2": { status: "nonsense" },
            "3": "garbage",
            "4": { status: "broken", error: "reason", testedAt: 9 }
        })
        compare(m["1"].status, "ok")
        compare(m["4"].error, "reason")
        verify(!("2" in m))
        verify(!("3" in m))
        compare(JSON.stringify(WeCompat.sanitize(null)), "{}")
    }
}
