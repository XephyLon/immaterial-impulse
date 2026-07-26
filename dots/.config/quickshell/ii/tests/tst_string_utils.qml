import QtQuick
import QtTest
import qs.modules.common.functions

// Behavioral tests for modules/common/functions/StringUtils.qml.
TestCase {
    name: "StringUtilsTest"

    function test_cleanMusicTitle_strips_leading_brackets() {
        // A leading bracketed tag is removed, the real title kept.
        compare(StringUtils.cleanMusicTitle("[MV] Real Title"), "Real Title")
        compare(StringUtils.cleanMusicTitle("(Official) Song"), "Song")
        compare(StringUtils.cleanMusicTitle("【東方】 Track"), "Track")
    }

    function test_cleanMusicTitle_keeps_fully_bracketed_title() {
        // A title that is ENTIRELY bracketed strips to nothing; we must keep the
        // original rather than blanking the media widget out. See issue #29.
        compare(StringUtils.cleanMusicTitle("[BLEED BLOOD]"), "[BLEED BLOOD]")
        compare(StringUtils.cleanMusicTitle("(ns)"), "(ns)")
        compare(StringUtils.cleanMusicTitle("  [only tag]  "), "[only tag]")
    }

    function test_cleanMusicTitle_empty_and_plain() {
        compare(StringUtils.cleanMusicTitle(""), "")
        compare(StringUtils.cleanMusicTitle(null), "")
        compare(StringUtils.cleanMusicTitle("Plain Title"), "Plain Title")
    }
}
