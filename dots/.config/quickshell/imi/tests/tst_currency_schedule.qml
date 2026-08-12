import QtTest
import "../modules/common/plugins/designsystem/services/currency_schedule.js" as Schedule

// The currency service's retry arithmetic. The service used to make ONE
// attempt per session; these pin the schedule that replaced that.
TestCase {
    name: "CurrencyScheduleTest"

    function test_the_first_retry_is_quick() {
        // The common failure is the shell starting before the network; the
        // boot race resolves in seconds and the retry should too.
        compare(Schedule.nextRetryMs(1), 5000);
    }

    function test_failure_backs_off_and_caps() {
        compare(Schedule.nextRetryMs(2), 15000);
        compare(Schedule.nextRetryMs(3), 60000);
        compare(Schedule.nextRetryMs(4), 300000);
        compare(Schedule.nextRetryMs(50), 300000,
                "an hour offline still recovers within five minutes");
    }

    function test_success_refreshes_hourly() {
        verify(Schedule.REFRESH_MS === 3600000,
               "the dataset updates daily; hourly is already generous");
    }

    function test_one_attempt_tries_the_mirror_too() {
        const urls = Schedule.urlsFor("usd");
        compare(urls.length, 2);
        verify(urls[0].indexOf("currency-api.pages.dev") !== -1);
        verify(urls[1].indexOf("cdn.jsdelivr.net") !== -1);
        verify(urls[0].indexOf("/usd.json") !== -1);
    }

    function test_the_base_code_is_url_encoded() {
        const urls = Schedule.urlsFor("a/b");
        verify(urls[0].indexOf("a%2Fb") !== -1);
    }
}
