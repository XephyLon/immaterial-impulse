import QtQuick
import QtTest
import "../modules/common/plugins/PluginValidator.js" as PluginValidator

TestCase {
    name: "PluginValidatorTest"

    function test_validManifest() {
        var manifest = {
            "id": "my_clock",
            "name": "My Clock",
            "desktopWidget": {
                "type": "StyledRectangularShadow",
                "props": { "radius": 17 },
                "children": [
                    {
                        "type": "StyledText",
                        "bindings": { "text": "DateTime.time" }
                    }
                ]
            }
        };

        var result = PluginValidator.validateManifest(manifest);
        verify(result.valid, "Manifest should be valid: " + (result.error ? result.error : ""));
    }

    function test_validDockerManifest() {
        var manifest = {
            "id": "my_docker",
            "name": "My Docker",
            "permissions": ["process", "settings_read", "settings_write"],
            "capabilities": ["bar-widget"],
            "barWidget": { "component": "DockerWidget.qml" }
        };

        var result = PluginValidator.validateManifest(manifest);
        verify(result.valid, "Docker manifest should be valid: " + (result.error ? result.error : ""));
    }

    function test_rejectsEscapingPackageComponent() {
        var result = PluginValidator.validateManifest({
            "id": "escape",
            "name": "Escape",
            "desktopWidget": { "component": "../Outside.qml" }
        });
        verify(!result.valid);
        compare(result.error,
            "Invalid desktopWidget: Component must be a relative path inside the plugin package");
    }

    function test_rejectsUnknownPermission() {
        var result = PluginValidator.validateManifest({
            "id": "unsafe",
            "name": "Unsafe",
            "permissions": ["root"],
            "desktopWidget": { "type": "Item" }
        });
        verify(!result.valid);
        compare(result.error, "Unsupported plugin permission 'root'");
    }

    function test_validAtAGlanceManifest() {
        var manifest = {
            "id": "at_a_glance",
            "name": "At a Glance",
            "options": [
                { "key": "showGreeting", "type": "boolean", "default": true },
                {
                    "key": "alignment",
                    "type": "choice",
                    "default": "left",
                    "choices": [{ "displayName": "Left", "value": "left" }]
                },
                { "key": "fontSize", "type": "number", "default": 24, "from": 14, "to": 48 }
                , { "key": "currency", "type": "text", "default": "USD" }
            ],
            "desktopWidget": {
                "type": "AtAGlance",
                "props": {
                    "width": 420,
                    "showQuote": true
                },
                "blur": false
            }
        };

        var result = PluginValidator.validateManifest(manifest);
        verify(result.valid, "At-a-glance manifest should be valid: " + (result.error ? result.error : ""));
    }

    function test_missingId() {
        var manifest = {
            "name": "My Clock",
            "desktopWidget": { "type": "Item" }
        };
        var result = PluginValidator.validateManifest(manifest);
        verify(!result.valid);
        compare(result.error, "Manifest must have a string 'id'");
    }

    function test_invalidComponentType() {
        var manifest = {
            "id": "bad_plugin",
            "name": "Bad Plugin",
            "desktopWidget": {
                "type": "Process", // not whitelisted
            }
        };
        var result = PluginValidator.validateManifest(manifest);
        verify(!result.valid);
        compare(result.error, "Invalid desktopWidget: Component type 'Process' is not whitelisted");
    }

    function test_invalidPluginOptionType() {
        var manifest = {
            "id": "bad_options",
            "name": "Bad Options",
            "options": [{ "key": "script", "type": "javascript" }],
            "desktopWidget": { "type": "Item" }
        };
        var result = PluginValidator.validateManifest(manifest);
        verify(!result.valid);
        compare(result.error, "Unsupported plugin option type 'javascript'");
    }

    function test_shapeOptionTypeIsAccepted() {
        var manifest = {
            "id": "shape_options",
            "name": "Shape Options",
            "options": [{
                "key": "shape",
                "type": "shape",
                "default": "Heart",
                "choices": [{ "displayName": "Heart", "value": "Heart" }]
            }],
            "desktopWidget": { "component": "Widget.qml" }
        };
        var result = PluginValidator.validateManifest(manifest);
        verify(result.valid);
    }

    // A shape row with no choices renders an empty Flow, not an error, so the
    // validator has to be the one that catches it.
    function test_shapeOptionWithoutChoicesIsRejected() {
        var manifest = {
            "id": "empty_shape",
            "name": "Empty Shape",
            "options": [{ "key": "shape", "type": "shape", "default": "Heart" }],
            "desktopWidget": { "component": "Widget.qml" }
        };
        var result = PluginValidator.validateManifest(manifest);
        verify(!result.valid);
        compare(result.error, "Choice option 'shape' must have choices");
    }

    function test_invalidBindingTarget() {
        var manifest = {
            "id": "bad_binding",
            "name": "Bad Binding",
            "desktopWidget": {
                "type": "StyledText",
                "bindings": { "text": "Config.options.lock.enable" } // not whitelisted
            }
        };
        var result = PluginValidator.validateManifest(manifest);
        verify(!result.valid);
        compare(result.error, "Invalid desktopWidget: Binding target 'Config.options.lock.enable' is not whitelisted");
    }

    function test_validGridSpan() {
        var manifest = {
            "id": "grid_notes",
            "name": "Grid Notes",
            "grid": { "cols": 2, "rows": 2 },
            "desktopWidget": { "component": "Widget.qml" }
        };
        var result = PluginValidator.validateManifest(manifest);
        verify(result.valid, "Grid manifest should be valid: " + (result.error ? result.error : ""));
    }

    function test_gridDefaultsWhenPartial() {
        var result = PluginValidator.validateManifest({
            "id": "grid_col_only",
            "name": "Grid Col Only",
            "grid": { "cols": 3 },
            "desktopWidget": { "component": "Widget.qml" }
        });
        verify(result.valid, "Partial grid should be valid: " + (result.error ? result.error : ""));
    }

    function test_rejectsNonIntegerGrid() {
        var result = PluginValidator.validateManifest({
            "id": "grid_frac",
            "name": "Grid Frac",
            "grid": { "cols": 2.5, "rows": 1 },
            "desktopWidget": { "component": "Widget.qml" }
        });
        verify(!result.valid);
        compare(result.error, "grid.cols must be an integer between 1 and 12");
    }

    function test_rejectsNegativeGrid() {
        var result = PluginValidator.validateManifest({
            "id": "grid_neg",
            "name": "Grid Neg",
            "grid": { "cols": 1, "rows": -1 },
            "desktopWidget": { "component": "Widget.qml" }
        });
        verify(!result.valid);
        compare(result.error, "grid.rows must be an integer between 1 and 12");
    }

    function test_rejectsOversizedGrid() {
        var result = PluginValidator.validateManifest({
            "id": "grid_big",
            "name": "Grid Big",
            "grid": { "cols": 13, "rows": 1 },
            "desktopWidget": { "component": "Widget.qml" }
        });
        verify(!result.valid);
        compare(result.error, "grid.cols must be an integer between 1 and 12");
    }

    // A manifest's options and the host's own per-plugin state are one
    // PluginState namespace. `__gridSize` (the span the user resized a widget
    // to) lives there, so a manifest declaring a `__`-prefixed option would ship
    // a settings control that writes over host state.
    function test_rejectsReservedOptionKeyPrefix() {
        var result = PluginValidator.validateManifest({
            "id": "reserved_opt",
            "name": "Reserved Opt",
            "options": [{ "key": "__gridSize", "type": "boolean", "default": false }],
            "desktopWidget": { "component": "Widget.qml" }
        });
        verify(!result.valid);
        compare(result.error, "Plugin option key '__gridSize' is reserved: '__' is the host's prefix");
    }

    function test_acceptsASingleLeadingUnderscore() {
        var result = PluginValidator.validateManifest({
            "id": "underscore_opt",
            "name": "Underscore Opt",
            "options": [{ "key": "_private", "type": "boolean", "default": false }],
            "desktopWidget": { "component": "Widget.qml" }
        });
        verify(result.valid, "Single underscore should stay valid: " + (result.error ? result.error : ""));
    }

    function test_rejectsNonObjectGrid() {
        var result = PluginValidator.validateManifest({
            "id": "grid_arr",
            "name": "Grid Arr",
            "grid": [2, 2],
            "desktopWidget": { "component": "Widget.qml" }
        });
        verify(!result.valid);
        compare(result.error, "Manifest 'grid' must be an object with integer 'cols'/'rows'");
    }

    // `locked` and `clickThrough` seed the per-plugin PluginState options of the
    // same name. They are optional, so their absence must stay valid.
    function test_desktopWidgetInteractionFlagsAreAccepted() {
        var result = PluginValidator.validateManifest({
            "id": "pinned",
            "name": "Pinned",
            "desktopWidget": { "component": "Widget.qml", "locked": true, "clickThrough": true }
        });
        verify(result.valid, "Interaction flags should be valid: " + (result.error ? result.error : ""));
    }

    // A string "true" is the realistic mistake, and it is truthy - left
    // unchecked it would silently pin a widget the author only meant to
    // annotate, with no error anywhere.
    function test_rejectsNonBooleanClickThrough() {
        var result = PluginValidator.validateManifest({
            "id": "bad_click",
            "name": "Bad Click",
            "desktopWidget": { "component": "Widget.qml", "clickThrough": "true" }
        });
        verify(!result.valid);
        compare(result.error, "desktopWidget.clickThrough must be a boolean");
    }

    function test_rejectsNonBooleanLocked() {
        var result = PluginValidator.validateManifest({
            "id": "bad_lock",
            "name": "Bad Lock",
            "desktopWidget": { "component": "Widget.qml", "locked": 1 }
        });
        verify(!result.valid);
        compare(result.error, "desktopWidget.locked must be a boolean");
    }

    function test_rejectsNonBooleanBlur() {
        var result = PluginValidator.validateManifest({
            "id": "bad_blur",
            "name": "Bad Blur",
            "desktopWidget": { "component": "Widget.qml", "blur": "yes" }
        });
        verify(!result.valid);
        compare(result.error, "desktopWidget.blur must be a boolean");
    }

    function test_nestedInvalidChild() {
        var manifest = {
            "id": "nested_invalid",
            "name": "Nested",
            "desktopWidget": {
                "type": "Column",
                "children": [
                    { "type": "StyledText" },
                    { "type": "UnknownType" }
                ]
            }
        };
        var result = PluginValidator.validateManifest(manifest);
        verify(!result.valid);
        compare(result.error, "Invalid desktopWidget: Component type 'UnknownType' is not whitelisted");
    }
}
