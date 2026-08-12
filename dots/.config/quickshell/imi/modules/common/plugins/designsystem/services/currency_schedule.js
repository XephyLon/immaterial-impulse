.pragma library

// When the currency service tries again, as arithmetic.
//
// The service used to make exactly ONE attempt, 50ms after startup, and any
// failure - most commonly the shell starting before the network is up -
// left "Network timeout" on screen until a settings edit happened to trigger
// a new request. Rates also never refreshed within a session.
//
// Failure backs off: quick retries first (the boot race resolves in
// seconds), then patient ones, capped at five minutes so a laptop that was
// offline for an hour still recovers within five minutes of the network
// returning. Success settles into an hourly refresh - the upstream dataset
// updates daily, so anything faster is discourtesy to a free API.

var RETRY_DELAYS_MS = [5000, 15000, 60000, 300000];
var REFRESH_MS = 3600000;

function nextRetryMs(failureCount) {
    if (failureCount <= 0) return RETRY_DELAYS_MS[0];
    var index = Math.min(failureCount - 1, RETRY_DELAYS_MS.length - 1);
    return RETRY_DELAYS_MS[index];
}

// The hosts, in the order they are tried within one attempt. Both serve the
// same dataset (fawazahmed0/exchange-api); the pages.dev host is primary and
// the jsdelivr mirror is the documented fallback.
function urlsFor(baseCode) {
    var code = encodeURIComponent(baseCode);
    return [
        "https://latest.currency-api.pages.dev/v1/currencies/" + code + ".json",
        "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/" + code + ".json"
    ];
}
