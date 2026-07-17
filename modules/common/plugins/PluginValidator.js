.pragma library

const componentWhitelist = [
    "StyledText", "StyledRectangularShadow", "MaterialSymbol", "GroupedList",
    "RippleButton", "ResourceCard", "StyledImage", "MaterialShape", "StyledPopup", "ConfigSwitch", "NoticeBox",
    "Row", "Column", "Item", "Rectangle"
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
    if (!manifest.root || typeof manifest.root !== 'object') {
        return { valid: false, error: "Manifest must have a 'root' node object" };
    }

    return validateNode(manifest.root);
}

function validateNode(node) {
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
