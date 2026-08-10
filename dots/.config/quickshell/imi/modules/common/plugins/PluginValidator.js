.pragma library

const componentWhitelist = [
    "StyledText", "StyledRectangularShadow", "MaterialSymbol", "GroupedList",
    "RippleButton", "ResourceCard", "StyledImage", "MaterialShape", "StyledPopup", "ConfigSwitch", "NoticeBox",
    "Row", "Column", "Item", "Rectangle", "AtAGlance"
];

const bindingWhitelist = [
    "DateTime.time", "DateTime.date", "DateTime.shortDate",
    "Battery.percentage", "Battery.charging", "Battery.pluggedIn",
    "Network.networkName", "Network.primaryIp", "SystemInfo.cpuUsage",
    "SystemInfo.ramUsage", "Audio.volume", "Audio.muted"
];

function validateManifest(manifest) {
    if (!manifest || typeof manifest !== 'object') {
        return { valid: false, error: "Manifest must be an object" };
    }
    if (!manifest.id || typeof manifest.id !== 'string') {
        return { valid: false, error: "Manifest must have a string 'id'" };
    }
    if (!manifest.name || typeof manifest.name !== 'string') {
        return { valid: false, error: "Manifest must have a string 'name'" };
    }
    if (manifest.permissions !== undefined) {
        if (!Array.isArray(manifest.permissions))
            return { valid: false, error: "Manifest 'permissions' must be an array" };
        const supportedPermissions = ["process", "network", "filesystem_read", "filesystem_write", "settings_read", "settings_write"];
        for (const permission of manifest.permissions) {
            if (!supportedPermissions.includes(permission))
                return { valid: false, error: "Unsupported plugin permission '" + permission + "'" };
        }
    }
    if (manifest.capabilities !== undefined && !Array.isArray(manifest.capabilities))
        return { valid: false, error: "Manifest 'capabilities' must be an array" };
    const entryPoints = ["desktopWidget", "barWidget", "controlCenterWidget", "launcherProvider", "panel", "settingsUi"];
    let hasEntryPoint = false;

    for (let i = 0; i < entryPoints.length; i++) {
        let ep = entryPoints[i];
        if (manifest[ep]) {
            hasEntryPoint = true;
            let res = validateNode(manifest[ep]);
            if (!res.valid) {
                return { valid: false, error: "Invalid " + ep + ": " + res.error };
            }
        }
    }

    if (!hasEntryPoint) {
        return { valid: false, error: "Manifest must have at least one entry point (e.g. desktopWidget, barWidget)" };
    }

    // Host desktop-widget defaults. Each one only seeds the initial value of
    // the matching PluginState option, so a non-boolean would slip through as
    // a truthy default nobody can account for later - reject it here instead.
    if (manifest.desktopWidget) {
        const desktopFlags = ["blur", "locked", "clickThrough", "keepTranslucent",
            "followParallax"];
        for (const flag of desktopFlags) {
            if (manifest.desktopWidget[flag] !== undefined
                    && typeof manifest.desktopWidget[flag] !== "boolean") {
                return { valid: false, error: "desktopWidget." + flag + " must be a boolean" };
            }
        }
    }

    // Optional component-grid span: `"grid": { "cols": int>=1, "rows": int>=1 }`.
    // cols/rows default to 1 when omitted; both must be integers in 1..12.
    if (manifest.grid !== undefined) {
        if (!manifest.grid || typeof manifest.grid !== "object" || Array.isArray(manifest.grid)) {
            return { valid: false, error: "Manifest 'grid' must be an object with integer 'cols'/'rows'" };
        }
        const gridAxes = ["cols", "rows"];
        for (const axis of gridAxes) {
            const value = manifest.grid[axis];
            if (value === undefined) continue;
            if (typeof value !== "number" || value !== Math.floor(value) || value < 1 || value > 12) {
                return { valid: false, error: "grid." + axis + " must be an integer between 1 and 12" };
            }
        }
    }

    if (manifest.options !== undefined) {
        if (!Array.isArray(manifest.options)) {
            return { valid: false, error: "Manifest 'options' must be an array" };
        }
        const optionKeys = new Set();
        for (const option of manifest.options) {
            if (!option || typeof option !== "object" || typeof option.key !== "string" || !option.key) {
                return { valid: false, error: "Every plugin option must have a non-empty string 'key'" };
            }
            if (optionKeys.has(option.key)) {
                return { valid: false, error: "Duplicate plugin option key '" + option.key + "'" };
            }
            // A manifest's options and the host's own per-plugin state share one
            // PluginState namespace, so a manifest could otherwise declare a
            // control that writes over host state - `__gridSize`, the span the
            // user resized the widget to, is the first of those. The prefix is
            // the host's; nothing under it may come from a manifest.
            if (option.key.startsWith("__")) {
                return { valid: false, error: "Plugin option key '" + option.key + "' is reserved: '__' is the host's prefix" };
            }
            optionKeys.add(option.key);
            if (!["boolean", "choice", "shape", "color", "number", "text"].includes(option.type)) {
                return { valid: false, error: "Unsupported plugin option type '" + option.type + "'" };
            }
            if (option.type === "color" && typeof option.default !== "string") {
                return { valid: false, error: "Color option '" + option.key + "' must have a string default" };
            }
            if ((option.type === "choice" || option.type === "shape" || option.type === "color")
                    && (!Array.isArray(option.choices) || option.choices.length === 0)) {
                return { valid: false, error: "Choice option '" + option.key + "' must have choices" };
            }
            if (option.type === "number"
                    && (typeof option.from !== "number" || typeof option.to !== "number" || option.from > option.to)) {
                return { valid: false, error: "Number option '" + option.key + "' must have a valid range" };
            }
            if (option.type === "text" && typeof option.default !== "string") {
                return { valid: false, error: "Text option '" + option.key + "' must have a string default" };
            }
        }
    }

    return { valid: true };
}

function validateNode(node) {
    if (node.component !== undefined) {
        if (typeof node.component !== 'string' || !node.component || node.component.startsWith("/")
                || node.component.includes("..")) {
            return { valid: false, error: "Component must be a relative path inside the plugin package" };
        }
        if (node.type !== undefined)
            return { valid: false, error: "Entry point cannot define both 'type' and 'component'" };
        return { valid: true };
    }
    if (!node.type || typeof node.type !== 'string') {
        return { valid: false, error: "Node must have a string 'type'" };
    }
    if (!componentWhitelist.includes(node.type)) {
        return { valid: false, error: "Component type '" + node.type + "' is not whitelisted" };
    }

    if (node.bindings) {
        if (typeof node.bindings !== 'object') {
            return { valid: false, error: "Node 'bindings' must be an object" };
        }
        for (let prop in node.bindings) {
            let bindTarget = node.bindings[prop];
            if (typeof bindTarget !== 'string') {
                return { valid: false, error: "Binding target for property '" + prop + "' must be a string" };
            }
            if (!bindingWhitelist.includes(bindTarget)) {
                return { valid: false, error: "Binding target '" + bindTarget + "' is not whitelisted" };
            }
        }
    }

    if (node.children) {
        if (!Array.isArray(node.children)) {
            return { valid: false, error: "Node 'children' must be an array" };
        }
        for (let i = 0; i < node.children.length; i++) {
            let childRes = validateNode(node.children[i]);
            if (!childRes.valid) return childRes;
        }
    }

    return { valid: true };
}
