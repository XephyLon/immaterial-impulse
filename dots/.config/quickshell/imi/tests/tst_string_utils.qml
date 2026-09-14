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

    // The predicate AiInline's privacy gate and the Settings hint rest on:
    // the host must BE loopback, not merely start with it.
    function test_isLoopbackUrl_accepts_loopback_and_rejects_lookalikes() {
        verify(StringUtils.isLoopbackUrl("http://localhost:11434/v1/chat/completions"));
        verify(StringUtils.isLoopbackUrl("http://127.0.0.1/"));
        verify(StringUtils.isLoopbackUrl("https://[::1]:8080/x"));
        verify(StringUtils.isLoopbackUrl("HTTP://LOCALHOST"));
        verify(!StringUtils.isLoopbackUrl("http://localhost.evil.com/v1"));
        verify(!StringUtils.isLoopbackUrl("http://127.0.0.1.attacker.net/"));
        verify(!StringUtils.isLoopbackUrl("http://localhost@evil.com/"));
        verify(!StringUtils.isLoopbackUrl("localhost:11434"), "scheme-less is not a URL the shell would send to");
        verify(!StringUtils.isLoopbackUrl("http://127.1:11434/"));
        verify(!StringUtils.isLoopbackUrl(""));
        verify(!StringUtils.isLoopbackUrl(null));
    }
}
