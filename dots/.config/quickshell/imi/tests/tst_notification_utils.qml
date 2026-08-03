import QtQuick
import QtTest
import qs.modules.common.functions

// Behavioral tests for modules/common/functions/NotificationUtils.qml, and in
// particular for the KDE Connect body decode.
//
// The fixture below is the real thing, captured off the session bus rather
// than written from memory - it is the exact body KDE Connect delivered for a
// Teams message from the phone. The tags are escaped once and the quotes
// twice, which is the signature of a single toHtmlEscaped() over text that was
// already HTML, and it is what makes one decode the right answer rather than a
// guess.
TestCase {
    id: root
    name: "NotificationUtilsTest"

    readonly property string capturedKdeConnectBody:
        "Bilal, Haya, and Nesma: &lt;b&gt;Haya Ezzat&lt;/b&gt;&lt;br/&gt;" +
        "&amp;quot;companyId&amp;quot;: 146,  &amp;quot;companyLicenseCode&amp;quot;: 146,"

    function test_kdeconnect_markup_is_decoded_to_real_markup() {
        const out = NotificationUtils.processNotificationBody(root.capturedKdeConnectBody, "KDE Connect")
        verify(out.includes("<b>Haya Ezzat</b>"))
        verify(out.includes("<br/>"))
        verify(!out.includes("&lt;"))
    }

    // The double-escaped quotes are the reason the decode is a single pass.
    // Two passes would turn &amp;quot; into a bare quote, dropping a level of
    // escaping the phone deliberately kept.
    function test_kdeconnect_decode_removes_exactly_one_level() {
        const out = NotificationUtils.processNotificationBody(root.capturedKdeConnectBody, "KDE Connect")
        verify(out.includes("&quot;companyId&quot;"))
        verify(!out.includes("&amp;quot;"))
    }

    function test_the_sender_is_matched_regardless_of_spacing() {
        const forms = ["KDE Connect", "kdeconnect", "KDE-Connect", "kde_connect", "org.kde.kdeconnect"]
        for (let i = 0; i < forms.length; i++)
            verify(NotificationUtils.isDoubleEscapingRelay(forms[i]), forms[i])
    }

    // Everything else escapes the non-markup parts of its body itself, exactly
    // as the spec asks of a sender when the server advertises body-markup.
    // Decoding those would corrupt them, and the renderer already handles them.
    function test_other_senders_are_left_alone() {
        const body = "a &lt; b &amp;&amp; c"
        compare(NotificationUtils.processNotificationBody(body, "teams-for-linux"), body)
        compare(NotificationUtils.processNotificationBody(body, ""), body)
        compare(NotificationUtils.processNotificationBody(body, undefined), body)
    }

    function test_a_plain_kdeconnect_body_survives_unchanged() {
        const body = "Alice: see you at 5"
        compare(NotificationUtils.processNotificationBody(body, "KDE Connect"), body)
    }

    function test_decoding_covers_the_entities_qt_escapes() {
        compare(NotificationUtils.decodeHtmlEntitiesOnce("&lt;&gt;&amp;&quot;&apos;&#39;"), "<>&\"''")
    }

    // Pre-existing behaviour, pinned so the decode above cannot quietly break
    // it: Chromium browsers put a link on the first line, which is dropped.
    function test_chromium_first_line_is_still_dropped() {
        const body = "<a href=\"https://x\">x</a>\n\nreal content"
        compare(NotificationUtils.processNotificationBody(body, "Brave"), "real content")
        compare(NotificationUtils.processNotificationBody(body, "firefox"), body)
    }

    function test_images_are_still_separated_onto_their_own_line() {
        verify(NotificationUtils.processNotificationBody("text<img src='x'/>", "whatever")
               .includes("\n\n<img"))
    }
}
