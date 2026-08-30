import QtTest
import "../services/ai_provider_keys.js" as ProviderKeys

// Custom AI providers' keys live under `custom_provider_<index>`, so removing
// a provider has to move every key below it up a slot. It used to blank the
// removed slot only, and the next provider fetched with its neighbour's key.
TestCase {
    name: "AiProviderKeysTest"

    function test_removing_a_provider_moves_the_keys_below_it_up() {
        const before = { custom_provider_0: "a", custom_provider_1: "b", custom_provider_2: "c", gemini: "g" };
        const after = ProviderKeys.apiKeysAfterRemoval(before, 0, 3);
        compare(after.custom_provider_0, "b");
        compare(after.custom_provider_1, "c");
        compare(after.custom_provider_2, "");
        compare(after.gemini, "g");
    }

    function test_removing_the_last_provider_blanks_its_slot_only() {
        const before = { custom_provider_0: "a", custom_provider_1: "b" };
        const after = ProviderKeys.apiKeysAfterRemoval(before, 1, 2);
        compare(after.custom_provider_0, "a");
        compare(after.custom_provider_1, "");
    }

    function test_a_missing_slot_reads_as_empty() {
        const after = ProviderKeys.apiKeysAfterRemoval({ custom_provider_0: "a" }, 0, 2);
        compare(after.custom_provider_0, "");
        compare(after.custom_provider_1, "");
    }

    function test_only_changed_ids_are_written_back() {
        const before = { custom_provider_0: "a", custom_provider_1: "b", gemini: "g" };
        const after = ProviderKeys.apiKeysAfterRemoval(before, 0, 2);
        compare(ProviderKeys.changedIds(before, after).sort(), ["custom_provider_0", "custom_provider_1"]);
    }

    function test_the_input_is_not_mutated() {
        const before = { custom_provider_0: "a", custom_provider_1: "b" };
        ProviderKeys.apiKeysAfterRemoval(before, 0, 2);
        compare(before.custom_provider_0, "a");
    }
}
