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
    assert source.count("new XMLHttpRequest()") == 1


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


def test_currency_service_has_bounded_non_reentrant_request():
    source = SERVICE.read_text()
    assert "id: requestTimeout" in source
    assert ".abort()" not in source
    assert 'root.attemptFailed("Network timeout")' in source, \
        "the timeout feeds the retry schedule now, not a terminal message"


if __name__ == "__main__":
    import sys
    from contract_runner import run
    sys.exit(run(globals()))
