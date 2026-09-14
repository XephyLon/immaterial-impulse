import QtQuick
import QtTest
import "../services/ai/ai_tool_policy.js" as Policy

// The tools' permission vocabulary, pure: which tier a tool is in (unknown
// = reviewed, never silently allowed), argument validation against the
// registry schema (coerce, drop unknown, report missing), the card's summary
// line, and the result bound.
TestCase {
    name: "AiToolPolicy"

    function test_tiers() {
        compare(Policy.tierOf("read_file"), "read");
        compare(Policy.tierOf("get_clipboard"), "read");
        compare(Policy.tierOf("write_file"), "reviewed");
        compare(Policy.tierOf("set_wallpaper"), "reviewed");
        compare(Policy.tierOf("set_shell_config"), "reviewed");
        compare(Policy.tierOf("run_shell_command"), "destructive");
        compare(Policy.tierOf("some_future_tool"), "reviewed", "a tool nobody classified is never auto-run");
        // Every listed name is in exactly one tier.
        const seen = {};
        for (const tier in Policy.TIERS)
            for (const n of Policy.TIERS[tier]) { verify(!(n in seen), `${n} twice`); seen[n] = tier; }
    }

    readonly property var def: ({
        name: "x",
        parameters: { type: "object", properties: {
            path: { type: "string" }, depth: { type: "integer" }, force: { type: "boolean" },
            mode: { type: "string", "enum": ["dark", "light"] } }, required: ["path"] }
    })

    function test_validate_coerces_drops_and_reports() {
        const v = Policy.validateArgs(def, { path: "/a", depth: "3", force: "true", mode: "dark", extra: 1 });
        verify(v.ok);
        compare(v.args.depth, 3);
        compare(v.args.force, true);
        compare(v.args.mode, "dark");
        verify(!("extra" in v.args), "unknown keys are dropped");
        const bad = Policy.validateArgs(def, { depth: "x", mode: "purple" });
        verify(!bad.ok);
        compare(bad.missing, ["path"]);
        verify(!("depth" in bad.args), "an uncoercible number is dropped");
        verify(!("mode" in bad.args), "a value outside the enum is dropped");
        verify(Policy.validateArgs({ name: "noargs" }, null).ok, "a parameterless tool validates an empty call");
    }

    function test_summary_speaks_the_users_language() {
        verify(Policy.summaryFor("write_file", { path: "/x/y.md", content: "abc" }).indexOf("Write /x/y.md") === 0);
        verify(Policy.summaryFor("set_wallpaper", { path: "random" }).indexOf("random") !== -1);
        verify(Policy.summaryFor("set_accent", { color: "auto" }).indexOf("wallpaper") !== -1);
        verify(Policy.summaryFor("set_color_scheme", { scheme: "dark" }).indexOf("dark") !== -1);
        const longSummary = Policy.summaryFor("set_clipboard", { text: "a".repeat(300) });
        verify(longSummary.length < 200, "a long clipboard text is elided on the card");
        verify(Policy.summaryFor("unknown_tool", { a: 1 }).indexOf("unknown_tool") === 0, "an unknown tool still shows something");
    }

    function test_bound_cuts_and_says_so() {
        compare(Policy.bound("short", 100), "short");
        const cut = Policy.bound("x".repeat(150), 100);
        verify(cut.indexOf("x".repeat(100)) === 0);
        verify(cut.indexOf("50 more characters cut") !== -1);
        compare(Policy.bound(null, 10), "");
    }
}
