import QtTest
import "../services/math_query.js" as MathQuery

// Which launcher queries are worth spawning `qalc` for.
//
// The half that costs is the "no": before this gate, every non-prefixed query
// started a qalc process per keystroke (measured: eight for "firefox"), and
// the math row rendered qalc's opinion of an application name. So the app
// names below are the load-bearing cases, not the arithmetic.
TestCase {
    name: "MathQueryTest"

    readonly property string prefix: "="

    function test_an_application_name_is_not_a_math_query() {
        // Every one of these used to spawn qalc, once per character typed.
        for (const name of ["firefox", "code", "discord", "steam", "kitty",
                            "visual studio code", "obs studio", "spotify"]) {
            verify(!MathQuery.isMathQuery(name, prefix), `"${name}" is not arithmetic`);
            // ...and neither is any prefix of it, which is what actually gets
            // evaluated while someone types.
            for (let i = 1; i <= name.length; i++)
                verify(!MathQuery.isMathQuery(name.slice(0, i), prefix),
                       `"${name.slice(0, i)}" is not arithmetic either`);
        }
    }

    function test_an_expression_is_a_math_query() {
        for (const expr of ["2+2", "2+2*10", "(3*4)/2", "1024/8", ".5*3",
                            "-40 C to F", "5 km to miles", "3^8", "1e3+1"]) {
            verify(MathQuery.isMathQuery(expr, prefix), `"${expr}" is arithmetic`);
        }
    }

    function test_the_prefix_is_explicit_intent() {
        // Nothing about "pi" or "e^2" opens like arithmetic; the prefix says
        // the user meant it anyway.
        verify(MathQuery.isMathQuery("=pi", prefix));
        verify(MathQuery.isMathQuery("=e^2", prefix));
        verify(MathQuery.isMathQuery("=5 kg to lb", prefix));
        // A bare prefix is someone who has typed one character. Spawning there
        // is the per-keystroke waste in miniature.
        verify(!MathQuery.isMathQuery("=", prefix));
        verify(!MathQuery.isMathQuery("=   ", prefix));
    }

    function test_a_shape_without_a_number_is_not_arithmetic() {
        // Opens like an expression, is not one - qalc answers these by echoing
        // the query back, which is the useless row the gate exists to stop.
        verify(!MathQuery.isMathQuery("(a+b)", prefix));
        verify(!MathQuery.isMathQuery("-", prefix));
        verify(!MathQuery.isMathQuery("...", prefix));
        verify(!MathQuery.isMathQuery("+++", prefix));
    }

    function test_an_empty_query_asks_for_nothing() {
        verify(!MathQuery.isMathQuery("", prefix));
        verify(!MathQuery.isMathQuery("   ", prefix));
        verify(!MathQuery.isMathQuery(undefined, prefix));
        verify(!MathQuery.isMathQuery(null, prefix));
    }

    function test_the_prefix_is_configurable_and_may_be_empty() {
        // Config.options.search.prefix.math is a user setting; a user who set
        // it to something else must not lose the explicit path, and a user who
        // cleared it must not have every query treated as prefixed.
        verify(MathQuery.isMathQuery("#pi", "#"));
        verify(!MathQuery.isMathQuery("=pi", "#"));
        verify(!MathQuery.isMathQuery("firefox", ""));
        verify(MathQuery.isMathQuery("2+2", ""));
    }

    function test_the_expression_is_the_query_minus_its_prefix() {
        compare(MathQuery.expressionFor("=2+2", prefix), "2+2");
        compare(MathQuery.expressionFor("2+2", prefix), "2+2");
        // Only the leading prefix goes; an "=" inside the expression is qalc's
        // business (`=x=4` is an assignment there, not a double prefix).
        compare(MathQuery.expressionFor("=x=4", prefix), "x=4");
        compare(MathQuery.expressionFor("", prefix), "");
    }
}
