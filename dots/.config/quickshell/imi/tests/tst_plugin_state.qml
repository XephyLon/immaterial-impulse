import QtQuick
import QtTest
import qs.modules.common
import qs.modules.common.plugins

TestCase {
    name: "PluginStateTest"

    property bool savedTransparency: false

    function init() {
        savedTransparency = Config.options.appearance.transparency.enable;
    }

    function cleanup() {
        Config.options.appearance.transparency.enable = savedTransparency;
    }

    function test_positionDefaultsWhenUnset() {
        var pos = PluginState.position("nonexistent_plugin", "DP-1");
        compare(pos.x, 100);
        compare(pos.y, 100);
        compare(pos.placementStrategy, "free");
    }

    function test_setPositionRoundTrips() {
        PluginState.setPosition("docker_plugin", "DP-1", { x: 564, y: 432, placementStrategy: "free" });
        var pos = PluginState.position("docker_plugin", "DP-1");
        compare(pos.x, 564);
        compare(pos.y, 432);
        compare(pos.placementStrategy, "free");
    }

    // Regression test: AbstractBackgroundWidget's onReleased used to write straight into
    // Config.options.background.widgets[configEntryName], an undeclared JsonObject key for
    // plugin widgets, which crashed qs on drag-release. Positions must round-trip purely
    // through PluginState instead, with no dependency on a Config-side entry existing.
    function test_setPositionDoesNotRequireConfigEntry() {
        PluginState.setPosition("some_never_configured_plugin", "HDMI-A-1", { x: 12, y: 34, placementStrategy: "free" });
        var pos = PluginState.position("some_never_configured_plugin", "HDMI-A-1");
        compare(pos.x, 12);
        compare(pos.y, 34);
    }

    function test_positionIsPerScreen() {
        PluginState.setPosition("at_a_glance_plugin", "DP-1", { x: 10, y: 20, placementStrategy: "free" });
        PluginState.setPosition("at_a_glance_plugin", "DP-2", { x: 30, y: 40, placementStrategy: "free" });
        compare(PluginState.position("at_a_glance_plugin", "DP-1").x, 10);
        compare(PluginState.position("at_a_glance_plugin", "DP-2").x, 30);
    }

    function test_normalizedPositionRejectsMalformedValues() {
        var pos = PluginState.normalizedPosition({ x: "not a number", y: 50, placementStrategy: 42 });
        compare(pos.x, 100);
        compare(pos.y, 50);
        compare(pos.placementStrategy, "free");
    }

    function test_normalizedPositionRejectsNonObject() {
        var pos = PluginState.normalizedPosition("garbage");
        compare(pos.x, 100);
        compare(pos.y, 100);
        compare(pos.placementStrategy, "free");
    }

    function test_optionDefaultsWhenUnset() {
        compare(PluginState.option("nonexistent_plugin", "blurEnabled", false), false);
        compare(PluginState.option("nonexistent_plugin", "fontSize", 24), 24);
    }

    function test_setOptionRoundTrips() {
        PluginState.setOption("at_a_glance_plugin", "blurEnabled", true);
        PluginState.setOption("at_a_glance_plugin", "fontSize", 26);
        compare(PluginState.option("at_a_glance_plugin", "blurEnabled", false), true);
        compare(PluginState.option("at_a_glance_plugin", "fontSize", 24), 26);
    }

    function test_setOptionDoesNotClobberOtherPlugins() {
        PluginState.setOption("docker_plugin", "blurEnabled", true);
        PluginState.setOption("at_a_glance_plugin", "blurEnabled", false);
        compare(PluginState.option("docker_plugin", "blurEnabled", false), true);
        compare(PluginState.option("at_a_glance_plugin", "blurEnabled", true), false);
    }

    // A manifest can ship a host behaviour on by default (the visualiser ships
    // `desktopWidget.clickThrough: true`), and the seed is passed as the
    // fallback argument here. Turning it back off in Settings stores `false`,
    // which must win over the `true` seed - so the lookup has to test for
    // `undefined`, not for falsiness. A `value || fallback` implementation
    // would silently make a shipped-on default impossible to switch off.
    function test_storedFalseOverridesATrueManifestDefault() {
        PluginState.setOption("visualizer", "clickThrough", false);
        compare(PluginState.option("visualizer", "clickThrough", true), false);
        PluginState.setOption("visualizer", "positionLocked", false);
        compare(PluginState.option("visualizer", "positionLocked", true), false);
    }

    // The inverse: with nothing stored, the manifest seed is what the host sees.
    function test_manifestDefaultAppliesUntilTheUserDecides() {
        compare(PluginState.option("never_configured_widget", "clickThrough", true), true);
        compare(PluginState.option("never_configured_widget", "clickThrough", false), false);
    }

    // Turning transparency off removes a widget's frost - PluginWidget gates
    // its blur Repeater on the same flag - but the panel's own alpha came from
    // `plugins.blurOpacity`, which does not consult it. Blur gone plus a 10%
    // panel is a hole onto the sharp wallpaper, which is the bug: opacity has
    // to follow the toggle too.
    function test_backgroundOpacityGoesOpaqueWithTransparencyOff() {
        compare(PluginState.resolveBackgroundOpacity(0.1, false, false), 1);
    }

    function test_backgroundOpacityKeepsItsValueWithTransparencyOn() {
        compare(PluginState.resolveBackgroundOpacity(0.1, true, false), 0.1);
    }

    // The escape hatch, for a widget whose whole point is to be see-through.
    function test_keepTranslucentExemptsAWidgetFromTheForcedOpacity() {
        compare(PluginState.resolveBackgroundOpacity(0.1, false, true), 0.1);
    }

    function test_effectiveBackgroundOpacityFollowsTheTransparencyToggle() {
        Config.options.appearance.transparency.enable = true;
        compare(PluginState.effectiveBackgroundOpacity("notes"),
            Config.options.plugins.blurOpacity);
        Config.options.appearance.transparency.enable = false;
        compare(PluginState.effectiveBackgroundOpacity("notes"), 1);
    }

    // The opt-out is a stored PluginState option, so it survives a restart and
    // stays reversible from Settings > Widgets - and it must not leak to the
    // widgets that did not ask for it.
    function test_effectiveBackgroundOpacityHonoursAStoredOptOut() {
        Config.options.appearance.transparency.enable = false;
        PluginState.setOption("see_through_widget", "keepTranslucent", true);
        compare(PluginState.effectiveBackgroundOpacity("see_through_widget"),
            Config.options.plugins.blurOpacity);
        compare(PluginState.effectiveBackgroundOpacity("opaque_widget"), 1);
    }

    // Same seed-then-override rule as clickThrough above: a manifest can ship
    // the opt-out on, and a stored `false` has to win over that seed.
    function test_keepTranslucentTakesTheManifestSeedUntilTheUserDecides() {
        Config.options.appearance.transparency.enable = false;
        compare(PluginState.effectiveBackgroundOpacity("seeded_widget", 0.1, true), 0.1);
        PluginState.setOption("seeded_widget", "keepTranslucent", false);
        compare(PluginState.effectiveBackgroundOpacity("seeded_widget", 0.1, true), 1);
    }

    // The generic designsystem widgets have no plugin identity, so they pass an
    // empty id and their own default alpha: the toggle still applies, there is
    // just nothing to opt out.
    function test_anUnidentifiedWidgetStillFollowsTheToggle() {
        Config.options.appearance.transparency.enable = false;
        compare(PluginState.effectiveBackgroundOpacity("", 0.1), 1);
        Config.options.appearance.transparency.enable = true;
        compare(PluginState.effectiveBackgroundOpacity("", 0.1), 0.1);
    }

    // The world clock keeps its four timezones here, and it is the only plugin
    // option that is a list rather than a scalar. Nothing in `setOption` is
    // list-aware - it does an `Object.assign` shallow copy and hands the value
    // straight to `JSON.stringify` - so this pins that an array survives both
    // the in-memory store and the serialize/parse round trip through the file,
    // element order included. A silently flattened or stringified list would
    // hand the service `undefined` timezones and no error.
    function test_setOptionRoundTripsAList() {
        var zones = ["Australia/Sydney", "Asia/Tokyo", "Europe/London", "America/New_York"];
        PluginState.setOption("world-clock", "timezones", zones);
        var stored = PluginState.option("world-clock", "timezones", []);
        compare(Array.isArray(stored), true);
        compare(stored.length, 4);
        compare(stored.join(","), zones.join(","));
    }

    function test_aListSurvivesTheFileRoundTrip() {
        PluginState.setOption("world-clock", "timezones",
            ["Europe/Berlin", "Asia/Kolkata", "America/Denver", "Pacific/Auckland"]);
        PluginState.loadText(PluginState.snapshot());
        var stored = PluginState.option("world-clock", "timezones", []);
        compare(Array.isArray(stored), true);
        compare(stored.join(","),
            "Europe/Berlin,Asia/Kolkata,America/Denver,Pacific/Auckland");
    }

    function test_loadTextIgnoresMalformedState() {
        PluginState.setPosition("docker_plugin", "DP-1", { x: 1, y: 2, placementStrategy: "free" });
        PluginState.loadText("{ not valid json");
        // Falls back to an empty state rather than crashing or keeping stale data.
        var pos = PluginState.position("docker_plugin", "DP-1");
        compare(pos.x, 100);
        compare(pos.y, 100);
    }

    function test_loadTextRejectsNonObjectRoot() {
        PluginState.loadText("[1, 2, 3]");
        compare(Object.keys(PluginState.state.desktopPositions).length, 0);
    }
}
