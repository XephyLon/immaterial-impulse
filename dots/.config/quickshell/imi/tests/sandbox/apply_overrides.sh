#!/usr/bin/env bash
# apply_overrides.sh <sandbox-dir> <overrides.json> : merge the overrides' config into the running sandbox (hot-reloaded); appearance lives wrapped in config.d/appearance.json
SB="$1"; shift
python3 - "$SB/config/immaterial-impulse" "$1" <<'PY'
import json, sys, os
d = sys.argv[1]; ov = json.load(open(sys.argv[2])).get("config", {})
def merge(a, b):
    for k, v in b.items():
        if isinstance(v, dict) and isinstance(a.get(k), dict): merge(a[k], v)
        else: a[k] = v
for k, v in ov.items():
    # a split domain lives in its own file, keyed bare; the rest in config.json under its key
    own = os.path.join(d, "config.d", k + ".json")
    if os.path.exists(own):
        cfg = json.load(open(own))
        # the split file wraps its domain under its own key
        target = cfg[k] if isinstance(cfg.get(k), dict) else cfg
        for stray in [s for s in v if s in cfg and target is not cfg]: cfg.pop(stray)
        merge(target, v); json.dump(cfg, open(own, "w"), indent=2); print("applied", k, "-> config.d/" + k + ".json", v)
    else:
        cfg = json.load(open(os.path.join(d, "config.json"))); merge(cfg, {k: v}); json.dump(cfg, open(os.path.join(d, "config.json"), "w"), indent=2); print("applied", k, "-> config.json", v)
PY
python3 -c "import time; time.sleep(2.5)"
