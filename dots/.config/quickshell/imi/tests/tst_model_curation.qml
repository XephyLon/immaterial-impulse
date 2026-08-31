import QtTest
import "../services/ai/model_curation.js" as Curation

// Which fetched models SURFACE (spec 2026-08-31): empty selection means
// all - a four-model provider needs no ceremony - and a named selection
// means exactly those. Pure fold, shared by the picker filter and the
// browse toggles so they cannot disagree.
TestCase {
    name: "ModelCurationTest"

    function test_empty_selection_surfaces_everything() {
        verify(Curation.isSurfaced([], "anything"));
        verify(Curation.isSurfaced(null, "anything"));
    }

    function test_named_selection_surfaces_only_those() {
        verify(Curation.isSurfaced(["a", "b"], "a"));
        verify(!Curation.isSurfaced(["a", "b"], "c"));
    }

    function test_toggle_folds_copy_on_write() {
        const one = Curation.withToggled([], "a");
        compare(one.join(","), "a");
        const two = Curation.withToggled(one, "b");
        compare(two.join(","), "a,b");
        const back = Curation.withToggled(two, "a");
        compare(back.join(","), "b");
        compare(one.join(","), "a", "copy, not mutation");
    }

    function test_provider_index_of() {
        compare(Curation.providerIndexOf("custom_provider_0"), 0);
        compare(Curation.providerIndexOf("custom_provider_12"), 12);
        compare(Curation.providerIndexOf("openrouter"), -1);
        compare(Curation.providerIndexOf(""), -1);
        compare(Curation.providerIndexOf(undefined), -1);
    }
}
