pragma Singleton
import QtQuick
import Quickshell
import "CurrencyMath.js" as CurrencyMath

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

    // PluginState bindings are applied just after this singleton is created.  A
    // short debounce prevents the default USD request from winning that race
    // and also coalesces settings edits into one batch of API requests.
    Timer {
        id: refreshDebounce
        interval: 50
        repeat: false
        onTriggered: root.refresh()
    }

    Timer {
        id: requestTimeout
        interval: 12000
        repeat: false
        onTriggered: {
            // Invalidate the callback without aborting from inside a timer.
            // Qt's XHR abort path can synchronously re-enter QML handlers.
            root.requestGeneration++;
            root.loading = false;
            root.errorMessage = "Network timeout";
        }
    }

    function scheduleRefresh() {
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

    function refresh() {
        if (!root.baseCurrency) return;
        requestTimeout.stop();
        root.loading = true;
        root.errorMessage = "";
        const generation = ++root.requestGeneration;
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

        const xhr = new XMLHttpRequest();
        xhr.open("GET", `https://latest.currency-api.pages.dev/v1/currencies/${encodeURIComponent(target)}.json`);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || generation !== root.requestGeneration) return;
            requestTimeout.stop();
            root.loading = false;
            if (xhr.status !== 200) {
                root.errorMessage = xhr.status === 0 ? "No network" : `HTTP ${xhr.status}`;
                return;
            }
            try {
                const table = JSON.parse(xhr.responseText)[target] || {};
                const fetchedRates = CurrencyMath.ratesIntoTarget(table, uniqueQuotes);
                root.rates = fetchedRates;
                root.errorMessage = Object.keys(fetchedRates).length > 0 ? "" : "No rates returned";
            } catch (error) {
                root.errorMessage = "Parse error";
            }
        };
        requestTimeout.restart();
        xhr.send();
    }
}
