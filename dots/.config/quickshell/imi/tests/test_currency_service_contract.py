from pathlib import Path


SERVICE = Path("modules/common/plugins/designsystem/services/CurrencyService.qml")
WRAPPER = Path("modules/common/plugins/bundled/nandoroid-currency/Widget.qml")


def test_currency_service_fetches_one_target_table_from_api():
    source = SERVICE.read_text()
    assert "currencies/${encodeURIComponent(target)}.json" in source
    assert "CurrencyMath.ratesIntoTarget(table, uniqueQuotes)" in source
    assert source.count("new XMLHttpRequest()") == 1


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
    assert 'root.errorMessage = "Network timeout"' in source


if __name__ == "__main__":
    import sys
    from contract_runner import run
    sys.exit(run(globals()))
