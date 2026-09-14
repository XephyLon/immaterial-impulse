import QtQuick
import QtTest
import "../modules/common/plugins/bundled/clock/cookie_presets.js" as Presets

// The cookie clock's per-category look, without the clock.
TestCase {
    name: "CookiePresets"

    function test_every_preset_has_the_six_fields_applyStyle_takes() {
        const dial = ["none", "full", "dots"], hands = ["fill", "hollow", "classic"], minute = ["thin", "medium", "bold", "classic"],
              second = ["dot", "classic"], date = ["bubble", "hide", "border", "rect"];
        for (const k in Presets.PRESETS) {
            const p = Presets.PRESETS[k];
            compare(p.length, 6, k);
            verify(p[0] >= 6 && p[0] <= 24, `${k}: sides ${p[0]}`);
            verify(dial.indexOf(p[1]) !== -1, `${k}: dial ${p[1]}`);
            verify(hands.indexOf(p[2]) !== -1, `${k}: hour ${p[2]}`);
            verify(minute.indexOf(p[3]) !== -1, `${k}: minute ${p[3]}`);
            verify(second.indexOf(p[4]) !== -1, `${k}: second ${p[4]}`);
            verify(date.indexOf(p[5]) !== -1, `${k}: date ${p[5]}`);
        }
    }

    function test_lookup_trims_and_ignores_case_and_unknowns() {
        compare(Presets.presetFor(" Minimalist\n")[0], 6);
        compare(Presets.presetFor("city"), Presets.presetFor("space"));
        compare(Presets.presetFor(""), null);
        compare(Presets.presetFor(null), null);
        compare(Presets.presetFor("velvet"), null);
    }

    function test_a_preset_is_a_copy() {
        const a = Presets.presetFor("anime"); a[0] = 99;
        compare(Presets.presetFor("anime")[0], 7);
    }
}
