pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import "CurrencyMath.js" as CurrencyMath
import "currency_schedule.js" as Schedule
import "currency_history.js" as History
import "currency_daily.js" as Daily

Singleton {
    id: root
    property bool loading: false
    property string errorMessage: ""
    property var rates: ({})
    // The shell's own 24-hour memory of those rates (currency_history.js):
    // one sample per successful refresh, persisted so a restart does not
    // forget the day. The 3x1's chart line and the per-quote movement read
    // it - the upstream dataset is daily, so what this machine observed IS
    // the past 24 hours, honestly.
    property var history: []
    property double lastSuccessTime: 0
    // The month of daily closes (currency_daily.js): fetched from the
    // dataset's dated snapshots - one file per day carries every currency
    // against the base - so the 3x2's 7-day and 30-day charts cost ~30
    // cached CDN files once, then one new file per day. `dailyUnavailable`
    // records dates the CDN answered 404 for (the dataset's early years
    // have gaps), so they are not re-asked every pass.
    property var daily: ({})
    property var dailyUnavailable: ({})
    // The dataset's own code -> display name table ("egp" -> "Egyptian
    // Pound"), fetched once and kept.
    property var currencyNames: ({})
    function nameFor(code) {
        return root.currencyNames[String(code || "").toLowerCase()]
            ?? String(code || "").toUpperCase();
    }
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
        const now = Date.now();
        root.lastSuccessTime = now;
        root.history = History.pushSample(root.history, now,
            normalizedCode(root.baseCurrency).toUpperCase(), root.rates);
        historySave.restart();
        root.refreshDaily();
        root.fetchNamesOnce();
        nextAttempt.interval = Schedule.REFRESH_MS;
        nextAttempt.restart();
    }

    // ---- the month of closes, fetched date by date --------------------
    //
    // One date at a time, 400ms apart, so a cold store is ~30 polite CDN
    // hits rather than a burst; a warm store asks for one file a day. The
    // walker re-checks what is missing after every answer, so a base
    // change mid-walk simply redirects the remaining steps.
    property var pendingDaily: null
    function refreshDaily() {
        if (root.pendingDaily !== null) return;
        dailyStep.restart();
    }
    property Timer dailyStep: Timer {
        interval: 400
        onTriggered: {
            const base = normalizedCode(root.baseCurrency);
            if (base === "") return;
            const store = (root.daily && root.daily.base === base.toUpperCase())
                ? root.daily : { base: base.toUpperCase(), days: {} };
            const missing = Daily.missingDates(store, Date.now(),
                Daily.DAYS_KEPT, root.dailyUnavailable);
            if (missing.length === 0) { root.pendingDaily = null; return; }
            root.fetchDailyDate(base, missing[0]);
        }
    }
    function fetchDailyDate(base, date) {
        const urls = [
            `https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@${date}/v1/currencies/${encodeURIComponent(base)}.json`,
            `https://${date}.currency-api.pages.dev/v1/currencies/${encodeURIComponent(base)}.json`
        ];
        root.tryDailyHost(base, date, urls, 0);
    }
    function tryDailyHost(base, date, urls, hostIndex) {
        if (hostIndex >= urls.length) {
            // Both hosts refused: record the gap and move on. A transient
            // outage marks a date unavailable for this session only - the
            // marker is not persisted, so tomorrow asks again.
            const skip = Object.assign({}, root.dailyUnavailable);
            skip[date] = true;
            root.dailyUnavailable = skip;
            root.pendingDaily = null;
            dailyStep.restart();
            return;
        }
        const xhr = new XMLHttpRequest();
        root.pendingDaily = { date: date };
        xhr.open("GET", urls[hostIndex]);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status !== 200) {
                root.tryDailyHost(base, date, urls, hostIndex + 1);
                return;
            }
            try {
                const table = JSON.parse(xhr.responseText)[base] || {};
                const quotes = [root.quote1, root.quote2, root.quote3, root.quote4]
                    .map(normalizedCode).filter(code => code.length > 0);
                const folded = CurrencyMath.ratesIntoTarget(table, quotes);
                root.daily = Daily.foldSnapshot(root.daily, base.toUpperCase(),
                    date, folded, Date.now());
                historySave.restart();
            } catch (error) {
                const skip = Object.assign({}, root.dailyUnavailable);
                skip[date] = true;
                root.dailyUnavailable = skip;
            }
            root.pendingDaily = null;
            dailyStep.restart();
        };
        xhr.send();
    }
    // The names table, once. No retry schedule of its own: the next rates
    // refresh re-asks if it is still empty.
    function fetchNamesOnce() {
        if (Object.keys(root.currencyNames).length > 0) return;
        const xhr = new XMLHttpRequest();
        xhr.open("GET", "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies.json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200) return;
            try {
                root.currencyNames = JSON.parse(xhr.responseText) || {};
                historySave.restart();
            } catch (error) {}
        };
        xhr.send();
    }

    // ---- the day's memory, on disk ------------------------------------
    readonly property string historyPath: `${Directories.cache}/currency-history.json`
    property Timer historySave: Timer {
        interval: 2000
        onTriggered: historyFile.setText(JSON.stringify({
            history: root.history, lastSuccessTime: root.lastSuccessTime,
            daily: root.daily, currencyNames: root.currencyNames }))
    }
    property FileView historyFile: FileView {
        path: root.historyPath
        onLoaded: {
            try {
                const stored = JSON.parse(historyFile.text());
                // Pruned on the way in, so a file from last week loads as
                // the empty ring it really is.
                root.history = History.prune(stored.history, Date.now());
                const t = Number(stored.lastSuccessTime);
                if (Number.isFinite(t) && t > 0 && t <= Date.now())
                    root.lastSuccessTime = t;
                if (stored.daily && stored.daily.days)
                    root.daily = stored.daily;
                if (stored.currencyNames)
                    root.currencyNames = stored.currencyNames;
                root.refreshDaily();
            } catch (error) {
                console.warn("[CurrencyService] unreadable history, starting fresh");
                root.history = [];
            }
        }
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                console.warn("[CurrencyService] history load failed:", error);
        }
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
