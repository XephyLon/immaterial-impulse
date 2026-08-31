#!/usr/bin/env python3
"""The watchdog's planner: what one poll tick decides, without a bus."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts/tray"))
import sni_watchdog as wd

CHECKS = []
def check(fn): CHECKS.append(fn); return fn


@check
def test_items_parse_and_classify():
    items = wd.parse_items('as 2 ":1.5/StatusNotifierItem" ":1.9/org/ayatana/NotificationItem/steam"')
    assert items == [":1.5/StatusNotifierItem", ":1.9/org/ayatana/NotificationItem/steam"]
    assert wd.resurrectable(items[0])
    assert not wd.resurrectable(items[1]), "ayatana clients re-register themselves"
    assert wd.service_of(items[1]) == ":1.9"


@check
def test_steady_state_remembers_and_acts_not():
    state = {"owner": None, "absent_since": None, "remembered": {}}
    state, actions = wd.plan_actions(state, "PID=1", [":1.5/StatusNotifierItem"], {":1.5"}, 100)
    assert actions == []
    assert state["remembered"] == {":1.5": ":1.5/StatusNotifierItem"}


@check
def test_rebirth_reregisters_survivors_only():
    state = {"owner": "PID=1", "absent_since": None,
             "remembered": {":1.5": ":1.5/StatusNotifierItem", ":1.7": ":1.7/StatusNotifierItem"}}
    # watcher reborn (new owner), :1.7's app quit, :1.5 alive but unregistered
    state, actions = wd.plan_actions(state, "PID=2", [], {":1.5"}, 200)
    assert actions == [("register", ":1.5")]
    assert ":1.7" not in state["remembered"], "a dead service is forgotten"


@check
def test_rebirth_skips_already_registered():
    state = {"owner": "PID=1", "absent_since": None,
             "remembered": {":1.5": ":1.5/StatusNotifierItem"}}
    state, actions = wd.plan_actions(state, "PID=2", [":1.5/StatusNotifierItem"], {":1.5"}, 200)
    assert actions == []


@check
def test_absence_activates_after_grace_not_before():
    state = {"owner": "PID=1", "absent_since": None, "remembered": {}}
    state, actions = wd.plan_actions(state, None, [], set(), 100)
    assert actions == [] and state["absent_since"] == 100
    state, actions = wd.plan_actions(state, None, [], set(), 100 + wd.ABSENT_GRACE_S)
    assert actions == [("activate",)]
    # and the memory survives the outage
    assert state["remembered"] == {}


passed = 0
for fn in CHECKS:
    fn(); passed += 1
print(f"{passed}/{len(CHECKS)} watchdog planner checks passed")
