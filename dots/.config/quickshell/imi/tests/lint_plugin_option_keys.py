#!/usr/bin/env python3
"""No bundled manifest may declare an option key under the host's `__` prefix.

A manifest's `options` and the host's own per-plugin state share one PluginState
namespace (`pluginOptions[pluginId][key]`), and the host now keeps the user's
chosen grid span there as `__gridSize`. A manifest declaring that key would
render a settings control in Settings > Widgets that writes straight over it.

PluginValidator.js rejects such a manifest at load, which is the defence for an
installed third-party plugin. That is silent for a *bundled* one: the widget
would simply stop appearing, with the reason only in the log. This is the
greppable half.
"""
from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
BUNDLED = ROOT / "modules/common/plugins/bundled"
RESERVED_PREFIX = "__"

failures = []

for manifest_path in sorted(BUNDLED.glob("*/manifest.json")):
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        failures.append(f"{manifest_path.relative_to(ROOT)}: unreadable manifest ({error})")
        continue
    for option in manifest.get("options", []) or []:
        if not isinstance(option, dict):
            continue
        key = option.get("key")
        if isinstance(key, str) and key.startswith(RESERVED_PREFIX):
            failures.append(
                f"{manifest_path.relative_to(ROOT)}: option key '{key}' uses the host's "
                f"'{RESERVED_PREFIX}' prefix, which is reserved for host state")

# The rule is only worth anything while the host enforces it at load too.
validator = (ROOT / "modules/common/plugins/PluginValidator.js").read_text(encoding="utf-8")
if 'option.key.startsWith("__")' not in validator:
    failures.append(
        "modules/common/plugins/PluginValidator.js: lost its reserved option-key check")

if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)
print("Plugin option key lint passed: no manifest claims the host's '__' prefix")
