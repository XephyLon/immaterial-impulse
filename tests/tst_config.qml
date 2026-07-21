import QtQuick
import QtTest
import qs.modules.common

TestCase {
    name: "ConfigDefaultsTest"

    function test_defaults() {
        // Access Config singleton directly
        var config = Config
        verify(config !== null)

        // Test high-level settings
        compare(config.options.panelFamily, "ii")

        // Test policies
        compare(config.options.policies.ai, 1)
        compare(config.options.policies.weeb, 1)

        // Test appearance
        compare(config.options.appearance.fakeScreenRounding, 2)
        compare(config.options.appearance.transparency.enable, false)
        compare(config.options.appearance.transparency.backgroundTransparency, 0.11)
        compare(config.options.appearance.transparency.contentTransparency, 0.57)
        compare(config.options.appearance.terminal.background.enabled, false)
        compare(config.options.appearance.terminal.background.imagePath, "")
        compare(config.options.appearance.terminal.background.layout, "tiled")
        compare(config.options.appearance.terminal.background.opacity, 0.18)

        // Test audio protection
        compare(config.options.audio.protection.enable, false)
        compare(config.options.audio.protection.maxAllowedIncrease, 10)
        compare(config.options.audio.protection.maxAllowed, 99)

        // Bar divider. Divisor.qml switches on `style` by string and takes its
        // blank width from `spacing`, so an unset or renamed key here degrades
        // the divider silently rather than failing loudly.
        compare(config.options.bar.divider.style, "rect")
        compare(config.options.bar.divider.spacing, 20)

        // Test other options
        compare(config.options.dock.enable, false)
        compare(config.options.osd.timeout, 1000)
        compare(config.options.resources.updateInterval, 3000)
    }
}
