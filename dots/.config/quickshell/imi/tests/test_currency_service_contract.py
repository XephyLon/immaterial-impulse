from pathlib import Path


SERVICE = Path("modules/common/plugins/designsystem/services/CurrencyService.qml")
WRAPPER = Path("modules/common/plugins/bundled/nandoroid-currency/Widget.qml")


def test_currency_service_fetches_one_target_table_from_api():
    source = SERVICE.read_text()
    schedule = (SERVICE.parent / "currency_schedule.js").read_text()
    # URL building moved into the schedule module when the service gained a
    # mirror host - one attempt walks both before counting as a failure.
    assert "currencies/" in schedule and "encodeURIComponent(baseCode)" in schedule
    assert "cdn.jsdelivr.net" in schedule, "the documented mirror"
    assert "CurrencyMath.ratesIntoTarget(table, uniqueQuotes)" in source
    # Three requests live here and only three: the live rates, the daily
    # walker's one-date-at-a-time step, and the names table. A fourth is a
    # question to ask before it ships.
    assert source.count("new XMLHttpRequest()") == 3


def test_currency_service_retries_instead_of_giving_up():
    """The service used to make ONE attempt per session, so a shell that
    started before the network stayed on 'Network timeout' forever."""
    source = SERVICE.read_text()
    schedule = (SERVICE.parent / "currency_schedule.js").read_text()
    assert "attemptFailed" in source and "nextAttempt" in source
    assert "Schedule.nextRetryMs" in source
    assert "Schedule.REFRESH_MS" in source, "success settles into periodic refresh"
    assert "failureCount" in source
    assert "RETRY_DELAYS_MS" in schedule


def test_currency_service_ignores_stale_responses():
    source = SERVICE.read_text()
    assert "requestGeneration" in source
    assert "generation !== root.requestGeneration" in source


def test_currency_service_refetches_after_plugin_bindings_settle():
    source = SERVICE.read_text()
    assert "id: refreshDebounce" in source
    assert "onBaseCurrencyChanged: scheduleRefresh()" in source
    for quote in range(1, 5):
        assert f"onQuote{quote}Changed: scheduleRefresh()" in source
    assert "Component.onCompleted: scheduleRefresh()" in source


def test_wrapper_does_not_duplicate_service_refreshes():
    source = WRAPPER.read_text()
    assert "CurrencyService.refresh()" not in source


def test_a_timeout_reaches_the_mirror_rather_than_ending_the_attempt():
    """A hung primary is the case the mirror most exists for.

    The timeout used to call `attemptFailed()` directly - it had no way to
    name the attempt it was killing - so the one failure mode the fallback was
    added for (DNS blackhole, TLS stall: connection accepted, nothing ever
    answers) went straight to backoff without ever trying jsdelivr. Only a
    non-200, a parse error or an empty table reached it.
    """
    source = SERVICE.read_text()
    assert "property var pendingAttempt" in source
    timeout = source[source.index("id: requestTimeout"):]
    timeout = timeout[:timeout.index("\n    }")]
    assert "root.tryHost(attempt.urls, attempt.hostIndex + 1" in timeout, \
        "the timeout must advance to the next host"
    # ...and the attempt must be cleared wherever it ends, or a later timeout
    # would resume a request that already answered.
    assert source.count("root.pendingAttempt = null") >= 3


def test_currency_service_has_bounded_non_reentrant_request():
    source = SERVICE.read_text()
    assert "id: requestTimeout" in source
    assert ".abort()" not in source
    assert 'root.attemptFailed("Network timeout")' in source, \
        "the timeout feeds the retry schedule now, not a terminal message"


def test_service_remembers_a_day_of_rates():
    """The 3x1's chart line and movement columns read the shell's own
    observations - the upstream dataset is daily, so sampled refreshes are
    the only honest 24-hour history. Sampled on success, pruned to the
    window, persisted so a restart does not forget the day."""
    source = SERVICE.read_text()
    history = (SERVICE.parent / "currency_history.js").read_text()
    assert "History.pushSample(root.history, now" in source
    assert "root.lastSuccessTime = now" in source
    assert "historyFile.setText" in source, "the day must survive a restart"
    assert "History.prune(stored.history, Date.now())" in source,         "a stale file must load as the empty ring it really is"
    assert "MIN_GAP_MS" in history and "PRUNE_MS" in history
    # The sampling adds no network of its own (the daily walker and the
    # names fetch are counted in the fetch test).
    assert "History.pushSample" in source


def test_service_walks_the_dated_snapshots_politely():
    """The 3x2's 7- and 30-day charts read fetched daily closes. One date
    per step on a spaced timer - a cold store is ~30 polite CDN hits, a
    warm one asks for one file a day - a 404'd date is recorded for the
    session rather than re-asked every pass, and a change of base clears
    the store through the same fold that fills it."""
    source = SERVICE.read_text()
    daily = (SERVICE.parent / "currency_daily.js").read_text()
    assert "Daily.missingDates" in source
    assert "Daily.foldSnapshot" in source
    assert "dailyUnavailable" in source
    assert "interval: 400" in source, "the walker is spaced, not a burst"
    assert "currency-api@${date}" in source and ".currency-api.pages.dev" in source,         "both dated hosts, like the live pair"
    assert "DAYS_KEPT" in daily
    assert '"daily: root.daily' not in source  # sanity: no stringified typo
    assert "daily: root.daily" in source, "the month must survive a restart"


if __name__ == "__main__":
    import sys
    from contract_runner import run
    sys.exit(run(globals()))
