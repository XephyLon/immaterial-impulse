import QtQuick
import QtTest
import "../modules/common/plugins/designsystem/services/CurrencyMath.js" as CurrencyMath

TestCase {
    name: "CurrencyMathTest"

    function test_preservesApiPairValues() {
        const rates = CurrencyMath.normalizeRates({
            usd: 50.544401,
            eur: 57.81241,
            jpy: 0.311217
        });
        compare(rates.USD, 50.544401);
        compare(rates.EUR, 57.81241);
        compare(rates.JPY, 0.311217);
    }

    function test_convertsSingleApiTableIntoTargetRates() {
        const rates = CurrencyMath.ratesIntoTarget({
            usd: 0.01978,
            eur: 0.01730,
            jpy: 3.213
        }, ["usd", "eur", "jpy"]);
        verify(Math.abs(rates.USD - 50.5561) < 0.001);
        verify(Math.abs(rates.EUR - 57.8035) < 0.001);
        verify(Math.abs(rates.JPY - 0.3112) < 0.001);
    }

    function test_usesReadablePrecision() {
        compare(CurrencyMath.fractionDigits(0.001234), 6);
        compare(CurrencyMath.fractionDigits(0.0197), 4);
        compare(CurrencyMath.fractionDigits(3.21), 2);
        compare(CurrencyMath.fractionDigits(1200), 0);
    }
}
