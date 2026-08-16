import QtTest
import "../modules/imi/bar/bar_widget_source.js" as BarWidgetSource

// Which file draws a bar widget. Both bars ask this module, so the kinds it
// knows about are the kinds BOTH bars support - which is the whole point: the
// vertical bar used to carry its own copy that had never learned `plugin:`,
// and capitalised the id into `Plugin:docker_plugin.qml`.
TestCase {
    name: "BarWidgetSourceTest"

    function test_a_plain_widget_name_is_capitalised_into_its_file() {
        compare(BarWidgetSource.fileNameFor("media"), "Media.qml");
        compare(BarWidgetSource.fileNameFor("clockWidget"), "ClockWidget.qml");
        compare(BarWidgetSource.fileNameFor("sysTray"), "SysTray.qml");
    }

    function test_an_absent_widget_name_resolves_to_nothing() {
        compare(BarWidgetSource.fileNameFor(""), "");
        compare(BarWidgetSource.fileNameFor(undefined), "");
        compare(BarWidgetSource.fileNameFor(null), "");
    }

    function test_a_plugin_id_never_reaches_the_capitalising_fallback() {
        // The defect verbatim: `plugin:docker_plugin` came out of the vertical
        // bar as `Plugin:docker_plugin.qml`. A colon cannot appear in any file
        // this shell ships, so it is the shape to refuse, not one id.
        const names = ["plugin:docker_plugin", "plugin:discord_voice",
                       "plugin:some_installed_package", "plugin:x"];
        for (const name of names) {
            const fileName = BarWidgetSource.fileNameFor(name);
            verify(fileName.indexOf(":") === -1,
                   `${name} resolved to ${fileName}, which is a capitalised id rather than a file`);
            verify(fileName.indexOf("plugin:") === -1,
                   `${name} resolved to ${fileName}`);
        }
    }

    function test_the_two_bundled_bar_plugins_take_their_native_components() {
        compare(BarWidgetSource.fileNameFor("plugin:docker_plugin"), "DockerPlugin.qml");
        compare(BarWidgetSource.fileNameFor("plugin:discord_voice"), "DiscordVoicePlugin.qml");
    }

    function test_every_other_plugin_takes_the_generic_package_host() {
        compare(BarWidgetSource.fileNameFor("plugin:some_installed_package"), "PluginBarWidget.qml");
        compare(BarWidgetSource.fileNameFor("plugin:nandoroid_media"), "PluginBarWidget.qml");
    }

    // An installed plugin picks its own id, so the native-component lookup is
    // an attacker-chosen key into an object literal. Without the hasOwnProperty
    // guard these resolve to something off Object's prototype.
    function test_an_id_naming_a_prototype_member_still_takes_the_package_host() {
        compare(BarWidgetSource.fileNameFor("plugin:constructor"), "PluginBarWidget.qml");
        compare(BarWidgetSource.fileNameFor("plugin:toString"), "PluginBarWidget.qml");
        compare(BarWidgetSource.fileNameFor("plugin:__proto__"), "PluginBarWidget.qml");
    }

    function test_a_plugin_id_is_the_layout_token_minus_its_prefix() {
        compare(BarWidgetSource.pluginIdOf("plugin:docker_plugin"), "docker_plugin");
        compare(BarWidgetSource.pluginIdOf("media"), "");
        compare(BarWidgetSource.pluginIdOf(""), "");
        compare(BarWidgetSource.pluginIdOf(undefined), "");
        // Not a prefix match anywhere but the front.
        compare(BarWidgetSource.pluginIdOf("myplugin:thing"), "");
    }

    function test_only_a_plugin_the_user_disabled_is_dropped_from_a_layout() {
        const enabled = ["docker_plugin", "notes"];
        verify(!BarWidgetSource.isDisabledPlugin("plugin:docker_plugin", enabled));
        verify(BarWidgetSource.isDisabledPlugin("plugin:discord_voice", enabled));
        // A built-in widget is not a plugin and is never dropped by this rule,
        // whatever the enabled list happens to hold.
        verify(!BarWidgetSource.isDisabledPlugin("media", enabled));
        verify(!BarWidgetSource.isDisabledPlugin("media", []));
    }
}
