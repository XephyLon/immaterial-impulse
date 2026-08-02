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
