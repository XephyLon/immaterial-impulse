pragma Singleton
import QtQuick
import Quickshell
import "CurrencyMath.js" as CurrencyMath
import "currency_schedule.js" as Schedule

Singleton {
    id: root
    property bool loading: false
    property string errorMessage: ""
    property var rates: ({})
    property string baseCurrency: "USD"
    property string quote1: "EUR"
    property string quote2: "GBP"
    property string quote3: "JPY"
    property string quote4: "CAD"
    property int requestGeneration: 0
    // Consecutive failures, for the backoff. Reset by success and by any
    // settings change (a new base deserves a fresh quick attempt).
    property int failureCount: 0

    // PluginState bindings are applied just after this singleton is created.  A
    // short debounce prevents the default USD request from winning that race
    // and also coalesces settings edits into one batch of API requests.
    Timer {
        id: refreshDebounce
        interval: 50
        repeat: false
        onTriggered: root.refresh()
    }

    // What the running request is, so a timeout can advance to the next host
    // rather than ending the attempt. A hung primary - DNS blackhole, TLS
    // stall - is the case the mirror most exists for, and it was the one case
    // that never reached it: the timeout called attemptFailed() directly
    // because it had no way to name the attempt it was killing.
    property var pendingAttempt: null

    Timer {
        id: requestTimeout
        interval: 12000
        repeat: false
        onTriggered: {
            // Invalidate the callback without aborting from inside a timer.
            // Qt's XHR abort path can synchronously re-enter QML handlers.
            root.requestGeneration++;
            const attempt = root.pendingAttempt;
            root.errorMessage = "Network timeout";
            if (attempt) {
                root.pendingAttempt = null;
                root.tryHost(attempt.urls, attempt.hostIndex + 1,
                             attempt.target, attempt.uniqueQuotes);
                return;
            }
            root.attemptFailed("Network timeout");
        }
    }

    // The schedule (currency_schedule.js): failure backs off from quick
    // retries to patient ones; success settles into an hourly refresh. The
    // service used to make ONE attempt per session, so a shell that started
    // before the network stayed on "Network timeout" forever.
    Timer {
        id: nextAttempt
        repeat: false
        onTriggered: root.refresh()
    }

    function scheduleRefresh() {
        root.failureCount = 0;
        nextAttempt.stop();
        refreshDebounce.restart();
    }

    onBaseCurrencyChanged: scheduleRefresh()
    onQuote1Changed: scheduleRefresh()
    onQuote2Changed: scheduleRefresh()
    onQuote3Changed: scheduleRefresh()
    onQuote4Changed: scheduleRefresh()
    Component.onCompleted: scheduleRefresh()

    function normalizedCode(value) {
        return String(value || "").trim().toLowerCase();
    }

    function attemptFailed(message) {
        root.loading = false;
        // Stale rates stay on screen; the message only fills empty slots.
        root.errorMessage = message;
        root.failureCount++;
        nextAttempt.interval = Schedule.nextRetryMs(root.failureCount);
        nextAttempt.restart();
    }

    function attemptSucceeded() {
        root.loading = false;
        root.failureCount = 0;
        nextAttempt.interval = Schedule.REFRESH_MS;
        nextAttempt.restart();
    }

    function refresh() {
        if (!root.baseCurrency) return;
        requestTimeout.stop();
        root.loading = true;
        const target = normalizedCode(root.baseCurrency);
        const quotes = [root.quote1, root.quote2, root.quote3, root.quote4]
            .map(normalizedCode).filter(code => code.length > 0);
        const uniqueQuotes = quotes.filter((code, index) => quotes.indexOf(code) === index);
        if (uniqueQuotes.length === 0) {
            root.loading = false;
            root.errorMessage = "No quote currencies";
            root.rates = ({});
            return;
        }
        root.tryHost(Schedule.urlsFor(target), 0, target, uniqueQuotes);
    }

    // One attempt walks the host list (primary, then the mirror) before it
    // counts as a failure and backs off.
    function tryHost(urls, hostIndex, target, uniqueQuotes) {
        if (hostIndex >= urls.length) {
            root.pendingAttempt = null;
            root.attemptFailed(root.errorMessage || "No network");
            return;
        }
        const generation = ++root.requestGeneration;
        root.pendingAttempt = { urls: urls, hostIndex: hostIndex,
                                target: target, uniqueQuotes: uniqueQuotes };
        const xhr = new XMLHttpRequest();
        xhr.open("GET", urls[hostIndex]);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || generation !== root.requestGeneration) return;
            requestTimeout.stop();
            root.pendingAttempt = null;
            if (xhr.status !== 200) {
                root.errorMessage = xhr.status === 0 ? "No network" : `HTTP ${xhr.status}`;
                root.tryHost(urls, hostIndex + 1, target, uniqueQuotes);
                return;
            }
            try {
                const table = JSON.parse(xhr.responseText)[target] || {};
                const fetchedRates = CurrencyMath.ratesIntoTarget(table, uniqueQuotes);
                if (Object.keys(fetchedRates).length > 0) {
                    root.rates = fetchedRates;
                    root.errorMessage = "";
                    root.attemptSucceeded();
                } else {
                    root.errorMessage = "No rates returned";
                    root.tryHost(urls, hostIndex + 1, target, uniqueQuotes);
                }
            } catch (error) {
                root.errorMessage = "Parse error";
                root.tryHost(urls, hostIndex + 1, target, uniqueQuotes);
            }
        };
        requestTimeout.restart();
        xhr.send();
    }
}
