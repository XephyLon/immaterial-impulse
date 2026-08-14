# Integration testing for a desktop shell — design

**Status:** design, not implemented. §9 holds nine questions for the maintainer; four of them
change the shape of the work rather than a detail of it.
**Scope:** `tests/` (the runner, the drivers, a new fixture module), the root-level `*RuntimeTest.qml`
/ `*Probe.qml` harnesses, `sdata/tests/`, and one new workflow beside
`.github/workflows/docs-receipt.yml`. No shell source changes are proposed.

Paths are relative to `dots/.config/quickshell/imi/` unless written repo-relative, per AGENT.md's
layout note.

**Supersedes** [#19](https://github.com/XephyLon/immaterial-impulse/pull/19) in part — see §6 for
what is taken from it and what is rejected.

---

## Problem

The suite is genuinely strong at two things: pure-JS units under `qmltestrunner`, and source-text
contracts in Python. Measured on a full green run of `./tests/run_tests.sh` from this worktree
(`gh/main` = `8bd9f242f`), it is **704 `qmltestrunner` assertions + 816 Python `unittest` cases
across 88 modules + 159 `contract_runner` checks**, in 4m26s wall clock. The familiar "704 passed"
headline is the `qmltestrunner` line alone, and it accounts for 3.8 seconds of that run.

It is also, quietly, already doing integration testing — twenty Python modules stand up a real `qs`
process against a headless compositor, and one shell script stands up a nested **Hyprland** on its
own D-Bus session because weston cannot show it what it needs to see.

So "add integration tests" is the wrong framing. The tier exists. What it lacks is a boundary, a
shared fixture, an isolation contract, and any defence at all against the failure mode this repo
keeps paying for: **a harness that passes while the bug ships.**

Two facts set the size of the problem.

**First, the seam that has broken most often is the one nothing can reach.** AGENT.md's layer-shell
section (`AGENT.md:698-912`) is sixteen bullet points, fourteen of them distinct shipped defects,
and it ends with the admission:

> **This whole area is invisible to the test suite.** Quickshell's plugin does not load in
> `qmltestrunner`, so `Region` cannot be constructed there and no test can see whether a region is
> empty, published, or ignored. Every bug in this section was found by looking at the screen, and
> two of them were misattributed first. (`AGENT.md:896-900`)

**Second, the harnesses that do exist cannot report that they stopped checking.** Every one of the
thirteen runtime harnesses ends the same way:

```qml
function check(label, ok) {
    console.log(`[DockEdge] ${label}: ${ok ? "ok" : "FAIL"}`);
    if (!ok)
        harness.failures++;
}                                                     // DockEdgeRuntimeTest.qml:45-50

console.log(`[DockEdge] failures: ${harness.failures}`);
Qt.exit(harness.failures === 0 ? 0 : 1);              // DockEdgeRuntimeTest.qml:215-216
```

and every driver asserts exactly one thing about it:

```python
self.assertIn("[DockEdge] failures: 0", output, ...)  # test_dock_edge_runtime.py:93
```

A harness whose step list is emptied prints `failures: 0` on its first tick and passes. No driver
asserts that any check ran. That is not a hypothetical: `WeatherTreeMotionProbe` printed a full
green trail for a transition it never ran (`a26298efa`), and both shadow probes reported on a motion
they had switched off (`AGENT.md:1350-1359`, `2c9c9b5e7`).

An integration layer multiplies that risk, because setup is expensive and a silent skip is the
cheapest way to make a slow test fast.

---

## 1. What "integration testing" means for this shell

### 1.1 The three tiers that already exist, named

| Tier | What it is | Where | Count today | Sees |
| --- | --- | --- | --- | --- |
| **0** | pure logic + source contracts | `qmltestrunner`, `python3 test_*.py`, `lint_*.py` | ~700 checks | JS modules, source text, generated files |
| **1** | a real `qs` under **headless weston** | `*RuntimeTest.qml` + a Python driver | 20 modules | real QML trees, real input events, real files on disk, faked subprocesses |
| **2** | a real `qs` under a **nested Hyprland** on its own bus | `run_notification_blur_probe.sh` | **1**, wired into nothing | layer surfaces, exclusive zones, blur, D-Bus peers, generated lua the compositor re-reads |

Tier 1 is not a lesser thing that needs replacing. It is already integration testing of everything
that is a QML tree: `WidgetResizeGripRuntimeTest.qml` builds real `PluginWidget`s on a real
`WidgetCanvas` and drives them with real mouse events; `NotificationCardsRuntimeTest.qml` runs the
real notification server. What it cannot see is stated in its own docstrings, repeatedly and
accurately:

> Headless weston rather than the caller's session because the harness opens a window. It implements
> no wlr-layer-shell, so this proves nothing about the `PanelWindow` the real `Background.qml` puts
> the canvas on. (`test_widget_interaction_runtime.py:16-18`)

> It reaches the dock's *content* tree only; weston implements no wlr-layer-shell, so anchors, the
> exclusive zone, the reveal push and the compositor's inferred slide are all invisible to it.
> (`DockEdgeRuntimeTest.qml:29-34`)

**So the design question is not "what is an integration test". It is: what does tier 2 add that
tier 1 cannot give, and is that worth sixty seconds a run.**

### 1.2 The seams, ranked by how often they have actually broken

AGENT.md is a catalogue of real incidents with commit citations, so it is evidence rather than
guesswork. Counting distinct shipped defects per seam, and then discounting by what tiers 0 and 1
already reach:

| Rank | Seam | Incidents in AGENT.md | Reachable today? | Tier-2 priority |
| --- | --- | --- | --- | --- |
| 1 | **Layer surfaces**: lifetime, layer/stacking, mask, blur region, focus grab | **~14** (`:698-912`) | **No.** `qmltestrunner` cannot construct `Region`; weston has no wlr-layer-shell and no `ext-background-effect` | **1st** |
| 2 | **Config / state files** written and re-read | ~15 (`:430-545`, `:652-695`, `:901-907`, `:1381-1388`, `:1472-1484`, `:1812-1821`) | **Yes** — six tier-1 modules already force these races | 5th (served) |
| 3 | **Wallpaper / frost / parallax** surface | ~8 (`:1547-1565`, `:1756-1810`) | **No.** "nothing about the rendered frost is reachable from a test" (`:1788-1790`) | 4th |
| 4 | **Plugin loading by URL** and installed manifests | ~8 (`:1041-1064`, `:1119-1128`, `:1137-1142`, `:1174-1184`, `:1457-1463`) | **Partly.** `DesignSystemCompile.qml` sweeps *bundled* packages; nothing ever loads an *installed* one | 3rd |
| 5 | **D-Bus**: MPRIS, notifications, tray | ~7 (`:1823-1877`) | **Split.** `busctl`-driven services (Clight, PhoneConnect) are already faked at tier 1; MPRIS and the tray go through Quickshell's own bindings and are faked by nothing | **2nd** (MPRIS/tray half) |
| 6 | **The compositor's reserved area** and the generated lua it re-reads | ~6 (`:592-600`, `:652-695`, `:671-687`) | **Half.** Tier 1 writes the lua and asserts its *text*; nothing asserts Hyprland accepted it | **2nd** |

Three observations fall out of that table, and they are the whole design.

**(a) The top-ranked seam and the least-covered seam are the same seam.** Fourteen incidents, zero
coverage, and the section's own closing line says so. Every one of those bugs cost a deploy-and-look
cycle, and two were misattributed first (`AGENT.md:898-900`, and the `4a1b4f850` popup-region case
where "a region was written, deployed and only shown to be inert by looking at it on screen",
`:759-761`).

**(b) The seam with the most incidents is already the best covered.** Config and state broke fifteen
times and now has `test_config_dir_migration_runtime.py` (which forces the losing interleaving with
`IMI_MIGRATE_DELAY` rather than hoping to observe it), `test_kboptions_migration_runtime.py`,
`test_parallax_migration_runtime.py`, `test_notes_migration_runtime.py`,
`test_config_control_write_back.py` and `test_quick_toggles_layout_runtime.py`. Tier 2 should add
nothing here. Ranking by raw incident count alone would have got this exactly backwards.

**(c) The D-Bus seam splits in two, and the split is decided by whether the shell has a binding.**
`services/Clight.qml` and `services/PhoneConnect.qml` shell out to `busctl` because "the shell has
no D-Bus binding" (`AGENT.md:396`, `:399-403`) — which is why `test_clight_integration_runtime.py`
can fake the whole daemon with a shim binary on `PATH`, at tier 1, for nothing. MPRIS
(`services/MprisController.qml:11`, `import Quickshell.Services.Mpris`) and the tray
(`services/TrayService.qml:6`) go through Quickshell's own C++ bindings, so the only way to fake
them is to put a real peer on a real bus. That is tier 2 and nothing else.

### 1.3 What tier 2 asserts against — the oracle rule

The rule that makes tier 2 worth sixty seconds, and the rule that keeps it from becoming an
expensive re-spelling of tier 0:

> **A tier-2 test asserts against the compositor's or the peer's own answer, never against a QML
> property.** If the assertion can be satisfied by reading a binding in the shell under test, it
> belongs at tier 0 or 1.

This is AGENT.md's own lesson generalised — "A state property that says 'hovered' is not evidence a
pixel moved" (`:1413`), "'The frost is gated on the toggle' is not 'the surface is gated on the
toggle'" (`:1517`), "A surface the compositor *covers* is not a surface QML considers hidden"
(`:1289`). Concretely, per seam:

| Seam | Oracle | Verified available |
| --- | --- | --- |
| layer present / level / geometry | `hyprctl layers -j` | live: `quickshell:bar` at level 2, `y=5 h=63`; `quickshell:barPopup` at level 3 full-screen |
| exclusive zone | `hyprctl monitors -j` → `reserved` | live: `[0, 45, 0, 0]` on a 5120x1440 output with the dock unpinned |
| surface **lifetime** (`visible:false` destroys it) | namespace absent from `hyprctl layers -j` | — |
| compositor blur | `grim` + the two control cards | already built: `run_notification_blur_probe.sh:122-160` |
| keybind shim accepted | `hyprctl binds -j` | — (nothing reads it today) |
| `main.lua` accepted | `hyprctl getoption <key>` | — (nothing reads it today) |
| MPRIS selection | a fake player published on the private bus | — |
| tray icon runaway | a fake SNI whose `IconName` getter fails | — |

The last four are the new capability. Note what #6 in the ranking table buys:
`test_keybind_overrides_runtime.py:173-178` asserts the shim file *contains*
`unbind_chord("SUPER + Q")`. It does not and cannot assert that Hyprland removed the bind — which is the exact shape of issue #69, where "a
migration cleared a stale `input.kbOptions = grp:win_space_toggle` from `config.json` and the
compositor went on toggling layouts regardless" (`AGENT.md:660-663`). That bug shipped **twice**.
`hyprctl binds -j` under a nested instance is the first thing that could ever have caught it.

---

## 2. Isolation: what a test at this level must never touch

The four things named in the brief, plus the one that is already a live hazard.

### 2.1 The user's compositor — and the bug in the harness that exists

**This is the most important rule in the document, and the only harness that reaches tier 2 today
gets it wrong.**

`hyprctl` selects its target instance from `HYPRLAND_INSTANCE_SIGNATURE` **and from nothing else**.
Measured on this machine, read-only:

```
$ HYPRLAND_INSTANCE_SIGNATURE=bogus_1_1 hyprctl monitors
Couldn't connect to /run/user/1000/hypr/bogus_1_1/.socket.sock. (4)

$ env -u HYPRLAND_INSTANCE_SIGNATURE hyprctl monitors
HYPRLAND_INSTANCE_SIGNATURE not set! (is hyprland running?)

$ WAYLAND_DISPLAY=wayland-99 hyprctl monitors
Monitor DP-1 (ID 1):  5120x1440@239.761 at 0x0        # WAYLAND_DISPLAY is ignored
```

`HYPRLAND_INSTANCE_SIGNATURE` is exported into every process in the user's session. The blur probe
never overrides it — it exports `XDG_CONFIG_HOME`, `XDG_CACHE_HOME`, `XDG_STATE_HOME`,
`XDG_DATA_HOME` and later `WAYLAND_DISPLAY` (`run_notification_blur_probe.sh:38-39`, `:92`), and
none of those reach `hyprctl`. So this line:

```bash
hyprctl dispatch exit >/dev/null 2>&1              # run_notification_blur_probe.sh:114
```

is aimed at **the outer session**, not at the nested one it just started. `grep -rn
HYPRLAND_INSTANCE_SIGNATURE tests/` returns nothing.

The rule, therefore:

> **Every `hyprctl` invocation inside a tier-2 test goes through the fixture, which pins
> `-i <nested signature>` or exports the nested `HYPRLAND_INSTANCE_SIGNATURE`. A bare `hyprctl` in
> `tests/` fails the suite.**

That is a lint (`lint_test_isolation.py`, §7 step 2), not a note — this repo's own rule is that a
mistake made twice becomes a check, and the sibling mistake (`pgrep -f` matching its own caller)
already has one, `lint_self_matching_process_patterns.py`, added after two plan documents warned
about it and it was hit anyway (`AGENT.md:159-163`).

Give the nested instance its own `XDG_RUNTIME_DIR` as well. `run_weather_probe.sh:6` already does
this for weston (`export XDG_RUNTIME_DIR="$TMP/runtime"; chmod 700`); the blur probe does not, which
is why it has to *discover* its socket by diffing `ls $XDG_RUNTIME_DIR` before and after
(`:74-91`) instead of simply naming it.

### 2.2 The user's `~/.config/immaterial-impulse`

`Directories.qml` derives every shell path from `StandardPaths` (`:26-34`) and hangs the config
directory off it (`:53-57`), so redirecting the XDG variables before `qs` is spawned is sufficient
*and provably so* — no path in the shell is hardcoded to `$HOME`.

The gap is that the tier-1 drivers do it inconsistently. Nine of them set only a subset:

| Driver | XDG vars redirected |
| --- | --- |
| `test_notification_cards_runtime.py:79-82` | CONFIG, CACHE, STATE, DATA ✅ |
| `test_config_dir_migration_runtime.py` | CONFIG, CACHE, STATE, DATA ✅ |
| `test_widget_interaction_runtime.py:76-77` | CONFIG, STATE only ❌ |
| `test_widget_resize_grip_runtime.py` | CONFIG, STATE only ❌ |
| `test_widget_resize_motion_runtime.py` | CONFIG, STATE only ❌ |
| `test_widget_group_drag_runtime.py` | CONFIG, STATE only ❌ |
| `test_widget_parallax_optout.py` | CONFIG, STATE only ❌ |
| `test_dock_edge_runtime.py` | CONFIG, STATE only ❌ |
| `test_notes_surfaces_runtime.py` | CONFIG, STATE only ❌ |
| `test_config_control_write_back.py` | CONFIG, STATE only ❌ |
| `test_notes_migration_runtime.py` | CONFIG, STATE only ❌ |

Those nine run a real shell whose `Directories.cache` and `Directories.genericCache` resolve into
the caller's real `~/.cache` and `~/.local/share`. Nothing catastrophic has come of it — the
harnesses build widget trees, not wallpaper caches — but it is one `Background.captureGreeterStill`
away from a test writing into `~/.cache/quickshell/wallpaperengine-stills/`, and there is no reason
for a test to be able to.

> **The fixture sets all five (`XDG_CONFIG_HOME`, `XDG_CACHE_HOME`, `XDG_STATE_HOME`,
> `XDG_DATA_HOME`, `XDG_RUNTIME_DIR`) under one temp root, refuses to launch if any of them still
> points outside it, and no driver assembles that environment by hand.**

Making it a precondition inside the fixture rather than a convention is the point: sixteen
hand-built copies of the same twenty-five-line block is exactly how they drifted apart.

### 2.3 The user's session bus, MPRIS players and notification daemon

Two isolation shapes already exist in-tree and both are correct for different jobs:

- **Private bus** — `dbus-run-session -- <script>` (`test_notification_cards_runtime.py:105`). Use
  where the shell must *own* a name (`org.freedesktop.Notifications`) or must *see* a peer we
  publish. The driver's own comment states the rule: "The harness owns
  `org.freedesktop.Notifications` on this bus, so the `notify-send` calls below have to run on the
  same one - and must not reach the caller's real notification daemon." (`:87-89`)
- **No bus at all** — `DBUS_SESSION_BUS_ADDRESS="unix:path=/nonexistent"`
  (`run_weather_probe.sh:12`). Use where the subject is unrelated to D-Bus and the point is to prove
  it does not quietly acquire a dependency on one.

> **A tier-1 or tier-2 harness must set one of the two. Inheriting `DBUS_SESSION_BUS_ADDRESS` is a
> lint failure.** Today, `test_widget_interaction_runtime.py` and its siblings inherit it — so a
> harness that grew an `MprisController` reference would silently read the user's Spotify.

The MPRIS work in §1.2 depends on this: a fake player is only safe on a private bus, and on a
private bus it is *total* isolation — the shell under test cannot see the user's players because
they are not on its bus at all.

### 2.4 The live `qs -c imi` process

Never launched, never signalled, never killed. Two mechanisms:

1. Every harness is `qs -p <harness>.qml`, which loads one file and no panel family. Already
   universal; make it a lint (`qs -c` anywhere under `tests/` fails).
2. The process-matching rule already in AGENT.md (`:145-163`) — `pgrep -x`, never `pgrep -f` —
   already has its lint. Tier 2 adds a corollary: **the fixture kills by PID it holds**, never by
   name. `_stop(proc)` in the drivers (`test_widget_interaction_runtime.py:36-42`) is already the
   right shape; keep it and delete the `kill $QPID`-by-variable shell idiom when the probes are
   ported.

There is also a deploy-side rule already enforced: `sdata/lib/deploy-exclude.txt:5-7` keeps
`*RuntimeTest.qml`, `*Probe.qml` and `*Playground.qml` out of the install
(`83d76606a "fix(deploy): the probe and playground harnesses stay out of the install"`). A new
`*SessionTest.qml` suffix must be added to that file in the same commit that introduces it, and
`sdata/tests/test_deploy_exclude.py` extended — which brings us to the next section, because that
file is currently run by nothing.

---

## 3. The recurring failure mode, and the four defences

This project's characteristic defect is not an untested path. It is a **test that runs, reports
green, and is not looking at the thing it names.** The catalogue, all shipped, all with commits:

| # | Instance | Shape |
| --- | --- | --- |
| 1 | `WeatherTreeMotionProbe` drove a list of `[from, to]` pairs but committed only `to`, so `3x2 → 2x1` measured `3x1 → 2x1`, filed its shot as `3x2_settled.png`, and printed a green trail for every element under the wrong label (`a26298efa`, `AGENT.md:1254-1262`) | **wrong subject, right report** |
| 2 | The same probe's "did this move" floor was `0.5` for every trail — right for a position, nonsense for an opacity, so the sun arc's `0.32 → 0` fade filed as `static` (`AGENT.md:1262-1266`) | **threshold below the signal** |
| 3 | `test_calendar_card.py`'s rest-shadow floor was "darker than 6" against a field that measures 12.0 after the grab, so the floor sat *below* the background and the assertion could not fail; planting `shadowEnabled: false` still passed (`9977de572`) | **threshold below the background** |
| 4 | `tst_sun_arc.qml` compared `curveY(u)` against `80 - heightAt(phaseAt(u))`, which *is* `curveY`'s body — a distortion crafted to vanish at phases 0/0.5/1 bent the drawn arc 30% and left all 18 cases green (`9564df4c4`) | **assertion is the subject, spelled twice** |
| 5 | Both shadow probes **assigned** `motionActive` rather than driving motion, so neither could see that its only producer was the one motion that does not cost anything — the span animation ran with the shadow live for the whole life of the feature (`2c9c9b5e7`, `AGENT.md:1350-1359`) | **harness switches off the interaction it scores** |
| 6 | The parallax opt-out harness set `animatePosition: false` on both probes and panned by assignment: it disabled both halves of the interaction it existed to score and stayed green for the entire life of the bug (`AGENT.md:1228-1233`) | same |
| 7 | The plugin runtime harness declared its synthetic manifests inline on the harness root, which never crosses a `Repeater` model — so `Array.isArray` returning false across the model boundary was invisible to it while every real widget lost its grip (`AGENT.md:1174-1184`) | **harness avoids the real data path** |
| 8 | `DesignSystemCompile.qml` carried a hardcoded package array naming two directories that had never existed at that path since the `ii→imi` rename — every run reported two meaningless failures, and nothing ever ran it anyway (`18c7067e7`) | **enumerated subjects rot** |
| 9 | Three `test_*.py` files had drifted out of `run_tests.sh`, including one added that release whose own docstring says "this test is the fix" (`cbec67563`) | same |
| 10 | The resize-grip probe first ran at 2x2 pulling left — at a wall both semantics hold the span, so the mutated tree passed and the check was vacuous (`93734a263`) | **discriminating case not reached** |

Ten instances. Note the direction of every one: **none of them reddens. They go quiet.** A probe
that says nothing about an element reads exactly like a probe with nothing to say about it
(`AGENT.md:1266`).

Tier 2 makes this worse for three structural reasons: setup costs sixty seconds, so nobody re-runs
it casually; the environment is fragile, so `skipUnless` is the natural response to any trouble; and
the assertions are statistical (pixel spreads, geometry within tolerance), so a floor in the wrong
place is invisible by construction — instance #2 and #3 are both already that.

### The four defences

**D1 — A verdict states how many checks ran, and the driver asserts the number.**

```qml
// harness: check() increments checksRun as well as failures
console.log(`[DockEdge] checks: ${harness.checksRun} failures: ${harness.failures}`);
```
```python
# driver: the count is a literal, established the first time it is written
self.assertIn(f"[DockEdge] checks: {EXPECTED_CHECKS} failures: 0", output, ...)
```

Note that the count cannot be derived by grepping the harness — `DockEdgeRuntimeTest.qml` has four
`check(` call sites and emits considerably more than four checks, because they sit inside per-edge
and per-slot loops. That is exactly why the *harness* has to count and the *driver* has to hold the
expected number: a loop that stops iterating is the failure this catches, and a static count of call
sites would not see it.

Adding a check is a two-line diff; *losing* one is a red build. This closes instances #1, #8 and
#9, costs nothing, and retrofits to all thirteen existing harnesses mechanically. **It lands first, before any new capability**, because every later
step's green is worth exactly as much as this one is.

**D2 — Every tier-2 harness carries a named negative control, run in the same session.**

`IMI_HARNESS_MUTATE=<name>` selects a mutation the harness applies to its own subject; the driver
runs the harness once clean and once mutated and requires the *named* check to redden — not merely
"some failure occurred". Three commits already did this by hand and said so
(`9977de572`: "Proved by planting `shadowEnabled: false`"; `93734a263`: "measured by planting the
regression, not guessed"; `844111176`: "Planted the old `onCountChanged` trigger back and confirmed
it reddens on 'the second popup's card is on screen'"). CONTRIBUTING.md already *requires* it —
"Prove a new static check can fail" (`:268-269`) — and has no way to check that anyone did.

Doing it in-session is what makes it affordable: the compositor, the bus and the shell are already
up, so the mutation costs one more render pass rather than another sixty seconds. It also sidesteps
CONTRIBUTING.md's plant-and-revert trap ("`git checkout -- <file>` reverts to HEAD, destroying every
uncommitted edit in that file", `:270-276`) — nothing is edited on disk at all.

This closes instances #3, #5, #6 and #10.

**D3 — A skip is a distinct outcome from a pass, and is a failure on a machine that claims the
tier.**

Today `unittest` exits 0 when every test in a module skips, `run_tests.sh` checks only the exit
code, and twenty modules skip on CI with no summary anywhere. Introduce `IMI_TEST_TIER`:

- unset or `0` — tier 1 and 2 modules skip, and `run_tests.sh` prints a **skip ledger** naming every
  module that skipped and the binary it wanted.
- `1` — a tier-1 module that cannot find `qs`/`weston` **fails** instead of skipping.
- `2` — same for `Hyprland`/`grim`/`dbus-run-session`.

CI sets `IMI_TEST_TIER=0` explicitly, so "CI skipped it" is a declared state rather than an
accident. A developer machine sets `1` (or `2`) in their environment and can no longer half-run the
suite without noticing.

**D4 — The runner enumerates nothing by hand.**

`run_tests.sh` names 108 checks one at a time, which is how three files drifted out of it
(`cbec67563`) and how `DesignSystemCompile`'s package list rotted (`18c7067e7`). The fix that
release applied was to add the three missing names — a re-audit, not a mechanism. **`run_tests.sh`
must fail when a `test_*.py` or `lint_*.py` exists under either test root and is not invoked.**

Because there is a second root, and it is currently orphaned in full:

```
$ ls sdata/tests/
test_deploy_exclude.py  test_migrate_detect.py  test_we_wrapper_env.py
$ grep -rn "sdata/tests" --include=*.sh --include=*.yml --include=*.py .
(nothing)
$ python3 sdata/tests/test_deploy_exclude.py && python3 sdata/tests/test_migrate_detect.py \
      && python3 sdata/tests/test_we_wrapper_env.py
Ran 1 test ... OK / Ran 4 tests ... OK / Ran 6 tests ... OK
```

Eleven passing tests, added between 2026-07-23 and 2026-08-01, invoked by no runner and no workflow.
They guard the deploy exclusion list, the legacy-install detection and the Wallpaper Engine wrapper
environment — all three of them installer-lifecycle checks, which is precisely PR #19's first
candidate scope. The proposal's premise that the installer has "zero coverage" is out of date; what
it has is coverage nothing runs.

---

## 4. Cost, and what runs where

### 4.1 Measured

One full green run, timestamped per line, on this machine with the live session up
(`./tests/run_tests.sh`, everything including `DesignSystemCompile`): **265.6 s wall**.

The seventeen compositor-bound blocks account for **227 s of it — 85% of the run**:

| s | block |
| --- | --- |
| 28.1 | widget resize grip runtime |
| 27.0 | Clight integration runtime |
| 25.3 | notification card list runtime |
| 21.8 | config directory migration runtime |
| 17.9 | stale kbOptions clear runtime |
| 14.4 | widget resize motion runtime |
| 13.7 | night light state runtime |
| 12.7 | notes migration runtime |
| 11.0 | dock edge runtime |
| 10.8 | widget parallax opt-out |
| 7.7 | widget group drag runtime |
| 7.7 | parallax migration runtime |
| 7.2 | widget elevation (pixels) |
| 6.2 | widget interaction runtime |
| 6.1 | design system compile |
| 5.1 | calendar card (pixels) |
| 4.6 | widget card shadow (pixels) |

Everything else — 88 Python modules, 24 lints and the whole 704-assertion `qmltestrunner` sweep —
is the remaining ~38 s, of which the QML sweep is 3.8 s.

Two consequences.

**Tier 1 is already the expensive tier, and it is not the tier with the coverage.** 85% of the wall
clock buys 20 modules; 15% buys 1679 checks. Anything added at tier 2 lands on top of an already
compositor-dominated run, so the cost question is not "can we afford tier 2" but "which run does
tier 2 belong to".

**The cost is waiting, not working.** A tier-1 harness is dominated by fixed settle timers and
socket polls — `test_widget_interaction_runtime.py:69-71` polls up to 15 s for the weston socket
before `qs` even starts; `DockEdgeRuntimeTest.qml:203-210` ticks one step per 600 ms *by design*,
because "a check sharing a frame with the release it scores would read a position the animation is
still travelling through". These are not inefficiencies to optimise away.

**The one tier-2 harness**: 44 s of hardcoded sleeps (`run_notification_blur_probe.sh:98-111`:
8 + 4 + 12 + 4 + 12 + 4) on top of a compositor wait looping up to 30 s (`:79-85`). Budget
**60-75 s per nested-Hyprland session** — and note that 24 of those seconds exist only to outlive
the notification's 7 s timeout twice, because the surface has to really go down and come back. That
cannot be shortened without changing what is being tested.

That figure sets the cost policy: a tier-2 session is not something to pay per test, it is something
to pay **once and reuse for every assertion that needs it**.

### 4.2 CI has no compositor, and that is not going to change cheaply

`.github/workflows/tests.yml` installs `qt6-declarative-dev`, the qml6 modules, `ffmpeg` and `zstd`
— and nothing else. No `weston`, no `Hyprland`, no `grim`, no `magick`, and above all **no
Quickshell**: there is no `qs` on a GitHub runner and building one is a compile of a C++/Qt project
plus its Wayland protocol dependencies. So every one of the twenty tier-1 modules skips, the
`DesignSystemCompile` step skips loudly by design (`run_tests.sh:895-897`), and the three pixel
harnesses skip on `magick` as well.

CI is therefore, and honestly, **a tier-0 gate**. Saying so is worth more than pretending otherwise.

### 4.3 The proposed gate

| Where | Runs | Blocking? | Budget |
| --- | --- | --- | --- |
| **CI** (`tests.yml`, unchanged) | tier 0, `IMI_TEST_TIER=0`, plus the skip ledger | yes, on every PR | ~40 s of checks |
| **CI** (new small job) | asserts the skip ledger equals the *declared* CI capability set | yes | seconds |
| **Local `./tests/run_tests.sh`** with `IMI_TEST_TIER=1` | tiers 0 + 1 | yes for any PR touching `modules/`, `services/` or `tests/` | 4m26s measured |
| **Local `./tests/run_session_tests.sh`** (`IMI_TEST_TIER=2`) | tier 2 | **path-triggered**, see below | ~3-5 min |

The second row is the one that earns its place. Today a tier-0 test that quietly acquires a
dependency on `qs` becomes a tier-1 test, starts skipping on CI, and nobody learns. Pinning the
ledger turns that into a red build the day it happens.

**The tier-2 trigger, and how it is enforced.** Requiring tier 2 on every PR would get it ignored;
requiring it on judgement would get it skipped. Use the mechanism this repo already built for
exactly this problem — `.github/workflows/docs-receipt.yml` and the `Docs:` line
(CONTRIBUTING.md:302-313), which exists because "the judgment call above was silently skipped four
PRs running" and "a receipt converts 'did you consider the docs' (unverifiable) into 'the line
exists and the reason holds up' (ten seconds)".

A second receipt, computed from the diff rather than from the author's memory:

```
Session tests: LayerSurfaceSessionTest — checks: 18 failures: 0
Session tests: not needed — <reason>
```

required when the diff touches any of: a file declaring `WlrLayershell.*`, `dots/.config/hypr/
hyprland/rules.lua`, `WindowBlurRegion.qml` or a `blurRegion` publisher, a `services/*` file that
generates a `shellOverrides/*.lua`, or `services/MprisController.qml` / `MprisSelection.js` /
`TrayService.qml`. The workflow computes the path set and fails when the receipt is missing, exactly
as `docs-receipt.yml` does for `Docs:`.

### 4.4 What is deliberately *not* proposed

**A self-hosted CI runner, for now.** It would make tier 1 and possibly tier 2 blocking, but it puts
a Hyprland session and this user's real machine in the path of every PR, and §9 Q1 asks whether
truly headless Hyprland works at all on a machine with no seat. Until that is answered, tier 2 is
local, receipted, and honest about it.

**Running tier 2 fail-fast.** `run_tests.sh` exits at the first failing check (`exit 1` after each
block). That is right when a check costs 200ms and wrong when the session cost 60s and five more
assertions were going to ride on it. `run_session_tests.sh` runs every harness in a session and
reports at the end.

---

## 5. Architecture of the new layer

Three files, no framework.

### 5.1 `tests/session.py` — the fixture

Extracted from the **sixteen** hand-written copies of the weston-startup block in the Python
drivers (`grep -l '"weston"' tests/*.py`) and the six more in the probe scripts, plus a new sibling
for Hyprland.

```python
with weston_session(name="widget-interaction", size=(1200, 800)) as s:
    out = s.run_harness("WidgetInteractionRuntimeTest.qml", timeout=180)

with hyprland_session(name="layer-surfaces", rules=SHIPPED) as s:
    s.start_harness("LayerSurfaceSessionTest.qml")
    layers = s.hyprctl("layers", json=True)      # pinned to the nested instance
    s.grim("/tmp/shot.png")
```

Responsibilities, all of them isolation:

1. One temp root; all five XDG variables under it; **refuse to start** if any still resolves outside
   it. (§2.2)
2. `DBUS_SESSION_BUS_ADDRESS` set to a private bus (`dbus-run-session`) or to
   `unix:path=/nonexistent`; never inherited. (§2.3)
3. For `hyprland_session`: capture the nested instance's `HYPRLAND_INSTANCE_SIGNATURE` and pin every
   `hyprctl` to it. **No bare `hyprctl` anywhere.** (§2.1)
4. `LIBGL_ALWAYS_SOFTWARE=1`, `QT_QUICK_BACKEND=software` — already the convention in every driver
   ("This box's headless EGL has no driver", `test_widget_interaction_runtime.py:73-74`).
5. Tear down by held PID, never by name. (§2.4)
6. Honour `IMI_TEST_TIER`: skip, or fail, per D3.

### 5.2 The nested compositor's config is *generated from the shipped one*

`run_notification_blur_probe.sh:46-71` hand-copies eleven layer rules with the comment "Mirrors
`dots/.config/hypr/hyprland/rules.lua` for the namespaces under test". A hand-copy of a rule set is
the same two-files-that-must-agree shape that `lint_blur_region_pairing.py` exists to police
(`AGENT.md:735-748`) — and if it drifts, the probe photographs a blur configuration nobody runs.

> **`hyprland_session` sources the repo's real `rules.lua` and overrides only the machine-specific
> lines** — monitor mode and scale, `animations.enabled = false`, `disable_autoreload`, the logo and
> splash. The layer rules under test come from the file that ships.

This is not tidiness; it buys a check nothing has today. `services/PopupBlurThreshold.qml` generates
`hypr/hyprland/shellOverrides/popupBlur.lua`, which `rules.lua` `dofile`s behind a `pcall` with a
first-run fallback (`AGENT.md:761-767`). Under a real nested Hyprland sourcing the real `rules.lua`,
that whole generate-write-reload-apply chain runs for the first time in a test.

### 5.3 `*SessionTest.qml` — the harness convention

Same shape as `*RuntimeTest.qml`, with three additions:

- verdict line carries `checks: N` (D1);
- reads `IMI_HARNESS_MUTATE` and applies one named mutation to its own subject (D2);
- **asserts nothing it could assert from QML alone.** The harness's job at tier 2 is to *drive*
  — open the popup, toggle fullscreen, publish the region — and to hold still while the driver reads
  the compositor. Assertions that belong in QML stay in a `*RuntimeTest.qml` at tier 1.

Add `*SessionTest.qml` to `sdata/lib/deploy-exclude.txt` and to
`sdata/tests/test_deploy_exclude.py:27` in the same commit.

---

## 6. What this takes from PR #19, and what it rejects

[#19 "Proposal: integration test script"](https://github.com/XephyLon/immaterial-impulse/pull/19) is
a draft PR by the maintainer, open since 2026-07-24, adding a single file
(`docs/proposals/integration-tests.md`, 50 lines, no comments on the PR). It is the only prior art
and this document does not get to ignore it.

### Taken

**Its central claim, which is still true.** "Unit coverage exists … but nothing exercises real
*flows*." Seventy commits have touched AGENT.md in the three weeks since #19 was opened, and they
have made the case stronger rather than closing it: the layer-shell section still stands at
sixteen entries, and every one of them was found by looking at a screen.

**Its scope 2, promoted to first place with a different justification.** #19 ranks "live shell
flows" second and describes it as "heavier; likely a local/self-hosted script before it can be
GitHub CI". This document agrees it is local-only and disagrees about the ranking: the evidence in
§1.2 puts compositor-owned state first by a wide margin.

**Its freeze-detection recipe, kept as a tool rather than a test.** The IPC-roundtrip latency probe
(`qs ipc call` every 300ms; idle ≈ 85ms, a stall is a freeze) plus log-heartbeat gap analysis is
how the 2026-07-24 preset-cycle regression was measured, 11 stalls ≤ 4.8s down to 0. That is a real
technique and it belongs beside the repo-root `diagnose` script, or as a documented one-off. It is
**not** made an
assertion: a latency floor is a threshold, thresholds in this repo have twice been set below the
signal they measure (§3 instances #2 and #3), and a wall-clock budget measured on this machine has
no defined meaning on any other.

**Its scope-3 observation that file assertions need no display server** — which is why the theming
pipeline stays at tier 0/1 and is not part of the new layer at all.

### Rejected

**Its ranking, specifically "updater/installer lifecycle first".** #19 justifies this with "two
divergent code paths (`setup install` vs `setup exp-update`) share zero coverage". That is no longer
accurate. `tests/test_installer_file_sync.py`, `test_installer_legacy_migration.py`,
`test_installer_greeting_traps.py`, `test_exp_update_contract.py`, `test_uninstall_login_shell.py`,
`test_wallpaperengine_prebuilt.py` and `test_updates_contract.py` all exist and all run; three more
sit unrun in `sdata/tests/`. The remaining installer gap is **wiring, not coverage** — §7 step 3
closes it in one commit. Standing up a container-based install-then-update harness would be the most
expensive item on the list to buy the least new information.

**Its scope 4, "shell boot smoke: the shell starts, all QML loads without errors".** This is a real
gap — AGENT.md:184-186 says plainly that "`tests/run_tests.sh` cannot catch this class of bug" — but
it has been substantially closed since #19 was written, by `DesignSystemCompile.qml`, which compiles
the design system, every bundled package, every settings page and the desktop-widget host
(CONTRIBUTING.md:252-256). What remains is a full panel-family load, which tier 2 gets **for free**:
`LayerSurfaceSessionTest.qml` has to load the real family to have layer surfaces to measure, so
"`Configuration Loaded` appeared and no `ERROR:` cascade did" is an assertion it makes on the way
past, not a separate harness.

**Its container-first framing.** "Scopes 1 & 3 are container-friendly (Arch container …)". Arch
containers are right for the installer and the theming pipeline, both of which are tier 0/1 file
assertions. They are wrong for the seam that matters: a container does not have a compositor either,
so it moves the problem without solving it.

**Its filing location.** #19 puts the document in `docs/proposals/`. This one goes in
`docs/superpowers/specs/` with the other nineteen design specs, because it makes decisions rather
than parking an idea.

### The recommendation for #19 itself

Close it, referencing this spec, once §7 step 3 lands (the step that wires the orphaned installer
tests in) — that is the concrete part of #19's first scope, delivered. Leave it open until then, so
the idea is not lost twice.

---

## 7. Landing plan

Eleven steps. Each one leaves `./tests/run_tests.sh` green, is independently reviewable, and none of
the first four adds a new capability — they make the existing green mean something, which is the
precondition for trusting anything built on top.

**Step 1 — `checks: N` in every verdict, asserted by every driver.** (D1)
Thirteen harnesses × two lines; thirteen drivers × one assertion. No behaviour change, no new
dependency, runs everywhere the harnesses already run. *Green check:* delete one step from a
harness's list locally and confirm its driver reddens.

**Step 2 — `lint_test_isolation.py`.** Fails on: a bare `hyprctl` under `tests/` or in a root-level
harness; `qs -c` anywhere under `tests/`; a driver that sets `XDG_CONFIG_HOME` without setting the
other four; a driver that spawns `qs` without setting `DBUS_SESSION_BUS_ADDRESS`. It will red on
day one against the nine drivers in §2.2 and against `run_notification_blur_probe.sh:114` — so this
step includes fixing them. *This step alone removes the "exit the user's session" hazard.*

**Step 3 — run the tests nothing runs, and make that impossible again.** (D4)
Wire `sdata/tests/*.py` into `run_tests.sh`; add a guard that fails when any `test_*.py` /
`lint_*.py` under either root is not invoked by the runner. Eleven tests gain enforcement; the
enumeration drift that bit in `cbec67563` becomes unrepeatable.

**Step 4 — `IMI_TEST_TIER` and the skip ledger.** (D3) Plus the small CI job that pins the ledger to
CI's declared capability set. Default behaviour unchanged for anyone who sets nothing.

**Step 5 — `tests/session.py`, `weston_session()` only.** Port the sixteen tier-1 drivers onto it.
Pure refactor; the isolation preconditions from step 2 move from a lint into the fixture, where they
cannot be forgotten by the seventeenth driver.

**Step 6 — `hyprland_session()`, and the blur probe becomes a test.** Nested Hyprland, own runtime
dir, own bus, pinned instance signature, `rules.lua` generated from the shipped file (§5.2). Port
`run_notification_blur_probe.sh` onto it, give it a Python driver, and add
`tests/run_session_tests.sh`. The first tier-2 test is the one that already exists — no new
assertions, so a failure here is the fixture's fault and nothing else's.

**Step 7 — D2: the in-session negative control.** `IMI_HARNESS_MUTATE`, wired into the blur test
first (its mutation is "publish no region", which is the bug it was written for). Then retrofit one
named mutation to each tier-1 harness as it is touched — not in a big bang.

**Step 8 — Seam 1: `LayerSurfaceSessionTest.qml`.** The real panel family under the nested
compositor. Asserts, all from `hyprctl`: every expected namespace present at its expected level; the
bar's `reserved` top matches its declared exclusive zone; the dock's `reserved` bottom is its
geometry when pinned and 0 when not; `quickshell:background` is *still in the layer list* after a
fullscreen toggle (the `visible:false`-destroys-it regression, `AGENT.md:710-719`); the bar is
promoted to `Overlay` under fullscreen + special workspace and back to `Top` after
(`AGENT.md:703-709`). Plus, free, `Configuration Loaded` with no `ERROR:` cascade.

**Step 9 — Seam 2: what the compositor accepted.** Extend the keybind-override and kbOptions runtime
tests with a tier-2 sibling that asserts `hyprctl binds -j` no longer carries the unbound chord and
`hyprctl getoption input:kb_options` is clear. This is the assertion issue #69 never had.

**Step 10 — Seam 2b: D-Bus peers on the private bus.** A fake MPRIS player script publishing
`org.mpris.MediaPlayer2.<name>`, instantiated three ways — a `playerctld`-shaped proxy, a pair with
`.instance<pid>` suffixes, and a `plasma-browser-integration`-shaped duplicate — asserting
`MprisController.activePlayer` end to end for the first time (`AGENT.md:1823-1858` is three shipped
bugs here, currently guarded only by the pure-JS `tst_mpris_selection.qml` and a source contract).
Then a fake SNI whose `IconName` getter fails, for the runaway at `AGENT.md:1871-1877`.

**Step 11 (optional, after §9 Q4) — the `Session tests:` receipt** and its workflow.

Seams 3 (the frost) and 4 (installed plugins) are deliberately left out of the first plan. Both are
real; neither is worth starting before steps 1-6 have proved the fixture. §9 Q6 asks whether to
schedule them.

---

## 8. Risks worth naming before building

- **Nested Hyprland may not be reliably headless.** The existing probe runs `Hyprland` with no
  backend flag, inside a Wayland session, so it nests as a client. On a machine with no session
  there may be no working backend at all. If so, tier 2 is not merely local-only but
  *interactive-session-only*, which changes the receipt story. §9 Q1.
- **The blur measurement is a threshold, and this repo has set two thresholds below their own
  signal.** The probe's design already mitigates it correctly — it prints two *control* cards beside
  every shot and instructs the reader to "read the notification number against them, not against an
  absolute threshold" (`run_notification_blur_probe.sh:20-25`). Any automated version must assert
  the *relation* to the controls, never a constant.
- **Timing.** Every existing harness settles with fixed `Timer` intervals and fixed `sleep`s. Under
  a loaded machine these become flaky rather than wrong, **and this was reproduced while measuring
  for this document.** On the first full run, with thirteen weston harnesses and their `qs`
  processes alongside the live session, `tst_weather_forecast.qml` died with SIGABRT (return code
  `-6`) inside `test_weather_forecast_contract.py:196` — which reported it as
  *"tst_weather_forecast.qml fails under TZ=Pacific/Kiritimati, so a forecast card is labelled with
  the wrong day for part of every day there"*. It is not: the same file passes 15/15 under both
  zones in isolation, and the second full suite run was green throughout (704 passed, 0 failed).
  **A crash and a wrong answer must not share an assertion** — the driver asserts `returncode == 0`
  and describes what a non-zero one means, so a signal death is reported as a domain bug. Every
  `assertEqual(proc.returncode, 0, ...)` in the suite has this shape; tier 2, which runs more
  processes under more load, will hit it more often. Distinguish `returncode < 0` and say "the
  runner died" instead.
- **The fixture becomes a second thing to get wrong.** Sixteen copies drifted; one fixture can drift
  from what the shell actually needs. Mitigation: the fixture asserts its own preconditions and
  fails loudly, rather than defaulting.
- **A receipt that is always "not needed" is a receipt nobody reads.** The `Docs:` receipt works
  because the path trigger is the whole diff. Compute the `Session tests:` trigger from paths, and
  keep the trigger narrow enough that it fires a few times a month, not on every PR.

---

## 9. Open questions for the maintainer

**Q1 — Can Hyprland run genuinely headless on this machine, and on a runner?**
The blur probe only ever runs nested inside a live session. If Hyprland needs a seat/DRM device,
tier 2 can never be CI at all and the receipt in §4.3 is the permanent answer rather than a stopgap.
Needs a spike; it changes §7 step 6 and everything after.

**Q2 — Synthetic input under the nested compositor.**
Tier 1 gets clicks free from `TestCase` because the harness owns the window. A layer surface does
not, and the outside-click focus-grab behaviour (`AGENT.md:857-860`, `0cec47e6f`) is one of the
seam's real bugs. Options: `ydotool` (the repo already ships `test_ydotool_contract.py` and the
shell drives it, but it needs uinput permissions), `wtype`, or `hyprctl dispatch movecursor` plus
something for buttons. Which is acceptable to require on a dev machine?

**Q3 — Which `quickshell` should tier 2 run?**
`qs` resolves to `/usr/local/bin/quickshell`, while the installer pins a prebuilt at
`~/.cache/immaterial-impulse/prebuilt/<ref>/bin/quickshell` and only that one is Wallpaper
Engine-capable (`AGENT.md:152-155`). They can differ. Should the fixture prefer the pinned build,
require them to match, or record which it used in the verdict?

**Q4 — Is a `Session tests:` PR receipt wanted, or is that one receipt too many?**
The alternative is a git hook, or a label, or nothing at all beyond the spec saying when to run it.
The `Docs:` receipt exists because judgement was silently skipped four PRs running; whether the same
argument applies here is the maintainer's call, not mine.

**Q5 — Should the installer/updater lifecycle get its own container suite eventually?**
§6 rejects it as *first*, not as *never*. #19's argument about `rsync -a --delete` having real
data-loss semantics stands; the question is whether the per-directory mode table in
`sdata/subcmd-install/3.files-exp.yaml` is better asserted from a container run or from the file
contracts that already exist.

**Q6 — Schedule seams 3 and 4, or leave them?**
The frost (`AGENT.md:1769-1793`, #157) and installed-plugin loading (`AGENT.md:1457-1463`) are both
real holes. Both are more work than steps 8-10. Do they belong in this initiative or a later one?

**Q7 — Tier-2 wall-clock budget before the gate stops being obeyed.**
Five minutes? Fifteen? The answer decides how many sessions the plan may stand up — one shared
session for all tier-2 harnesses is ~75s plus assertions; one per harness is ~75s each.

**Q8 — Should `run_tests.sh` keep fail-fast at tier 0/1?**
§4.4 proposes tier 2 runs everything and reports at the end. Should tiers 0 and 1 change too? It
would lengthen a failing run and shorten the number of iterations to a clean one.

**Q9 — What to do about the three orphaned `sdata/tests/` files' *home*.**
Step 3 wires them into `run_tests.sh`, which lives under the shell's theme directory and whose
`PROJECT_ROOT` is the theme root. `lint_doc_citations.py` already has this problem and solved it by
walking up to the repo root, with a docstring explaining "this is the only test runner the repo
has". Is that acceptable, or does the repo want a root-level runner that calls both?

---

## Appendix: what was measured for this document

Everything asserted above as "live", "measured" or "verified" was run read-only against this machine
on 2026-08-14, or against the worktree at `gh/main` = `8bd9f242f`:

| Claim | How |
| --- | --- |
| `hyprctl` resolves by `HYPRLAND_INSTANCE_SIGNATURE` alone | three read-only `hyprctl monitors` invocations, §2.1 |
| the live layer stack and reserved area | `hyprctl layers -j`, `hyprctl monitors -j` |
| the three `sdata/tests/` files pass and are invoked by nothing | `python3 <file>` each; `grep -rn "sdata/tests"` |
| no harness prints a check count; every driver asserts only `failures: 0` | `grep -n "failures:" *RuntimeTest.qml *Probe.qml`; `grep -n assertIn tests/test_*runtime*.py` |
| twenty modules gate on a compositor | `grep -l skipUnless tests/*.py` and their `_runtime_available()` bodies |
| the nine drivers redirecting only some XDG vars | per-file `grep -o 'XDG_[A-Z_]*'` |
| CI installs no compositor and no Quickshell | `.github/workflows/tests.yml` |
| whole-suite wall clock, per-block timings, check totals | `./tests/run_tests.sh` timestamped per line; run twice |
| the SIGABRT transient, and that it is a transient | first run red at `test_weather_forecast_contract.py`; the file re-run alone under both zones, and the whole suite re-run, both green |
| no probe script is invoked by `run_tests.sh` | `grep -n probe tests/run_tests.sh` → nothing |

The live shell was not restarted, not deployed to, and `~/.config/immaterial-impulse` was not
written. The suite was run from the worktree, which has its own copy of everything it touches.
