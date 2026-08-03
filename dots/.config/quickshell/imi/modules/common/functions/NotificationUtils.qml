pragma Singleton
import Quickshell

Singleton {
    id: root
    /**
     * @param { string } summary 
     * @returns { string }
     */
    function findSuitableMaterialSymbol(summary = "") {
        const defaultType = 'chat';
        if (summary.length === 0) return defaultType;

        const keywordsToTypes = {
            'reboot': 'restart_alt',
            'record': 'screen_record',
            'battery': 'power',
            'power': 'power',
            'screenshot': 'screenshot_monitor',
            'welcome': 'waving_hand',
            'time': 'scheduleb',
            'installed': 'download',
            'configuration reloaded': 'reset_wrench',
            'unable': 'question_mark',
            "couldn't": 'question_mark',
            'config': 'reset_wrench',
            'update': 'update',
            'ai response': 'neurology',
            'control': 'settings',
            'upsca': 'compare',
            'music': 'queue_music',
            'install': 'deployed_code_update',
            'input': 'keyboard_alt',
            'preedit': 'keyboard_alt',
            'startswith:file': 'folder_copy', // Declarative startsWith check
        };

        const lowerSummary = summary.toLowerCase();

        for (const [keyword, type] of Object.entries(keywordsToTypes)) {
            if (keyword.startsWith('startswith:')) {
                const startsWithKeyword = keyword.replace('startswith:', '');
                if (lowerSummary.startsWith(startsWithKeyword)) {
                    return type;
                }
            } else if (lowerSummary.includes(keyword)) {
                return type;
            }
        }

        return defaultType;
    }

    /**
     * @param { number | string | Date } timestamp 
     * @returns { string }
     */
    function getFriendlyNotifTimeString(timestamp) {
        if (!timestamp) return '';
        const messageTime = new Date(timestamp);
        const now = new Date();
        const diffMs = now.getTime() - messageTime.getTime();

        // Less than 1 minute
        if (diffMs < 60000)
            return 'Now';

        // Same day - show relative time
        if (messageTime.toDateString() === now.toDateString()) {
            const diffMinutes = Math.floor(diffMs / 60000);
            const diffHours = Math.floor(diffMs / 3600000);

            if (diffHours > 0) {
                return `${diffHours}h`;
            } else {
                return `${diffMinutes}m`;
            }
        }

        // Yesterday
        if (messageTime.toDateString() === new Date(now.getTime() - 86400000).toDateString())
            return 'Yesterday';

        // Older dates
        return Qt.formatDateTime(messageTime, "MMMM dd");
    }

    // One level of HTML entity decoding, in a single left-to-right pass.
    //
    // The single pass is the point, and `&amp;quot;` is why: scanning left to
    // right, `&amp;` matches first and becomes `&`, and the trailing `quot;`
    // is left alone because the scan resumes past it - so the result is
    // `&quot;`, one level decoded rather than two. Decoding `&amp;` in a
    // separate later pass would turn it into `"` and silently eat a level of
    // escaping the sender meant to keep.
    function decodeHtmlEntitiesOnce(text) {
        const named = {
            "lt": "<", "gt": ">", "amp": "&",
            "quot": "\"", "apos": "'", "#39": "'"
        };
        return text.replace(/&(lt|gt|amp|quot|apos|#39);/g, (match, entity) => named[entity]);
    }

    // KDE Connect relays a phone notification's text verbatim and runs it
    // through Qt's toHtmlEscaped() on the way out. When the Android app put
    // markup in that text - Teams does, and it is what makes the sender's name
    // bold and puts the message on its own line - the escaping arrives here as
    // literal `<b>` and `<br/>` on screen.
    //
    // Captured off the bus to be sure, rather than inferred:
    //   Bilal, Haya, and Nesma: &lt;b&gt;Haya Ezzat&lt;/b&gt;&lt;br/&gt;&amp;quot;companyId&amp;quot;: 146,
    // The tags are escaped once and the quotes twice, which is exactly one
    // toHtmlEscaped() over text that was already HTML - so one decode inverts
    // it precisely, leaving `<b>`/`<br/>` as markup and `&quot;` as the quote
    // character the phone intended.
    //
    // Scoped to this sender on purpose. Every other app is expected to escape
    // the parts of its body that are *not* markup, exactly as the spec asks
    // given we advertise body-markup - decoding those would corrupt them, and
    // the renderer already handles them correctly.
    function isDoubleEscapingRelay(appName) {
        return !!appName && appName.replace(/[\s_-]/g, "").toLowerCase().includes("kdeconnect");
    }

    function processNotificationBody(body, appName) {
        let processedBody = body

        if (root.isDoubleEscapingRelay(appName))
            processedBody = root.decodeHtmlEntitiesOnce(processedBody)

        // Clean Chromium-based browsers notifications - remove first line
        if (appName) {
            const lowerApp = appName.toLowerCase()
            const chromiumBrowsers = [
                "brave", "chrome", "chromium", "vivaldi", "opera", "microsoft edge"
            ]

            if (chromiumBrowsers.some(name => lowerApp.includes(name))) {
                const lines = body.split('\n\n')

                if (lines.length > 1 && lines[0].startsWith('<a')) {
                    processedBody = lines.slice(1).join('\n\n')
                }
            }
        }

        processedBody = processedBody.replace(/<img/gi, '\n\n<img');
        
        return processedBody
    }
}
