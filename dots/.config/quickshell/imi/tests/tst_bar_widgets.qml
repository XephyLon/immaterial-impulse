import QtQuick
import QtTest
import qs.modules.common.plugins

// The bar widget catalogue, promoted out of BarConfig.qml (Edit Mode spec
// §4.2): `available` is the one list of what can sit on the bar, and
// `nameFor(id)` is the one answer for what an id is called on screen. The
// settings page reads this singleton, and stage 8's drawer will read the same
// one - a second copy is the drift these tests exist to refuse.
//
// PluginManager here is the tests-mirror double (a writable
// `availablePlugins`), which is what lets the plugin-derivation tests drive
// the property the real singleton only changes on an install or uninstall.
TestCase {
    name: "BarWidgetsTest"

    property var savedPlugins: []

    function init() {
        savedPlugins = PluginManager.availablePlugins;
    }

    function cleanup() {
        PluginManager.availablePlugins = savedPlugins;
    }

    function test_theCatalogueCarriesTheBuiltInWidgets() {
        verify(BarWidgets.available.length >= 21,
               "expected the 21 built-in bar widgets, got "
               + BarWidgets.available.length);
        const ids = BarWidgets.available.map(w => w.id);
        // A spot check per bucket of the old BarConfig array: first entry,
        // one from the middle, and the divider that closed it.
        verify(ids.includes("leftSidebarButton"));
        verify(ids.includes("clockWidget"));
        verify(ids.includes("divisor"));
    }

    function test_everyEntryIsDrawable() {
        for (const w of BarWidgets.available) {
            verify(typeof w.id === "string" && w.id.length > 0,
                   "an entry with no id cannot be stored in a layout");
            verify(typeof w.name === "string" && w.name.length > 0,
                   `${w.id} has no display name`);
            verify(typeof w.icon === "string" && w.icon.length > 0,
                   `${w.id} has no icon`);
        }
    }

    function test_idsAreUnique() {
        const seen = {};
        for (const w of BarWidgets.available) {
            verify(!seen[w.id], `duplicate catalogue id ${w.id}`);
            seen[w.id] = true;
        }
    }

    function test_nameForAnswersForEveryCataloguedId() {
        for (const w of BarWidgets.available) {
            compare(BarWidgets.nameFor(w.id), w.name);
        }
    }

    // A layout can hold an id the catalogue no longer offers - a plugin that
    // was uninstalled. The chip for it must keep rendering something rather
    // than an empty label, which is what BarConfig.getWidgetName always did.
    function test_anUncataloguedIdFallsBackToItself() {
        compare(BarWidgets.nameFor("some_retired_widget"), "some_retired_widget");
    }

    function test_aPluginBarWidgetJoinsTheCatalogue() {
        PluginManager.availablePlugins = [
            { id: "docker_plugin", name: "Docker", icon: "", barWidget: "Widget.qml" },
            { id: "desktop_only", name: "Desktop Only" }
        ];
        const ids = BarWidgets.available.map(w => w.id);
        verify(ids.includes("plugin:docker_plugin"),
               "a manifest with a barWidget entry point must appear");
        verify(!ids.includes("plugin:desktop_only"),
               "a manifest with no barWidget entry point must not appear");
        compare(BarWidgets.nameFor("plugin:docker_plugin"), "Docker");
    }

    function test_aPluginWithNoIconGetsTheExtensionFallback() {
        PluginManager.availablePlugins = [
            { id: "docker_plugin", name: "Docker", icon: "", barWidget: "Widget.qml" }
        ];
        const entry = BarWidgets.available.find(w => w.id === "plugin:docker_plugin");
        compare(entry.icon, "extension");
    }

    // The derivation must be a binding on the property, not a one-shot read:
    // AGENT.md's LiveDesktopEntry entry is the invokable-call shape that does
    // not re-evaluate. Driving the property twice in one test is what proves
    // the list follows it.
    function test_theCatalogueFollowsThePluginList() {
        PluginManager.availablePlugins = [
            { id: "docker_plugin", name: "Docker", icon: "dock", barWidget: "Widget.qml" }
        ];
        verify(BarWidgets.available.some(w => w.id === "plugin:docker_plugin"));
        PluginManager.availablePlugins = [];
        verify(!BarWidgets.available.some(w => w.id === "plugin:docker_plugin"),
               "an uninstalled plugin's bar widget must leave the catalogue");
    }
}
