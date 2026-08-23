import QtTest
import "../modules/common/plugins/option_visibility.js" as OptionVisibility

// Whether a manifest option's row is shown, as a pure function of the
// plugin's current values. The rule worth pinning hardest is the fail-open
// one: a rule this cannot read answers VISIBLE, because a row wrongly hidden
// is a setting the user cannot reach and nothing logs.
TestCase {
    name: "OptionVisibilityTest"

    function reader(values) {
        return key => values[key];
    }

    function test_no_rule_is_visible() {
        verify(OptionVisibility.visible({ key: "a" }, reader({})));
    }

    function test_in_matches_a_choice_value() {
        const option = { key: "cookieSides", visibleWhen: { key: "style", in: ["cookie"] } };
        verify(OptionVisibility.visible(option, reader({ style: "cookie" })));
        verify(!OptionVisibility.visible(option, reader({ style: "digital" })));
    }

    function test_equals_matches_one_value_exactly() {
        const option = { key: "x", visibleWhen: { key: "flag", equals: true } };
        verify(OptionVisibility.visible(option, reader({ flag: true })));
        verify(!OptionVisibility.visible(option, reader({ flag: 1 })));
        verify(!OptionVisibility.visible(option, reader({ flag: false })));
    }

    function test_a_bare_key_is_truthiness() {
        const option = { key: "x", visibleWhen: { key: "flag" } };
        verify(OptionVisibility.visible(option, reader({ flag: "yes" })));
        verify(!OptionVisibility.visible(option, reader({ flag: "" })));
    }

    function test_any_of_is_an_or_across_two_style_keys() {
        // The clock: the desktop style and the lock-screen style can differ,
        // and a cookie option has something to say if EITHER is a cookie.
        const option = { key: "cookieSides", visibleWhen: { anyOf: [
            { key: "style", in: ["cookie"] }, { key: "styleLocked", in: ["cookie"] }
        ] } };
        verify(OptionVisibility.visible(option, reader({ style: "digital", styleLocked: "cookie" })));
        verify(OptionVisibility.visible(option, reader({ style: "cookie", styleLocked: "pixel" })));
        verify(!OptionVisibility.visible(option, reader({ style: "digital", styleLocked: "pixel" })));
    }

    function test_all_of_is_an_and() {
        const option = { key: "x", visibleWhen: { allOf: [
            { key: "a", equals: true }, { key: "b", in: ["k"] }
        ] } };
        verify(OptionVisibility.visible(option, reader({ a: true, b: "k" })));
        verify(!OptionVisibility.visible(option, reader({ a: true, b: "z" })));
    }

    function test_enabled_when_still_hides_on_a_false_boolean() {
        // The older field, kept: the clock's two quote rows rely on it.
        const option = { key: "quoteText", enabledWhen: "quoteEnable" };
        verify(OptionVisibility.visible(option, reader({ quoteEnable: true })));
        verify(!OptionVisibility.visible(option, reader({ quoteEnable: false })));
    }

    function test_both_fields_must_agree() {
        const option = { key: "x", enabledWhen: "on", visibleWhen: { key: "style", in: ["a"] } };
        verify(OptionVisibility.visible(option, reader({ on: true, style: "a" })));
        verify(!OptionVisibility.visible(option, reader({ on: false, style: "a" })));
        verify(!OptionVisibility.visible(option, reader({ on: true, style: "b" })));
    }

    function test_a_rule_that_cannot_be_read_fails_open() {
        verify(OptionVisibility.visible({ key: "x", visibleWhen: {} }, reader({})));
        verify(OptionVisibility.visible({ key: "x", visibleWhen: { in: ["a"] } }, reader({})));
        verify(OptionVisibility.visible({ key: "x", visibleWhen: { key: 7 } }, reader({})));
        verify(OptionVisibility.visible({ key: "x", visibleWhen: null }, reader({})));
    }

    function test_the_reader_is_asked_for_the_value_not_guessed() {
        // A rule against a default the user never changed must read the
        // widget's value - which is the reader's job, not this file's.
        let asked = [];
        const option = { key: "x", visibleWhen: { key: "style", in: ["cookie"] } };
        OptionVisibility.visible(option, key => { asked.push(key); return "cookie"; });
        compare(asked, ["style"]);
    }
}
